#!/bin/sh
# autopilot-driver.sh — the autopilot profile's driver.
#
# Deterministic dispatch for phases 2-9 of a flight (phase 1 is the interactive
# interview: /fly runs it and launches this script as its last act). The driver
# launches headless sessions, checks each phase's preflight, reads routed
# verdicts, holds the bounce counters, and stops at the caps. It decides
# nothing: routing is the reviewers' judgment, executed mechanically
# (docs: .ai/process/autopilot.md in the target, ADR-0008 in the kit repo).
#
# POSIX shell. Runtime dependencies: git, the two headless harness CLIs, and
# gh (push + draft PR ribbon). Concrete model identifiers are never written
# here: they come from .ai/autopilot/models.env, written by /fly from the
# project's Model Roster with the operator confirming. Config files are DATA,
# not code: parsed key by key against a strict grammar, never sourced; a
# malformed line, an unknown key, or a duplicate key is fatal — a config the
# driver does not fully understand must not half-apply.
#
# Permission policy (ADR-0008 amendments): producers run codex in its
# workspace-write sandbox with automatic approvals; reviewers run claude with
# the operator's Claude Code sandbox plus acceptEdits. A bypass is never a
# silent default and never inherited from the caller's environment — it exists
# only as an explicit AP_*_ARGS line in models.env, written by the operator.
# The permission policy is coarse by necessity (every reviewer needs the shell
# to run suites), so it is not what carries the hard wall: the wall is enforced
# on the WRITE-SET — see "the wall on the write-set" below and .ai/wall.env.
#
# The base branch is `develop`, fixed by ADR-0008 — not configurable.
#
# Entry preconditions (ADR-0008: re-entry always passes the gate): before ANY
# phase launch — first phase, normal flow, or an -s relaunch — the artifacts
# on disk must justify entering it. The only path into phase 8 is a plan
# carrying the approved Gate row that only phase 7 writes; the only path into
# phase 9 additionally carries the Implementation GREEN row on the testplan
# Log that only phase 8 appends — implementation cannot be skipped by re-entry.
#
# State lives under .ai/autopilot/<feature>/ (gitignored). Terminal statuses:
#   DONE     pushed and draft PR opened                      exit 0
#   PUSHED   pushed, PR NOT opened — operator completes      exit 1
#   STOPPED  caps / preflight / git failure — nothing pushed exit 1
# Exit 2 = usage / precondition failure (no state written).
#
# Usage: autopilot-driver.sh -f <feature> [-s <phase 2-9>] [-F] [dir]
#   -s  phase to (re-)enter after amending a stop — accepted only when the
#       artifacts' state satisfies that phase's entry precondition
#   -F  force: clear a stale lock/RUNNING marker

set -u

usage() { echo "usage: $0 -f <feature> [-s <phase 2-9>] [-F] [dir]" >&2; exit 2; }
die() { echo "autopilot-driver: $*" >&2; exit 2; }

FEATURE=''
START=2
FORCE=0
while getopts f:s:Fh opt; do
  case $opt in
    f) FEATURE=$OPTARG ;;
    s) START=$OPTARG ;;
    F) FORCE=1 ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))
ROOT=${1:-.}

[ -n "$FEATURE" ] || usage
printf '%s' "$FEATURE" | grep -Eq '^[a-z0-9][a-z0-9-]*$' \
  || die "feature must be kebab-case ([a-z0-9-]): '$FEATURE'"
case $START in 2|3|4|5|6|7|8|9) ;; *) die "-s must be 2-9" ;; esac
cd "$ROOT" || exit 2

# --- config: strict KEY='value' files, parsed (never sourced) ----------------
cfg_validate() { # $1 = file, $2 = whitespace-separated known keys
  known=$(printf '%s' "$2" | tr '\n' ' ')
  seen=' '
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|'#'*) continue ;; esac
    key=$(printf '%s' "$line" | sed -n "s/^\([A-Z_][A-Z_0-9]*\)='[^']*'[[:space:]]*\$/\1/p")
    [ -n "$key" ] || die "$1: malformed line (expected KEY='value'): $line"
    case " $known " in *" $key "*) ;; *) die "$1: unknown key '$key'" ;; esac
    case $seen in *" $key "*) die "$1: duplicate key '$key'" ;; esac
    seen="$seen$key "
  done < "$1"
}
cfg_get() { # $1 = file, $2 = key
  sed -n "s/^$2='\([^']*\)'[[:space:]]*\$/\1/p" "$1" | head -n 1
}
is_model_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]*$'; }
is_model_list() { # ids separated by single ASCII spaces — the exact grammar the
                  # dispatch loop consumes; a tab or a double space is NOT a list
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]*( [A-Za-z0-9][A-Za-z0-9._:/-]*)*$'
}
is_args() { # an option string: non-empty, starts with '-', allowed charset only
  printf '%s' "$1" | grep -Eq '^-[A-Za-z0-9 ._=:-]*$'
}
# The wall's path-entry grammar (R8-B1): entries separated by single spaces,
# each 'dir/' (prefix), '*suffix' (path suffix, no slash), or an exact path.
# ASCII only, never a leading '/' or '-', and never '..' — an entry that can
# match nothing on git's normalized paths must be refused, not kept.
WALL_ENTRY='(\*[A-Za-z0-9._-]+|[A-Za-z0-9._-][A-Za-z0-9._/-]*)'
is_path_list() {
  printf '%s' "$1" | grep -Eq "^${WALL_ENTRY}( ${WALL_ENTRY})*\$" || return 1
  case $1 in *..*) return 1 ;; esac
}
# Bounded decimal grammar: shell arithmetic has a finite range, and an
# out-of-range digit string WRAPS instead of failing — "all digits" is not
# "a safe integer". COUNTER_MAX and the {0,8} bound must move together.
COUNTER_MAX=999999999
is_count() { printf '%s' "$1" | grep -Eq '^[1-9][0-9]{0,8}$'; }

S=.ai/autopilot/$FEATURE
MODELS_ENV=.ai/autopilot/models.env
FLIGHT_ENV=$S/flight.env
WALL_ENV=.ai/wall.env

[ -f .ai/kit.json ] || die "no .ai/kit.json (not a kit install)"
profile=$(sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .ai/kit.json | head -n 1)
[ "$profile" = autopilot ] || die "active profile is '$profile', not autopilot (/switch-profile)"
[ -f "$MODELS_ENV" ] || die "$MODELS_ENV missing (/fly writes it)"
[ -f "$FLIGHT_ENV" ] || die "$FLIGHT_ENV missing (/fly writes it)"
[ -f "$WALL_ENV" ] || die "$WALL_ENV missing — the wall is versioned project config, one AP_WALL_TESTS='…' line naming the test paths; without it phases 4 and 8 cannot be judged (/fly writes it, autopilot.md § The wall)"

cfg_validate "$MODELS_ENV" 'AP_MODEL_REVIEW AP_MODEL_FLAGSHIP AP_MODEL_COSTEFF AP_MODEL_MID
AP_LADDER_FLAGSHIP AP_LADDER_COSTEFF AP_LADDER_MID AP_LADDER_REVIEW
AP_CLAUDE_ARGS AP_CODEX_ARGS'
cfg_validate "$FLIGHT_ENV" 'AP_ISSUE_REF'
cfg_validate "$WALL_ENV" 'AP_WALL_TESTS'

MODEL_REVIEW=$(cfg_get "$MODELS_ENV" AP_MODEL_REVIEW)
MODEL_FLAGSHIP=$(cfg_get "$MODELS_ENV" AP_MODEL_FLAGSHIP)
MODEL_COSTEFF=$(cfg_get "$MODELS_ENV" AP_MODEL_COSTEFF)
MODEL_MID=$(cfg_get "$MODELS_ENV" AP_MODEL_MID)
LADDER_FLAGSHIP=$(cfg_get "$MODELS_ENV" AP_LADDER_FLAGSHIP)
LADDER_COSTEFF=$(cfg_get "$MODELS_ENV" AP_LADDER_COSTEFF)
LADDER_MID=$(cfg_get "$MODELS_ENV" AP_LADDER_MID)
LADDER_REVIEW=$(cfg_get "$MODELS_ENV" AP_LADDER_REVIEW)
for v in "AP_MODEL_REVIEW=$MODEL_REVIEW" "AP_MODEL_FLAGSHIP=$MODEL_FLAGSHIP" \
         "AP_MODEL_COSTEFF=$MODEL_COSTEFF" "AP_MODEL_MID=$MODEL_MID"; do
  val=${v#*=}
  is_model_id "$val" \
    || die "models.env: ${v%%=*} missing or not a single valid model id ('$val')"
done
for v in "AP_LADDER_FLAGSHIP=$LADDER_FLAGSHIP" "AP_LADDER_COSTEFF=$LADDER_COSTEFF" \
         "AP_LADDER_MID=$LADDER_MID" "AP_LADDER_REVIEW=$LADDER_REVIEW"; do
  val=${v#*=}
  [ -z "$val" ] || is_model_list "$val" || die "models.env: ${v%%=*} is not a valid model list ('$val')"
done

# Permission policy: the per-project record in models.env, else the guarded
# default. Never read from the environment (ADR-0008 amendment: a bypass exists
# only as an explicit line in the machine binding).
CLAUDE_POLICY=$(cfg_get "$MODELS_ENV" AP_CLAUDE_ARGS)
CODEX_POLICY=$(cfg_get "$MODELS_ENV" AP_CODEX_ARGS)
[ -n "$CLAUDE_POLICY" ] || CLAUDE_POLICY='--permission-mode acceptEdits'
[ -n "$CODEX_POLICY" ] || CODEX_POLICY='--approve-for-me'
is_args "$CLAUDE_POLICY" || die "invalid AP_CLAUDE_ARGS ('$CLAUDE_POLICY')"
is_args "$CODEX_POLICY" || die "invalid AP_CODEX_ARGS ('$CODEX_POLICY')"

BASE_BRANCH=develop   # fixed by ADR-0008; not configurable
ISSUE_REF=$(cfg_get "$FLIGHT_ENV" AP_ISSUE_REF)
printf '%s' "$ISSUE_REF" | grep -Eq '^[A-Za-z0-9_#-]*$' \
  || die "flight.env: AP_ISSUE_REF has invalid characters ('$ISSUE_REF')"

# The wall's machine-readable half (ADR-0008, R8-B1): which paths hold tests in
# THIS project. Versioned — the same wall on every clone — and fail-closed:
# without a parseable value the flight does not start.
WALL_TESTS=$(cfg_get "$WALL_ENV" AP_WALL_TESTS)
is_path_list "$WALL_TESTS" || die "wall.env: AP_WALL_TESTS missing or not a valid path list ('$WALL_TESTS')"

# Test seams (binaries and caps only — never the permission policy).
CLAUDE_BIN=${AP_CLAUDE_BIN:-claude}
CODEX_BIN=${AP_CODEX_BIN:-codex}
GH_BIN=${AP_GH_BIN:-gh}
MAX_GATE_REJECTS=${AP_MAX_GATE_REJECTS:-2}   # the (N+1)th rejection on one gate stops
MAX_EDGES=${AP_MAX_EDGES:-6}                 # global backward-edge cap per flight
MAX_TRIES=${AP_MAX_TRIES:-3}                 # 1 attempt + 2 retries per model
for v in "AP_MAX_GATE_REJECTS=$MAX_GATE_REJECTS" "AP_MAX_EDGES=$MAX_EDGES" \
         "AP_MAX_TRIES=$MAX_TRIES"; do
  is_count "${v#*=}" || die "${v%%=*} must be a positive integer ('${v#*=}')"
done

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "not a git repo"
[ "$branch" = "feature/$FEATURE" ] || die "on '$branch', expected 'feature/$FEATURE'"
git show-ref --verify -q "refs/heads/$BASE_BRANCH" \
  || die "local branch '$BASE_BRANCH' missing (a tag is not a base) — its creation is a human act (ADR-0008)"
[ -z "$(git status --porcelain)" ] || die "working tree not clean"

mkdir -p "$S/logs" "$S/verdicts" "$S/probes"
if [ "$FORCE" -eq 1 ]; then rm -rf "$S/lock"; fi
mkdir "$S/lock" 2>/dev/null || die "$S/lock exists — another driver may be flying (rerun with -F if stale)"
printf '%s\n' "$$" > "$S/lock/pid"
echo RUNNING > "$S/status"

TESTPLAN=.ai/plans/$FEATURE.testplan.md
PLAN=.ai/plans/$FEATURE.md
ADR=.ai/plans/$FEATURE.adr.md
LAST_VERDICT=''
NOTES_FILE=''
EXPECTED_REJ=0
ENTRY_STATUS_ROW=''   # testplan Status row as the phase found it (blocked-producer backstop)
ENTRY_GREEN=0         # canonical GREEN rows on the testplan Log as the phase found them
ACCEPTED_HEAD=''      # HEAD of the last accepted phase — the only ref the ribbon may publish
ACCEPTED_SNAP=''      # that phase's pre-dispatch snapshot, for the publication-time ancestry check

# --- state helpers -----------------------------------------------------------
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$S/driver.log"; }

# Counters run in the PARENT shell only: stop_flight must be able to terminate
# the driver, and an exit inside $(...) would only kill the subshell — the
# flight would keep flying on a state it just declared corrupt.
read_int() { # $1 = state file -> RI; corrupt or out-of-range state is fatal,
             # never silently reset — the bounded grammar keeps every persisted
             # value inside the arithmetic range (an oversized digit string
             # would wrap to a small, reusable id instead of failing)
  if [ -f "$S/$1" ]; then RI=$(cat "$S/$1"); else RI=0; fi
  case $RI in 0) ;; *) is_count "$RI" || stop_flight "corrupt state: $S/$1 ('$RI')" ;; esac
}
bump() { # $1 = state file -> BUMPED; the increment must grow and stay in range
  read_int "$1"
  BUMPED=$((RI + 1))
  { [ "$BUMPED" -gt "$RI" ] && [ "$BUMPED" -le "$COUNTER_MAX" ]; } \
    || stop_flight "counter out of range: $S/$1 ('$RI')"
  printf '%s\n' "$BUMPED" > "$S/$1" || stop_flight "cannot write $S/$1"
}
show_int() { # report-context reader: tolerant, never recurses into stop_flight
  if [ -f "$S/$1" ]; then cat "$S/$1"; else echo 0; fi
}

write_report() { # $1 = final status line
  {
    printf '# Flight report — %s\n\n' "$FEATURE"
    printf '%s\n\n' "$1"
    printf 'Backward edges: %s/%s · gate rejections: 3:%s 5:%s 7:%s 9:%s\n\n' \
      "$(show_int edges)" "$MAX_EDGES" "$(show_int rej.3)" "$(show_int rej.5)" "$(show_int rej.7)" "$(show_int rej.9)"
    printf 'Artifacts: %s · %s · %s\n\n' "$ADR" "$TESTPLAN" "$PLAN"
    if [ -n "$LAST_VERDICT" ] && [ -f "$LAST_VERDICT" ]; then
      printf 'Last verdict (%s):\n\n```json\n' "$LAST_VERDICT"; cat "$LAST_VERDICT"; printf '\n```\n\n'
    fi
    printf '## Journey\n\n```\n'; cat "$S/driver.log"; printf '```\n'
  } > "$S/report.md"
}

stop_flight() { # $1 = reason
  log "STOP: $1"
  echo STOPPED > "$S/status"
  write_report "**STOPPED** — $1. Nothing was pushed. Amend, then relaunch the driver with -s <phase> (the entry precondition of that phase must hold)."
  echo "autopilot-driver: flight stopped — $1 (report: $S/report.md)" >&2
  exit 1
}
cleanup() { # EXIT: release the lock; an abnormal exit must not leave RUNNING behind
  rm -rf "$S/lock"
  if [ "$(cat "$S/status" 2>/dev/null)" = RUNNING ]; then
    echo STOPPED > "$S/status"
    write_report "**STOPPED** — the driver exited abnormally (see the journey tail). Nothing was pushed."
  fi
}
trap cleanup EXIT
trap 'stop_flight "interrupted"' INT TERM HUP

# --- verdict files: one closed flat-object grammar, matched and extracted as
# a single full-string ERE — never two independent regexes, so text inside
# "notes" can never shadow the routing fields. Notes forbid raw quotes,
# backslashes, and control bytes; extra keys, duplicate keys, or a second
# line (newline-terminated or not) fail the match.
NL='
'
VJ_RX='^\{[[:space:]]*"verdict"[[:space:]]*:[[:space:]]*"(approve|reject|blocked)"[[:space:]]*,[[:space:]]*"route"[[:space:]]*:[[:space:]]*"([a-z]+)"[[:space:]]*,[[:space:]]*"notes"[[:space:]]*:[[:space:]]*"([^"[:cntrl:]\\]*)"[[:space:]]*\}[[:space:]]*$'
verdict_parse() { # $1 = file -> V_VERDICT, V_ROUTE, V_NOTES; 1 on any deviation
  V_VERDICT=''; V_ROUTE=''; V_NOTES=''
  [ -f "$1" ] || return 1
  [ "$(wc -l < "$1")" -le 1 ] || return 1
  # The grammar below is matched on a shell variable, and command substitution
  # DROPS NUL bytes: a NUL inside "notes" — or inside a token — would vanish
  # before the ERE ever saw it, and [:cntrl:] would never fire. So the raw
  # file is rejected byte for byte first; only then is it read.
  LC_ALL=C tr -d '\000' < "$1" | cmp -s - "$1" || return 1
  VC=$(cat "$1")
  case $VC in *"$NL"*) return 1 ;; esac
  printf '%s' "$VC" | grep -Eq "$VJ_RX" || return 1
  V_VERDICT=$(printf '%s' "$VC" | sed -E "s/$VJ_RX/\1/")
  V_ROUTE=$(printf '%s' "$VC" | sed -E "s/$VJ_RX/\2/")
  V_NOTES=$(printf '%s' "$VC" | sed -E "s/$VJ_RX/\3/")
}

# --- artifact status parsing (anchored to the canonical rows) ----------------
status_line_is() { # $1 = file, $2 = ERE for the value — exactly one Status row,
                   # its value closed by end-of-line or a " — " annotation (the
                   # date on DONE), so APPROVED never matches "APPROVED junk"
                   # and READY never matches READYNESS
  [ -f "$1" ] || return 1
  [ "$(grep -cE '^(> )?\*\*Status:\*\*' "$1")" -eq 1 ] || return 1
  grep -qE "^(> )?\*\*Status:\*\*[[:space:]]+($2)( — .*)?\$" "$1"
}
status_row() { # the single canonical Status row, verbatim; 1 if not exactly one
  [ -f "$1" ] || return 1
  [ "$(grep -cE '^(> )?\*\*Status:\*\*' "$1")" -eq 1 ] || return 1
  grep -E '^(> )?\*\*Status:\*\*' "$1"
}
has_gate_row() { [ -f "$1" ] && grep -qE '^- \*\*Gate:\*\*' "$1"; }
GATE_ROW='^- \*\*Gate:\*\* APPROVED — [0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01]), all gate checks passed \(CLAUDE\.md, gate phase\)$'
gate_row_ok() { # exactly one Gate row, and it is the full canonical approved row
  [ -f "$1" ] || return 1
  [ "$(grep -cE '^- \*\*Gate:\*\*' "$1")" -eq 1 ] || return 1
  grep -qE "$GATE_ROW" "$1"
}
# Phase 8's durable completion signal: without it, "ready for 9" and "ready
# for 8" are observably identical and a direct -s 9 would skip implementation.
# The signal is a row ON THE LOG — not those bytes anywhere in the file: an
# inventory row, an example, or a manually misplaced line must not authorize
# phase 9. Append-only (a re-run after a phase-9 reject adds another row), so
# the predicate counts rows: at least one, never exactly one.
#
# TWO CONDITIONS, and the first one is structural — four review rounds showed
# that "recognize the row" alone is not decidable in Markdown:
#
#   1. POSITION. The row must be the file's LAST non-blank line. Phase 8 is
#      the last phase that writes before phase 9 reads, so the contract can
#      demand it (autopilot.md phase 8, the phase-8 prompt, the template).
#      A canonical row that IS the last line cannot be inert text: every
#      construct that could hide it — an HTML comment, a fenced block — has
#      to be closed after it, and a closer is itself a line, so the row would
#      not be last. This is the condition that does not depend on how much
#      Markdown the reader below knows.
#   2. SHAPE. Exactly one canonical Log heading, no section after it, and no
#      container left open at end of file. This is what makes "last line"
#      mean what it says, and it is what phases 2, 4 and 8 check on their own
#      output, before any row exists.
#
# The Log is NORMATIVE-LAST (autopilot.md, phase 2), and that is what makes
# its scope decidable. Earlier rounds tried to find where the section ENDS —
# first end-of-file, then "the next column-zero H1/H2" — and every heading
# form the predicate did not know (0-3-space ATX, Setext) became another way
# to sit outside the Log while counting as inside it. So the direction is
# inverted: the reader does not look for the end, it REFUSES an artifact that
# has anything after the Log. Missing a boundary would be a bypass; seeing
# one that is not there is a stop the operator can read and fix.
#
# WHAT THE READER MODELS — exactly this list. It is a bounded reader, not a
# Markdown parser, and what is not on the list is refused, never guessed:
#
#   - fenced blocks (``` / ~~~, 0-3 space indent): opaque — inside one,
#     nothing counts: no heading, no row, no comment. Closed only by
#     CommonMark's rule — same character, at least as long as the opener,
#     nothing but whitespace after it. A ``` line inside a ```` block, or a
#     closer carrying an info string, does NOT close: those are the exact
#     bytes that made an inert, fenced row count in the seventh review.
#   - HTML comments (<!-- … -->, ending at the first line containing -->):
#     opaque the same way. Modelled, not refused, because the shipped
#     template's own Log legitimately carries them.
#   - ATX headings (0-3 space indent, at most six #) and Setext underlines:
#     H1/H2 bound sections, deeper ones do not, so a phase may still
#     structure its own Log entries.
#
# REFUSED rather than modelled: any other line that starts with '<' (a raw
# HTML block — <div>, <script>, <![CDATA[ — would make the row inert), and a
# fenced block or comment still open at end of file (the file's structure is
# then undecidable). Condition 1 covers everything else: whatever construct a
# future reviewer invents, it has to be written after the row to hide it.
#
# That is also why phase 4 fences the RED output it pastes here (autopilot.md,
# phase 4): real test output carries ruler lines ("------") that Markdown
# reads as a Setext heading, and unfenced they would make an honest testplan
# malformed.
#
# One awk pass, and the canonical strings live in exactly one place. awk is
# POSIX, like the sed/grep the rest of the driver uses.
LOG_AWK='
function runlen(s, ch,   n) { n = 0; while (substr(s, n + 1, 1) == ch) n++; return n }
function blank(s) { return s ~ /^[ \t]*$/ }
BEGIN {
  GRX = "^- \\*\\*Implementation:\\*\\* GREEN — [0-9][0-9][0-9][0-9]-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01]), full suite \\+ typecheck \\(Implementer\\)$"
  fence = ""; flen = 0; comment = 0; html = 0
  head = 0; dup = 0; tail = 0; green = 0; para = 0; lastnb = ""
  openline = 0; htmlline = 0; dupline = 0; tailline = 0   # where a refusal starts
}
{
  line = $0
  if (!blank(line)) lastnb = line
  match(line, /^ */); ind = RLENGTH; body = substr(line, ind + 1)
  # opaque containers first: inside one, nothing counts
  if (comment) { if (index(line, "-->") > 0) comment = 0; para = 0; next }
  if (fence != "") {
    if (ind <= 3 && substr(body, 1, 1) == fence) {
      n = runlen(body, fence)
      if (n >= flen && blank(substr(body, n + 1))) { fence = ""; flen = 0 }
    }
    para = 0; next
  }
  ch = substr(body, 1, 1)
  if (ind <= 3 && (ch == "`" || ch == "~")) {
    n = runlen(body, ch)
    # a backtick fence may not carry a backtick in its info string
    if (n >= 3 && !(ch == "`" && index(substr(body, n + 1), "`") > 0)) {
      fence = ch; flen = n; openline = NR; para = 0; next
    }
  }
  if (ind <= 3 && substr(body, 1, 4) == "<!--") {
    if (index(body, "-->") == 0) { comment = 1; openline = NR }
    para = 0; next
  }
  if (ind <= 3 && ch == "<") { if (!htmlline) htmlline = NR; html = 1; para = 0; next }
  # ATX heading, 0-3 space indent, at most six #. H1/H2 bound sections;
  # deeper ones do not, so a phase may still structure its own Log entries.
  hn = 0
  if (ind <= 3) {
    h = body
    while (substr(h, 1, 1) == "#") { hn++; h = substr(h, 2) }
    if (hn > 6) hn = 0
    if (hn > 0 && h != "" && substr(h, 1, 1) != " " && substr(h, 1, 1) != "\t") hn = 0
  }
  if (hn > 0) {
    if (hn <= 2) {
      if (line == "## 6. Log (append-only)") { head++; if (head > 1) { if (!dupline) dupline = NR; dup = 1 } }
      else if (head > 0) { if (!tailline) tailline = NR; tail = 1 }
    }
    para = 0; next
  }
  # Setext underline: a heading only under a paragraph line — a ruler under a
  # list item or a blank line is a thematic break, not a section boundary.
  if (ind <= 3 && para && (body ~ /^-+[ \t]*$/ || body ~ /^=+[ \t]*$/)) {
    if (head > 0) { if (!tailline) tailline = NR; tail = 1 }
    para = 0; next
  }
  if (head > 0 && line ~ GRX) green++
  if (body == "" || body ~ /^([-*+]|[0-9]+[.)])([ \t]|$)/ || substr(body, 1, 1) == ">") para = 0
  else para = 1
}
END {
  shape = "ok"; bad = 0
  if (html) { shape = "html"; bad = htmlline }
  else if (comment) { shape = "opencomment"; bad = openline }
  else if (fence != "") { shape = "openfence"; bad = openline }
  else if (head == 0) shape = "nohead"
  else if (dup) { shape = "dup"; bad = dupline }
  else if (tail) { shape = "tail"; bad = tailline }
  printf "%s %d %d %d\n", shape, green, (lastnb ~ GRX) ? 1 : 0, bad
}'
log_scan() { # $1 = file -> LOG_SHAPE, LOG_GREEN, LOG_LAST, LOG_LINE (0 = no line
             # to point at); 1 when there is no file to read
  LOG_SHAPE=missing; LOG_GREEN=0; LOG_LAST=0; LOG_LINE=0
  [ -f "$1" ] || return 1
  scan=$(awk "$LOG_AWK" "$1") || return 1
  LOG_SHAPE=${scan%% *}; scan=${scan#* }
  LOG_GREEN=${scan%% *}; scan=${scan#* }
  LOG_LAST=${scan%% *}; LOG_LINE=${scan##* }
}
log_shape_ok() { log_scan "$1" && [ "$LOG_SHAPE" = ok ]; }
log_shape_why() { # the refusal in the operator's words, pointing at the line that
                  # starts it — never "the row is missing"
  log_scan "$1"
  at=''; [ "${LOG_LINE:-0}" -gt 0 ] && at=" (line $LOG_LINE)"
  case $LOG_SHAPE in
    ok)      echo '' ;;
    missing) echo "$1 is missing" ;;
    nohead)  echo "no canonical '## 6. Log (append-only)' heading (exactly one is required)" ;;
    dup)     echo "more than one canonical Log heading — 'the Log' must be one place$at" ;;
    tail)    echo "a section starts after the Log — it must be the file's last section (fence pasted output)$at" ;;
    html)    echo "a line starts with '<' — raw HTML is refused, never interpreted: fence it or reword it$at" ;;
    opencomment) echo "an HTML comment is opened and never closed (no '-->') — the file's structure is undecidable$at" ;;
    openfence)   echo "a fenced block is opened and never closed — a closing fence repeats the opening characters, at least as long, alone on its line$at" ;;
  esac
}
impl_green_count() { # canonical GREEN rows on the Log of a well-shaped testplan
  if log_shape_ok "$1"; then echo "$LOG_GREEN"; else echo 0; fi
}
impl_green() { # the phase-9 authorization: a canonical row on the Log AND the
               # file's last non-blank line is one (condition 1 above)
  log_shape_ok "$1" && [ "$LOG_GREEN" -ge 1 ] && [ "$LOG_LAST" -eq 1 ]
}
impl_green_why() { # assumes impl_green just failed on a well-shaped file
  if [ "$LOG_GREEN" -ge 1 ]; then
    echo "the Implementation GREEN row is not the testplan's last non-blank line — phase 8's proof is only a proof where nothing can be written after it (repair: autopilot.md § Repairing a refused Log)"
  else
    echo "no Implementation GREEN row on the testplan's canonical Log — phase 8 has not completed on this testplan"
  fi
}

# --- phase metadata ----------------------------------------------------------
phase_role() {
  case $1 in
    2) echo 'TestPlan Designer' ;;  3) echo 'TestPlan Reviewer' ;;
    4) echo 'Test Writer' ;;        5) echo 'Test Reviewer' ;;
    6) echo 'Handoff Planner' ;;    7) echo 'Plan Reviewer' ;;
    8) echo 'Implementer' ;;        9) echo 'Final Reviewer' ;;
  esac
}
phase_harness() { case $1 in 3|5|7|9) echo claude ;; *) echo codex ;; esac; }
phase_models() { # primary + ladder, space-separated
  case $1 in
    2|6) echo "$MODEL_FLAGSHIP $LADDER_FLAGSHIP" ;;
    4)   echo "$MODEL_COSTEFF $LADDER_COSTEFF" ;;
    8)   echo "$MODEL_MID $LADDER_MID" ;;
    *)   echo "$MODEL_REVIEW $LADDER_REVIEW" ;;
  esac
}
reject_routes() { # backward routes a REVIEWER may take
  case $1 in
    3) echo 'testplan' ;;
    5) echo 'tests testplan' ;;
    7) echo 'plan' ;;
    9) echo 'implementation plan' ;;
  esac
}
producer_route() { case $1 in 4) echo testplan ;; 8) echo plan ;; *) echo '' ;; esac; }
route_phase() { case $1 in testplan) echo 2 ;; tests) echo 4 ;; plan) echo 6 ;; implementation) echo 8 ;; esac; }

# --- the wall on the write-set (ADR-0008, R8-B1) -----------------------------
# The hard wall is not a prompt instruction here: after each attempt the driver
# measures WHAT the phase touched — the diff between the phase snapshot and
# HEAD; the clean-tree backstop makes that diff the attempt's whole write-set —
# and refuses the attempt on three edges: reviewers (3/5/7/9) write only the
# two flight artifacts, the Test Writer (4) writes only test paths and the
# testplan, the Implementer (8) never writes a test path. What counts as a
# test path is the project's recorded AP_WALL_TESTS; a path the driver cannot
# read (git had to quote it) is refused, never guessed. Phases 2 and 6 build
# single artifacts already pinned by their artifact backstops.
wall_is_test() { # $1 = path -> 0 when an AP_WALL_TESTS entry claims it. The
                 # list is walked as a string, never expanded unquoted: the
                 # shell's globber would turn a '*suffix' entry into whatever
                 # files happen to sit in the current directory, and the wall
                 # would silently depend on the repository's contents.
  wit_rest=$WALL_TESTS
  while [ -n "$wit_rest" ]; do
    e=${wit_rest%% *}
    case $wit_rest in *' '*) wit_rest=${wit_rest#* } ;; *) wit_rest='' ;; esac
    case $e in
      \**) case $1 in *"${e#\*}") return 0 ;; esac ;;   # '*suffix' claims by path suffix
      */)  case $1 in "$e"*)      return 0 ;; esac ;;   # 'dir/' claims by prefix
      *)   [ "$1" = "$e" ] && return 0 ;;               # exact path
    esac
  done
  return 1
}
wall_ok() { # $1 = phase, $2 = snapshot sha; WALL_WHY set on refusal
  WALL_WHY=''
  case $1 in 3|4|5|7|8|9) ;; *) return 0 ;; esac
  while IFS= read -r wp; do
    [ -n "$wp" ] || continue
    case $wp in
      \"*) WALL_WHY="phase $1 touched a path git had to quote ($wp) — the wall refuses what it cannot read"; return 1 ;;
    esac
    case $1 in
      3|5|7|9)
        if [ "$wp" != "$TESTPLAN" ] && [ "$wp" != "$PLAN" ]; then
          WALL_WHY="$(phase_role "$1") touched '$wp' — a reviewer writes only $TESTPLAN and $PLAN"
          return 1
        fi ;;
      4)
        if [ "$wp" != "$TESTPLAN" ] && ! wall_is_test "$wp"; then
          WALL_WHY="Test Writer touched '$wp' — outside the testplan and the recorded test paths ($WALL_ENV)"
          return 1
        fi ;;
      8)
        if [ "$wp" != "$TESTPLAN" ] && wall_is_test "$wp"; then
          WALL_WHY="Implementer touched test path '$wp' — the Implementer never touches tests"
          return 1
        fi ;;
    esac
  done <<WALL_EOF
$(git -c core.quotePath=false diff --name-only --no-renames "$2" HEAD)
WALL_EOF
  return 0
}

# Entry precondition: the artifacts on disk must justify launching this phase —
# EVERY input its contract consumes (existence, non-triviality, canonical
# lifecycle state), not just one status token. Checked before EVERY launch —
# first phase, routed re-entry, or -s relaunch — so no path (including the
# recovery interface) reaches a consumer ungated or with a missing input.
nontrivial() { [ -f "$1" ] && [ "$(wc -c < "$1")" -gt "$2" ]; }
adr_ok() { nontrivial "$ADR" 200; }
entry_ok() { # $1 = phase -> 0/1; REASON set on failure
  REASON=''
  case $1 in
    2) adr_ok || REASON="design record $ADR missing or trivial" ;;
    3) adr_ok && nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" DRAFT \
         || REASON="phase 3 judges a DRAFT inventory against the design record: need $ADR + a non-trivial DRAFT testplan" ;;
    4) nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" 'READY|REJECTED\([0-9]+\)' \
         || REASON="testplan missing, trivial, or not READY (or bounced REJECTED(n))" ;;
    5) nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" RED \
         || REASON="testplan missing, trivial, or not RED" ;;
    6) adr_ok && nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" APPROVED \
         || REASON="phase 6 plans from the gated testplan and the design record: need $ADR + testplan APPROVED" ;;
    7) adr_ok && nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" APPROVED \
         && nontrivial "$PLAN" 400 && status_line_is "$PLAN" RED && ! has_gate_row "$PLAN" \
         || REASON="phase 7 judges an ungated RED plan against the gated testplan and $ADR (phase 7 stamps the Gate itself)" ;;
    8) if ! { nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" APPROVED \
              && nontrivial "$PLAN" 400 && status_line_is "$PLAN" RED && gate_row_ok "$PLAN"; }; then
         REASON="need testplan APPROVED + plan RED + exactly one canonical approved Gate row"
       elif ! log_shape_ok "$TESTPLAN"; then
         REASON="the testplan Log is malformed, so phase 8 could not leave its proof there: $(log_shape_why "$TESTPLAN") (repair: autopilot.md § Repairing a refused Log)"
       fi ;;
    9) if ! { adr_ok && nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" APPROVED \
              && nontrivial "$PLAN" 400 && status_line_is "$PLAN" RED && gate_row_ok "$PLAN"; }; then
         REASON="phase 9 judges the implementation against plan + design record: need $ADR + testplan APPROVED + gated RED plan"
       elif ! log_shape_ok "$TESTPLAN"; then
         REASON="the testplan Log is malformed, so no row in it proves anything: $(log_shape_why "$TESTPLAN") (repair: autopilot.md § Repairing a refused Log)"
       elif ! impl_green "$TESTPLAN"; then
         REASON=$(impl_green_why)
       fi ;;
  esac
  [ -z "$REASON" ]
}

# Artifact-on-disk backstop: after the phase, its output must exist, be
# non-trivial, and carry the canonical state its verdict/route pair claims —
# on the reject side too, so the durable record never denies a rejection.
# A BLOCKED producer is checked as strictly as a working one, on its INPUT:
# a stop is exactly when the artifacts become the operator's recovery
# interface, so they must still say what the lifecycle and the route say.
# ENTRY_STATUS_ROW / ENTRY_GREEN are the phase's entry snapshot (run_phase).
artifact_ok() { # $1 = phase, $2 = route
  case $1 in
    2) [ -f "$TESTPLAN" ] && [ "$(wc -c < "$TESTPLAN")" -gt 400 ] && status_line_is "$TESTPLAN" DRAFT \
         && log_shape_ok "$TESTPLAN" ;;  # the Log every later phase appends to: once, and last
    3) if [ "$2" = proceed ]; then status_line_is "$TESTPLAN" READY
       else status_line_is "$TESTPLAN" DRAFT; fi ;;
    4) if [ "$2" = testplan ]; then   # blocked: the READY/REJECTED(n) input must survive untouched
         nontrivial "$TESTPLAN" 400 && [ "$(status_row "$TESTPLAN")" = "$ENTRY_STATUS_ROW" ] \
           && log_shape_ok "$TESTPLAN" && [ "$(impl_green_count "$TESTPLAN")" -eq "$ENTRY_GREEN" ]
       else status_line_is "$TESTPLAN" RED; fi ;;
    5) if [ "$2" = proceed ]; then status_line_is "$TESTPLAN" APPROVED
       else status_line_is "$TESTPLAN" "REJECTED\($EXPECTED_REJ\)"; fi ;;
    6) [ -f "$PLAN" ] && [ "$(wc -c < "$PLAN")" -gt 400 ] && status_line_is "$PLAN" RED \
         && ! has_gate_row "$PLAN" ;;   # the Plan Reviewer stamps the Gate, never the planner
    7) if [ "$2" = proceed ]; then gate_row_ok "$PLAN"
       else status_line_is "$PLAN" RED && ! has_gate_row "$PLAN"; fi ;;
    8) if [ "$2" = plan ]; then   # blocked: gated inputs intact, and no GREEN row claimed
         nontrivial "$TESTPLAN" 400 && status_line_is "$TESTPLAN" APPROVED \
           && nontrivial "$PLAN" 400 && status_line_is "$PLAN" RED && gate_row_ok "$PLAN" \
           && log_shape_ok "$TESTPLAN" && [ "$(impl_green_count "$TESTPLAN")" -eq "$ENTRY_GREEN" ]
       else # the phase left a NEW row, and left it where it proves something
            [ "$(impl_green_count "$TESTPLAN")" -gt "$ENTRY_GREEN" ] && impl_green "$TESTPLAN"; fi ;;
    9) if [ "$2" = proceed ]; then status_line_is "$PLAN" DONE
       else status_line_is "$PLAN" RED && gate_row_ok "$PLAN"; fi ;;
  esac
}

# --- prompt building ---------------------------------------------------------
phase_task() { # $1 = phase, $2 = verdict path, $3 = notes file ('' if none)
  notes=''
  [ -n "$3" ] && notes="A previous verdict bounced this work back to you — read the notes in $3 and answer them point by point in the testplan Log. "
  case $1 in
    2) printf '%sInput: the design record %s. Produce %s from .ai/templates/test_plan_template.md per your phase contract: the full test-case inventory, the canonical "> **Status:** DRAFT" line, the template'"'"'s Log heading "## 6. Log (append-only)" kept verbatim, exactly once, and LAST — no section may follow it (every later phase appends under it), your Log entry. Commit when done.' "$notes" "$ADR" "$TESTPLAN" ;;
    3) printf 'Judge %s against %s and the repository, per your phase contract. Approve: set the canonical Status line to READY, append your Log entry, commit. Reject: append point-by-point notes to the Log, commit. Then write your routed verdict to %s as compact single-line JSON — exactly {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}, these three keys, one line, nothing else in the file; approve pairs only with route "proceed", reject only with "testplan".' "$TESTPLAN" "$ADR" "$2" ;;
    4) printf '%sInput: the READY testplan %s. Transcribe the inventory into test code per your phase contract — no spec decisions. Write only test files and the testplan: the driver refuses any other path in your diff. Run the focused tests, verify RED mechanically, append the RED output to the Log INSIDE a fenced block (```) — unfenced output can carry ruler lines that Markdown reads as a new section, which would malform the testplan — set the canonical Status line to RED, commit. If the inventory is unworkable (missing/ambiguous expected value), do NOT guess: log the gap, commit, and write exactly {"verdict":"blocked","route":"testplan","notes":"<why>"} to %s — one line, nothing else in the file.' "$notes" "$TESTPLAN" "$2" ;;
    5) printf 'Run the six-point test gate on the RED tests against %s, per your phase contract. Approve: canonical Status line to APPROVED, Log, commit. Reject: set the canonical Status line to REJECTED(%s) — this is rejection number %s on this gate — point-by-point Log notes, commit. Then write your routed verdict to %s as compact single-line JSON — exactly {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}, one line, nothing else in the file; approve pairs only with route "proceed"; reject pairs with "tests" (transcription faults) or "testplan" (inventory faults).' "$TESTPLAN" "$EXPECTED_REJ" "$EXPECTED_REJ" "$2" ;;
    6) printf '%sInput: the APPROVED testplan %s and the design record %s. Produce the implementation plan %s from .ai/templates/plan_template.md per your phase contract: signatures copied verbatim, constraints derived, Source testplan row present, canonical "> **Status:** RED" line, and NO Gate row (the Plan Reviewer stamps it). Append your Log entry to the testplan, commit.' "$notes" "$TESTPLAN" "$ADR" "$PLAN" ;;
    7) printf 'Judge the plan %s against the gated testplan %s and the design record %s, per your phase contract. Approve: add the canonical row "- **Gate:** APPROVED — <YYYY-MM-DD>, all gate checks passed (CLAUDE.md, gate phase)" to the plan §3, Log entry in the testplan, commit. Reject: Log notes, commit. Then write your routed verdict to %s as compact single-line JSON — exactly {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}, one line, nothing else in the file; approve pairs only with route "proceed", reject only with "plan".' "$PLAN" "$TESTPLAN" "$ADR" "$2" ;;
    8) printf '%sYou are governed by AGENTS.md. Read the gated plan %s and implement the minimum code to turn the listed RED tests green: run the focused tests while iterating, then the full suite and typecheck. Never touch test files. When green: append the canonical row "- **Implementation:** GREEN — <YYYY-MM-DD>, full suite + typecheck (Implementer)" to the testplan Log — the section under the heading "## 6. Log (append-only)", which is the file'"'"'s last section: nowhere else, never under a heading of your own, never inside a fenced block or an HTML comment — and write it as the FILE'"'"'S LAST NON-BLANK LINE: anything else you log for this phase goes before it, nothing at all after it (a row nothing follows cannot be inert text — that is what makes it a proof). Then commit everything. If the plan cannot be implemented as written, do NOT improvise and do NOT write the GREEN row: log the reason in the testplan Log, commit, and write exactly {"verdict":"blocked","route":"plan","notes":"<why>"} to %s — one line, nothing else in the file.' "$notes" "$PLAN" "$2" ;;
    9) printf 'Final review, per your phase contract: judge the implementation against the plan %s AND the design record %s. Full suite, typecheck, lint, format:check, the shared review checklist. You never edit code: your write-set is the plan and the testplan only — the driver refuses any other path in your diff. Approve: set the plan canonical Status line to DONE with the date, Log entry, commit; if tracker tools are available move the issue %s to review, else propose the move in your notes. Reject: Log notes, commit. Then write your routed verdict to %s as compact single-line JSON — exactly {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}, one line, nothing else in the file; approve pairs only with route "proceed"; reject pairs with "implementation" (code fixes) or "plan" (structural faults). New-scope findings become proposed issues in your notes, never fixes in this flight.' "$PLAN" "$ADR" "${ISSUE_REF:-<none>}" "$2" ;;
  esac
}

build_prompt() { # $1 phase, $2 role, $3 probe, $4 verdict path, $5 notes file
  printf 'PREFLIGHT — before anything else: read the file %s with your file tools and open your final reply with the line: PREFLIGHT: <its exact content>. If your tools do not work, reply "PREFLIGHT: FAIL <reason>" and stop.\n\nYou are the %s of the autopilot profile — phase %s of the unattended flight for feature "%s". Work from the repository root. Read in order: .ai/process/autopilot.md (your contract — follow your phase section exactly), CLAUDE.md, .ai/PROJECT_ARCHITECTURE.md, then your inputs. Commit messages: semantic prefix%s.\n\n%s\n' \
    "$3" "$2" "$1" "$FEATURE" \
    "${ISSUE_REF:+, and every commit message must reference $ISSUE_REF}" \
    "$(phase_task "$1" "$4" "$5")"
}

# --- phase execution ---------------------------------------------------------
run_phase() { # $1 = phase; sets ROUTE on success, stops the flight otherwise
  p=$1
  role=$(phase_role "$p")
  harness=$(phase_harness "$p")
  models=$(phase_models "$p")
  is_reviewer=0; case $p in 3|5|7|9) is_reviewer=1 ;; esac
  EXPECTED_REJ=0
  if [ "$is_reviewer" -eq 1 ]; then
    read_int "rej.$p"; EXPECTED_REJ=$((RI + 1))
  fi
  # Entry snapshot of the inputs a producer may not silently alter. Taken once
  # per phase: a failed attempt is reset to the same snapshot, so it holds for
  # every try on every ladder rung.
  ENTRY_STATUS_ROW=$(status_row "$TESTPLAN" || :)
  ENTRY_GREEN=$(impl_green_count "$TESTPLAN")

  for model in $models; do
    tries=0
    while [ "$tries" -lt "$MAX_TRIES" ]; do
      tries=$((tries + 1))
      bump dispatch; d=$BUMPED
      probe=$S/probes/p$p.d$d
      verdict=$S/verdicts/phase$p.d$d.json
      logf=$S/logs/phase$p.d$d.log
      rm -f "$verdict"   # never let a stale file pass for this dispatch's verdict
      nonce=$(od -An -N8 -tx8 /dev/urandom | tr -d ' \n')
      printf '%s\n' "$nonce" > "$probe"
      snap=$(git rev-parse HEAD)
      log "phase $p ($role) — dispatch $d, model $model, try $tries/$MAX_TRIES"

      prompt=$(build_prompt "$p" "$role" "$probe" "$verdict" "$NOTES_FILE")
      if [ "$harness" = claude ]; then
        # shellcheck disable=SC2086
        "$CLAUDE_BIN" -p $CLAUDE_POLICY --model "$model" "$prompt" > "$logf" 2>&1
      else
        # shellcheck disable=SC2086
        "$CODEX_BIN" exec $CODEX_POLICY -m "$model" "$prompt" > "$logf" 2>&1
      fi
      rc=$?

      # Branch integrity before anything else: if the phase left the feature
      # branch or rewrote its history, the reset-based retry recovery and the
      # commit checks below would run against the wrong ref — stop, honestly.
      [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "feature/$FEATURE" ] \
        || stop_flight "phase $p left branch feature/$FEATURE (HEAD is now '$(git rev-parse --abbrev-ref HEAD 2>/dev/null)') — repository state needs operator inspection"
      git merge-base --is-ancestor "$snap" HEAD 2>/dev/null \
        || stop_flight "phase $p rewrote history: snapshot $snap is no longer an ancestor of HEAD — operator inspection required"

      fail=''
      grep -qF "PREFLIGHT: $nonce" "$logf" || fail='preflight line missing or wrong'
      [ -z "$fail" ] && grep -q 'PREFLIGHT: FAIL' "$logf" && fail='phase reported PREFLIGHT: FAIL'
      [ -z "$fail" ] && [ "$rc" -ne 0 ] && fail="harness exit $rc"

      route=proceed
      if [ -z "$fail" ]; then
        if [ -f "$verdict" ]; then
          if verdict_parse "$verdict"; then
            v=$V_VERDICT; route=$V_ROUTE
            if [ "$is_reviewer" -eq 1 ]; then
              case $v in
                approve) [ "$route" = proceed ] || fail="verdict approve with route '$route'" ;;
                reject)  echo " $(reject_routes "$p") " | grep -qF " $route " \
                           || fail="verdict reject with invalid route '$route' for phase $p" ;;
                *) fail="invalid reviewer verdict '$v'" ;;
              esac
            else
              case $v in
                blocked) [ "$route" = "$(producer_route "$p")" ] \
                           || fail="blocked producer with invalid route '$route' for phase $p" ;;
                *) fail="invalid producer verdict '$v' (only 'blocked' may be written)" ;;
              esac
            fi
          else
            fail='verdict file is not the prescribed single-line JSON'
          fi
        elif [ "$is_reviewer" -eq 1 ]; then
          fail='reviewer ended without a verdict file'
        fi
      fi
      [ -z "$fail" ] && { artifact_ok "$p" "$route" || fail='expected artifact/status missing, trivial, or malformed for this route'; }
      [ -z "$fail" ] && [ "$(git rev-parse HEAD)" = "$snap" ] && fail='no commit (HEAD did not advance)'
      [ -z "$fail" ] && [ -n "$(git status --porcelain)" ] && fail='working tree not clean after the phase'
      [ -z "$fail" ] && { wall_ok "$p" "$snap" || fail="wall: $WALL_WHY"; }
      if [ -z "$fail" ]; then
        # every commit of the phase carries the semantic prefix and the tracker
        # reference — the audit trail holds commit by commit, not in aggregate
        for c in $(git rev-list "$snap..HEAD"); do
          git log -1 --format=%s "$c" | grep -qE '^(feat|fix|refactor|docs|test|chore)(\([^)]*\))?!?: ' \
            || { fail="commit ${c} lacks a semantic prefix"; break; }
          if [ -n "$ISSUE_REF" ]; then
            git log -1 --format=%B "$c" | grep -qF "$ISSUE_REF" \
              || { fail="commit ${c} missing tracker reference '$ISSUE_REF'"; break; }
          fi
        done
      fi

      if [ -z "$fail" ]; then
        [ -f "$verdict" ] && LAST_VERDICT=$verdict
        ROUTE=$route
        # The reviewed commit, pinned: the ribbon publishes THIS sha, never
        # "whatever feature/<f> points at by then" (a surviving child of the
        # harness can still move a ref after the checks above have run).
        ACCEPTED_HEAD=$(git rev-parse HEAD)
        ACCEPTED_SNAP=$snap
        log "phase $p ok — route: $route"
        return 0
      fi

      log "phase $p attempt failed: $fail (log: $logf)"
      git reset --hard "$snap" >/dev/null 2>&1
      git clean -fd >/dev/null 2>&1
      rm -f "$verdict"
    done
    log "model $model exhausted its $MAX_TRIES tries on phase $p — next ladder rung"
  done
  stop_flight "phase $p ($role): every model on the ladder failed its preflight/backstops"
}

# --- the flight --------------------------------------------------------------
log "flight start — feature $FEATURE, entering phase $START (caps: $MAX_GATE_REJECTS/gate, $MAX_EDGES edges; policies: claude '$CLAUDE_POLICY', codex '$CODEX_POLICY')"
PHASE=$START
while :; do
  entry_ok "$PHASE" \
    || stop_flight "phase $PHASE entry precondition failed: $REASON"
  run_phase "$PHASE"
  if [ "$ROUTE" = proceed ]; then
    NOTES_FILE=''
    if [ "$PHASE" -eq 9 ]; then break; fi
    PHASE=$((PHASE + 1))
    continue
  fi
  # backward edge
  bump edges; edges=$BUMPED
  [ "$edges" -le "$MAX_EDGES" ] || stop_flight "global cap: backward edge $edges exceeds $MAX_EDGES"
  case $PHASE in
    3|5|7|9)
      bump "rej.$PHASE"; r=$BUMPED
      [ "$r" -le "$MAX_GATE_REJECTS" ] || stop_flight "gate cap: rejection $r on gate $PHASE exceeds $MAX_GATE_REJECTS"
      ;;
  esac
  NOTES_FILE=$LAST_VERDICT
  log "backward edge $edges/$MAX_EDGES: phase $PHASE -> $(route_phase "$ROUTE") (route: $ROUTE)"
  PHASE=$(route_phase "$ROUTE")
done

# --- the ribbon: push + draft PR ---------------------------------------------
log "phase 9 approved — pushing and opening the draft PR"
# The published ref must BE the reviewed commit — not merely the branch that
# carried it. Between phase 9's checks and this push a surviving child of the
# harness (or any concurrent mutation) can still move the ref, so all five
# hold or nothing is pushed: right branch, clean tree, HEAD == the accepted
# sha, the branch ref == the accepted sha, and the phase snapshot still an
# ancestor. Then that sha is pushed explicitly, by object, not by name.
[ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = "feature/$FEATURE" ] \
  || stop_flight "not on feature/$FEATURE at publication time — refusing to push"
[ -z "$(git status --porcelain)" ] \
  || stop_flight "working tree not clean at publication time — refusing to push"
[ -n "$ACCEPTED_HEAD" ] \
  || stop_flight "no accepted phase 9 commit recorded — refusing to push"
[ "$(git rev-parse HEAD 2>/dev/null)" = "$ACCEPTED_HEAD" ] \
  || stop_flight "HEAD moved after the accepted final review (reviewed $ACCEPTED_HEAD, now $(git rev-parse HEAD 2>/dev/null)) — refusing to push"
[ "$(git rev-parse "refs/heads/feature/$FEATURE" 2>/dev/null)" = "$ACCEPTED_HEAD" ] \
  || stop_flight "feature/$FEATURE no longer points at the reviewed commit $ACCEPTED_HEAD — refusing to push"
git merge-base --is-ancestor "$ACCEPTED_SNAP" "$ACCEPTED_HEAD" 2>/dev/null \
  || stop_flight "history under the reviewed commit was rewritten — refusing to push"
git push origin "$ACCEPTED_HEAD:refs/heads/feature/$FEATURE" >> "$S/driver.log" 2>&1 \
  || stop_flight "git push failed — nothing was published; branch intact locally (see driver.log)"
# Upstream tracking is a convenience for the operator, never a flight outcome:
# pushing by object cannot set it, so it is set after the fact and never fatal.
git branch --set-upstream-to="origin/feature/$FEATURE" "feature/$FEATURE" >> "$S/driver.log" 2>&1 || :

verdict_parse "$LAST_VERDICT" || :   # -> V_NOTES ('' if the file went away)
{
  printf 'Autopilot flight — feature `%s`%s\n\n' "$FEATURE" "${ISSUE_REF:+ (${ISSUE_REF})}"
  printf '## Summary (from the plan)\n\n'
  sed -n '/^## 1\. Goal/,/^## /p' "$PLAN" | sed '1d;/^## /d' | head -n 12
  printf '\n## Flight\n\n'
  printf 'Design record: `%s` · testplan: `%s` · plan: `%s`\n' "$ADR" "$TESTPLAN" "$PLAN"
  printf 'Backward edges: %s/%s · gate rejections: 3:%s 5:%s 7:%s 9:%s\n\n' \
    "$(show_int edges)" "$MAX_EDGES" "$(show_int rej.3)" "$(show_int rej.5)" "$(show_int rej.7)" "$(show_int rej.9)"
  printf 'Final review notes: %s\n\n' "$V_NOTES"
  printf 'Opened by the autopilot driver. Promotion from draft, merge, and issue closure are human acts.\n'
} > "$S/pr-body.md"

if pr_url=$("$GH_BIN" pr create --draft --base "$BASE_BRANCH" --head "feature/$FEATURE" \
      --title "feat: $FEATURE${ISSUE_REF:+ ($ISSUE_REF)}" --body-file "$S/pr-body.md" 2>>"$S/driver.log"); then
  echo DONE > "$S/status"
  write_report "**DONE** — the flight completed phase 9. Draft PR: $pr_url
Check the tracker: the Final Reviewer moves the issue to review when it has tracker tools — otherwise its notes propose the move; cross-link issue and PR."
  log "flight done — report: $S/report.md"
  exit 0
else
  echo PUSHED > "$S/status"
  write_report "**PUSHED** — the branch is pushed, but the draft PR could NOT be opened (see driver.log). Finish publication by hand: open a draft PR against '$BASE_BRANCH' using $S/pr-body.md, move the tracker issue to review, cross-link both."
  log "flight pushed WITHOUT a PR — operator completes publication (report: $S/report.md)"
  echo "autopilot-driver: pushed, PR not opened — see $S/report.md" >&2
  exit 1
fi

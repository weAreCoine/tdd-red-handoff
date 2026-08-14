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
# not code: they are parsed key by key against a strict grammar, never sourced.
#
# Permission policy (ADR-0008 amendments): producers run codex in its
# workspace-write sandbox with automatic approvals; reviewers run claude with
# the operator's Claude Code sandbox plus acceptEdits. A bypass policy is never
# a silent default — it must be recorded in models.env by the operator.
#
# The base branch is `develop`, fixed by ADR-0008 — not configurable.
#
# State lives under .ai/autopilot/<feature>/ (gitignored). Terminal statuses:
#   DONE     pushed and draft PR opened                      exit 0
#   PUSHED   pushed, PR NOT opened — operator completes      exit 1
#   STOPPED  caps / preflight / git failure — nothing pushed exit 1
# Exit 2 = usage / precondition failure (no state written).
#
# Usage: autopilot-driver.sh -f <feature> [-s <phase 2-9>] [-F] [dir]
#   -s  phase to (re-)enter — operator relaunch after amending a stop
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

# --- config: strict KEY='value' lines, parsed (never sourced) ----------------
cfg_get() { # $1 = file, $2 = key
  sed -n "s/^$2='\([^']*\)'[[:space:]]*\$/\1/p" "$1" | head -n 1
}
is_model_list() { # every space-separated token is a plausible CLI model id
  [ -n "$1" ] || return 1
  for t in $1; do
    printf '%s' "$t" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:/-]*$' || return 1
  done
}
is_args() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9 ._=:-]*$'; }

S=.ai/autopilot/$FEATURE
MODELS_ENV=.ai/autopilot/models.env
FLIGHT_ENV=$S/flight.env

[ -f .ai/kit.json ] || die "no .ai/kit.json (not a kit install)"
profile=$(sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .ai/kit.json | head -n 1)
[ "$profile" = autopilot ] || die "active profile is '$profile', not autopilot (/switch-profile)"
[ -f "$MODELS_ENV" ] || die "$MODELS_ENV missing (/fly writes it)"
[ -f "$FLIGHT_ENV" ] || die "$FLIGHT_ENV missing (/fly writes it)"

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
  is_model_list "$val" && [ "${val##* }" = "$val" ] \
    || die "models.env: ${v%%=*} missing or not a single valid model id ('$val')"
done
for v in "AP_LADDER_FLAGSHIP=$LADDER_FLAGSHIP" "AP_LADDER_COSTEFF=$LADDER_COSTEFF" \
         "AP_LADDER_MID=$LADDER_MID" "AP_LADDER_REVIEW=$LADDER_REVIEW"; do
  val=${v#*=}
  [ -z "$val" ] || is_model_list "$val" || die "models.env: ${v%%=*} is not a valid model list ('$val')"
done

# Permission policy: env (test seam) > models.env record > sandboxed default.
CLAUDE_POLICY=${AP_CLAUDE_ARGS:-$(cfg_get "$MODELS_ENV" AP_CLAUDE_ARGS)}
CODEX_POLICY=${AP_CODEX_ARGS:-$(cfg_get "$MODELS_ENV" AP_CODEX_ARGS)}
[ -n "$CLAUDE_POLICY" ] || CLAUDE_POLICY='--permission-mode acceptEdits'
[ -n "$CODEX_POLICY" ] || CODEX_POLICY='--approve-for-me'
is_args "$CLAUDE_POLICY" || die "invalid AP_CLAUDE_ARGS ('$CLAUDE_POLICY')"
is_args "$CODEX_POLICY" || die "invalid AP_CODEX_ARGS ('$CODEX_POLICY')"

BASE_BRANCH=develop   # fixed by ADR-0008; not configurable
ISSUE_REF=$(cfg_get "$FLIGHT_ENV" AP_ISSUE_REF)
printf '%s' "$ISSUE_REF" | grep -Eq '^[A-Za-z0-9_#-]*$' \
  || die "flight.env: AP_ISSUE_REF has invalid characters ('$ISSUE_REF')"

CLAUDE_BIN=${AP_CLAUDE_BIN:-claude}
CODEX_BIN=${AP_CODEX_BIN:-codex}
GH_BIN=${AP_GH_BIN:-gh}
MAX_GATE_REJECTS=${AP_MAX_GATE_REJECTS:-2}   # the (N+1)th rejection on one gate stops
MAX_EDGES=${AP_MAX_EDGES:-6}                 # global backward-edge cap per flight
MAX_TRIES=${AP_MAX_TRIES:-3}                 # 1 attempt + 2 retries per model

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || die "not a git repo"
[ "$branch" = "feature/$FEATURE" ] || die "on '$branch', expected 'feature/$FEATURE'"
git rev-parse --verify -q "$BASE_BRANCH" >/dev/null \
  || die "base branch '$BASE_BRANCH' missing — its creation is a human act (ADR-0008)"
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

# --- state helpers -----------------------------------------------------------
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$S/driver.log"; }

read_int() { # $1 = state file; corrupt state is fatal, never silently reset
  if [ -f "$S/$1" ]; then c=$(cat "$S/$1"); else c=0; fi
  case $c in ''|*[!0-9]*) stop_flight "corrupt state: $S/$1 ('$c')" ;; esac
  printf '%s' "$c"
}
bump() { c=$(($(read_int "$1") + 1)); echo "$c" > "$S/$1"; printf '%s' "$c"; }
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
  write_report "**STOPPED** — $1. Nothing was pushed. Amend, then relaunch the driver with -s <phase>."
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

json_field() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1; }

# --- artifact status parsing (anchored to the canonical rows) ----------------
status_line_is() { # $1 = file, $2 = expected status value
  [ -f "$1" ] || return 1
  n=$(grep -cE '^(> )?\*\*Status:\*\*' "$1" || true)
  [ "$n" -eq 1 ] || return 1
  grep -qE "^(> )?\*\*Status:\*\*[[:space:]]*$2" "$1"
}
has_status_line() { [ -f "$1" ] && [ "$(grep -cE '^(> )?\*\*Status:\*\*' "$1" || true)" -eq 1 ]; }
has_gate_row() { [ -f "$1" ] && grep -qE '^- \*\*Gate:\*\* APPROVED' "$1"; }

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

# Artifact-on-disk backstop: the phase's expected output exists, is non-trivial,
# and carries the canonical status/gate row the chapter prescribes.
artifact_ok() { # $1 = phase, $2 = route
  case $1 in
    2) [ -f "$TESTPLAN" ] && [ "$(wc -c < "$TESTPLAN")" -gt 400 ] && has_status_line "$TESTPLAN" ;;
    3) [ "$2" != proceed ] || status_line_is "$TESTPLAN" READY ;;
    4) [ "$2" = testplan ] || status_line_is "$TESTPLAN" RED ;;
    5) [ "$2" != proceed ] || status_line_is "$TESTPLAN" APPROVED ;;
    6) [ -f "$PLAN" ] && [ "$(wc -c < "$PLAN")" -gt 400 ] && has_status_line "$PLAN" \
         && ! has_gate_row "$PLAN" ;;   # the Plan Reviewer stamps the Gate, never the planner
    7) [ "$2" != proceed ] || has_gate_row "$PLAN" ;;
    8) : ;;
    9) [ "$2" != proceed ] || status_line_is "$PLAN" DONE ;;
  esac
}

# --- prompt building ---------------------------------------------------------
phase_task() { # $1 = phase, $2 = verdict path, $3 = notes file ('' if none)
  notes=''
  [ -n "$3" ] && notes="A previous verdict bounced this work back to you — read the notes in $3 and answer them point by point in the testplan Log. "
  case $1 in
    2) printf '%sInput: the design record %s. Produce %s from .ai/templates/test_plan_template.md per your phase contract: the full test-case inventory, the canonical "> **Status:** DRAFT" line, your Log entry. Commit when done.' "$notes" "$ADR" "$TESTPLAN" ;;
    3) printf 'Judge %s against %s and the repository, per your phase contract. Approve: set the canonical Status line to READY, append your Log entry, commit. Reject: append point-by-point notes to the Log, commit. Then write your routed verdict as single-line JSON to %s — {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}; approve pairs only with route "proceed", reject only with "testplan".' "$TESTPLAN" "$ADR" "$2" ;;
    4) printf '%sInput: the READY testplan %s. Transcribe the inventory into test code per your phase contract — no spec decisions. Run the focused tests, verify RED mechanically, append the RED output to the Log, set the canonical Status line to RED, commit. If the inventory is unworkable (missing/ambiguous expected value), do NOT guess: log the gap, commit, and write {"verdict":"blocked","route":"testplan","notes":"<why>"} to %s.' "$notes" "$TESTPLAN" "$2" ;;
    5) printf 'Run the six-point test gate on the RED tests against %s, per your phase contract. Approve: canonical Status line to APPROVED, Log, commit. Reject: Status REJECTED(n), point-by-point Log notes, commit. Then write your routed verdict as single-line JSON to %s — approve pairs only with route "proceed"; reject pairs with "tests" (transcription faults) or "testplan" (inventory faults).' "$TESTPLAN" "$2" ;;
    6) printf '%sInput: the APPROVED testplan %s and the design record %s. Produce the implementation plan %s from .ai/templates/plan_template.md per your phase contract: signatures copied verbatim, constraints derived, Source testplan row present, canonical "> **Status:** RED" line, and NO Gate row (the Plan Reviewer stamps it). Append your Log entry to the testplan, commit.' "$notes" "$TESTPLAN" "$ADR" "$PLAN" ;;
    7) printf 'Judge the plan %s against the gated testplan %s and the design record %s, per your phase contract. Approve: add the canonical row "- **Gate:** APPROVED — <date>, all gate checks passed (CLAUDE.md, gate phase)" to the plan §3, Log entry in the testplan, commit. Reject: Log notes, commit. Then write your routed verdict as single-line JSON to %s — approve pairs only with route "proceed", reject only with "plan".' "$PLAN" "$TESTPLAN" "$ADR" "$2" ;;
    8) printf '%sYou are governed by AGENTS.md. Read the gated plan %s and implement the minimum code to turn the listed RED tests green: run the focused tests while iterating, then the full suite and typecheck. Never touch test files. Commit when green. If the plan cannot be implemented as written, do NOT improvise: log the reason in the testplan Log, commit, and write {"verdict":"blocked","route":"plan","notes":"<why>"} to %s.' "$notes" "$PLAN" "$2" ;;
    9) printf 'Final review, per your phase contract: judge the implementation against the plan %s AND the design record %s. Full suite, typecheck, lint, format:check, the shared review checklist. Approve: set the plan canonical Status line to DONE with the date, Log entry, commit; if tracker tools are available move the issue %s to review, else propose the move in your notes. Reject: Log notes, commit. Then write your routed verdict as single-line JSON to %s — approve pairs only with route "proceed"; reject pairs with "implementation" (code fixes) or "plan" (structural faults). New-scope findings become proposed issues in your notes, never fixes in this flight.' "$PLAN" "$ADR" "${ISSUE_REF:-<none>}" "$2" ;;
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

  for model in $models; do
    tries=0
    while [ "$tries" -lt "$MAX_TRIES" ]; do
      tries=$((tries + 1))
      d=$(bump dispatch)
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

      fail=''
      grep -qF "PREFLIGHT: $nonce" "$logf" || fail='preflight line missing or wrong'
      [ -z "$fail" ] && grep -q 'PREFLIGHT: FAIL' "$logf" && fail='phase reported PREFLIGHT: FAIL'
      [ -z "$fail" ] && [ "$rc" -ne 0 ] && fail="harness exit $rc"

      route=proceed
      if [ -z "$fail" ]; then
        if [ -f "$verdict" ]; then
          v=$(json_field "$verdict" verdict); route=$(json_field "$verdict" route)
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
        elif [ "$is_reviewer" -eq 1 ]; then
          fail='reviewer ended without a verdict file'
        fi
      fi
      [ -z "$fail" ] && { artifact_ok "$p" "$route" || fail='expected artifact/status missing, trivial, or malformed'; }
      [ -z "$fail" ] && [ "$(git rev-parse HEAD)" = "$snap" ] && fail='no commit (HEAD did not advance)'
      [ -z "$fail" ] && [ -n "$(git status --porcelain)" ] && fail='working tree not clean after the phase'
      if [ -z "$fail" ] && [ -n "$ISSUE_REF" ]; then
        git log --format=%B "$snap..HEAD" | grep -qF "$ISSUE_REF" \
          || fail="tracker reference '$ISSUE_REF' missing from the phase's commit message(s)"
      fi

      if [ -z "$fail" ]; then
        [ -f "$verdict" ] && LAST_VERDICT=$verdict
        ROUTE=$route
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
  run_phase "$PHASE"
  if [ "$ROUTE" = proceed ]; then
    NOTES_FILE=''
    if [ "$PHASE" -eq 9 ]; then break; fi
    PHASE=$((PHASE + 1))
    continue
  fi
  # backward edge
  edges=$(bump edges)
  [ "$edges" -le "$MAX_EDGES" ] || stop_flight "global cap: backward edge $edges exceeds $MAX_EDGES"
  case $PHASE in
    3|5|7|9)
      r=$(bump "rej.$PHASE")
      [ "$r" -le "$MAX_GATE_REJECTS" ] || stop_flight "gate cap: rejection $r on gate $PHASE exceeds $MAX_GATE_REJECTS"
      ;;
  esac
  NOTES_FILE=$LAST_VERDICT
  log "backward edge $edges/$MAX_EDGES: phase $PHASE -> $(route_phase "$ROUTE") (route: $ROUTE)"
  PHASE=$(route_phase "$ROUTE")
done

# --- the ribbon: push + draft PR ---------------------------------------------
log "phase 9 approved — pushing and opening the draft PR"
git push -u origin "feature/$FEATURE" >> "$S/driver.log" 2>&1 \
  || stop_flight "git push failed — nothing was published; branch intact locally (see driver.log)"

{
  printf 'Autopilot flight — feature `%s`%s\n\n' "$FEATURE" "${ISSUE_REF:+ (${ISSUE_REF})}"
  printf '## Summary (from the plan)\n\n'
  sed -n '/^## 1\. Goal/,/^## /p' "$PLAN" | sed '1d;/^## /d' | head -n 12
  printf '\n## Flight\n\n'
  printf 'Design record: `%s` · testplan: `%s` · plan: `%s`\n' "$ADR" "$TESTPLAN" "$PLAN"
  printf 'Backward edges: %s/%s · gate rejections: 3:%s 5:%s 7:%s 9:%s\n\n' \
    "$(show_int edges)" "$MAX_EDGES" "$(show_int rej.3)" "$(show_int rej.5)" "$(show_int rej.7)" "$(show_int rej.9)"
  printf 'Final review notes: %s\n\n' "$(json_field "$LAST_VERDICT" notes)"
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

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
# POSIX shell, no dependencies beyond git and the two headless harness CLIs
# (same doctrine as verify-kit.sh, ADR-0006). Concrete model identifiers are
# never written here: they come from .ai/autopilot/models.env, written by /fly
# from the project's Model Roster with the operator confirming.
#
# State lives under .ai/autopilot/<feature>/ (gitignored): verdict JSONs,
# counters, preflight probes, logs, report.md. The durable record is in the
# artifacts under .ai/plans/.
#
# Exit codes: 0 = flight DONE · 1 = flight STOPPED (caps, preflight, git) ·
#             2 = usage / preconditions.
#
# Usage: autopilot-driver.sh -f <feature> [-s <phase 2-9>] [-F] [dir]
#   -s  phase to (re-)enter — operator relaunch after amending a stop
#   -F  force: ignore a stale RUNNING status marker

set -u

usage() { echo "usage: $0 -f <feature> [-s <phase 2-9>] [-F] [dir]" >&2; exit 2; }

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
case $START in 2|3|4|5|6|7|8|9) ;; *) echo "autopilot-driver: -s must be 2-9" >&2; exit 2 ;; esac
cd "$ROOT" || exit 2

# --- seams (env-overridable: tests stub the harnesses through these) ---------
CLAUDE_BIN=${AP_CLAUDE_BIN:-claude}
CODEX_BIN=${AP_CODEX_BIN:-codex}
GH_BIN=${AP_GH_BIN:-gh}
# Unattended flights need non-interactive permission handling; the operator
# opted into this repo-wide when launching the flight. Override to tighten.
CLAUDE_ARGS=${AP_CLAUDE_ARGS:---dangerously-skip-permissions}
CODEX_ARGS=${AP_CODEX_ARGS:---full-auto}
MAX_GATE_REJECTS=${AP_MAX_GATE_REJECTS:-2}   # the (N+1)th rejection on one gate stops
MAX_EDGES=${AP_MAX_EDGES:-6}                 # global backward-edge cap per flight
MAX_TRIES=${AP_MAX_TRIES:-3}                 # 1 attempt + 2 retries per model

S=.ai/autopilot/$FEATURE

# --- preconditions -----------------------------------------------------------
[ -f .ai/kit.json ] || { echo "autopilot-driver: no .ai/kit.json (not a kit install)" >&2; exit 2; }
profile=$(sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .ai/kit.json | head -n 1)
[ "$profile" = autopilot ] || { echo "autopilot-driver: active profile is '$profile', not autopilot (/switch-profile)" >&2; exit 2; }
[ -f .ai/autopilot/models.env ] || { echo "autopilot-driver: .ai/autopilot/models.env missing (/fly writes it)" >&2; exit 2; }
[ -f "$S/flight.env" ] || { echo "autopilot-driver: $S/flight.env missing (/fly writes it)" >&2; exit 2; }
. ./.ai/autopilot/models.env
. "./$S/flight.env"
BASE_BRANCH=${AP_BASE_BRANCH:-develop}
ISSUE_REF=${AP_ISSUE_REF:-}
: "${AP_MODEL_REVIEW:?models.env: AP_MODEL_REVIEW missing}"
: "${AP_MODEL_FLAGSHIP:?models.env: AP_MODEL_FLAGSHIP missing}"
: "${AP_MODEL_COSTEFF:?models.env: AP_MODEL_COSTEFF missing}"
: "${AP_MODEL_MID:?models.env: AP_MODEL_MID missing}"
AP_LADDER_FLAGSHIP=${AP_LADDER_FLAGSHIP:-}
AP_LADDER_COSTEFF=${AP_LADDER_COSTEFF:-}
AP_LADDER_MID=${AP_LADDER_MID:-}
AP_LADDER_REVIEW=${AP_LADDER_REVIEW:-}

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || { echo "autopilot-driver: not a git repo" >&2; exit 2; }
[ "$branch" = "feature/$FEATURE" ] || { echo "autopilot-driver: on '$branch', expected 'feature/$FEATURE'" >&2; exit 2; }
git rev-parse --verify -q "$BASE_BRANCH" >/dev/null || { echo "autopilot-driver: base branch '$BASE_BRANCH' missing — its creation is a human act" >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { echo "autopilot-driver: working tree not clean" >&2; exit 2; }
if [ -f "$S/status" ] && [ "$(cat "$S/status")" = RUNNING ] && [ "$FORCE" -ne 1 ]; then
  echo "autopilot-driver: $S/status says RUNNING (another driver? stale? rerun with -F)" >&2; exit 2
fi

mkdir -p "$S/logs" "$S/verdicts" "$S/probes"
echo RUNNING > "$S/status"

TESTPLAN=.ai/plans/$FEATURE.testplan.md
PLAN=.ai/plans/$FEATURE.md
ADR=.ai/plans/$FEATURE.adr.md
DISPATCH=0
LAST_VERDICT=''
NOTES_FILE=''

# --- state helpers -----------------------------------------------------------
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$S/driver.log"; }
counter() { [ -f "$S/$1" ] && cat "$S/$1" || echo 0; }
bump() { c=$(($(counter "$1") + 1)); echo "$c" > "$S/$1"; echo "$c"; }

write_report() { # $1 = final status line
  {
    printf '# Flight report — %s\n\n' "$FEATURE"
    printf '%s\n\n' "$1"
    printf 'Backward edges: %s/%s · gate rejections: 3:%s 5:%s 7:%s 9:%s\n\n' \
      "$(counter edges)" "$MAX_EDGES" "$(counter rej.3)" "$(counter rej.5)" "$(counter rej.7)" "$(counter rej.9)"
    printf 'Artifacts: %s · %s · %s\n\n' "$ADR" "$TESTPLAN" "$PLAN"
    [ -n "$LAST_VERDICT" ] && [ -f "$LAST_VERDICT" ] && { printf 'Last verdict (%s):\n\n```json\n' "$LAST_VERDICT"; cat "$LAST_VERDICT"; printf '\n```\n\n'; }
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
trap 'stop_flight "interrupted"' INT TERM

json_field() { sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1; }

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
    2|6) echo "$AP_MODEL_FLAGSHIP $AP_LADDER_FLAGSHIP" ;;
    4)   echo "$AP_MODEL_COSTEFF $AP_LADDER_COSTEFF" ;;
    8)   echo "$AP_MODEL_MID $AP_LADDER_MID" ;;
    *)   echo "$AP_MODEL_REVIEW $AP_LADDER_REVIEW" ;;
  esac
}
valid_routes() {
  case $1 in
    3) echo 'proceed testplan' ;;
    4) echo 'proceed testplan' ;;
    5) echo 'proceed tests testplan' ;;
    7) echo 'proceed plan' ;;
    8) echo 'proceed plan' ;;
    9) echo 'proceed implementation plan' ;;
    *) echo 'proceed' ;;
  esac
}
route_phase() { case $1 in testplan) echo 2 ;; tests) echo 4 ;; plan) echo 6 ;; implementation) echo 8 ;; esac; }

# Artifact-on-disk backstop: the phase's expected output exists and is non-trivial;
# approve verdicts also left the status string the chapter prescribes.
artifact_ok() { # $1 = phase, $2 = route
  case $1 in
    2) [ -f "$TESTPLAN" ] && [ "$(wc -c < "$TESTPLAN")" -gt 400 ] ;;
    3) [ "$2" != proceed ] || grep -q 'READY' "$TESTPLAN" ;;
    4) [ "$2" != proceed ] || grep -q 'Status:.*RED' "$TESTPLAN" ;;
    5) [ "$2" != proceed ] || grep -q 'APPROVED' "$TESTPLAN" ;;
    6) [ -f "$PLAN" ] && [ "$(wc -c < "$PLAN")" -gt 400 ] ;;
    7) [ "$2" != proceed ] || grep -q 'Gate: APPROVED' "$PLAN" ;;
    8) : ;;
    9) [ "$2" != proceed ] || grep -q 'DONE' "$PLAN" ;;
  esac
}

# --- prompt building ---------------------------------------------------------
phase_task() { # $1 = phase, $2 = verdict path, $3 = notes file ('' if none)
  notes=''
  [ -n "$3" ] && notes="A previous verdict bounced this work back to you — read the notes in $3 and answer them point by point in the testplan Log. "
  case $1 in
    2) printf '%sInput: the design record %s. Produce %s from .ai/templates/test_plan_template.md per your phase contract: the full test-case inventory, Status: DRAFT, your Log entry. Commit when done.' "$notes" "$ADR" "$TESTPLAN" ;;
    3) printf 'Judge %s against %s and the repository, per your phase contract. Approve: set Status: READY, append your Log entry, commit. Reject: append point-by-point notes to the Log, commit. Then write your routed verdict as single-line JSON to %s — {"verdict":"approve|reject","route":"<route>","notes":"<short summary>"}; valid routes: proceed (approve), testplan (reject).' "$TESTPLAN" "$ADR" "$2" ;;
    4) printf '%sInput: the READY testplan %s. Transcribe the inventory into test code per your phase contract — no spec decisions. Run the focused tests, verify RED mechanically, append the RED output to the Log, set Status: RED, commit. If the inventory is unworkable (missing/ambiguous expected value), do NOT guess: log the gap, commit, and write {"verdict":"blocked","route":"testplan","notes":"<why>"} to %s.' "$notes" "$TESTPLAN" "$2" ;;
    5) printf 'Run the six-point test gate on the RED tests against %s, per your phase contract. Approve: Status: APPROVED, Log, commit. Reject: Status: REJECTED(n), point-by-point Log notes, commit. Then write your routed verdict as single-line JSON to %s — valid routes: proceed (approve), tests (transcription faults), testplan (inventory faults).' "$TESTPLAN" "$2" ;;
    6) printf '%sInput: the APPROVED testplan %s and the design record %s. Produce the implementation plan %s from .ai/templates/plan_template.md per your phase contract: signatures copied verbatim, constraints derived, Source testplan row present, NO Gate row (the Plan Reviewer stamps it). Append your Log entry to the testplan, commit.' "$notes" "$TESTPLAN" "$ADR" "$PLAN" ;;
    7) printf 'Judge the plan %s against the gated testplan %s and the design record %s, per your phase contract. Approve: stamp "Gate: APPROVED — <date>" in the plan §3, Log entry in the testplan, commit. Reject: Log notes, commit. Then write your routed verdict as single-line JSON to %s — valid routes: proceed (approve), plan (reject).' "$PLAN" "$TESTPLAN" "$ADR" "$2" ;;
    8) printf '%sYou are governed by AGENTS.md. Read the gated plan %s and implement the minimum code to turn the listed RED tests green: run the focused tests while iterating, then the full suite and typecheck. Never touch test files. Commit when green. If the plan cannot be implemented as written, do NOT improvise: log the reason in the testplan Log, commit, and write {"verdict":"blocked","route":"plan","notes":"<why>"} to %s.' "$notes" "$PLAN" "$2" ;;
    9) printf 'Final review, per your phase contract: judge the implementation against the plan %s AND the design record %s. Full suite, typecheck, lint, format:check, the shared review checklist. Approve: set the plan Status: DONE with the date, Log entry, commit; if tracker tools are available move the issue %s to review, else propose the move in your notes. Reject: Log notes, commit. Then write your routed verdict as single-line JSON to %s — valid routes: proceed (approve), implementation (code fixes), plan (structural faults). New-scope findings become proposed issues in your notes, never fixes in this flight.' "$PLAN" "$ADR" "${ISSUE_REF:-<none>}" "$2" ;;
  esac
}

build_prompt() { # $1 phase, $2 role, $3 probe, $4 verdict path, $5 notes file
  printf 'PREFLIGHT — before anything else: read the file %s with your file tools and open your final reply with the line: PREFLIGHT: <its exact content>. If your tools do not work, reply "PREFLIGHT: FAIL <reason>" and stop.\n\nYou are the %s of the autopilot profile — phase %s of the unattended flight for feature "%s". Work from the repository root. Read in order: .ai/process/autopilot.md (your contract — follow your phase section exactly), CLAUDE.md, .ai/PROJECT_ARCHITECTURE.md, then your inputs. Commit messages: semantic prefix%s.\n\n%s\n' \
    "$3" "$2" "$1" "$FEATURE" \
    "${ISSUE_REF:+, reference $ISSUE_REF}" \
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
      DISPATCH=$((DISPATCH + 1))
      probe=$S/probes/p$p.d$DISPATCH
      verdict=$S/verdicts/phase$p.d$DISPATCH.json
      logf=$S/logs/phase$p.d$DISPATCH.log
      nonce=$(od -An -N8 -tx8 /dev/urandom | tr -d ' \n')
      printf '%s\n' "$nonce" > "$probe"
      snap=$(git rev-parse HEAD)
      log "phase $p ($role) — dispatch $DISPATCH, model $model, try $tries/$MAX_TRIES"

      prompt=$(build_prompt "$p" "$role" "$probe" "$verdict" "$NOTES_FILE")
      if [ "$harness" = claude ]; then
        # shellcheck disable=SC2086
        "$CLAUDE_BIN" -p $CLAUDE_ARGS --model "$model" "$prompt" > "$logf" 2>&1
      else
        # shellcheck disable=SC2086
        "$CODEX_BIN" exec $CODEX_ARGS -m "$model" "$prompt" > "$logf" 2>&1
      fi
      rc=$?

      fail=''
      grep -qF "PREFLIGHT: $nonce" "$logf" || fail='preflight line missing or wrong'
      [ -z "$fail" ] && grep -q 'PREFLIGHT: FAIL' "$logf" && fail='phase reported PREFLIGHT: FAIL'
      [ -z "$fail" ] && [ "$rc" -ne 0 ] && fail="harness exit $rc"
      # tool-failure burst backstop (mid-session degradation)
      [ -z "$fail" ] && [ "$(grep -c '"is_error"[[:space:]]*:[[:space:]]*true' "$logf")" -gt 5 ] && fail='tool-failure burst in event log'

      route=proceed
      if [ -z "$fail" ]; then
        if [ -f "$verdict" ]; then
          v=$(json_field "$verdict" verdict); route=$(json_field "$verdict" route)
          if [ -z "$route" ]; then fail='verdict file without a route field'
          else echo " $(valid_routes "$p") " | grep -qF " $route " || fail="invalid route '$route' for phase $p"; fi
          [ -z "$v" ] && fail='verdict file without a verdict field'
        elif [ "$is_reviewer" -eq 1 ]; then
          fail='reviewer ended without a verdict file'
        fi
      fi
      [ -z "$fail" ] && { artifact_ok "$p" "$route" || fail='expected artifact/status missing or trivial'; }
      [ -z "$fail" ] && [ "$(git rev-parse HEAD)" = "$snap" ] && fail='no commit (HEAD did not advance)'
      [ -z "$fail" ] && [ -n "$(git status --porcelain)" ] && fail='working tree not clean after the phase'

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
log "flight start — feature $FEATURE, entering phase $START (caps: $MAX_GATE_REJECTS/gate, $MAX_EDGES edges)"
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
push_note=''
if git push -u origin "feature/$FEATURE" >> "$S/driver.log" 2>&1; then
  {
    printf 'Autopilot flight — feature `%s`%s\n\n' "$FEATURE" "${ISSUE_REF:+ (${ISSUE_REF})}"
    printf 'Design record: `%s` · testplan: `%s` · plan: `%s`\n' "$ADR" "$TESTPLAN" "$PLAN"
    printf 'Backward edges: %s/%s · gate rejections: 3:%s 5:%s 7:%s 9:%s\n\n' \
      "$(counter edges)" "$MAX_EDGES" "$(counter rej.3)" "$(counter rej.5)" "$(counter rej.7)" "$(counter rej.9)"
    printf 'Final verdict notes: %s\n\n' "$(json_field "$LAST_VERDICT" notes)"
    printf 'Opened by the autopilot driver. Promotion from draft, merge, and issue closure are human acts.\n'
  } > "$S/pr-body.md"
  if pr_url=$("$GH_BIN" pr create --draft --base "$BASE_BRANCH" --head "feature/$FEATURE" \
        --title "feat: $FEATURE${ISSUE_REF:+ ($ISSUE_REF)}" --body-file "$S/pr-body.md" 2>>"$S/driver.log"); then
    push_note="Draft PR: $pr_url"
  else
    push_note="Pushed, but the draft PR could not be opened — body saved at $S/pr-body.md, open it by hand"
  fi
else
  push_note="Push failed — see $S/driver.log; branch is intact locally"
fi
log "$push_note"

echo DONE > "$S/status"
write_report "**DONE** — the flight completed phase 9. $push_note"
log "flight done — report: $S/report.md"
exit 0

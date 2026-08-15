#!/bin/sh
# tests/driver/run.sh — behavior tests for bin/autopilot-driver.sh.
#
# Each scenario builds a disposable git repository shaped like a kit target
# (kit.json on the autopilot profile, a committed design record, develop +
# feature/demo branches, a bare origin), then runs the driver with the stub
# harnesses in ./stubs standing in for the real CLIs (AP_*_BIN test seams).
# Model ids are opaque strings — no real model name ever appears here.
#
# The stubs are not passive: each declares its harness family and the actor
# refuses a phase that belongs to the other family, or a model id that is not
# the one that phase's roster tier defines. Every dispatch is recorded, and one
# scenario asserts the whole eight-phase sequence — a driver that sent the
# flight through a single harness would pass a suite that only ran phases.
#
# Exit 0 only if every assertion passes. TAP-ish output, one line per check.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/../.." && pwd)
DRIVER=$KIT/bin/autopilot-driver.sh
STUBS=$HERE/stubs
BASE=$(mktemp -d "${TMPDIR:-/tmp}/autopilot-driver-tests.XXXXXX")
trap 'rm -rf "$BASE"' EXIT

PASSED=0; FAILED=0
chk() { d=$1; shift; if "$@" >/dev/null 2>&1; then PASSED=$((PASSED+1)); echo "ok   - $d"; else FAILED=$((FAILED+1)); echo "FAIL - $d"; fi; }
chknot() { d=$1; shift; if "$@" >/dev/null 2>&1; then FAILED=$((FAILED+1)); echo "FAIL - $d"; else PASSED=$((PASSED+1)); echo "ok   - $d"; fi; }

scrub_env() { unset AP_MAX_TRIES AP_MAX_EDGES AP_MAX_GATE_REJECTS AP_CLAUDE_ARGS AP_CODEX_ARGS \
                    STUB_SCENARIO_DIR STUB_BAD_PREFLIGHT_PHASES STUB_BAD_NONCE_MODELS \
                    STUB_GH_FAIL 2>/dev/null || true; }

write_models_env() { # cwd = flight repo; $1 = optional extra lines
  {
    printf "AP_MODEL_REVIEW='rev-1'\n"
    printf "AP_MODEL_FLAGSHIP='flag-1'\n"
    printf "AP_MODEL_COSTEFF='cost-1'\n"
    printf "AP_MODEL_MID='mid-1'\n"
    [ -n "${1:-}" ] && printf '%s\n' "$1"
  } > .ai/autopilot/models.env
}

make_flight() { # $1 = scenario name -> G (repo), S (flight state dir), ORIGIN
  G=$BASE/$1; ORIGIN=$BASE/$1-origin.git
  git init -q --bare "$ORIGIN"
  git init -q -b main "$G"
  (
    cd "$G" || exit 1
    git config user.email test@test && git config user.name test
    mkdir -p .ai/plans .ai/autopilot/demo
    printf '{"profile":"autopilot","kitVersion":"0.0.0"}\n' > .ai/kit.json
    printf '.ai/autopilot/\n' > .gitignore
    {
      printf '# Design record — demo\n\nGoal, scope and non-goals, signatures, edge-case map.\n\n'
      i=0; while [ $i -lt 12 ]; do echo "- design note $i, pinned during the interview"; i=$((i+1)); done
    } > .ai/plans/demo.adr.md
    git add -A && git commit -qm 'feat: demo — design record (TEST-1)'
    git branch develop
    git checkout -qb feature/demo
    git remote add origin "$ORIGIN"
    write_models_env "${2:-}"
    printf "AP_ISSUE_REF='TEST-1'\n" > .ai/autopilot/demo/flight.env
  )
  S=$G/.ai/autopilot/demo
}

run_driver() { # extra driver args; uses G, sets RC and OUT
  OUT=$G.out   # OUTSIDE the flight repo: a file inside it would dirty the tree
               # and trip the driver's own clean-tree precondition
  (cd "$G" && AP_CLAUDE_BIN=$STUBS/claude AP_CODEX_BIN=$STUBS/codex AP_GH_BIN=$STUBS/gh \
     "$DRIVER" -f demo "$@" .) > "$OUT" 2>&1
  RC=$?
}

st() { [ "$(cat "$S/status" 2>/dev/null)" = "$1" ]; }
log_has() { grep -qF -- "$1" "$S/driver.log"; }
out_has() { grep -qF -- "$1" "$OUT"; }

# Pre-baked artifacts for the -s relaunch / entry-matrix scenarios (cwd = flight repo).
seed_testplan() { # $1 = Status value to seed
  {
    printf '# Test plan — demo\n\n> **Status:** %s\n\n## Inventory\n\n' "$1"
    i=0; while [ $i -lt 12 ]; do echo "- case $i: input, expected value, boundary noted"; i=$((i+1)); done
    printf '\n## 6. Log (append-only)\n\n- seeded for the relaunch scenario\n'
  } > .ai/plans/demo.testplan.md
}
seed_plan() { # $1 = 'gated' | 'ungated' (Status RED either way)
  {
    printf '# Plan — demo\n\n> **Status:** RED\n\n## 1. Goal\n\nTurn the red tests green.\n\n## 3. Constraints\n\n'
    i=0; while [ $i -lt 12 ]; do echo "- constraint $i derived from the testplan"; i=$((i+1)); done
  } > .ai/plans/demo.md
  [ "$1" = gated ] && printf -- '- **Gate:** APPROVED — 2026-08-15, all gate checks passed (CLAUDE.md, gate phase)\n' >> .ai/plans/demo.md
  return 0
}
seed_commit() { git add -A && git commit -qm 'feat: demo seeded artifacts (TEST-1)'; }
seed_impl_green() { # the durable phase-8 completion row on the testplan Log
  printf -- '- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)\n' >> .ai/plans/demo.testplan.md
}
seed_impl_green_outside_log() { # the same row, placed ABOVE the Log heading (R4-B1)
  awk '/^## 6\. Log \(append-only\)$/ && !d {
         print "- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)"
         print ""; d = 1
       } { print }' .ai/plans/demo.testplan.md > .ai/plans/demo.testplan.tmp \
    && mv .ai/plans/demo.testplan.tmp .ai/plans/demo.testplan.md
}
seed_impl_green_after_section() { # the row under a LATER H2 — outside the Log section
  printf '\n## 7. Appendix\n\n- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)\n' \
    >> .ai/plans/demo.testplan.md
}
seed_impl_green_under_subheading() { # inside the Log, under a deeper heading
  printf '\n### Rejection notes\n\n- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)\n' \
    >> .ai/plans/demo.testplan.md
}
seed_second_log_head() { # a duplicate Log heading: "the Log" stops being one place
  printf '\n## 6. Log (append-only)\n\n- a second Log section\n' >> .ai/plans/demo.testplan.md
}
seed_no_log_head() { # a testplan whose Log heading drifted from the template
  sed 's/^## 6\. Log (append-only)$/## Log/' .ai/plans/demo.testplan.md > .ai/plans/demo.testplan.tmp \
    && mv .ai/plans/demo.testplan.tmp .ai/plans/demo.testplan.md
}
seed_gated_artifacts() { # $1 = 'gated' | 'ungated'
  seed_testplan APPROVED
  seed_plan "$1"
  seed_commit
}
drop_adr() { git rm -q .ai/plans/demo.adr.md && git commit -qm 'chore: drop the design record (TEST-1)'; }

# ---------------------------------------------------------------- scenarios --

echo '# happy path'
scrub_env; make_flight happy
run_driver
chk 'happy: exit 0' test "$RC" -eq 0
chk 'happy: status DONE' st DONE
chk 'happy: PR url in the report' grep -qF 'https://example.invalid/pr/1' "$S/report.md"
chk 'happy: branch on origin' git -C "$ORIGIN" show-ref --verify -q refs/heads/feature/demo
chk 'happy: 8 phases proceed' test "$(grep -c -- 'ok — route: proceed' "$S/driver.log")" -eq 8
chk 'happy: gh called with the exact publication argv' \
  grep -qx -- '--base' "$S/../gh-args"
chk 'happy: gh targeted develop <- feature/demo' \
  sh -c 'grep -qx develop "$1" && grep -qx feature/demo "$1"' _ "$S/../gh-args"

echo '# bounce: gate 5 rejects once with REJECTED(1), then approves'
scrub_env; make_flight bounce
SC=$BASE/sc-bounce; mkdir -p "$SC"
cat > "$SC/phase5" <<'EOF'
if [ -f "$FLIGHT_DIR/p5-bounced" ]; then
  sed 's/^> \*\*Status:\*\*.*/> **Status:** APPROVED/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
  printf -- '- stub: test gate passed on retry\n' >> "$TESTPLAN"
  git add -A && git commit -qm 'docs: demo test gate (TEST-1)'
  printf '{"verdict":"approve","route":"proceed","notes":"fixed"}' > "$VERDICT"
else
  touch "$FLIGHT_DIR/p5-bounced"
  sed 's/^> \*\*Status:\*\*.*/> **Status:** REJECTED(1)/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
  printf -- '- stub: transcription fault, point-by-point notes\n' >> "$TESTPLAN"
  git add -A && git commit -qm 'docs: demo test gate reject (TEST-1)'
  printf '{"verdict":"reject","route":"tests","notes":"one assert is weakened"}' > "$VERDICT"
fi
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'bounce: still DONE' st DONE
chk 'bounce: one backward edge' test "$(cat "$S/edges")" -eq 1
chk 'bounce: one rejection on gate 5' test "$(cat "$S/rej.5")" -eq 1
chk 'bounce: routed 5 -> 4' log_has 'phase 5 -> 4 (route: tests)'

echo '# gate cap: third rejection on gate 3 stops the flight'
scrub_env; make_flight gatecap
SC=$BASE/sc-gatecap; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
printf -- '- stub: inventory rejected, notes appended\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate reject (TEST-1)'
printf '{"verdict":"reject","route":"testplan","notes":"inventory faults"}' > "$VERDICT"
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'gatecap: exit 1' test "$RC" -eq 1
chk 'gatecap: status STOPPED' st STOPPED
chk 'gatecap: reason is the gate cap' log_has 'gate cap: rejection 3 on gate 3'
chk 'gatecap: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# preflight ladder: review tier fails preflight, ladder rung tried, then stop'
scrub_env; make_flight ladder
(cd "$G" && write_models_env "AP_LADDER_REVIEW='rev-2'")
AP_MAX_TRIES=2 STUB_BAD_PREFLIGHT_PHASES=3; export AP_MAX_TRIES STUB_BAD_PREFLIGHT_PHASES
run_driver
chk 'ladder: exit 1' test "$RC" -eq 1
chk 'ladder: status STOPPED' st STOPPED
chk 'ladder: primary exhausted' log_has 'model rev-1 exhausted its 2 tries on phase 3'
chk 'ladder: rung exhausted' log_has 'model rev-2 exhausted its 2 tries on phase 3'
chk 'ladder: final reason' log_has 'every model on the ladder failed'

echo '# stale verdict: a pre-seeded verdict file must not pass for a new dispatch'
scrub_env; make_flight stale
mkdir -p "$S/verdicts"
printf '{"verdict":"approve","route":"proceed","notes":"stale"}' > "$S/verdicts/phase3.d2.json"
SC=$BASE/sc-stale; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
printf -- '- stub: gate work but NO verdict written\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'stale: status STOPPED' st STOPPED
chk 'stale: missing verdict detected' log_has 'reviewer ended without a verdict file'
chknot 'stale: phase 3 never passed' log_has 'phase 3 ok'

echo '# corrupt dispatch counter: fail closed, never DONE (N-B1)'
scrub_env; make_flight corruptd
printf 'not-an-integer\n' > "$S/dispatch"
run_driver
chk 'corruptd: exit 1' test "$RC" -eq 1
chk 'corruptd: status STOPPED' st STOPPED
chk 'corruptd: reason recorded' grep -qF 'corrupt state' "$S/report.md"
chknot 'corruptd: no phase ever passed' log_has 'ok — route'
chk 'corruptd: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# corrupt edges counter: first backward edge stops the flight'
scrub_env; make_flight corrupte
printf 'garbage\n' > "$S/edges"
SC=$BASE/sc-gatecap; STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'corrupte: status STOPPED' st STOPPED
chk 'corrupte: reason recorded' grep -qF 'corrupt state' "$S/report.md"

echo '# -s 8 on an ungated plan: refused by the entry precondition (N-B2)'
scrub_env; make_flight sungated
(cd "$G" && seed_gated_artifacts ungated)
run_driver -s 8
chk 'sungated: exit 1' test "$RC" -eq 1
chk 'sungated: status STOPPED' st STOPPED
chk 'sungated: entry precondition named' log_has 'phase 8 entry precondition failed'
chknot 'sungated: implementer never launched' log_has 'phase 8 (Implementer)'

echo '# -s 8 on a gated plan: the legitimate relaunch flies to DONE'
scrub_env; make_flight sgated
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 8
chk 'sgated: exit 0' test "$RC" -eq 0
chk 'sgated: status DONE' st DONE
chk 'sgated: phase 8 ran' log_has 'phase 8 (Implementer)'

echo '# reject without artifact state: verdict says reject, testplan still RED (N-M1)'
scrub_env; make_flight rejstate
SC=$BASE/sc-rejstate; mkdir -p "$SC"
cat > "$SC/phase5" <<'EOF'
printf -- '- stub: rejecting but forgetting the status row\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo test gate reject (TEST-1)'
printf '{"verdict":"reject","route":"tests","notes":"faults"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'rejstate: status STOPPED' st STOPPED
chk 'rejstate: artifact/status backstop fired' log_has 'expected artifact/status'
chknot 'rejstate: no backward edge counted' log_has 'backward edge'

echo '# non-JSON verdict: prose containing the fields is rejected (M3)'
scrub_env; make_flight nonjson
SC=$BASE/sc-nonjson; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf 'this is not JSON but contains "verdict":"approve", "route":"proceed", trust me' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'nonjson: status STOPPED' st STOPPED
chk 'nonjson: strict grammar fired' log_has 'not the prescribed single-line JSON'

echo '# commit without the tracker reference: per-commit validation (m7)'
scrub_env; make_flight noref
SC=$BASE/sc-noref; mkdir -p "$SC"
cat > "$SC/phase2" <<'EOF'
{
  printf '# Test plan — demo\n\n> **Status:** DRAFT\n\n## Inventory\n\n'
  i=0; while [ $i -lt 12 ]; do echo "- case $i: input, expected value, boundary noted"; i=$((i+1)); done
  printf '\n## 6. Log (append-only)\n\n- stub: inventory written\n'
} > "$TESTPLAN"
git add -A && git commit -qm 'feat: inventory with no tracker ref'
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'noref: status STOPPED' st STOPPED
chk 'noref: missing reference named' log_has 'missing tracker reference'

echo '# config grammar: duplicates, unknown keys, malformed lines, bad args, bad caps'
scrub_env; make_flight cfgdup
printf "AP_MODEL_REVIEW='rev-9'\n" >> "$G/.ai/autopilot/models.env"
run_driver
chk 'cfgdup: exit 2' test "$RC" -eq 2
chk 'cfgdup: duplicate named' out_has 'duplicate key'

scrub_env; make_flight cfgunknown
printf "AP_EVIL='x'\n" >> "$G/.ai/autopilot/models.env"
run_driver
chk 'cfgunknown: exit 2' test "$RC" -eq 2
chk 'cfgunknown: unknown key named' out_has 'unknown key'

scrub_env; make_flight cfgmalformed
printf 'AP_MODEL_MID=$(boom)\n' >> "$G/.ai/autopilot/models.env"
run_driver
chk 'cfgmalformed: exit 2' test "$RC" -eq 2
chk 'cfgmalformed: malformed line named' out_has 'malformed line'

scrub_env; make_flight cfgargs
(cd "$G" && write_models_env "AP_CLAUDE_ARGS='   '")
run_driver
chk 'cfgargs: exit 2' test "$RC" -eq 2
chk 'cfgargs: invalid args named' out_has 'invalid AP_CLAUDE_ARGS'

scrub_env; make_flight cfgcaps
AP_MAX_TRIES=not-a-number; export AP_MAX_TRIES
run_driver
chk 'cfgcaps: exit 2' test "$RC" -eq 2
chk 'cfgcaps: integer rule named' out_has 'must be a positive integer'

echo '# environment never sets the permission policy (M8)'
scrub_env; make_flight envpolicy
AP_CLAUDE_ARGS='--dangerously-skip-permissions'; export AP_CLAUDE_ARGS
run_driver
chk 'envpolicy: flight still DONE' st DONE
chk 'envpolicy: guarded default used' log_has "claude '--permission-mode acceptEdits'"
chknot 'envpolicy: bypass never recorded' grep -qF 'dangerously' "$S/driver.log"

echo '# a develop tag is not a develop branch (N-m1)'
scrub_env; make_flight devtag
(cd "$G" && git branch -D develop -q && git tag develop)
run_driver
chk 'devtag: exit 2' test "$RC" -eq 2
chk 'devtag: branch rule named' out_has "local branch 'develop' missing"

echo '# push failure: STOPPED, nothing published'
scrub_env; make_flight pushfail
(cd "$G" && git remote set-url origin "$BASE/nowhere.git")
run_driver
chk 'pushfail: exit 1' test "$RC" -eq 1
chk 'pushfail: status STOPPED' st STOPPED
chk 'pushfail: reason recorded' log_has 'git push failed'

echo '# gh failure after a good push: PUSHED, body saved for the operator'
scrub_env; make_flight ghfail
STUB_GH_FAIL=1; export STUB_GH_FAIL
run_driver
chk 'ghfail: exit 1' test "$RC" -eq 1
chk 'ghfail: status PUSHED' st PUSHED
chk 'ghfail: branch on origin' git -C "$ORIGIN" show-ref --verify -q refs/heads/feature/demo
chk 'ghfail: PR body saved' test -s "$S/pr-body.md"

echo '# counter overflow: an all-digit value outside the arithmetic range fails closed (R3-B1)'
scrub_env; make_flight overflowd
printf '18446744073709551616\n' > "$S/dispatch"
run_driver
chk 'overflowd: exit 1' test "$RC" -eq 1
chk 'overflowd: status STOPPED' st STOPPED
chk 'overflowd: corrupt state named' grep -qF 'corrupt state' "$S/report.md"
chknot 'overflowd: no phase ever passed' log_has 'ok — route'
chk 'overflowd: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# counter grammar: leading zeros are not canonical (R3-B1)'
scrub_env; make_flight zerod
printf '007\n' > "$S/dispatch"
run_driver
chk 'zerod: status STOPPED' st STOPPED
chk 'zerod: corrupt state named' grep -qF 'corrupt state' "$S/report.md"

echo '# counter ceiling: the maximum reads back fine, maximum+1 stops before wrapping (R3-B1)'
scrub_env; make_flight ceiling
printf '999999998\n' > "$S/dispatch"
run_driver
chk 'ceiling: maximum accepted for the first dispatch' log_has 'dispatch 999999999'
chk 'ceiling: maximum+1 stops the flight' log_has 'counter out of range'
chk 'ceiling: status STOPPED' st STOPPED
chk 'ceiling: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# oversized caps and non-space model separators are refused at startup (R3-m1)'
scrub_env; make_flight bigcap
AP_MAX_TRIES=99999999999; export AP_MAX_TRIES
run_driver
chk 'bigcap: exit 2' test "$RC" -eq 2
chk 'bigcap: integer rule named' out_has 'must be a positive integer'

scrub_env; make_flight tabmodel
(cd "$G" && {
  printf "AP_MODEL_REVIEW='rev-1'\n"
  printf "AP_MODEL_FLAGSHIP='flag-1\tflag-2'\n"
  printf "AP_MODEL_COSTEFF='cost-1'\n"
  printf "AP_MODEL_MID='mid-1'\n"
} > .ai/autopilot/models.env)
run_driver
chk 'tabmodel: exit 2' test "$RC" -eq 2
chk 'tabmodel: single-id rule named' out_has 'not a single valid model id'

scrub_env; make_flight tabladder
(cd "$G" && write_models_env "$(printf "AP_LADDER_REVIEW='rev-2\trev-3'")")
run_driver
chk 'tabladder: exit 2' test "$RC" -eq 2
chk 'tabladder: list rule named' out_has 'not a valid model list'

echo '# verdict shadowing: routing text inside notes must not control the route (R3-B2)'
scrub_env; make_flight shadow
SC=$BASE/sc-shadow; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf '%s' '{"verdict":"reject","route":"testplan","notes":"shadow "verdict":"approve" and "route":"proceed""}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'shadow: status STOPPED' st STOPPED
chk 'shadow: grammar fired' log_has 'not the prescribed single-line JSON'
chknot 'shadow: phase 3 never passed' log_has 'phase 3 ok'
chk 'shadow: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# verdict with a second, unterminated line: rejected (R3-B2)'
scrub_env; make_flight tailjson
SC=$BASE/sc-tailjson; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf '{"verdict":"approve","route":"proceed","notes":"ok"}\ngarbage' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'tailjson: status STOPPED' st STOPPED
chk 'tailjson: grammar fired' log_has 'not the prescribed single-line JSON'

echo '# branch escape: a phase that leaves feature/demo stops the flight (R3-B4)'
scrub_env; make_flight sidebranch
SC=$BASE/sc-sidebranch; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf '{"verdict":"approve","route":"proceed","notes":"ok"}' > "$VERDICT"
git checkout -qb rewritten
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'sidebranch: exit 1' test "$RC" -eq 1
chk 'sidebranch: status STOPPED' st STOPPED
chk 'sidebranch: branch escape named' log_has 'left branch feature/demo'
chk 'sidebranch: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# history rewrite: the snapshot must stay an ancestor of HEAD (R3-B4)'
scrub_env; make_flight rewound
SC=$BASE/sc-rewound; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
git reset --hard -q HEAD~1
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'rewound: status STOPPED' st STOPPED
chk 'rewound: rewrite named' log_has 'no longer an ancestor of HEAD'
chk 'rewound: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# phase 7 reject must leave the plan RED with NO Gate row (R3-M1)'
scrub_env; make_flight rej7
SC=$BASE/sc-rej7; mkdir -p "$SC"
cat > "$SC/phase7" <<'EOF'
printf -- '- **Gate:** REJECTED — stale row\n' >> "$PLAN"
printf -- '- stub: plan gate reject with a stray row\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo plan gate reject (TEST-1)'
printf '{"verdict":"reject","route":"plan","notes":"faults"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'rej7: status STOPPED' st STOPPED
chk 'rej7: artifact backstop fired' log_has 'expected artifact/status'
chknot 'rej7: phase 7 never passed' log_has 'phase 7 ok'

echo '# phase 9 reject must leave the plan RED and gated (R3-M1)'
scrub_env; make_flight rej9
SC=$BASE/sc-rej9; mkdir -p "$SC"
cat > "$SC/phase9" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** DRAFT/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
printf -- '- stub: final review reject that mangles the plan status\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo final review reject (TEST-1)'
printf '{"verdict":"reject","route":"implementation","notes":"faults"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'rej9: status STOPPED' st STOPPED
chk 'rej9: artifact backstop fired' log_has 'expected artifact/status'
chknot 'rej9: phase 9 never passed' log_has 'phase 9 ok'

echo '# phase 9 legitimate reject: plan stays RED+gated, routes to implementation, then DONE'
scrub_env; make_flight rej9ok
SC=$BASE/sc-rej9ok; mkdir -p "$SC"
cat > "$SC/phase9" <<'EOF'
if [ -f "$FLIGHT_DIR/p9-bounced" ]; then
  sed 's/^> \*\*Status:\*\*.*/> **Status:** DONE — 2026-08-15/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
  printf -- '- stub: final review passed on retry\n' >> "$TESTPLAN"
  git add -A && git commit -qm 'docs: demo final review (TEST-1)'
  printf '{"verdict":"approve","route":"proceed","notes":"ship it"}' > "$VERDICT"
else
  touch "$FLIGHT_DIR/p9-bounced"
  printf -- '- stub: final review reject, code fixes needed\n' >> "$TESTPLAN"
  git add -A && git commit -qm 'docs: demo final review reject (TEST-1)'
  printf '{"verdict":"reject","route":"implementation","notes":"one edge unhandled"}' > "$VERDICT"
fi
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'rej9ok: status DONE' st DONE
chk 'rej9ok: routed 9 -> 8' log_has 'phase 9 -> 8 (route: implementation)'
chk 'rej9ok: one rejection on gate 9' test "$(cat "$S/rej.9")" -eq 1

echo '# producer block: phase 4 blocked routes back to the testplan, then DONE'
scrub_env; make_flight blocked4
SC=$BASE/sc-blocked4; mkdir -p "$SC"
cat > "$SC/phase4" <<'EOF'
if [ -f "$FLIGHT_DIR/p4-blocked" ]; then
  sed 's/^> \*\*Status:\*\*.*/> **Status:** RED/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
  printf -- '- stub: tests transcribed, RED verified\n' >> "$TESTPLAN"
  echo 'test stub retry' >> tests.txt
  git add -A && git commit -qm 'test: demo red tests (TEST-1)'
else
  touch "$FLIGHT_DIR/p4-blocked"
  printf -- '- stub: inventory gap, expected value missing\n' >> "$TESTPLAN"
  git add -A && git commit -qm 'docs: demo transcription blocked (TEST-1)'
  printf '{"verdict":"blocked","route":"testplan","notes":"case 7 has no expected value"}' > "$VERDICT"
fi
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
run_driver
chk 'blocked4: status DONE' st DONE
chk 'blocked4: routed 4 -> 2' log_has 'phase 4 -> 2 (route: testplan)'
chk 'blocked4: one backward edge' test "$(cat "$S/edges")" -eq 1

echo '# status value grammar: APPROVED followed by junk is not APPROVED (M1)'
scrub_env; make_flight junkstatus
SC=$BASE/sc-junkstatus; mkdir -p "$SC"
cat > "$SC/phase5" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** APPROVED trailing-junk/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
printf -- '- stub: sloppy status row\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo test gate (TEST-1)'
printf '{"verdict":"approve","route":"proceed","notes":"ok"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'junkstatus: status STOPPED' st STOPPED
chk 'junkstatus: artifact backstop fired' log_has 'expected artifact/status'

echo '# gate row grammar: a date-shaped prefix with junk is not the canonical row (M1)'
scrub_env; make_flight junkgate
SC=$BASE/sc-junkgate; mkdir -p "$SC"
cat > "$SC/phase7" <<'EOF'
printf -- '- **Gate:** APPROVED — 9999-99-99 trailing junk\n' >> "$PLAN"
printf -- '- stub: sloppy gate row\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo plan gate (TEST-1)'
printf '{"verdict":"approve","route":"proceed","notes":"ok"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'junkgate: status STOPPED' st STOPPED
chk 'junkgate: artifact backstop fired' log_has 'expected artifact/status'

echo '# entry matrix: every -s phase demands its full input set (R3-B3)'
scrub_env; make_flight m3v
(cd "$G" && seed_testplan DRAFT && seed_commit)
run_driver -s 3
chk 'matrix -s 3 (DRAFT testplan): DONE' st DONE

scrub_env; make_flight m4v
(cd "$G" && seed_testplan READY && seed_commit)
run_driver -s 4
chk 'matrix -s 4 (READY testplan): DONE' st DONE

scrub_env; make_flight m5v
(cd "$G" && seed_testplan RED && seed_commit)
run_driver -s 5
chk 'matrix -s 5 (RED testplan): DONE' st DONE

scrub_env; make_flight m6v
(cd "$G" && seed_testplan APPROVED && seed_commit)
run_driver -s 6
chk 'matrix -s 6 (APPROVED testplan): DONE' st DONE

scrub_env; make_flight m7v
(cd "$G" && seed_testplan APPROVED && seed_plan ungated && seed_commit)
run_driver -s 7
chk 'matrix -s 7 (APPROVED + ungated RED plan): DONE' st DONE

scrub_env; make_flight m2i
(cd "$G" && drop_adr)
run_driver
chk 'matrix -s 2 without design record: refused' log_has 'phase 2 entry precondition failed'
chk 'matrix -s 2 nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

scrub_env; make_flight m3i
run_driver -s 3
chk 'matrix -s 3 without testplan: refused' log_has 'phase 3 entry precondition failed'

scrub_env; make_flight m3i2
(cd "$G" && seed_testplan READY && seed_commit)
run_driver -s 3
chk 'matrix -s 3 on READY: refused' log_has 'phase 3 entry precondition failed'

scrub_env; make_flight m4i
(cd "$G" && seed_testplan DRAFT && seed_commit)
run_driver -s 4
chk 'matrix -s 4 on DRAFT: refused' log_has 'phase 4 entry precondition failed'

scrub_env; make_flight m5i
(cd "$G" && seed_testplan READY && seed_commit)
run_driver -s 5
chk 'matrix -s 5 on READY: refused' log_has 'phase 5 entry precondition failed'

scrub_env; make_flight m6i
(cd "$G" && seed_testplan RED && seed_commit)
run_driver -s 6
chk 'matrix -s 6 on RED: refused' log_has 'phase 6 entry precondition failed'

scrub_env; make_flight m6i2
(cd "$G" && seed_testplan APPROVED && seed_commit && drop_adr)
run_driver -s 6
chk 'matrix -s 6 without design record: refused' log_has 'phase 6 entry precondition failed'

scrub_env; make_flight m7i
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 7
chk 'matrix -s 7 on a gated plan: refused' log_has 'phase 7 entry precondition failed'

scrub_env; make_flight m7i2
(cd "$G" && seed_testplan RED && seed_plan ungated && seed_commit)
run_driver -s 7
chk 'matrix -s 7 without APPROVED testplan: refused' log_has 'phase 7 entry precondition failed'

scrub_env; make_flight m9i
(cd "$G" && seed_gated_artifacts gated && drop_adr)
run_driver -s 9
chk 'matrix -s 9 without design record: refused' log_has 'phase 9 entry precondition failed'

scrub_env; make_flight m9v
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_plan gated && seed_commit)
run_driver -s 9
chk 'matrix -s 9 (gated + Implementation GREEN row): DONE' st DONE
chk 'matrix -s 9 ran only the final review' test "$(grep -c -- 'ok — route: proceed' "$S/driver.log")" -eq 1

scrub_env; make_flight m9i2
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 9
chk 'matrix -s 9 freshly gated, no implementation: refused' log_has 'phase 9 entry precondition failed'
chk 'matrix -s 9 nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# R4-B1: the GREEN row authorizes phase 9 only from inside the canonical Log'
scrub_env; make_flight b1out
(cd "$G" && seed_testplan APPROVED && seed_impl_green_outside_log && seed_plan gated && seed_commit)
run_driver -s 9
chk 'GREEN row above the Log heading: -s 9 refused' log_has 'phase 9 entry precondition failed'
chk 'GREEN row above the Log heading: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

scrub_env; make_flight b1dup
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_second_log_head && seed_plan gated && seed_commit)
run_driver -s 9
chk 'two Log headings: -s 9 refused' log_has 'phase 9 entry precondition failed'

scrub_env; make_flight b1nohead
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_no_log_head && seed_plan gated && seed_commit)
run_driver -s 9
chk 'no canonical Log heading: -s 9 refused' log_has 'phase 9 entry precondition failed'

scrub_env; make_flight b1two
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_impl_green && seed_plan gated && seed_commit)
run_driver -s 9
chk 'two GREEN rows on the Log (append-only): DONE' st DONE

echo '# R4-B2: the ribbon publishes the reviewed commit, or nothing at all'
scrub_env; make_flight b2reset
SC=$BASE/sc-b2reset; mkdir -p "$SC"
cat > "$SC/phase9" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** DONE — 2026-08-15/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
printf -- '- stub: final review passed\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo final review (TEST-1)'
git rev-parse HEAD > "$FLIGHT_DIR/reviewed-sha"
printf '{"verdict":"approve","route":"proceed","notes":"ship it"}' > "$VERDICT"
# A child that outlives the harness and rewrites the branch once the driver has
# already accepted the phase — the window R4-B2 reported. Whether it wins the
# race or not, the invariant below must hold.
( n=0
  while [ "$n" -lt 300 ]; do
    if grep -q 'phase 9 ok' "$FLIGHT_DIR/driver.log" 2>/dev/null; then
      git reset --hard develop >/dev/null 2>&1
      echo done > "$FLIGHT_DIR/child-reset"
      exit 0
    fi
    sleep 0.02; n=$((n + 1))
  done ) >/dev/null 2>&1 &
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_plan gated && seed_commit)
run_driver -s 9
published_is_reviewed() { # origin holds the reviewed sha, or nothing was published
  o=$(git -C "$ORIGIN" rev-parse --verify -q refs/heads/feature/demo || echo none)
  [ "$o" = none ] || [ "$o" = "$(cat "$S/reviewed-sha" 2>/dev/null)" ]
}
chk 'delayed branch reset: origin holds the reviewed commit or nothing' published_is_reviewed
chk 'delayed branch reset: no DONE over an unpublished ref' \
  sh -c '[ "$(cat "$1/status")" != DONE ] || git -C "$2" show-ref --verify -q refs/heads/feature/demo' _ "$S" "$ORIGIN"

scrub_env; make_flight b2hook
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_plan gated && seed_commit
 cat > .git/hooks/pre-push <<'EOF'
#!/bin/sh
# moves the branch out from under the push, after the driver's checks ran
git update-ref refs/heads/feature/demo "$(git rev-parse develop)"
exit 0
EOF
 chmod +x .git/hooks/pre-push)
run_driver -s 9
chk 'ref moved during the push: the published commit carries the DONE plan' \
  sh -c 'git -C "$1" show refs/heads/feature/demo:.ai/plans/demo.md | grep -q "Status:\*\* DONE"' _ "$ORIGIN"

scrub_env; make_flight b2obj
SC=$BASE/sc-b2obj; mkdir -p "$SC"
cat > "$SC/phase9" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** DONE — 2026-08-15/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
printf -- '- stub: final review passed\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo final review (TEST-1)'
git rev-parse HEAD > "$FLIGHT_DIR/reviewed-sha"
printf '{"verdict":"approve","route":"proceed","notes":"ship it"}' > "$VERDICT"
EOF
STUB_SCENARIO_DIR=$SC; export STUB_SCENARIO_DIR
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_plan gated && seed_commit)
run_driver -s 9
chk 'publication: flight completed' st DONE
# git names the SOURCE of the refspec in its push output: pushing the reviewed
# object prints that sha, pushing the branch name prints the branch name.
chk 'publication: the push transmits the reviewed commit itself' \
  sh -c 'grep -qF "$(cat "$1/reviewed-sha")" "$1/driver.log"' _ "$S"

echo '# R4-M1: a blocked producer is checked on its inputs, not just on "it committed"'
scrub_env; make_flight m1p8bad
SC=$BASE/sc-m1p8bad; mkdir -p "$SC"
cat > "$SC/phase8" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** DRAFT/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
grep -v '^- \*\*Gate:\*\*' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
printf -- '- stub: blocked, and the gated plan was degraded on the way out\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo implementation blocked (TEST-1)'
printf '{"verdict":"blocked","route":"plan","notes":"cannot implement"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 8
chk 'blocked phase 8 that degraded the plan: STOPPED' st STOPPED
chk 'blocked phase 8 that degraded the plan: backstop fired' log_has 'expected artifact/status'
chknot 'blocked phase 8 that degraded the plan: no backward edge counted' log_has 'backward edge'

scrub_env; make_flight m1p8green
SC=$BASE/sc-m1p8green; mkdir -p "$SC"
cat > "$SC/phase8" <<'EOF'
printf -- '- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo implementation blocked (TEST-1)'
printf '{"verdict":"blocked","route":"plan","notes":"cannot implement"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 8
chk 'blocked phase 8 claiming GREEN: STOPPED' st STOPPED
chk 'blocked phase 8 claiming GREEN: backstop fired' log_has 'expected artifact/status'

scrub_env; make_flight m1stale
SC=$BASE/sc-m1stale; mkdir -p "$SC"
cat > "$SC/phase8" <<'EOF'
echo 'code without a GREEN row' >> src.txt
git add -A && git commit -qm 'feat: demo implementation (TEST-1)'
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
(cd "$G" && seed_testplan APPROVED && seed_impl_green && seed_plan gated && seed_commit)
run_driver -s 8
chk 'phase 8 riding an older GREEN row: STOPPED' st STOPPED
chk 'phase 8 riding an older GREEN row: backstop fired' log_has 'expected artifact/status'

scrub_env; make_flight m1p8ok
SC=$BASE/sc-m1p8ok; mkdir -p "$SC"
cat > "$SC/phase8" <<'EOF'
printf -- '- stub: blocked, the plan cannot be implemented as written\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo implementation blocked (TEST-1)'
printf '{"verdict":"blocked","route":"plan","notes":"cannot implement"}' > "$VERDICT"
EOF
AP_MAX_EDGES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_EDGES STUB_SCENARIO_DIR
(cd "$G" && seed_gated_artifacts gated)
run_driver -s 8
chk 'canonical blocked phase 8: route accepted' log_has 'phase 8 ok — route: plan'
chk 'canonical blocked phase 8: stopped at the edge cap' log_has 'global cap'
chk 'canonical blocked phase 8: testplan still APPROVED' \
  grep -qF '> **Status:** APPROVED' "$G/.ai/plans/demo.testplan.md"
chk 'canonical blocked phase 8: plan still RED and gated' \
  sh -c 'grep -qF "> **Status:** RED" "$1" && grep -qF -- "- **Gate:** APPROVED" "$1"' _ "$G/.ai/plans/demo.md"
chk 'canonical blocked phase 8: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

scrub_env; make_flight m1p4bad
SC=$BASE/sc-m1p4bad; mkdir -p "$SC"
cat > "$SC/phase4" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** DRAFT/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
printf -- '- stub: blocked, and the entry status was changed on the way out\n' >> "$TESTPLAN"
git add -A && git commit -qm 'docs: demo transcription blocked (TEST-1)'
printf '{"verdict":"blocked","route":"testplan","notes":"ambiguous inventory row"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
(cd "$G" && seed_testplan READY && seed_commit)
run_driver -s 4
chk 'blocked phase 4 that moved the status: STOPPED' st STOPPED
chk 'blocked phase 4 that moved the status: backstop fired' log_has 'expected artifact/status'

echo '# R4-M3: the phase -> harness/model matrix is asserted, not assumed'
scrub_env; make_flight dispatchmatrix
run_driver
chk 'dispatch matrix: flight completed' st DONE
dispatch_matrix_ok() { # the driver's phase -> harness/model matrix, dispatch by dispatch
  want=$(printf '%s\n' '2 codex flag-1' '3 claude rev-1' '4 codex cost-1' '5 claude rev-1' \
                        '6 codex flag-1' '7 claude rev-1' '8 codex mid-1' '9 claude rev-1')
  [ "$(cat "$G/.ai/autopilot/dispatches")" = "$want" ]
}
chk 'dispatch matrix: exact eight-phase harness/model sequence' dispatch_matrix_ok

echo '# R4-M2: a NUL byte cannot slip past the closed verdict grammar'
scrub_env; make_flight nulnotes
SC=$BASE/sc-nulnotes; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf '{"verdict":"approve","route":"proceed","notes":"le\000ft"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'NUL inside notes: STOPPED' st STOPPED
chk 'NUL inside notes: strict grammar fired' log_has 'not the prescribed single-line JSON'
chk 'NUL inside notes: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

scrub_env; make_flight nultoken
SC=$BASE/sc-nultoken; mkdir -p "$SC"
cat > "$SC/phase3" <<'EOF'
sed 's/^> \*\*Status:\*\*.*/> **Status:** READY/' "$TESTPLAN" > "$TESTPLAN.tmp" && mv "$TESTPLAN.tmp" "$TESTPLAN"
git add -A && git commit -qm 'docs: demo inventory gate (TEST-1)'
printf '{"verdict":"appro\000ve","route":"proceed","notes":"ok"}' > "$VERDICT"
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'NUL inside a routing token: STOPPED' st STOPPED
chk 'NUL inside a routing token: strict grammar fired' log_has 'not the prescribed single-line JSON'

echo '# R5-B1: the Log scope ends at the next H2, not at end of file'
scrub_env; make_flight b1sect
(cd "$G" && seed_testplan APPROVED && seed_impl_green_after_section && seed_plan gated && seed_commit)
run_driver -s 9
chk 'GREEN row under a later H2: -s 9 refused' log_has 'phase 9 entry precondition failed'
chk 'GREEN row under a later H2: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

scrub_env; make_flight b1sub
(cd "$G" && seed_testplan APPROVED && seed_impl_green_under_subheading && seed_plan gated && seed_commit)
run_driver -s 9
chk 'GREEN row under a deeper heading inside the Log: DONE' st DONE

echo '# phase 2 must leave the canonical Log heading behind'
scrub_env; make_flight nolog2
SC=$BASE/sc-nolog2; mkdir -p "$SC"
cat > "$SC/phase2" <<'EOF'
{
  printf '# Test plan — demo\n\n> **Status:** DRAFT\n\n## Inventory\n\n'
  i=0; while [ $i -lt 12 ]; do echo "- case $i: input, expected value, boundary noted"; i=$((i+1)); done
  printf '\n## Log\n\n- stub: inventory written, heading drifted from the template\n'
} > "$TESTPLAN"
git add -A && git commit -qm 'feat: demo test inventory (TEST-1)'
EOF
AP_MAX_TRIES=1 STUB_SCENARIO_DIR=$SC; export AP_MAX_TRIES STUB_SCENARIO_DIR
run_driver
chk 'testplan without the canonical Log heading: STOPPED' st STOPPED
chk 'testplan without the canonical Log heading: backstop fired' log_has 'expected artifact/status'
chknot 'testplan without the canonical Log heading: phase 2 never accepted' log_has 'phase 2 ok'

echo '# R5-M1: a wrong nonce is rejected on its own, not via a missing artifact'
scrub_env; make_flight badnonce
STUB_BAD_NONCE_MODELS='rev-1'; export STUB_BAD_NONCE_MODELS
run_driver
chk 'wrong nonce with canonical work: STOPPED' st STOPPED
chk 'wrong nonce with canonical work: rejected for the nonce itself' log_has 'preflight line missing or wrong'
chknot 'wrong nonce with canonical work: the gate never counted as ok' log_has 'phase 3 ok'
chk 'wrong nonce with canonical work: nothing pushed' test -z "$(git -C "$ORIGIN" for-each-ref)"

echo '# R5-M2: a configured ladder rung is valid, tried after the primary, and can complete'
scrub_env; make_flight ladderok "AP_LADDER_REVIEW='rev-2'"
STUB_BAD_NONCE_MODELS='rev-1'; AP_MAX_TRIES=2; export STUB_BAD_NONCE_MODELS AP_MAX_TRIES
run_driver
chk 'ladder rung completes the phase: DONE' st DONE
chk 'ladder rung completes the phase: the rung is named in the journey' log_has 'next ladder rung'
ladder_matrix_ok() { # primary exhausted twice, then the rung — for every reviewer phase
  want=$(printf '%s\n' '2 codex flag-1' \
                       '3 claude rev-1' '3 claude rev-1' '3 claude rev-2' \
                       '4 codex cost-1' \
                       '5 claude rev-1' '5 claude rev-1' '5 claude rev-2' \
                       '6 codex flag-1' \
                       '7 claude rev-1' '7 claude rev-1' '7 claude rev-2' \
                       '8 codex mid-1' \
                       '9 claude rev-1' '9 claude rev-1' '9 claude rev-2')
  [ "$(cat "$G/.ai/autopilot/dispatches")" = "$want" ]
}
chk 'ladder rung completes the phase: exact primary-then-rung dispatch order' ladder_matrix_ok

# ------------------------------------------------------------------- result --
scrub_env
echo
echo "driver tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

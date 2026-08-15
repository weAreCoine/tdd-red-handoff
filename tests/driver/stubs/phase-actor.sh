#!/bin/sh
# phase-actor.sh — shared brain of the claude/codex stubs used by the driver
# behavior tests. It plays a well-behaved phase worker: answers the preflight
# from the probe file, performs the canonical artifact work of its phase, and
# commits with the semantic prefix + tracker reference the driver checks.
#
# A test scenario overrides a phase by dropping an executable `phase<N>` script
# into $STUB_SCENARIO_DIR: the stub then runs that INSTEAD of the default,
# with PHASE/FEATURE/PROBE/VERDICT/TESTPLAN/PLAN/ADR/FLIGHT_DIR exported.
# The stubs never contain model names: models here are opaque ids.

set -u
PROMPT=$1

PROBE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*read the file \([^ ]*\) with your file tools.*/\1/p' | head -n 1)
PHASE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*phase \([2-9]\) of the unattended flight for feature "[a-z0-9-]*".*/\1/p' | head -n 1)
FEATURE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*phase [2-9] of the unattended flight for feature "\([a-z0-9-]*\)".*/\1/p' | head -n 1)
VERDICT=$(printf '%s\n' "$PROMPT" | grep -oE '[^ ]*verdicts/phase[0-9]+\.d[0-9]+\.json' | head -n 1)

TESTPLAN=.ai/plans/$FEATURE.testplan.md
PLAN=.ai/plans/$FEATURE.md
ADR=.ai/plans/$FEATURE.adr.md
FLIGHT_DIR=.ai/autopilot/$FEATURE
export PHASE FEATURE PROBE VERDICT TESTPLAN PLAN ADR FLIGHT_DIR

# Preflight: the honest answer, unless the scenario breaks this phase's worker
# (STUB_BAD_PREFLIGHT_PHASES: space-separated phase numbers that answer wrong).
case " ${STUB_BAD_PREFLIGHT_PHASES:-} " in
  *" $PHASE "*) echo 'PREFLIGHT: deadbeef-wrong-nonce'; exit 0 ;;
  *) echo "PREFLIGHT: $(cat "$PROBE")" ;;
esac

if [ -n "${STUB_SCENARIO_DIR:-}" ] && [ -f "$STUB_SCENARIO_DIR/phase$PHASE" ]; then
  sh "$STUB_SCENARIO_DIR/phase$PHASE"
  exit $?
fi

set_status() { # $1 = file, $2 = new canonical status value
  sed "s/^> \*\*Status:\*\*.*/> **Status:** $2/" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
stamp() { cat "$PROBE"; }   # per-dispatch nonce: guarantees a content change
commit() { git add -A >/dev/null && git commit -qm "$1"; }

case $PHASE in
  2)
    {
      printf '# Test plan — %s\n\n> **Status:** DRAFT\n\n## Inventory\n\n' "$FEATURE"
      i=0; while [ $i -lt 12 ]; do printf -- '- case %s: input, expected value, boundary noted\n' $i; i=$((i+1)); done
      printf '\n## Log\n\n- stub: inventory written (%s)\n' "$(stamp)"
    } > "$TESTPLAN"
    commit "feat: $FEATURE test inventory (TEST-1)"
    ;;
  3)
    set_status "$TESTPLAN" READY
    printf -- '- stub: inventory gate passed (%s)\n' "$(stamp)" >> "$TESTPLAN"
    commit "docs: $FEATURE inventory gate (TEST-1)"
    printf '{"verdict":"approve","route":"proceed","notes":"inventory ok"}' > "$VERDICT"
    ;;
  4)
    set_status "$TESTPLAN" RED
    printf -- '- stub: tests transcribed, RED verified (%s)\n' "$(stamp)" >> "$TESTPLAN"
    echo "test stub $(stamp)" >> tests.txt
    commit "test: $FEATURE red tests (TEST-1)"
    ;;
  5)
    set_status "$TESTPLAN" APPROVED
    printf -- '- stub: test gate passed (%s)\n' "$(stamp)" >> "$TESTPLAN"
    commit "docs: $FEATURE test gate (TEST-1)"
    printf '{"verdict":"approve","route":"proceed","notes":"tests ok"}' > "$VERDICT"
    ;;
  6)
    {
      printf '# Plan — %s\n\n> **Status:** RED\n\n## 1. Goal\n\nTurn the red tests green.\n\n## 3. Constraints\n\n' "$FEATURE"
      i=0; while [ $i -lt 12 ]; do printf -- '- constraint %s derived from the testplan\n' $i; i=$((i+1)); done
      printf '\n(%s)\n' "$(stamp)"
    } > "$PLAN"
    printf -- '- stub: plan issued (%s)\n' "$(stamp)" >> "$TESTPLAN"
    commit "feat: $FEATURE implementation plan (TEST-1)"
    ;;
  7)
    printf -- '- **Gate:** APPROVED — 2026-08-15, all gate checks passed (CLAUDE.md, gate phase)\n' >> "$PLAN"
    printf -- '- stub: plan gate passed (%s)\n' "$(stamp)" >> "$TESTPLAN"
    commit "docs: $FEATURE plan gate (TEST-1)"
    printf '{"verdict":"approve","route":"proceed","notes":"plan ok"}' > "$VERDICT"
    ;;
  8)
    echo "impl stub $(stamp)" >> src.txt
    commit "feat: $FEATURE implementation (TEST-1)"
    ;;
  9)
    set_status "$PLAN" 'DONE — 2026-08-15'
    printf -- '- stub: final review passed (%s)\n' "$(stamp)" >> "$TESTPLAN"
    commit "docs: $FEATURE final review (TEST-1)"
    printf '{"verdict":"approve","route":"proceed","notes":"ship it"}' > "$VERDICT"
    ;;
  *) echo "phase-actor: unknown phase '$PHASE'" >&2; exit 1 ;;
esac

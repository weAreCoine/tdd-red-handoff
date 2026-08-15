#!/bin/sh
# phase-actor.sh — shared brain of the claude/codex stubs used by the driver
# behavior tests. It plays a well-behaved phase worker: answers the preflight
# from the probe file, performs the canonical artifact work of its phase, and
# commits with the semantic prefix + tracker reference the driver checks.
#
# Invocation (from the stubs): phase-actor.sh <harness> <model id> <prompt>
#
# Before acting it enforces the DRIVER'S dispatch matrix — reviewer phases go
# to the claude family, producer phases to the codex family, and each phase
# carries an id its roster tier defines: the primary, or a rung of that tier's
# configured ladder, never a rung before the primary. Without this, a stub that
# runs any phase for any harness with any id turns the suite green on a driver
# that sent the whole flight through one family, or that tried its fallbacks
# first. Every dispatch is recorded in the gitignored flight dir so a scenario
# can assert the whole sequence.
#
# A test scenario overrides a phase by dropping an executable `phase<N>` script
# into $STUB_SCENARIO_DIR: the stub then runs that INSTEAD of the default,
# with PHASE/FEATURE/PROBE/VERDICT/TESTPLAN/PLAN/ADR/FLIGHT_DIR exported.
# Two failure seams, deliberately different: STUB_BAD_PREFLIGHT_PHASES makes a
# phase answer the nonce wrongly and stop dead, STUB_BAD_NONCE_MODELS makes the
# named model ids answer wrongly while doing their canonical work — only the
# second isolates the driver's nonce predicate from its artifact backstops.
# The stubs never contain model names: models here are opaque ids, and the
# expected id is read from the flight's own models.env by KEY.

set -u
HARNESS=$1
MODEL=$2
PROMPT=$3

PROBE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*read the file \([^ ]*\) with your file tools.*/\1/p' | head -n 1)
PHASE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*phase \([2-9]\) of the unattended flight for feature "[a-z0-9-]*".*/\1/p' | head -n 1)
FEATURE=$(printf '%s\n' "$PROMPT" | sed -n 's/.*phase [2-9] of the unattended flight for feature "\([a-z0-9-]*\)".*/\1/p' | head -n 1)
VERDICT=$(printf '%s\n' "$PROMPT" | grep -oE '[^ ]*verdicts/phase[0-9]+\.d[0-9]+\.json' | head -n 1)

TESTPLAN=.ai/plans/$FEATURE.testplan.md
PLAN=.ai/plans/$FEATURE.md
ADR=.ai/plans/$FEATURE.adr.md
FLIGHT_DIR=.ai/autopilot/$FEATURE
export PHASE FEATURE PROBE VERDICT TESTPLAN PLAN ADR FLIGHT_DIR

[ -n "$PHASE" ] || { echo "phase-actor: no phase in the prompt" >&2; exit 95; }

# The matrix, restated independently of the driver: reviewers on claude,
# producers on codex; each phase's ids read from models.env by their keys.
expect_harness() { case $PHASE in 3|5|7|9) echo claude ;; *) echo codex ;; esac; }
expect_model_key() {
  case $PHASE in
    2|6) echo AP_MODEL_FLAGSHIP ;;
    4)   echo AP_MODEL_COSTEFF ;;
    8)   echo AP_MODEL_MID ;;
    *)   echo AP_MODEL_REVIEW ;;
  esac
}
expect_ladder_key() {
  case $PHASE in
    2|6) echo AP_LADDER_FLAGSHIP ;;
    4)   echo AP_LADDER_COSTEFF ;;
    8)   echo AP_LADDER_MID ;;
    *)   echo AP_LADDER_REVIEW ;;
  esac
}
cfg() { sed -n "s/^$1='\([^']*\)'[[:space:]]*\$/\1/p" .ai/autopilot/models.env | head -n 1; }
rank() { # position of $1 in the allowed list, 0 if absent
  r=0; i=0
  for id in $ALLOWED; do i=$((i + 1)); [ "$id" = "$1" ] && r=$i; done
  echo "$r"
}

[ "$HARNESS" = "$(expect_harness)" ] \
  || { echo "phase-actor: phase $PHASE dispatched to '$HARNESS', expected '$(expect_harness)'" >&2; exit 96; }

KEY=$(expect_model_key); LKEY=$(expect_ladder_key)
PRIMARY=$(cfg "$KEY"); LADDER=$(cfg "$LKEY")
ALLOWED="$PRIMARY${LADDER:+ $LADDER}"
[ -n "$PRIMARY" ] || { echo "phase-actor: phase $PHASE has no $KEY in models.env" >&2; exit 96; }
MINE=$(rank "$MODEL")
[ "$MINE" -gt 0 ] \
  || { echo "phase-actor: phase $PHASE ran model '$MODEL', expected $KEY/$LKEY ('$ALLOWED')" >&2; exit 96; }
# The ladder is ordered: the primary is tried first, a rung only after it.
PREV=$(awk -v p="$PHASE" '$1 == p { last = $3 } END { print last }' .ai/autopilot/dispatches 2>/dev/null)
[ -z "$PREV" ] || [ "$MINE" -ge "$(rank "$PREV")" ] \
  || { echo "phase-actor: phase $PHASE went back to '$MODEL' after '$PREV' — ladder order broken" >&2; exit 96; }
printf '%s %s %s\n' "$PHASE" "$HARNESS" "$MODEL" >> .ai/autopilot/dispatches

# Preflight, three ways. STUB_BAD_PREFLIGHT_PHASES: this phase answers wrong
# and stops dead — a worker that produced nothing. STUB_BAD_NONCE_MODELS: this
# MODEL answers wrong but goes on to do its canonical work, so the only thing
# left to reject the attempt is the driver's nonce predicate itself.
case " ${STUB_BAD_PREFLIGHT_PHASES:-} " in
  *" $PHASE "*) echo 'PREFLIGHT: deadbeef-wrong-nonce'; exit 0 ;;
esac
case " ${STUB_BAD_NONCE_MODELS:-} " in
  *" $MODEL "*) echo 'PREFLIGHT: deadbeef-wrong-nonce' ;;
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
      printf '\n## 6. Log (append-only)\n\n- stub: inventory written (%s)\n' "$(stamp)"
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
    printf -- '- **Implementation:** GREEN — 2026-08-15, full suite + typecheck (Implementer)\n' >> "$TESTPLAN"
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

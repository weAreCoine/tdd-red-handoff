---
description: Switch the active kit profile (two-role | pipeline) — rewrite the CLAUDE.md import line and .ai/kit.json, nothing else; refuse if a testplan is in flight.
---

# /switch-profile `<two-role|pipeline>`

Switch **this** project's active profile. The switch is mechanical, offline, and lossless: both
process chapters are installed, so changing profile rewrites exactly **two things** — line 1 of
`CLAUDE.md` and the `profile` field of `.ai/kit.json`. Nothing else may restate the active
profile, so nothing else is touched.

> **No model check.** This command makes no spec decision: it repoints an import and runs
> checks. Any model tier can run it.

## Phase 0 — Preconditions

1. **Argument.** One of `two-role` | `pipeline`. Missing or anything else → STOP and ask.
2. **Profile-aware installation.** `.ai/kit.json` exists, `CLAUDE.md` line 1 is an
   `@.ai/process/….md` import, and **both** chapter files exist in `.ai/process/`. If `kit.json`
   is missing, this is a pre-profile installation → STOP and point the user to
   `/init-architecture` (its re-init path upgrades in place).
3. **Same profile?** If `kit.json` already names the requested profile, report "already active"
   and STOP — do not rewrite files to their own content.

## Phase 1 — Refusal rule (protects in-flight specification work)

Read every `.ai/plans/*.testplan.md`. If **any** has `Status` of `DRAFT`, `READY`, `RED` or
`REJECTED(n)` — i.e. no implementation plan was issued yet — **STOP**: name the feature and its
status, explain that the destination profile has no role that reads a testplan, and ask for
explicit confirmation before proceeding. Switching happens **between tasks**; this refusal
should be rare, and overriding it is the user's call, never yours.

`APPROVED` testplans (plan already issued) and plain `{feature}.md` plans don't block: plans are
readable under both profiles, and testplans simply go **inert** — never rewritten, moved, or
deleted; they come back to life on the way back to pipeline.

## Phase 2 — Apply

1. `CLAUDE.md` line 1 → `@.ai/process/<profile>.md` (the line is the whole change — do not
   touch the rest of the file: the overlay does not vary by profile).
2. `.ai/kit.json` → `"profile": "<profile>"`.

## Phase 3 — Self-check

The triad must agree — verify, don't assume:

```bash
head -n 1 CLAUDE.md            # @.ai/process/<profile>.md
grep '"profile"' .ai/kit.json  # same value
ls .ai/process/<profile>.md    # chapter exists
```

If `bin/verify-kit.sh` is reachable (kit repo checkout — pre-plugin it is not shipped into
targets), run it for the full mechanical pass: the `kit-manifest` check covers exactly this.

## Phase 4 — Report

- Old profile → new profile; the two files touched (never more — more means a bug).
- Which artifacts went inert (testplans, when leaving pipeline) or live again (when returning).
- The next task starts per the new chapter's roles, models from
  `.ai/PROJECT_ARCHITECTURE.md § Model Roster`.

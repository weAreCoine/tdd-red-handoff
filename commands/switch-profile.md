---
description: Switch the active kit profile (two-role | pipeline | autopilot) — rewrite the CLAUDE.md import line and .ai/kit.json, nothing else; refuse if a testplan or a flight is in flight.
---

# /switch-profile `<two-role|pipeline|autopilot>`

Switch **this** project's active profile. The switch is mechanical, offline, and lossless: all
process chapters are installed, so changing profile rewrites exactly **two things** — line 1 of
`CLAUDE.md` and the `profile` field of `.ai/kit.json`. Nothing else may restate the active
profile, so nothing else is touched.

> **No model check.** This command makes no spec decision: it repoints an import and runs
> checks. Any model tier can run it.

## Phase 0 — Preconditions

1. **Argument.** One of `two-role` | `pipeline` | `autopilot`. Missing or anything else → STOP and ask.
2. **Profile-aware installation.** `.ai/kit.json` exists, `CLAUDE.md` line 1 is an
   `@.ai/process/….md` import, and the **destination's** chapter file exists in `.ai/process/`
   (an install predating that chapter → point to `/update-kit` first). If `kit.json`
   is missing, this is a pre-profile installation → STOP and point the user to
   `/init-architecture` (its re-init path upgrades in place).
3. **Same profile?** If `kit.json` already names the requested profile, report "already active"
   and STOP — do not rewrite files to their own content.

## Phase 1 — Refusal rules (protect in-flight work)

**Testplans.** This rule fires only when the **destination** profile has no role that continues
an in-flight testplan (today: `two-role`, and `autopilot` — a flight produces its own artifacts
from a fresh interview and never adopts a half-done testplan). Switching **to** `pipeline`
never blocks — it *revives* inert **pipeline** testplans rather than orphaning them (a feature
with a sibling `{feature}.adr.md` design record is an autopilot flight and stays inert under
every profile — extended inertness).

Read every `.ai/plans/*.testplan.md`. If **any** has `Status` of `DRAFT`, `READY`, `RED` or
`REJECTED(n)` — i.e. no implementation plan was issued yet — **STOP**: name the feature and its
status, explain that the destination profile has no role that continues it, and ask for
explicit confirmation before proceeding. Switching happens **between tasks**; this refusal
should be rare, and overriding it is the user's call, never yours.

**Flights.** When leaving `autopilot`, read every `.ai/autopilot/*/status` file:

- Any `RUNNING` → **STOP** — a driver is (or believes it is) mid-flight; stop or finish the
  flight first. Not overridable by confirmation: two contracts steering one repo is never sane.
- Any `STOPPED` or `PUSHED` → an interrupted flight whose artifacts are mid-lifecycle. STOP,
  name the feature and its last state, and ask for explicit confirmation: switching abandons
  the flight (its artifacts go inert — the other chapters refuse to adopt them), and the way
  back is relaunching the driver under autopilot, not continuing under another profile.

`APPROVED` testplans (plan already issued) and plain `{feature}.md` plans don't block: plans are
readable under every profile, and testplans simply go **inert** — never rewritten, moved, or
deleted; those without a sibling design record come back to life on the way back to pipeline,
while ADR-signed sets stay autopilot's.

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

Then run the script the plugin ships for the full mechanical pass — the `kit-manifest` check
covers exactly this, and `-p` adds the install-integrity checks (chapters and per-feature
templates byte-identical to the plugin, `kitVersion` current):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" -p "${CLAUDE_PLUGIN_ROOT}" .
```

A `kit-version` or `install-files` FAIL here is **pre-existing drift, not a switch bug** — the
switch touched exactly two files, neither of them a shipped kit file. Report the switch as done,
report the drift separately, and point to `/update-kit` (which never changes the profile).

## Phase 4 — Report

- Old profile → new profile; the two files touched (never more — more means a bug).
- Which artifacts went inert (testplans, when leaving pipeline) or live again (when returning).
- The next task starts per the new chapter's roles, models from
  `.ai/PROJECT_ARCHITECTURE.md § Model Roster`.

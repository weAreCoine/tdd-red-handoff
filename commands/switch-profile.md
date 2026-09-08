---
description: Switch the active kit profile (two-role | pipeline | autopilot | free) — rewrite the CLAUDE.md import line and .ai/kit.json, plus the AGENTS.md park/restore when free is at either end; refuse if a testplan or a flight is in flight.
---

# /switch-profile `<two-role|pipeline|autopilot|free>`

Switch **this** project's active profile. The switch is mechanical, offline, and lossless: all
process chapters are installed, so changing profile rewrites exactly **two things** — line 1 of
`CLAUDE.md` and the `profile` field of `.ai/kit.json`. Nothing else may restate the active
profile, so nothing else is touched — with **one addition when `free` is at either end** of the
switch: the implementer contract `AGENTS.md` is parked on the way in and restored on the way out
(Phase 2). Under `free`, `AGENTS.md` is a symlink to `CLAUDE.md`, so every tool reads one file.

> **No model check.** This command makes no spec decision: it repoints an import, moves one
> file when `free` is involved, and runs checks. Any model tier can run it.

## Phase 0 — Preconditions

1. **Argument.** One of `two-role` | `pipeline` | `autopilot` | `free`. Missing or anything else
   → STOP and ask.
2. **Profile-aware installation.** `.ai/kit.json` exists, `CLAUDE.md` line 1 is an
   `@.ai/process/….md` import, and the **destination's** chapter file exists in `.ai/process/`
   (an install predating that chapter — `free.md` on a pre-1.6 install — → point to
   `/update-kit` first). If `kit.json` is missing, this is a pre-profile installation → STOP
   and point the user to `/init-architecture` (its re-init path upgrades in place).
3. **Same profile?** If `kit.json` already names the requested profile, report "already active"
   and STOP — do not rewrite files to their own content.
4. **The implementer contract's shape** — checked before any write, fail-closed:
   - **Entering `free`**: `AGENTS.md` must be a regular file (not a symlink) and
     `.ai/AGENTS.parked.md` must **not** exist. An `AGENTS.md` that is already a symlink, or a
     parked file already present, means an earlier switch was left half-done: STOP, name what
     you found, and let the user sort it out — never overwrite an earlier parked contract.
   - **Leaving `free`**: `.ai/AGENTS.parked.md` must exist as a regular file. If it is missing,
     STOP: the kit **never regenerates `AGENTS.md` from the template** on this path — that would
     silently lose the project's edits to its implementer contract. The user recovers the parked
     file (git history, a branch, another clone) and reruns.
   - **Neither end is `free`**: nothing to check here.

## Phase 1 — Refusal rules (protect in-flight work)

**Testplans.** This rule fires only when the **destination** profile has no role that continues
an in-flight testplan (today: `two-role`, `autopilot` — a flight produces its own artifacts
from a fresh interview and never adopts a half-done testplan — and `free`, which has no roles
at all and writes nothing in `.ai/plans/`). Switching **to** `pipeline` never blocks — it
*revives* inert **pipeline** testplans rather than orphaning them (a feature with a sibling
`{feature}.adr.md` design record is an autopilot flight and stays inert under every profile —
extended inertness).

Read every `.ai/plans/*.testplan.md`. If **any** has `Status` of `DRAFT`, `READY`, `RED` or
`REJECTED(n)` — i.e. no implementation plan was issued yet — **STOP**: name the feature and its
status, explain that the destination profile has no role that continues it, and ask for
explicit confirmation before proceeding. Switching happens **between tasks**; this refusal
should be rare, and overriding it is the user's call, never yours.

**Flights.** When leaving `autopilot` (to any destination, `free` included), read every
`.ai/autopilot/*/status` file:

- Any `RUNNING` → **STOP** — a driver is (or believes it is) mid-flight; stop or finish the
  flight first. Not overridable by confirmation: two contracts steering one repo is never sane.
- Any `STOPPED` or `PUSHED` → an interrupted flight whose artifacts are mid-lifecycle. STOP,
  name the feature and its last state, and ask for explicit confirmation: switching abandons
  the flight (its artifacts go inert — the other chapters refuse to adopt them), and the way
  back is relaunching the driver under autopilot, not continuing under another profile.

`APPROVED` testplans (plan already issued) and plain `{feature}.md` plans don't block: plans are
readable under every profile, and testplans simply go **inert** — never rewritten, moved, or
deleted; those without a sibling design record come back to life on the way back to pipeline,
while ADR-signed sets stay autopilot's. Under `free` **every** artifact is inert, and the
profile writes no new one.

## Phase 2 — Apply

1. `CLAUDE.md` line 1 → `@.ai/process/<profile>.md` (the line is the whole change — do not
   touch the rest of the file: the overlay does not vary by profile).
2. `.ai/kit.json` → `"profile": "<profile>"`.
3. **Only when `free` is at either end** — the implementer contract moves, as a tracked move so
   it stays versioned (Phase 0 step 4 already verified the shape):
   - **Entering `free`:**
     ```bash
     git mv AGENTS.md .ai/AGENTS.parked.md
     ln -s CLAUDE.md AGENTS.md          # the symlink points at the file that carries the line-1 import
     ```
     The direction is always `AGENTS.md → CLAUDE.md`: the real file is the one with the import.
   - **Leaving `free`:**
     ```bash
     rm AGENTS.md                       # the symlink, nothing else
     git mv .ai/AGENTS.parked.md AGENTS.md
     ```
   Tool-specific folders (`.codex/`, `.agents/`, `.claude/`, `.factory/`) are never touched: the
   switch changes only files the kit owns. Live docs and `.ai/plans/` are never touched either.

## Phase 3 — Self-check

The triad must agree — verify, don't assume:

```bash
head -n 1 CLAUDE.md            # @.ai/process/<profile>.md
grep '"profile"' .ai/kit.json  # same value
ls .ai/process/<profile>.md    # chapter exists
ls -l AGENTS.md .ai/AGENTS.parked.md 2>&1
                               # free: AGENTS.md -> CLAUDE.md, parked file present
                               # any other profile: AGENTS.md a regular file, no parked file
```

Then run the script the plugin ships for the full mechanical pass — the `kit-manifest` check
covers the triad, `free-shape` covers the symlink/parked-file shape under every profile, and
`-p` adds the install-integrity checks (chapters and per-feature templates byte-identical to the
plugin, `kitVersion` current):

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" -p "${CLAUDE_PLUGIN_ROOT}" .
```

A `kit-version` or `install-files` FAIL here is **pre-existing drift, not a switch bug** — the
switch touched the two restating files and, with `free` involved, the implementer contract's
location, none of them a shipped kit file. Report the switch as done, report the drift
separately, and point to `/update-kit` (which never changes the profile and never touches
`AGENTS.md` or the parked file). A `free-shape` FAIL **is** a switch bug: stop and show it.

## Phase 4 — Report

- Old profile → new profile; the files touched: the two restating files, plus the `AGENTS.md`
  move when `free` is at either end (never more — more means a bug).
- Which artifacts went inert (testplans, when leaving pipeline; everything, when entering
  `free`) or live again (when returning to a profile that reads them).
- The state of the implementer contract: parked at `.ai/AGENTS.parked.md` with `AGENTS.md` a
  symlink to `CLAUDE.md` (entered `free`), restored from it (left `free`), or untouched.
- The next task starts per the new chapter: its roles and their models from
  `.ai/PROJECT_ARCHITECTURE.md § Model Roster` — or, under `free`, no role and no model check,
  the shell below line 1 and the facts contract still binding.

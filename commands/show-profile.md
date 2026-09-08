---
description: Print the active kit profile (two-role | pipeline | autopilot | free) — read-only; reads the profile triad and reports drift instead of guessing.
---

# /show-profile

Print **this** project's active profile. The command is read-only: it writes nothing and asks
nothing — it reads the **profile triad** (the three places that must agree on the active
profile) and reports what it finds. Changing the profile is `/switch-profile`'s job, never
this command's.

> **No model check.** This command makes no spec decision: it reads three values and reports.
> Any model tier can run it.

## Phase 0 — Locate the installation

If `.ai/kit.json` is missing, this is not a profile-aware installation — report that and point
the user to `/init-architecture` (fresh bootstrap; its appendix and re-init paths cover legacy
and pre-profile installs), then STOP. Do not guess a profile from the other files: without the
manifest there is no triad to agree.

## Phase 1 — Read the triad

Three values must name the same profile — collect all three, take none on assumption:

```bash
grep '"profile"' .ai/kit.json   # the manifest field
head -n 1 CLAUDE.md             # @.ai/process/<profile>.md import
ls .ai/process/                 # the named chapter must exist
```

While in `kit.json`, also read `kitVersion` — the install stamp, reported alongside.

When the manifest says `free`, also look at the implementer contract's shape — read, not
repaired:

```bash
ls -l AGENTS.md .ai/AGENTS.parked.md 2>&1   # expected: AGENTS.md -> CLAUDE.md, parked file present
```

## Phase 2 — Report

**Triad agrees** (the normal case):

- **Active profile** — `two-role` (Architect + Implementer), `pipeline` (Designer /
  Test-Writer / Verifier + Implementer), `autopilot` (nine phases flown unattended by the
  driver, `/fly` opens a flight) or `free` (no role, no phase, no wall, no TDD order, no
  roster model check — the shell below line 1 and the facts contract still bind). Models
  resolve per role in `.ai/PROJECT_ARCHITECTURE.md § Model Roster`; under `free` there is no
  role to resolve.
- **Under `free` only** — where the implementer contract is: `AGENTS.md` is a symlink to
  `CLAUDE.md` (every tool reads one file) and the contract is parked at
  `.ai/AGENTS.parked.md`. If the shape differs from that — `AGENTS.md` a regular file, the
  parked file missing, the symlink pointing elsewhere — say so verbatim: a half-done switch,
  which `/verify-kit`'s `free-shape` check reports as a FAIL. Repair nothing here.
- **Kit version** — the `kitVersion` stamp from `.ai/kit.json`.
- Pointers: `/switch-profile` changes the profile; `/verify-kit` runs the full mechanical pass
  (this command checks the triad and nothing else).

**Triad disagrees**: report each source's value verbatim and stop — never pick a winner, never
repair (read-only). Route by symptom:

- Sources name different profiles → `/switch-profile <wanted>` rewrites both restating files
  back into agreement.
- A chapter file is missing from `.ai/process/` → `/update-kit` reinstalls the shipped files.

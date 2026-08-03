---
description: Record a model change in the Model Roster — the single place concrete model names live. New names come from the user, never from the agent's memory; self-checks that no name leaked into process files.
---

# /update-models-roster

Update the **Model Roster** — the single location where concrete model names live (Contract §6
of `PROJECT_ARCHITECTURE.md`). Every other kit file refers to models by role ("the Designer's
model"), so a model change should touch **only roster cells**. This command applies the change
and proves that invariant still holds.

> **No model check.** Unlike `/init-architecture` and `/migrate-architecture`, this command makes
> no spec decision: it transcribes the user's choice and runs greps. Any model tier can run it.

## Phase 0 — Locate the roster(s)

- **Bootstrapped project** — `.ai/PROJECT_ARCHITECTURE.md § Model Roster` exists → that table is
  the target.
- **Kit repo, or a project not yet initialized** — no live doc, but
  `.ai/templates/PROJECT_ARCHITECTURE.template.md` carries the prefilled roster → that table is
  the target. If the repo's README carries the kit's defaults table (i.e. this is the kit repo
  itself), update it in the same pass — those are the only two concrete-name locations there.
- Neither file exists → STOP: there is no roster to update; point the user to `/init-architecture`.

## Phase 1 — Collect the new lineup (INTERACTIVE)

1. Show the current roster table.
2. Ask which role(s) change and to **what**. The new model names come **from the user, never from
   your own knowledge** — your model list may be stale (same rule as versions-from-the-lockfile:
   facts come from a source, and here the source is the user). Do not propose a lineup from memory.
3. Sanity-check each pick against the role's **capability profile** (the roster's middle column):
   the Test-Writer slot on the scarcest tier, or the Designer slot on a cost-efficient tier,
   inverts the kit's economics. If a pick fights its profile, say so plainly — then let the user
   decide. Update the profile text only if the user explicitly redefines it.

## Phase 2 — Apply

Edit **only** the roster cell(s) agreed in Phase 1 (plus the README defaults table when Phase 0
identified the kit repo). No other file should need touching — that is the invariant working.

## Phase 3 — Self-check

1. Grep each **old** model name across the repo's process and facts files (`CLAUDE.md`,
   `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`, `.claude/commands/*.md`; in the kit repo also the
   templates and README). Any hit is a leak — someone inlined a name since the last update. Fix
   it (make it role-relative) and report it. Historical artifacts (`.ai/plans/*` Logs, ADRs) may
   keep old names — they are records, not references.
2. Grep each **new** name: hits are allowed only in the roster location(s) found in Phase 0.

## Phase 4 — Report

- Old → new, per role.
- Files touched (expected: one; two in the kit repo).
- Any leaks found in Phase 3 and where they were fixed — each one is a process-file regression
  worth flagging, not just cleanup.

---
description: Record a model change — or a temporary tier substitution — in the Model Roster, the single place concrete model names live. New names come from the user, never from the agent's memory; self-checks that no name leaked into process files.
---

# /update-models-roster

Update the **Model Roster** — the single location where concrete model names live (Contract §6
of `PROJECT_ARCHITECTURE.md`). Every other kit file refers to models by role ("the Designer's
model"), so a model change should touch **only roster cells**. This command applies the change
and proves that invariant still holds.

> **No model check.** Unlike `/init-architecture`, this command makes no spec decision: it
> transcribes the user's choice and runs greps. Any model tier can run it.

## Phase 0 — Locate the roster(s)

- **Bootstrapped project** — `.ai/PROJECT_ARCHITECTURE.md § Model Roster` exists → that table is
  the target.
- **Kit repo checkout** — no live doc, but the working tree itself carries
  `.ai/templates/PROJECT_ARCHITECTURE.template.md` with the prefilled roster → that table is the
  target, together with the README's defaults table — those are the kit repo's only two
  concrete-name locations.
- **Neither** → STOP: there is no roster to update; point the user to `/init-architecture`.
  Never edit the plugin's own copies under `${CLAUDE_PLUGIN_ROOT}` — that is a managed cache:
  changes there are lost on update and would bleed into every project. Kit defaults change in
  the kit repository.

## Phase 1 — Collect the new lineup (INTERACTIVE)

0. Establish **which of the two changes** this is — they are recorded in different places and
   confusing them loses information:
   - **Permanent reassignment** — the project wants a different model for a role from now on
     (new generation shipped, cost rebalanced) → edit the role's `Current model` cell.
   - **Tier substitution** — the roster's tier is temporarily unavailable (quota exhausted, access
     revoked, provider outage) and the role runs below it meanwhile → add a line to
     `### Tier substitutions (temporary)`, and **leave the table untouched**. The cell states the
     tier the project wants; overwriting it would erase that and hide, from every later reader,
     that the work ran below tier. Lifting a substitution = deleting its line.
   If the user's phrasing is ambiguous ("let's use the other model for now"), ask which one it is
   before editing anything.
1. Show the current roster table, and the substitution block if it has lines.
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

For a **tier substitution**, the edit is instead one line in `### Tier substitutions (temporary)`.
If that subsection is missing — the project's roster was written by a kit version that predates it —
create it directly under the roster table, with its heading and its note, then add the line. That is
the one case where this command adds a section to a live doc rather than editing a cell; a
`/update-kit` cannot do it for you, because the roster is a project fact and that command only
realigns the files that ship verbatim. The line carries: role, the model actually running, since when, until when (a date or the condition that
lifts it), and why the roster tier is unavailable. The README defaults table is never touched by a
substitution — it documents the kit's defaults, not one project's outage. Say plainly what the
substitution costs: a design-side role below tier decides worse where decisions propagate, and
when the substitute is the model of the role that reviews it, the gate loses its independence.
Then let the user decide — it is their call, and they may have nothing better available.

## Phase 3 — Self-check

1. Grep each **old** model name across the repo's process and facts files (`CLAUDE.md`,
   `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`, `.ai/process/`, `.ai/templates/`; in the kit repo
   also `commands/*.md` and the README). Any hit is a leak — someone inlined a name since the last update. Fix
   it (make it role-relative) and report it. Historical artifacts (`.ai/plans/*` Logs, ADRs) may
   keep old names — they are records, not references.
2. Grep each **new** name: hits are allowed only in the roster location(s) found in Phase 0.

## Phase 4 — Report

- Old → new, per role — or, for a substitution: role, substitute, and what lifts it.
- Files touched (expected: one; two in the kit repo).
- For a substitution, remind the user of the two downstream effects they will see: the design-side
  chapters now let a mismatched session proceed **for that role only**, declaring itself; and each
  artifact produced meanwhile records the substitution, permanently.
- Any leaks found in Phase 3 and where they were fixed — each one is a process-file regression
  worth flagging, not just cleanup.

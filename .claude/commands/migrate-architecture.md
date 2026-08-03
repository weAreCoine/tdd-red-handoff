---
description: Migrate a project bootstrapped with the old two-role kit (architect + implementer) to the multi-model design pipeline (Designer / Test-Writer / Verifier) — preserve every project fact, replace only process text, reconcile in-flight plans.
---

# /migrate-architecture

Upgrade **this** repository's live architecture docs from the old two-role kit to the
multi-model design pipeline. Work the phases **in order** — later ones depend on earlier output.

**What "old" and "new" mean here:**

| | Old kit (two roles) | New kit (pipeline) |
|---|---|---|
| `CLAUDE.md` | Single **architect** role; 4-phase TDD workflow; architect writes the tests AND the plan | **Designer / Test-Writer / Verifier** on three model tiers; 5-phase pipeline; gate + escalation rules |
| Artifacts per feature | One: `{feature}.md` (plan) | Two: `{feature}.testplan.md` (test-case inventory) + `{feature}.md` (plan, issued only after the gate) |
| `AGENTS.md` | Counterpart is "the architect" | Counterpart is the design pipeline; plan must carry `Gate: APPROVED` |
| `.ai/PROJECT_ARCHITECTURE.md` | References CLAUDE.md "Phase 4" | References the new phase numbering (2, 3, 5) |

The migration replaces **process** text only. **Facts** (stack, versions, commands, layer map,
traps, coverage floor) were expensive to establish at init and must survive **unchanged**. If a
fact changes during this migration, that is a bug in the migration, not an improvement.

> **Model check first.** This command rewrites the process contract — an escalation-tier task
> (`CLAUDE.md § Escalation`, trigger 4): it must run on **Claude Fable 5**. If the session is
> on another model, tell the user and stop before Phase 0.

## Phase 0 — Preconditions

1. **New kit files are present.** `.ai/templates/test_plan_template.md` must exist, and
   `.ai/templates/CLAUDE.template.md` must contain the phase/model table (grep for `Test-Writer`).
   If not, the user copied this command without the new templates — STOP and tell them to re-copy
   the kit's directories from the kit repo over this project (the same command that delivered
   this file):
   ```bash
   cp -r .ai .claude /path/to/this/project/
   ```
   That copy is safe: it overwrites only templates and commands (process files, never edited per
   project) and touches neither the live docs nor `.ai/plans/`.
2. **Live docs exist**: `CLAUDE.md`, `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`. If any is
   missing, this is not a migration — STOP and point the user to `/init-architecture`.
3. **Old format confirmed.** The live `CLAUDE.md` must match the old kit: it contains
   `You are the **architect**` and does **not** mention `Test-Writer`. If it already describes
   the pipeline, the project is migrated — report that and STOP.
4. **Git safety.** The working tree must be clean (at minimum: the three live docs unmodified).
   The migration must land as one reviewable diff — never mix it with other pending changes.
   Recommend a dedicated branch (e.g. `chore/migrate-design-pipeline`).

## Phase 1 — Inventory (read-only; write nothing yet)

Build the list of everything project-specific in the live docs. These are the sections that
carried `FILL` / `[[DECISION]]` markers in the templates — the init resolved them with real
project facts:

- **`CLAUDE.md`**: § Architecture (the resolved A/B/C structural model and layer notes),
  § Non-Obvious Traps, § What NOT to Test (the project-specific exclusions), § Coverage Targets
  (the floor and any per-layer targets), § Conventions, § Reference (preferred doc sources).
- **`AGENTS.md`**: § Code Conventions, § Layered Architecture (the resolved A/B/C branch),
  § Non-Obvious Traps, § Reference.
- **User-added content**: any heading or passage in a live doc with no counterpart in the
  templates. Carry it over verbatim — it exists because someone needed it.

Record the **coverage floor** value explicitly: it must come out of the migration identical in
`CLAUDE.md` and `PROJECT_ARCHITECTURE.md`.

Then list `.ai/plans/*.md` and classify each plan: **done** (implemented and reviewed — check
git history or ask) vs **in-flight**. Old-format plans have no sibling `{feature}.testplan.md`
and no `Gate:` line in their §3.

Summarize the full inventory before writing anything.

## Phase 2 — Migrate `CLAUDE.md` (rebuild + graft)

The process body changed too much for spot edits — rebuild it:

1. Replace `CLAUDE.md` with the contents of `.ai/templates/CLAUDE.template.md`.
2. **Graft** each fact section from the Phase-1 inventory into its counterpart section,
   resolving that section's `FILL` / `[[DECISION]]` markers exactly as the old file had resolved
   them. Same architecture branch, same traps, same floor, same doc sources — verbatim, not
   paraphrased.
3. **Renumber stale phase references** inside grafted content. Old → new: Phase 1 (Analyze) →
   Phase 1 (Design) · Phase 2 (Write Tests) → Phase 2 (Test Transcription) · Phase 3 (Handoff
   Plan) → Phase 3 (Gate & Plan) · Phase 4 (Review) → **Phase 5** (Review).
4. Re-append user-added sections where they sat before.

## Phase 3 — Migrate `AGENTS.md` and `.ai/PROJECT_ARCHITECTURE.md` (targeted edits)

These files are mostly facts; the process delta is small. Edit **in place** — do not rebuild —
and take every replacement text **from the current templates, not from memory**:

- **`AGENTS.md`**
  - Header blockquote: replace the "architect's counterpart" line with the design-pipeline
    counterpart text (template lines 6–8).
  - Step 1: add the gate qualifier — the plan is issued by the Verifier after the gate, and a
    plan without `Gate: APPROVED` in its §3 is not ready.
  - § Layered Architecture blockquote: "The architect's principle" → "The design pipeline's
    principle".
- **`.ai/PROJECT_ARCHITECTURE.md`**
  - Header blockquote: `CLAUDE.md` is now "the design pipeline: Designer / Test-Writer /
    Verifier", not "(architect)".
  - Contract invariant 1: `CLAUDE.md Phase 4` → `CLAUDE.md Phases 2, 3 and 5`.
  - § Documentation: `CLAUDE.md Phase 4 step 6` → `CLAUDE.md Phase 5 step 6`.

## Phase 4 — In-flight plans (INTERACTIVE — the only human gate)

Never silently rewrite plan files. For each old-format plan found in Phase 1:

- **Done** (implemented and reviewed) → historical record. Leave untouched.
- **In-flight** → present the choice per feature and wait for the user:
  - **(a) Grandfather** — the implementer proceeds on the old plan as-is; no testplan, no gate.
    Fastest; the feature ships without the gate's guarantee.
  - **(b) Re-enter the pipeline** — the Designer (Fable 5) retro-writes the testplan from the
    existing tests, the Verifier gates them and reissues the plan. Full guarantee; costs one
    Designer pass and one gate pass.

  Recommend (a) when implementation is already underway, (b) when tests exist but implementation
  hasn't started — but the user decides.

## Phase 5 — Self-check

Run both greps. Each must return **nothing**:

```bash
grep -nE 'FILL:|\[\[DECISION' CLAUDE.md AGENTS.md .ai/PROJECT_ARCHITECTURE.md
grep -nwiE 'architect' CLAUDE.md AGENTS.md .ai/PROJECT_ARCHITECTURE.md   # -w: "architecture" won't match
```

Any hit in the first = an unresolved marker; in the second = old role vocabulary that survived.
Fix and re-run. Then re-verify the five Contract invariants (`PROJECT_ARCHITECTURE.md
§ Contract`) — especially that the coverage floor is **identical** in both files and every
command name referenced by CLAUDE/AGENTS still has a § Toolchain row. Finally, diff the facts
against the Phase-1 inventory: every fact must be byte-identical. Surviving `TODO`s from before
the migration stay — they're open decisions, not migration debt.

## Phase 6 — Report

Tell the user:
- Per-file summary of what changed (process text only) and what was carried over (architecture
  model, coverage floor, traps, conventions, doc sources, user-added sections).
- The in-flight plan decision log: which features were grandfathered, which re-enter the pipeline.
- Any `TODO`s still open, with why.
- That the next feature starts with the Designer (Fable 5) per `CLAUDE.md § Pipeline`, and that
  re-entered features resume at Phase 1 (retro-testplan).

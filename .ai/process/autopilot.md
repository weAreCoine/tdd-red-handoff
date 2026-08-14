# Process chapter — `autopilot` profile

> This file is the roles-and-phases contract of the **autopilot** profile. It ships verbatim with
> the kit: it carries no fill markers and no project facts, and a target project never edits it.
> Switching profiles repoints the import on line 1 of `CLAUDE.md` and the `profile` field of
> `.ai/kit.json` — nothing else. Project facts live in `.ai/PROJECT_ARCHITECTURE.md`; the shared
> process sections and the project overlay follow this import in `CLAUDE.md`.

## What this profile is

A feature crosses the whole TDD wall **unattended**. The operator appears exactly twice: a
design interview at the start (`/fly <feature>`), a report plus a draft PR at the end. In
between, phases 2–9 run as headless sessions chained by the **driver** — a deterministic
script that dispatches, counts, and stops; it decides nothing. One **flight** = one feature =
one PR; the process terminates at the final review. There is no continuous loop.

**The hard wall is unchanged:** whoever writes tests never writes application code, and the
implementer never touches tests. Every phase boundary is an artifact in `.ai/plans/` — if it's
not in the artifact, the next phase doesn't know it.

**The family invariant:** one model family designs and judges (phases 1, 3, 5, 7, 9); the
other produces (phases 2, 4, 6, 8). Four produced artifacts, four cross-family gates. No
artifact is ever judged by the family that produced it, so a family's shared blind spots
cannot approve their own output.

## The nine phases

| # | Phase | Role | Capability tier (see roster) | Session | Output |
|---|-------|------|------------------------------|---------|--------|
| 1 | Design interview | **Designer** | strongest reasoning tier | interactive, with the operator | branch from the base branch, tracker issue → in progress, `{feature}.adr.md`, commit |
| 2 | Test inventory | **TestPlan Designer** | flagship production tier | headless, agentic | `{feature}.testplan.md` (`DRAFT`), commit |
| 3 | Inventory gate | **TestPlan Reviewer** | strong review tier | headless | routed verdict; approval grants `READY` |
| 4 | Test transcription | **Test Writer** | cost-efficient production tier | headless, agentic | RED tests, commit; testplan → `RED` |
| 5 | Test gate | **Test Reviewer** | strong review tier | headless | routed verdict → `APPROVED` / `REJECTED(n)` |
| 6 | Implementation plan | **Handoff Planner** | flagship production tier | headless, agentic | `{feature}.md`, commit |
| 7 | Plan gate | **Plan Reviewer** | strong review tier | headless | `Gate: APPROVED` on the plan |
| 8 | Implementation | **Implementer** | mid production tier | headless, agentic | minimum code until GREEN, commit |
| 9 | Final review | **Final Reviewer** | strong review tier | headless | `DONE` on the plan, push, draft PR, report |

Backward edges: 3 rejects → 2 · 4 blocked → 2 · 5 minor → 4, structural → 2 · 7 rejects → 6 ·
8 blocked → 6 · 9 minor → 8, structural → 6. Re-entry **always passes the gate again**: an
amended testplan re-passes phase 3, an amended plan re-passes phase 7. No amended artifact
reaches its consumer ungated.

## Models: roster, binding, ladders

Concrete model names are **not written here**: each role resolves in
**`.ai/PROJECT_ARCHITECTURE.md § Model Roster`** — the only place a model name appears; record
changes with `/update-models-roster`. The autopilot subset of the union roster:

- The **Designer** resolves to the Designer row.
- The four reviewer roles — **TestPlan Reviewer**, **Test Reviewer**, **Plan Reviewer**,
  **Final Reviewer** — all resolve to the **Verifier** row (the strong review tier).
- The production roles — **TestPlan Designer** and **Handoff Planner** (flagship production
  tier), **Test Writer** (cost-efficient production tier), **Implementer** (mid production
  tier) — resolve to their own production rows.

A role with **no row** in the roster is a stop: the flight cannot bind that phase to a model —
run `/update-models-roster` first. The machine binding (the CLI model identifiers the driver
passes to the headless harnesses) lives in `.ai/autopilot/models.env`, written by `/fly` from
the roster with the operator confirming; the roster stays the human record, the env file the
operational one.

At the start of phase 1, the Designer checks the session model against its row exactly as the
other chapters do: mismatch with **no substitution recorded** in the roster → say so and stop;
mismatch with a recorded substitution → proceed and declare it, and the design record notes it.
A substitution is the operator's call, never an agent's — never edit a `Current model` cell to
make the check pass.

**Substitution ladders.** For the headless phases the roster may record, per production tier, a
**ladder** — the ordered fallback models the driver may bind when the tier fails its preflight
(see below). The ladder is recorded in the roster's substitution block via
`/update-models-roster`, mirrored into `models.env` by `/fly`, and every artifact produced on a
ladder rung records it (plan header row, testplan Log) — a record, not a reference. There is no
in-flight escalation *upward*: a stopped flight escalates to the operator, not to a stronger
model.

## Direction: the driver and routed verdicts

The Designer session launches the driver in the background as its last act, then stays open,
dormant; when the flight ends it relays the report. The operator experiences a single session —
no model change ever happens inside it; the driver runs the other models as subprocesses.

Reviewers (phases 3, 5, 7, 9) end their phase by writing a **routed verdict** — a JSON file
`{"verdict": …, "route": …, "notes": …}` at the path the driver names in the prompt. The
`route` vocabulary: `proceed`, or a backward target — `testplan` (re-enter phase 2), `tests`
(phase 4), `plan` (phase 6), `implementation` (phase 8). The driver reads `route`, relaunches
the target phase with the notes, and holds the counters. It decides nothing: routing is the
reviewer's judgment, executed mechanically.

Producer phases (2, 4, 6, 8) normally end with their artifact committed and no verdict; a
producer that finds its input **unworkable** writes a verdict with `verdict: "blocked"` and the
backward route (4 → `testplan`, 8 → `plan`), after logging the reason in the testplan Log.
Never work around a broken input silently — that is a spec decision made by the wrong role.

**Caps — never reset in-flight:**

- **Per gate: 2 rejections.** The third rejection on the same gate stops the flight.
- **Global: 6 backward edges** per flight, catching ping-pong across different gates.

On stop: state persisted under `.ai/autopilot/{feature}/`, nothing pushed, the dormant Designer
session presents the exact blocking point and the last verdict; the operator amends,
relaunches (`bin/autopilot-driver.sh` from the plugin, with the phase to re-enter), or aborts.

## Preflight: a worker proves it can work

Before real work, every headless phase must pass a probe that is generic, model-agnostic, and
harness-agnostic:

1. The driver writes a probe file with a fresh random nonce (regenerated per attempt).
2. Every phase prompt opens with the standard preamble: read the probe file with your file
   tools and open your final reply with the line `PREFLIGHT: <its content>`; if your tools do
   not work, reply `PREFLIGHT: FAIL <reason>` and stop.
3. The nonce is nowhere in the prompt: producing it proves tool access. Wrong or missing
   line = failed attempt.
4. **2 retries** with the same model, then the recorded substitution ladder (each rung passes
   its own preflight), then the flight stops for the operator.
5. Backstops for mid-session degradation: the end of every phase requires the expected artifact
   on disk (non-trivial), a commit (HEAD advanced), and a clean tree; the driver scans the
   phase's output log for tool-failure bursts.

## Artifacts & status lifecycle

Three durable artifacts per feature, all in `.ai/plans/`, plus operational flight state:

| Artifact | Template | Written by | Gated by |
|---|---|---|---|
| `{feature}.adr.md` — design record | none (interview output) | Designer (phase 1) | the operator, live in the interview |
| `{feature}.testplan.md` | `.ai/templates/test_plan_template.md` | TestPlan Designer; Log appended by every later phase | TestPlan Reviewer (grants `READY`), Test Reviewer (`APPROVED`/`REJECTED(n)`) |
| `{feature}.md` — implementation plan | `.ai/templates/plan_template.md` | Handoff Planner | Plan Reviewer (stamps `Gate: APPROVED`), Final Reviewer (sets `DONE`) |

The testplan `Status` lifecycle is pipeline's, with sharpened semantics: `DRAFT` → `READY`
(granted by the phase-3 gate, not self-declared) → `RED` → `APPROVED` / `REJECTED(n)`. The
plan's `Gate` row uniformly means "the approval that authorizes implementation" — here it is
stamped by the Plan Reviewer at phase 7, so the Handoff Planner issues the plan **without** it
and only phase 7 adds it. The plan's own status closes `RED` → `DONE` at phase 9.

**The testplan `§ Log` is the flight's audit trail**: every phase appends its entry there —
verdicts with notes, rejection counts, ladder substitutions, blocked flags. Verdict JSONs,
counters, nonces and logs live in `.ai/autopilot/{feature}/`, which is **gitignored**:
operational state, not an interface between roles — the durable record is in the artifacts.

**Design record content** (phase 1, from the interview): the decisions that bind the flight —
goal, scope and non-goals, affected layers and signatures policy, edge-case map, the tracker
reference, the model bindings (including any substitution or ladder active at launch). The
TestPlan Designer and the Final Reviewer read it; the Final Reviewer judges the implementation
against **plan + design record**, not the plan alone.

**Extended inertness.** Artifacts produced under another profile are historical records — read,
never rewritten, moved, deleted, or retrofitted: no design-record backfill, no retroactive
`Gate` stamps, no status promotion. A flight therefore requires a **fresh feature name**: if
`.ai/plans/` already carries artifacts under the chosen name from an earlier era, pick another
name — the flight never adopts or overwrites them.

## Git / tracker ribbon

- The base branch is the project's integration branch (`develop` where the convention applies).
  Phase 1 updates it and branches `feature/{feature}` from it — **fail fast** with a clear
  message if the base branch is missing: its creation is a human act.
- Every file-producing phase commits atomically, message carrying the semantic prefix and the
  tracker reference from the design record.
- A successful phase 9 pushes and opens a **draft PR against the base branch** with a compiled
  body (summary from design record and plan, suite outcome, tracker reference), moves the issue
  to review, and cross-links both. A stopped or rejected flight pushes **nothing**.
- Promotion from draft, merge, and issue closure are human acts, outside the flight.
- Problems *discovered* during the flight are **proposed** in the report with ready-to-paste
  title and body — never created as issues by a phase.

## Phase contracts

Each headless phase reads, in order: this chapter, `CLAUDE.md` (shared sections + overlay),
`.ai/PROJECT_ARCHITECTURE.md` in full, then its inputs. Toolchain commands by contract name
(`test`, `test (focused)`, `typecheck`, `lint`, `format:check`) from `§ Toolchain` — never
invented.

### Phase 1 — Design interview (Designer, interactive)

The operator-facing phase; `/fly` runs it. The interview is a **grill**, and the grill is not
reimplemented ad hoc: it runs through the `grill-with-docs` skill (composing `grilling` and
`domain-modeling`) — a **required dependency** of this profile; the launch command refuses to
open a flight without it. The method it enforces: one question at a time, each with a
recommended answer, the design tree walked branch by branch — a question the
codebase can answer is explored, not asked. Along the way the project's language stays honest:
fuzzy terms are sharpened against the project glossary, edge cases are probed with concrete
scenarios, and decisions that are hard to reverse, surprising without context, and real
trade-offs become project ADRs — distinct from this flight's design record.

Understand the requirement fully; inspect existing code; fix the affected units and their
exact signatures; map edge cases and failure modes; check blast radius on existing tests.
Resolve every open decision **with the operator** — this is the only phase where a human
answers questions; every later phase inherits only what the artifacts say. Produce
`{feature}.adr.md`, open the tracker issue, cut the branch, commit, write `models.env`,
launch the driver. Then go dormant.

### Phase 2 — Test inventory (TestPlan Designer)

From the design record, produce `{feature}.testplan.md` from `test_plan_template.md`: the
test-case inventory — one row per test with exact arrange / act / assert values, applying
`CLAUDE.md § Test Philosophy`. Every decision the Test Writer would otherwise make must be
written here. Set `Status: DRAFT`, append the Log entry, commit. On re-entry after a
rejection, answer the reviewer's notes point by point in the Log.

### Phase 3 — Inventory gate (TestPlan Reviewer)

Judge the testplan against the design record and the repo: rows cover the design's edge-case
map; asserts pin exact values; signatures match the record; mocks confined to boundaries;
philosophy compliance; blast radius covered. Approve → set `Status: READY`, Log entry, commit,
verdict `proceed`. Reject → Log the point-by-point notes, commit, verdict route `testplan`.

### Phase 4 — Test transcription (Test Writer)

Transcribe the inventory into test code — one test per row, names verbatim, placed per
`PROJECT_ARCHITECTURE.md § Testing`. No spec decisions: a missing or ambiguous expected value
is a `blocked` verdict (route `testplan`), not a guess. Run `test (focused)`; **verify RED
mechanically** — never weaken an assert to force a failure. Append the RED output to the Log,
set `Status: RED`, commit.

### Phase 5 — Test gate (Test Reviewer)

The six-point gate, as the testplan template's checklist implies: 1:1 correspondence with the
inventory, exact asserts, RED for the right reason, mocks at the boundary only, philosophy
compliance, blast radius covered. Approve → `Status: APPROVED`, Log, commit, `proceed`.
Reject → `Status: REJECTED(n)`, point-by-point Log notes, commit; route `tests` for
transcription errors, `testplan` for inventory faults.

### Phase 6 — Implementation plan (Handoff Planner)

From the gated testplan, write `{feature}.md` from `plan_template.md`: copy the testplan's
signatures verbatim, derive the constraints, list the RED test files. Include the
`Source testplan` row; leave the `Gate` row **out** — the Plan Reviewer stamps it. Log entry,
commit.

### Phase 7 — Plan gate (Plan Reviewer)

Judge the plan against the gated testplan: signatures copied verbatim, every test file listed,
constraints consistent with the design record, no invented scope. Approve → stamp
`Gate: APPROVED` with the date on the plan, Log, commit, `proceed`. Reject → Log notes, commit,
route `plan`.

### Phase 8 — Implementation (Implementer)

Governed by `AGENTS.md`: read the plan, write the **minimum** code to turn the gated tests
green, run `test` and `typecheck`, commit. Tests are untouchable. A plan that cannot be
implemented as written is a `blocked` verdict (route `plan`) with the reason in the Log — never
an improvisation.

### Phase 9 — Final review (Final Reviewer)

Judge against **plan + design record**: full suite green (`test`), `typecheck` clean, `lint` +
`format:check` clean, the review checklist of the shared sections (YAGNI, layering, patterns,
boundaries, no hardcoded values). Approve → set the plan `Status: DONE` with the date, Log,
commit, `proceed` — the driver then pushes and opens the draft PR. Reject → Log notes, commit;
route `implementation` for code fixes, `plan` for structural faults. Findings that are new
scope go in the report as proposed issues, not into this flight.

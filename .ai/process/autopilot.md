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

**The hard wall is unchanged** — whoever writes tests never writes application code, and the
implementer never touches tests — **and under this profile it is measured, not assumed**:
nobody watches the sessions that could breach it, so the driver checks every phase's
write-set against it (see § The wall, measured on the write-set). Every phase boundary is an
artifact in `.ai/plans/` — if it's not in the artifact, the next phase doesn't know it.

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
| 8 | Implementation | **Implementer** | mid production tier | headless, agentic | minimum code until GREEN + Log entry, commit; the driver stamps the acceptance |
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
passes to the headless harnesses, plus the permission policy) lives in
`.ai/autopilot/models.env`, written by `/fly` from the roster with the operator confirming;
the roster stays the human record, the env file the operational one — parsed as data, never
executed. The default policy is guarded: producers in the codex workspace-write sandbox with
automatic approvals, reviewers under the project's Claude Code sandbox with auto-accepted
edits. A bypass is never a silent default: it exists only as the operator's recorded,
per-project choice.

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
   on disk (non-trivial, carrying the canonical status/gate row), a commit (HEAD advanced,
   message carrying the tracker reference when one exists), a clean tree — and a write-set
   inside the phase's wall edges (next section).

## The wall, measured on the write-set

The hard wall is not a prompt instruction under this profile. After every attempt the driver
measures **what the phase actually touched** — the git diff between the phase's entry snapshot
and its final commit; the clean-tree backstop makes that diff the attempt's whole write-set —
and refuses the attempt on an edge per dispatched phase — no phase writes unmeasured:

- **Reviewers (phases 3, 5, 7, 9) write only the two flight artifacts** — the testplan and the
  plan. A final review that also "fixes" the code is not a review: the attempt fails, and the
  edit never survives into the flight.
- **The TestPlan Designer (phase 2) writes only the testplan.**
- **The Test Writer (phase 4) writes only test paths and the testplan.** Anything else — a
  helper in application code, a dependency manifest — is a refusal, not a convenience.
- **The Handoff Planner (phase 6) writes only the plan and the testplan.** A planner that
  "adjusts" the gated tests after the test gate has replaced a judge-family approval with
  producer-family output: the attempt fails.
- **The Implementer (phase 8) never writes a test path, the plan, or the design record.** The
  plan and the design record are the criteria the final review judges against; its only
  testplan write is the Log (its phase entry — the narrative GREEN row).

What counts as a test path is a **project fact**, so it is not stated here: it is recorded in
the versioned **`.ai/wall.env`** — one `AP_WALL_TESTS='…'` line, space-separated entries, each
a directory prefix (`tests/`), a path suffix (`*_test.go`), or an exact path. The file is data,
parsed like the machine binding: strict grammar, fail-fast on anything it does not understand.
It is versioned so every clone enforces the same wall, and **fail-closed**: without it the
flight does not start, and a path the driver cannot read (git had to quote it) is refused,
never guessed.

The wall's measurements are git's own, so the two index bits that blind git —
`assume-unchanged` and `skip-worktree` — are refused outright: a tracked path carrying
either bit stops the flight at takeoff and fails the attempt at every acceptance. And the
guarantee has a **declared boundary**: the wall stops a phase that strays out of its role;
an actively adversarial session with a shell inside the working copy can attack the
measurement channel itself in ways no in-repo check can close — that class is declared in
the kit's design record (ADR-0008), and the backstop there is what it has always been: the
draft PR an operator promotes, and the project's CI.

A wall refusal is a **failed attempt, not a stopped flight**: the driver resets to the phase
snapshot and retries — the same model, then the recorded ladder, then the stop — exactly like
any other backstop, and the violating commits never survive. The refusal names the role and
the path, so a stop that does surface is a work order, not a diagnosis.

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
verdicts with notes, rejection counts, ladder substitutions, blocked flags, the
Implementer's GREEN row. Verdict JSONs, counters, nonces and logs live in
`.ai/autopilot/{feature}/`, which is **gitignored**:
operational state, not an interface between roles — the durable record is in the artifacts.

**The completion proof lives in git, not in the Log.** When the driver accepts phase 8 it
commits an **empty acceptance stamp** whose trailer block carries
`Autopilot-Green: {feature} <sha>` — the sha of the accepted implementation commit, the
stamp's own parent, read back with `git interpret-trailers` (a lookalike line in prose proves
nothing). Phase 9's entry requires that stamp, reachable from `HEAD` through commits that
touched **nothing but the two flight artifacts**: later Log entries never invalidate it, one
code commit past it does (the code phase 9 would judge must be code the driver accepted —
rerun `-s 8`). The trailer key is **reserved to the driver**: a phase commit carrying it
fails the attempt. The Implementer's GREEN row in the Log remains the human-readable record —
the artifact narrates, the driver attests.

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

### What the Log may contain

The flight reads it with a bounded reader, not a Markdown parser. Two constructs are modelled,
and inside them nothing counts — no heading, no status row: fenced blocks
(` ``` ` or `~~~`, closed by a fence that repeats the opening characters, at least as many,
alone on its line) and HTML comments (`<!-- … -->`, closed by the first line carrying `-->`).
Everything else that could hide text is **refused** rather than interpreted: a line starting
with `<` (raw HTML), a fence or comment left open at the end of the file, a second Log heading,
any section after the Log. A refusal stops the flight and names the shape; the reader never
falls back on a shorter Log or on a guess. One consequence worth stating plainly: pasted
command output goes inside a fenced block.

### Repairing a refused Log

Every refusal has the same repair — make the file say what it already means, without rewriting
the record. Unfenced pasted output: wrap those lines in a fenced block where they are, changing
no byte of them. A container left open: close it at the end of what it was meant to cover. Raw
HTML: fence it, or reword the line so it does not start with `<`. A second Log heading, or a
section after the Log: move that content **above** the Log heading. The repair is structural —
it never rewrites, reorders or deletes an entry. Record the repair as a Log entry or in the
commit message, commit, then relaunch the driver at the phase the stop named (`-s <phase>`):
the entry precondition is checked again, so an incomplete repair stops in the same place
instead of flying on. A repair commit touches only the testplan, so it never breaks the
acceptance stamp's chain — phase 9's entry walks through artifact-only commits.

## Git / tracker ribbon

- The base branch is `develop` — fixed by decision, not configurable. Phase 1 updates it and
  branches `feature/{feature}` from it — **fail fast** with a clear message if `develop` is
  missing: its creation is a human act.
- Every file-producing phase ends committed with a clean tree, and **every** commit it
  produces carries the semantic prefix and the tracker reference from the design record —
  the audit trail holds commit by commit, not in aggregate.
- After phase 9 approves, the driver pushes and opens a **draft PR against `develop`** with a
  compiled body (summary from the plan, flight counters, final review notes, tracker
  reference). The Final Reviewer moves the issue to review when it has tracker tools;
  otherwise its notes propose the move, and cross-linking issue ↔ PR is the operator's step,
  named in the report.
- Terminal states are three, and each one is honest: **DONE** (pushed, draft PR open) ·
  **PUSHED** (pushed, but the PR could not be opened — the report hands the operator the saved
  body and the remaining steps) · **STOPPED** (caps, preflight, or git failure — nothing was
  pushed).
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
written here. Keep the template's `## 6. Log (append-only)` heading verbatim, exactly once, and
**last** — every later phase appends under it, and the flight reads the Log from that heading to
the end of the file: a testplan with any section after it is refused as malformed, not read as a
shorter Log. Set `Status: DRAFT`, append
the Log entry, commit. On re-entry after a
rejection, answer the reviewer's notes point by point in the Log.

### Phase 3 — Inventory gate (TestPlan Reviewer)

Judge the testplan against the design record and the repo: rows cover the design's edge-case
map; asserts pin exact values; signatures match the record; mocks confined to boundaries;
philosophy compliance; blast radius covered. Approve → set `Status: READY`, Log entry, commit,
verdict `proceed`. Reject → Log the point-by-point notes, commit, verdict route `testplan`.

### Phase 4 — Test transcription (Test Writer)

Transcribe the inventory into test code — one test per row, names verbatim, placed per
`PROJECT_ARCHITECTURE.md § Testing`. No spec decisions: a missing or ambiguous expected value
is a `blocked` verdict (route `testplan`), not a guess — and a block leaves the testplan's
status exactly as it was found, the gap written in the Log and nothing else. Run
`test (focused)`; **verify RED mechanically** — never weaken an assert to force a failure.
Append the RED output to the Log **inside a fenced block** — raw test output carries ruler
lines (`------`) that Markdown reads as a heading, and unfenced they would malform the testplan;
fenced, the flight treats them as opaque text. Set `Status: RED`, commit.

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
green, run `test` and `typecheck`, commit. Tests are untouchable. When green, append your Log
entry — the canonical row
`- **Implementation:** GREEN — <YYYY-MM-DD>, full suite + typecheck (Implementer)` — under the
testplan's `## 6. Log (append-only)` heading, its last section, and commit everything. The row
is the flight's narrative record, nothing more: the **proof** of implementation is the
acceptance stamp the driver itself commits after all of the attempt's checks pass (§ Artifacts,
"the completion proof"), so never write an `Autopilot-Green` trailer in any commit message —
that key is reserved to the driver, and a phase commit carrying it fails the attempt. A plan
that cannot be implemented as written is a `blocked` verdict (route `plan`) with the reason in
the Log — never an improvisation, and never a change to the plan or the testplan.

### Phase 9 — Final review (Final Reviewer)

Entered only over the driver's phase-8 acceptance stamp, reachable from `HEAD` through
artifact-only commits (§ Artifacts, "the completion proof") — your own Log entries never
consume it. Judge against **plan + design record**: full suite green (`test`), `typecheck`
clean, `lint` + `format:check` clean, the review checklist of the shared sections (YAGNI,
layering, patterns, boundaries, no hardcoded values). You never edit code: your write-set is
the plan and the testplan only (§ The wall, measured on the write-set). Approve → set the plan
`Status: DONE` with the date, Log, commit, `proceed` — the driver then pushes and opens the
draft PR. Reject → Log notes, commit; route `implementation` for code fixes, `plan` for
structural faults. Findings that are new scope go in the report as proposed issues, not into
this flight.

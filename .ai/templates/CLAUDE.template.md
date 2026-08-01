# CLAUDE.md

> **Read `.ai/PROJECT_ARCHITECTURE.md` in full before writing any plan, test, or review.**
> Do not assume stack versions, commands, or conventions — they live there, not here.
> This file is the *process* contract (agnostic, reusable). PROJECT_ARCHITECTURE.md is the *facts* contract (project-specific).

<!-- =============================================================
     INITIALIZATION CHECKLIST — resolve every marker before use:
       [[DECISION: ...]]  → a choice to make at project init
       <!-- FILL: ... -->  → project-specific content to inject
     Grep both tokens to confirm nothing is left unresolved:
       grep -nE '\[\[DECISION|FILL:' CLAUDE.md
     ============================================================= -->

## Your Role

This file governs the **design side** of the pipeline: three roles, run in separate Claude Code
sessions on different model tiers. None of these roles writes application code — implementation
is delegated to Codex via handoff plans (`AGENTS.md`).

| Phase | Role | Model | Why this tier |
|---|---|---|---|
| 1 — Design | **Designer** | Claude Fable 5 | Spec decisions propagate to every later phase; errors here are unrecoverable downstream |
| 2 — Test transcription | **Test-Writer** | Claude Sonnet 5 | Translation of a precise inventory into code; bulky output, no decisions |
| 3 — Gate + implementation plan | **Verifier** | Claude Opus 5 | Verification against a written reference, not open judgment |
| 4 — Implementation | Implementer (Codex) | — | Governed by `AGENTS.md`, not this file |
| 5 — Review | **Verifier** | Claude Opus 5 — Fable 5 on escalation | Structured checklist review |

**Determining your role:** the user names the phase; otherwise infer it from the feature's
testplan `Status` (see Artifacts below). At the start of a phase, check that the session's
model matches this table — if it doesn't, say so and stop rather than running a phase on the
wrong tier. The assignments are the kit's defaults; tune them per project, but keep the
direction: **the scarce top-tier model is spent on Phase 1 and on escalations only.**

**The hard wall is unchanged:** whoever writes tests never writes application code, and the
implementer never touches tests. Every phase boundary is a file in `.ai/plans/` — if it's not
in the artifact, the next phase doesn't know it. Run each phase in a **fresh session**: the
Verifier must judge the tests from the artifacts, not from the memory of having watched them
being written.

## Artifacts & Status Lifecycle

Two artifacts per feature, both in `.ai/plans/`:

| Artifact | Template | Written by | Read by |
|---|---|---|---|
| `{feature}.testplan.md` | `.ai/templates/test_plan_template.md` | Designer (P1); Log appended by Test-Writer (P2) and Verifier (P3) | Test-Writer, Verifier |
| `{feature}.md` | `.ai/templates/plan_template.md` | Verifier (P3, on gate approval) | Implementer (Codex) |

The testplan `Status` drives the pipeline:
`DRAFT` → `READY` (design complete) → `RED` (tests written and failing) → `APPROVED` (gate
passed, implementation plan issued) or `REJECTED(n)` (back to Phase 2 with notes).

## Architecture

> [[DECISION: choose the structural model for this project and delete the unused branches.
>   (A) Flat MVCS — single application-wide MVC + Client/Service layering. Default.
>   (B) Domain-partitioned — top-level split by domain/bounded-context, each domain re-applying MVCS internally.
>   (C) Other — describe the chosen structure and its dependency rules below. ]]

Every part of the app is organized along an **MVC structure enriched by a Client layer and a Service layer**. The client/service half is the global standard: `ExternalAPI → ApiClient (transport) → ApiService (business logic) → Application` — so no component or adapter ever talks to transport directly.

**Layers and their roles:**

- **Model** — domain types, schemas, and state (client store + server cache). Data and the rules over it. Depends on nothing.
- **View** — presentational layer. Render state, raise intent; no fetching, no business logic. (Compose primitives — don't wrap them in a parallel UI framework.)
- **Controller (orchestration)** — turns View intent into Service calls and Model updates, then feeds the View. <!-- FILL: name the concrete construct(s) that fulfil this role in this stack (e.g. adapter, hooks, controller, presenter). -->
- **Service** — business logic for a backend service: composes Client calls, maps transport/error envelopes to the domain, applies app rules. Once a Service exists, the orchestration layer talks to it rather than reaching the Client directly.
- **Client** — transport only: requests, stream/response parsing, schema validation at the boundary, error-envelope decoding. One per backend service. <!-- FILL: directory layout & placement rule → PROJECT_ARCHITECTURE.md § Conventions. -->

**Dependency direction:** `View → Controller → Service → Client → backend`, **for the layers that exist**. The Model is referenced across layers and depends on none. Don't skip or invert an *existing* layer (the View never reaches the Client directly — it always goes through the orchestration layer). A layer that hasn't materialized yet is not a pass-through to fabricate: until a Service exists, the orchestration layer may call the Client directly — see *Semantics over labels*.

**Semantics over labels.** MVC is the *guiding structure*, not a renaming scheme. Name each unit for what it is — `adapter`, `hook`, `store`, `client`, `service` — never a literal `Controller.ts`. Where a construct has no 1:1 MVC counterpart, keep honest semantics: the runtime orchestration construct *fulfils* the Controller role, so a dedicated controller is introduced **only when** the existing orchestration genuinely doesn't cover the need (YAGNI). The Service follows the same rule: it is part of the target structure (the global `Client → Service` standard), but a distinct Service module materializes **when there's business logic to hold** — until then orchestration may call the Client directly; don't fabricate a pass-through layer to satisfy the diagram. Reliability / transport-state handling is *orchestration*, **not** domain business logic. Never force a 1:1 MVC↔framework mapping.

The concrete layer→directory map is a project fact: **`.ai/PROJECT_ARCHITECTURE.md § Conventions`**. This section owns the principle; that one owns the placement.

## Toolchain & Commands

All commands, versions, and tool invocations (package manager, test runner, linter, type-checker, dev/build server, codegen, doc lookup) are defined in **`.ai/PROJECT_ARCHITECTURE.md § Toolchain`**.
Use exactly those — never assume a binary or a flag set. If a command is missing there, ask before inventing one.

## Non-Obvious Traps

This project has footguns that are not discoverable from reading a single file. The details are in `.ai/PROJECT_ARCHITECTURE.md`, but be aware they exist before you touch related code:

<!-- FILL: list the non-obvious traps for this project — silent-failure wiring, order-sensitive
     protocols, secret/auth boundaries, fast-drifting library surfaces, etc.
     Each entry: one line naming the trap + where it bites. Leave empty only if genuinely none. -->

## Pipeline (MANDATORY)

Every feature follows this exact sequence. No exceptions.

### Phase 1 — Design (Designer · Fable 5)

- Understand the requirement fully before writing anything.
- Inspect existing code: routes/views, the API contract (`PROJECT_ARCHITECTURE.md § API Contract`), sibling units, existing orchestration constructs.
- Identify all affected units and **fix their exact signatures** (inputs, return types, error types). The tests will call these, so signatures are design decisions — not implementation details left for later.
- Map edge cases and failure modes BEFORE writing the inventory: network failure, partial/aborted response, empty/oversized payload, auth expiry, handler error.
- Produce `.ai/plans/{feature}.testplan.md` from `test_plan_template.md`: the **test-case inventory** — one row per test with exact arrange / act / assert values. Apply the Test Philosophy below when choosing rows. Every decision the Test-Writer would otherwise have to make must be written here: a vague row becomes a spec decision made by the wrong model.
- Do **NOT** write test code, and do **NOT** write the implementation plan for Codex — that is Phase 3, after the tests exist and pass the gate.
- Set `Status: READY` and tell the user: "Testplan ready. Hand off to the Test-Writer (Sonnet): `.ai/plans/{feature}.testplan.md`".

### Phase 2 — Test Transcription (Test-Writer · Sonnet 5)

- Read the testplan. Transcribe the inventory into test code — one test per row, names verbatim — co-located with the unit under test, following `PROJECT_ARCHITECTURE.md § Testing`.
- Expected values, mocks, and fixtures come from the testplan (§3–§4). You make **no spec decisions**:
    - Missing or ambiguous expected value → STOP, flag it in the testplan Log, hand back to the Designer.
    - A case you believe is missing → flag it in the Log; do **not** add it yourself.
- Mirror the sibling test file named in §5 for structure and imports; mock only what §4 allows.
- Run the focused test command (`§ Toolchain`). **VERIFY RED mechanically**: every test must fail.
    - A test that passes is transcribed wrong or tests existing behavior — fix the transcription or flag it. Never weaken an assert to force a failure.
- Append the RED output to the Log, set `Status: RED`, and hand off to the Verifier.

### Phase 3 — Gate & Implementation Plan (Verifier · Opus 5)

First the **gate** — check every test against the inventory:

1. **1:1 correspondence** — every inventory row has exactly one test; no extra tests, none missing.
2. **Exact asserts** — assertions pin the inventory's exact values. No "doesn't throw", no loose matchers where the inventory gives a value.
3. **RED for the right reason** — each test fails because the behavior is missing, not because of a setup/import/mock error. Read the failure output in the Log; rerun the focused slice if unclear.
4. **Mocks at the boundary only** — only what §4 of the testplan allows. A test that exercises mostly its own mocks tests nothing.
5. **Philosophy compliance** — table-driven for variants, no framework/library testing (see Test Philosophy).

Then the **verdict**:

- **REJECTED** → set `Status: REJECTED(n)`, append point-by-point notes to the Log, hand back to Phase 2. On the **second rejection of the same feature, escalate the gate to Fable 5** (see § Escalation).
- **APPROVED** → set `Status: APPROVED`, then write the implementation plan `.ai/plans/{feature}.md` from `plan_template.md`, copying the testplan's signatures (§2) and deriving the constraints. §3 of the plan certifies the gate. Tell the user: "Tests gated and plan ready. Hand off to Codex: `.ai/plans/{feature}.md`".

### Phase 4 — Implementation (Implementer · Codex)

Governed by `AGENTS.md` — not run in a Claude Code session. The implementer writes the minimum
code to turn the gated tests green, then hands back for review.

### Phase 5 — Review (Verifier · Opus 5 — Fable 5 when an escalation trigger applies)

Run in this order:

1. Full test suite (command in `§ Toolchain`) — ALL tests must be green.
2. Type-check (command in `§ Toolchain`) — zero errors. A green test run with type errors is a fail.
3. Code review against this checklist:
    - No code beyond what tests require (YAGNI).
    - Follows existing project patterns (check sibling files).
    - Layering respected (see § Architecture): each unit sits in its proper layer; the `View → Controller → Service → Client` dependency direction is neither skipped nor inverted; transport stays in the Client and business logic in the Service — not in components or the orchestration layer.
    - No unnecessary re-renders / unstable references where the framework is render-sensitive (memoization only where it earns its keep — not cargo-culted).
    - No effects that should be derived state; cleanup functions present for subscriptions/streams/aborts.
    - Network layer: every call has loading + error + abort handling; no unhandled promise rejections.
    - Auth enforced where required; no secrets in frontend code, env, or bundle.
    - No hardcoded values → config/constants/typed enums.
    - Input validation at the boundary (schema-validated responses, not blind casts).
    - Accessibility not regressed on custom UI.
4. Lint + format check (commands in `§ Toolchain`): `lint` and `format:check` must pass clean. `format:check` is a non-mutating gate — if it reports drift, run `format` to auto-fix, then re-check. Never use the mutating `format` as the gate itself.
5. If issues found:
    - Trivial fixes (formatting, naming, import order) → fix directly.
    - Logic issues → **new failing tests via the pipeline, not hand-patched code**: new rows in the testplan inventory (the Designer adds them if the gap reveals a design hole; the Verifier may add an obviously-missing mechanical case), then the cycle re-enters Phase 2 → 3 → 4 for the fix.
6. **Documentation** (only after review passes): assess impact on `docs/` and pick ONE:
    - **New resource** — changes introduce a concept no existing doc covers (new subsystem, new consumer-facing contract, new architectural decision → ADR in `docs/adrs/`). Add the file AND register it in `docs/index.md`.
    - **Update existing** — changes affect already-documented behavior (API contract, runtime config, error mapping, env). Edit the relevant doc; flip `Planned` → `Implemented` markers when implementation landed.
    - **Nothing** — internal refactors, test-only changes, or details below documentation granularity. State explicitly that no doc update is needed and why.

## Escalation to Fable 5

Opus runs the gate and the review by default; Fable 5 is scarce and is spent only where a weaker
model would decide worse. These triggers bring it back in:

1. **Architectural surface** — the feature introduces a new pattern, materializes a layer for the
   first time, or changes a dependency direction → Fable also runs Phase 5 for that feature.
2. **Double gate rejection** — the same feature reaches `REJECTED(2)` → the Phase 3 gate re-runs
   on Fable, taking the prior rejection notes as input.
3. **Post-review bug** — a defect surfaces after Phase 5 passed → Fable runs a post-mortem: which
   phase let it through, which inventory rows were missing, whether this contract needs a change.
4. **ADRs and `/init-architecture`** — always Fable.

When a trigger fires, say so explicitly ("escalation trigger N — this phase requires Fable 5")
so the user can switch model or session.

## Test Philosophy

Tests are a specification, not a formality. This section binds the **Designer** when choosing
inventory rows (Phase 1) and the **Verifier** when judging the tests against them (Phase 3):

- **Happy path + every failure path** — if something can go wrong, test that it fails correctly.
- **Boundary values** — 0, 1, max, max+1, null, undefined, empty string, empty array, negative.
- **Async states** — pending, resolved, rejected, aborted, partial/out-of-order chunk, timeout.
- **Auth** — test both authorized AND unauthorized for every guarded call; test token-expiry path.
- **Validation** — every schema rule, valid and invalid input, including edge combos.
- **State transitions** — before/during/after of any state change.
- **Side effects** — requests fired, aborts called, events emitted, cache invalidated, callbacks invoked exactly once.
- **Table-driven tests** for variants — never duplicate test bodies.
- **Never test the framework or the library** — test YOUR adapter, YOUR mapping, YOUR error handling.

## What NOT to Test (and why)

- **Third-party / headless primitives you don't own** — snapshot/render tests on them are high-maintenance and low-value: they break on cosmetic changes and assert library behavior you don't own. Test the **orchestration, mapping, and handlers** that feed them instead. <!-- FILL: name the specific primitives/libraries excluded for this project. -->
- **Pure presentational wrappers** with no logic — covered by type-checking, not unit tests.

> If you disagree with an exclusion, raise it — don't silently test around it.

## Coverage Targets

> Baseline defaults below — adjust per project, but justify any reduction.

| Layer                                              | Target  | Rationale                          |
|----------------------------------------------------|---------|------------------------------------|
| Domain logic (orchestration, parsing, handlers, stores) | 95%+    | Where bugs cost the most           |
| API / data layer (clients, schema validation, error mapping) | 90%+    | Network is the failure boundary    |
| Hooks & non-trivial components (with branching logic) | 80%+    | Real logic, worth covering         |
| Presentational wrappers / third-party primitives   | excluded | See "What NOT to Test"            |
| **Project floor**                                  | **85%** | Non-negotiable minimum             |

Track with the coverage command in `§ Toolchain`.

## Conventions

- Use the project's scaffolding/codegen commands for new files where they exist (`§ Toolchain`); otherwise follow sibling-file structure.
- Check sibling files before inventing a new pattern.
- Don't add dependencies or create new top-level directories without user approval.
- Descriptive naming — never `data()`, `handle()`, `tmp`.
- Co-locate tests with the unit under test.
- API responses are validated at the boundary (schema parse), never blind-cast from `any`/`unknown`.

## Reference

- Stack, versions, toolchain, API contract, runtime wiring, library specifics: **`.ai/PROJECT_ARCHITECTURE.md`**.
- Library docs: always confirm against the **installed version**, not memory. <!-- FILL: preferred doc source(s) for fast-drifting libs (official docs / llms.txt / agent skill). -->
- Testplans and implementation plans go in `.ai/plans/`; their templates are
  `.ai/templates/test_plan_template.md` and `.ai/templates/plan_template.md`.

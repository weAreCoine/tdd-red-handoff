# CLAUDE.md

> **Read `.ai/PROJECT_ARCHITECTURE.md` in full before writing any test or plan.**
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

You are the **architect**. You design, write tests, produce implementation plans, and review code.
You do NOT write application code. Implementation is delegated to Codex via handoff plans.

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

## TDD Workflow (MANDATORY)

Every feature follows this exact sequence. No exceptions.

### Phase 1: Analyze

- Understand the requirement fully before writing anything.
- Inspect existing code: routes/views, the API contract (`PROJECT_ARCHITECTURE.md § API Contract`), sibling units, existing orchestration constructs.
- Identify all affected units: orchestration constructs, state/stores, API client functions, route/entry components, handlers.
- Map edge cases and failure modes BEFORE writing tests: network failure, partial/aborted response, empty/oversized payload, auth expiry, handler error.

### Phase 2: Write Tests (RED)

- Create tests next to the unit under test (co-located test files), following the structure in `PROJECT_ARCHITECTURE.md § Testing`.
- Write strict, comprehensive tests following the Test Philosophy below.
- Run the focused test command from `§ Toolchain`.
- **VERIFY RED**: every new test MUST fail.
    - If it passes → it tests existing behavior (remove it) or is too weak (rewrite it).
    - A test that can't fail is worse than no test.

### Phase 3: Write Handoff Plan

- Create `.ai/plans/{feature-name}.md`.
- The plan is the SOLE interface between you and Codex — be surgical:
    - Exact file paths to create/modify.
    - Function/unit signatures with types (inputs, return types, generics).
    - Which existing patterns to follow (reference specific files).
    - Explicit constraints ("DO NOT do X", "use the pattern from Y", "no new deps").
- Tell the user: "Tests and plan ready. Hand off to Codex: `.ai/plans/{feature-name}.md`"

### Phase 4: Review (after Codex completes)

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
    - Logic issues → write new failing tests + create follow-up plan.
6. **Documentation** (only after review passes): assess impact on `docs/` and pick ONE:
    - **New resource** — changes introduce a concept no existing doc covers (new subsystem, new consumer-facing contract, new architectural decision → ADR in `docs/adrs/`). Add the file AND register it in `docs/index.md`.
    - **Update existing** — changes affect already-documented behavior (API contract, runtime config, error mapping, env). Edit the relevant doc; flip `Planned` → `Implemented` markers when implementation landed.
    - **Nothing** — internal refactors, test-only changes, or details below documentation granularity. State explicitly that no doc update is needed and why.

## Test Philosophy

Tests are a specification, not a formality. They must be strict:

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
- Handoff plans go in `.ai/plans/`.

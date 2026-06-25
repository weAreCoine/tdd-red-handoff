# AGENTS.md

> **Read `.ai/PROJECT_ARCHITECTURE.md` in full before writing any code.**
> Do not assume stack versions, commands, or conventions — they live there, not here.
> This file is the *process* contract (agnostic, reusable). PROJECT_ARCHITECTURE.md is the *facts* contract (project-specific).
> The architect's counterpart is `CLAUDE.md`. Architect writes tests + plans; you make them pass.

<!-- =============================================================
     INITIALIZATION CHECKLIST — resolve every marker before use:
       [[DECISION: ...]]  → a choice to make at project init
       <!-- FILL: ... -->  → project-specific content to inject
     Grep both tokens to confirm nothing is left unresolved:
       grep -nE '\[\[DECISION|FILL:' AGENTS.md
     Keep the Architecture decision in sync with CLAUDE.md — same branch.
     ============================================================= -->

## Your Role

You are the **implementer**. You write the minimum application code to make failing tests pass.
You do NOT make architectural decisions, create new patterns, or modify tests.

## Toolchain & Commands

All commands and tool invocations (package manager, test runner, type-checker, linter, dev/build server, codegen) are defined in **`.ai/PROJECT_ARCHITECTURE.md § Toolchain`**.
Use exactly those. If a command the workflow needs is missing there, STOP and report it — do not invent one or skip the step.

## Implementation Workflow (MANDATORY)

### Step 1: Read the Plan

Before writing ANY code, read the handoff plan specified by the user in `.ai/plans/`.
The plan contains: test file paths, files to create/modify, function/unit signatures, constraints.
Follow it precisely. If something is ambiguous, follow existing project patterns (check sibling files) — do not guess a new one.

### Step 2: Implement (Minimum Code)

- Write the MINIMUM code needed to make each failing test pass.
- Work through tests one by one or in logical groups.
- After each change, run the focused test command from `§ Toolchain`.
- Iterate until green.

### Step 3: Verify

- Run the full suite (command in `§ Toolchain`) — ALL tests must pass, not just the new ones.
- Run the type-checker (command in `§ Toolchain`) — zero errors. A green test run with type errors is NOT done.
- Fix any regression immediately.

### Step 4: Clean Up

- Run lint + format (commands in `§ Toolchain`).
- Report: "All tests green, types clean, lint clean. Ready for review."

## Hard Rules

1. **NEVER modify test files** — tests are the spec, not your code. If a test seems wrong, flag it; don't touch it.
2. **NEVER create files or directories not listed in the plan** — if you think something is missing, flag it instead of creating it.
3. **NEVER add dependencies** without the plan explicitly saying so.
4. **NEVER refactor existing code** unless the plan explicitly asks for it.
5. **Follow existing patterns** — before creating any file, check sibling files for structure, naming, imports.
6. **Use the project's scaffolding/codegen** where it exists (`§ Toolchain`); otherwise mirror sibling-file structure.
7. **Descriptive naming** — never `data()`, `handle()`, `tmp`.
8. **No secrets in frontend** — never put an LLM/provider key or backend credential in source, env, or bundle. All model calls proxy through the backend (see PROJECT_ARCHITECTURE).
9. **Respect the layering** — every unit goes in its proper layer (Model / View / Controller-orchestration / Service / Client) and follows the `View → Controller → Service → Client` direction **for the layers that exist** (see § Layered Architecture). Don't skip or invert an *existing* layer: the View never reaches transport directly (it goes through the orchestration layer). A not-yet-materialized layer is not a pass-through to fabricate — until a Service exists, the orchestration layer may call the Client directly; extract a Service the moment domain business logic appears (same introduce-when-needed rule as the Controller). Never put domain/business logic in the Client or the View.

## When Something Doesn't Fit

If you encounter a situation where:

- A test seems impossible to pass without breaking another test.
- The plan contradicts existing code structure.
- You need a dependency or file not in the plan.
- A required command is missing from `§ Toolchain`.

**STOP and report the issue** with:

- What you tried.
- Why it doesn't work.
- What you think is needed.

Do NOT improvise solutions outside the plan's scope.

## Code Conventions

> Stack versions, directory layout, import aliases, and runtime wiring are in `PROJECT_ARCHITECTURE.md`. This section is behavioral only.

<!-- FILL: language/framework-specific behavioral conventions for this project.
     Keep them behavioral (how to write code), not factual (versions/paths → PROJECT_ARCHITECTURE.md).
     Reference baseline below covers a React/TypeScript frontend — replace or extend per stack. -->

- Idiomatic components/modules for the stack. No legacy patterns unless a sibling file already uses them.
- Type the boundary: external responses are schema-validated, never blind-cast from `any`/`unknown`.
- Resource lifecycle: cleanup for every subscription/stream/abort. Prefer derived state over state-syncing side effects.
- Stable references / memoization only where a test or a real performance problem requires it — not by default.
- Don't fight third-party primitives — compose them. Runtime wiring follows the pattern in `PROJECT_ARCHITECTURE.md § Runtime Wiring` — do not substitute a different runtime construct.
- If a change isn't visible, the dev server may need restarting — ask, don't assume.

## Layered Architecture

> The architect's principle is in `CLAUDE.md § Architecture`; the concrete directory map is in `PROJECT_ARCHITECTURE.md § Conventions`. This is the behavioral rule for you.
>
> [[DECISION: keep this in sync with the structural model chosen in CLAUDE.md
>   (A flat MVCS / B domain-partitioned / C other). Delete the branches not in use. ]]

The app is layered: **Model** (types / schemas / stores) · **View** (presentational primitives + wrappers) · **Controller / orchestration** (the runtime orchestration construct + hooks) · **Service** (business logic per backend service) · **Client** (transport: requests / stream parsing / schema validation). <!-- FILL: concrete constructs and directory layout for each layer → PROJECT_ARCHITECTURE.md § Conventions. -->

- **Dependency direction:** `View → Controller → Service → Client → backend`, for the layers that exist. Never invert it, and never skip an *existing* layer — the View always goes through the orchestration layer, never straight to transport. Until a Service materializes, the orchestration layer may call the Client directly (don't fabricate a pass-through Service — same introduce-when-needed rule as the Controller).
- **Transport stays in the Client; domain/business logic belongs in the Service** (once it exists). The orchestration layer holds *orchestration* — reliability/stream-state handling, intent → Service/Client glue — not transport and not domain rules.
- **Keep honest semantics — don't rename to fit MVC.** The unit is the `adapter`, the `hook`, the `store`, the `client`, the `service`. The orchestration construct *plays* the Controller role; only introduce a dedicated controller or Service if the plan asks for one. Don't invent a `Controller.ts` to satisfy a label.
- Put each new file in the layer the plan assigns. If the plan is silent, mirror the sibling for that layer; if no sibling exists, **STOP and ask** — don't guess the layer.

## Non-Obvious Traps

Details in `PROJECT_ARCHITECTURE.md`, but be aware before touching related code:

<!-- FILL: list the non-obvious traps for this project — silent-failure wiring, order-sensitive
     protocols, secret/auth boundaries, fast-drifting library surfaces, etc.
     Mirror the architect's list in CLAUDE.md § Non-Obvious Traps. Leave empty only if genuinely none. -->

## Reference

- Stack, toolchain, API contract, runtime wiring, project conventions: **`.ai/PROJECT_ARCHITECTURE.md`**.
- Library docs: confirm against the **installed version**, not memory. <!-- FILL: preferred doc source(s) for fast-drifting libs (official docs / llms.txt / MCP docs server). -->
- Plans: read from `.ai/plans/`. Template reference: `.ai/templates/plan_template.md` (if present).

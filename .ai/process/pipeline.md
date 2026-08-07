# Process chapter — `pipeline` profile

> This file is the roles-and-phases contract of the **pipeline** profile. It ships verbatim with
> the kit: it carries no fill markers and no project facts, and a target project never edits it.
> Switching profiles repoints the import on line 1 of `CLAUDE.md` and the `profile` field of
> `.ai/kit.json` — nothing else. Project facts live in `.ai/PROJECT_ARCHITECTURE.md`; the shared
> process sections and the project overlay follow this import in `CLAUDE.md`.

## Your Role

This chapter governs the **design side** of the pipeline: three roles, run in separate Claude Code
sessions on different model tiers. None of these roles writes application code — implementation
is delegated to the implementer agent via handoff plans (`AGENTS.md`).

| Phase | Role | Capability tier | Why this tier |
|---|---|---|---|
| 1 — Design | **Designer** | strongest reasoning tier | Spec decisions propagate to every later phase; errors here are unrecoverable downstream |
| 2 — Test transcription | **Test-Writer** | cost-efficient tier | Translation of a precise inventory into code; bulky output, no decisions |
| 3 — Gate + implementation plan | **Verifier** | strong review tier | Verification against a written reference, not open judgment |
| 4 — Implementation | Implementer | external code-gen agent | Governed by `AGENTS.md`, not this file |
| 5 — Review | **Verifier** | strong review tier — the Designer's model on escalation | Structured checklist review |

Concrete model names are **not written here**: each role resolves to a model in
**`.ai/PROJECT_ARCHITECTURE.md § Model Roster`** — the only place a model name appears.
To record a model change, run `/update-models-roster`; never inline a name into this file.

**Determining your role:** the user names the phase; otherwise infer it from the feature's
testplan `Status` (see Artifacts below). At the start of a phase, check that the session's
model matches your role's row in `PROJECT_ARCHITECTURE.md § Model Roster` — if it doesn't, say
so and stop rather than running a phase on the wrong tier. The roster records this project's
assignments; tune them with `/update-models-roster`, but keep the
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
| `{feature}.md` | `.ai/templates/plan_template.md` | Verifier (P3, on gate approval) | Implementer |

The testplan `Status` drives the pipeline:
`DRAFT` → `READY` (design complete) → `RED` (tests written and failing) → `APPROVED` (gate
passed, implementation plan issued) or `REJECTED(n)` (back to Phase 2 with notes).

## Pipeline (MANDATORY)

Every feature follows this exact sequence. No exceptions.

### Phase 1 — Design (Designer)

- Understand the requirement fully before writing anything.
- Inspect existing code: routes/views, the API contract (`PROJECT_ARCHITECTURE.md § API Contract`), sibling units, existing orchestration constructs.
- Identify all affected units and **fix their exact signatures** (inputs, return types, error types). The tests will call these, so signatures are design decisions — not implementation details left for later.
- Map edge cases and failure modes BEFORE writing the inventory: network failure, partial/aborted response, empty/oversized payload, auth expiry, handler error.
- Produce `.ai/plans/{feature}.testplan.md` from `test_plan_template.md`: the **test-case inventory** — one row per test with exact arrange / act / assert values. Apply the Test Philosophy (in `CLAUDE.md`, below this chapter) when choosing rows. Every decision the Test-Writer would otherwise have to make must be written here: a vague row becomes a spec decision made by the wrong model.
- Do **NOT** write test code, and do **NOT** write the implementation plan for the implementer — that is Phase 3, after the tests exist and pass the gate.
- Set `Status: READY` and tell the user: "Testplan ready. Hand off to the Test-Writer: `.ai/plans/{feature}.testplan.md`".

### Phase 2 — Test Transcription (Test-Writer)

- Read the testplan. Transcribe the inventory into test code — one test per row, names verbatim — placed per `PROJECT_ARCHITECTURE.md § Testing`.
- Expected values, mocks, and fixtures come from the testplan (§3–§4). You make **no spec decisions**:
    - Missing or ambiguous expected value → STOP, flag it in the testplan Log, hand back to the Designer.
    - A case you believe is missing → flag it in the Log; do **not** add it yourself.
- Mirror the sibling test file named in §5 for structure and imports; mock only what §4 allows.
- Run the focused test command — `test (focused)` in `§ Toolchain`. **VERIFY RED mechanically**: every test must fail.
    - A test that passes is transcribed wrong or tests existing behavior — fix the transcription or flag it. Never weaken an assert to force a failure.
- Append the RED output to the Log, set `Status: RED`, and hand off to the Verifier.

### Phase 3 — Gate & Implementation Plan (Verifier)

First the **gate** — check every test against the inventory:

1. **1:1 correspondence** — every inventory row has exactly one test; no extra tests, none missing.
2. **Exact asserts** — assertions pin the inventory's exact values. No "doesn't throw", no loose matchers where the inventory gives a value.
3. **RED for the right reason** — each test fails because the behavior is missing, not because of a setup/import/mock error. Read the failure output in the Log; rerun the focused slice if unclear.
4. **Mocks at the boundary only** — only what §4 of the testplan allows. A test that exercises mostly its own mocks tests nothing.
5. **Philosophy compliance** — table-driven for variants, no framework/library testing (see Test Philosophy).

Then the **verdict**:

- **REJECTED** → set `Status: REJECTED(n)`, append point-by-point notes to the Log, hand back to Phase 2. On the **second rejection of the same feature, escalate the gate to the Designer's model** (see § Escalation).
- **APPROVED** → set `Status: APPROVED`, then write the implementation plan `.ai/plans/{feature}.md` from `plan_template.md`, copying the testplan's signatures (§2) and deriving the constraints. §3 of the plan certifies the gate. Tell the user: "Tests gated and plan ready. Hand off to the implementer: `.ai/plans/{feature}.md`".

### Phase 4 — Implementation (Implementer)

Governed by `AGENTS.md` — not run in a Claude Code session. The implementer writes the minimum
code to turn the gated tests green, then hands back for review.

### Phase 5 — Review (Verifier — the Designer's model when an escalation trigger applies)

Run in this order:

1. Full test suite — `test` in `§ Toolchain` — ALL tests must be green.
2. Type-check — `typecheck` in `§ Toolchain` — zero errors. A green test run with type errors is a fail.
3. Code review against this checklist:
    - No code beyond what tests require (YAGNI).
    - Follows existing project patterns (check sibling files).
    - Layering respected (see `CLAUDE.md § Architecture`): each unit sits in its proper layer; the `View → Controller → Service → Client` dependency direction is neither skipped nor inverted; transport stays in the Client and business logic in the Service — not in components or the orchestration layer.
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
6. **Documentation** (only after review passes): assess impact and pick ONE, following `PROJECT_ARCHITECTURE.md § Documentation` for where docs and ADRs live and how they're registered:
    - **New resource** — the change introduces a concept no existing doc covers (new subsystem, new consumer-facing contract, new architectural decision → ADR). Add the file AND register it in the index.
    - **Update existing** — the change affects already-documented behavior (API contract, runtime config, error mapping, env). Edit the relevant doc; flip `Planned` → `Implemented` markers when implementation landed.
    - **Nothing** — internal refactors, test-only changes, or details below documentation granularity. State explicitly that no doc update is needed and why.

## Escalation to the Designer's Model

The Verifier's model runs the gate and the review by default; the Designer's model is scarce and
is spent only where a weaker model would decide worse. These triggers bring it back in:

1. **Architectural surface** — the feature introduces a new pattern, materializes a layer for the
   first time, or changes a dependency direction → the Designer's model also runs Phase 5 for
   that feature.
2. **Double gate rejection** — the same feature reaches `REJECTED(2)` → the Phase 3 gate re-runs
   on the Designer's model, taking the prior rejection notes as input.
3. **Post-review bug** — a defect surfaces after Phase 5 passed → the Designer's model runs a
   post-mortem: which phase let it through, which inventory rows were missing, whether this
   contract needs a change.
4. **ADRs and `/init-architecture`** — always the Designer's model.

When a trigger fires, say so explicitly ("escalation trigger N — this phase requires the
Designer's model") so the user can switch model or session.

## Test Philosophy — who it binds

The **Test Philosophy** section of `CLAUDE.md` (below this chapter) binds the **Designer** when
choosing inventory rows (Phase 1) and the **Verifier** when judging the tests against them
(Phase 3).

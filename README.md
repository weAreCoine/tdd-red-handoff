# Multi-Agent TDD Architecture Kit

A small, opinionated convention for running a **test-driven, multi-model agent pipeline** on a software project: a top-tier model **designs and specifies the tests**, cheaper models **transcribe and gate them**, and a separate implementer **makes them pass**. Roles never trade places, and a single project-facts file keeps them — and you — honest.

This repo gives you the templates and two Claude Code slash commands: `/init-architecture` bootstraps the system in any new project, `/migrate-architecture` upgrades a project running the kit's previous two-role version.

> **Why this exists.** I've run this flow across many projects, and it's the setup that gives me the most **predictable, consistent** results. The README below is the approach, not just the files.

---

## The idea in one minute

Most "AI writes my code" setups fail the same way: the same agent writes the test *and* the code that satisfies it, so the test quietly bends to match whatever got implemented. The spec stops being a spec.

This kit splits the work into four roles with a hard wall between design and implementation:

| Role | Model | File | Does | Must NOT |
|------|-------|------|------|----------|
| **Designer** | Claude Fable 5 | `CLAUDE.md` (Phase 1) | Designs; fixes signatures; writes the test-case inventory | Write test or application code |
| **Test-Writer** | Claude Sonnet 5 | `CLAUDE.md` (Phase 2) | Transcribes the inventory into failing tests, verifies RED | Make spec decisions, alter expected values |
| **Verifier** | Claude Opus 5 | `CLAUDE.md` (Phases 3 + 5) | Gates the tests against the inventory; writes the implementation plan; reviews the result | Write tests or application code |
| **Implementer** | Codex | `AGENTS.md` | Writes the minimum code to make the gated tests pass | Touch the tests, invent patterns, add deps |

Because the implementer **cannot modify the tests**, the specification stays fixed while the code is written against it. That structural guarantee holds regardless of which models run which role — it doesn't depend on model diversity to pay off.

**Why three design roles instead of one architect?** "Writing the tests" packs two very different jobs together: *deciding what to test* — edge cases, failure modes, exact expected values — which is specification work where a weaker model silently makes worse decisions; and *transcribing those cases into code*, which is mechanical, bulky, and exactly what a cheaper model does well from a precise input. Splitting them means the scarce top-tier model is spent **only on the decisions that propagate** (Phase 1 and escalations), while the bulk of the output tokens moves down-tier. The Verifier's gate is what keeps the cheap transcription honest — it checks the tests against the inventory the Designer wrote, so it's verification against a reference, not open judgment.

The model assignments are the kit's defaults — tune them per project, but keep the direction: top tier for spec decisions and escalations only.

---

## The three files

The system separates **process** (reusable, project-agnostic) from **facts** (rewritten per project). That separation is the whole trick: you reuse the way-of-working everywhere and only ever re-author the facts.

| File | Role | Nature |
|------|------|--------|
| `CLAUDE.md` | Design pipeline contract (Designer / Test-Writer / Verifier) | **Process** — agnostic, reusable as-is |
| `AGENTS.md` | Implementer's contract | **Process** — agnostic, reusable as-is |
| `.ai/PROJECT_ARCHITECTURE.md` | Stack, toolchain, API contract, directory map | **Facts** — specific to one project |
| `.ai/templates/test_plan_template.md` | The Designer → Test-Writer handoff: the test-case inventory | **Process** |
| `.ai/templates/plan_template.md` | The Verifier → Implementer handoff: the implementation plan | **Process** |

`CLAUDE.md` and `AGENTS.md` **deliberately refuse to guess project facts**. Versions, command names, directory layout, the API contract — none of it lives in the process files. It all lives in `PROJECT_ARCHITECTURE.md`, and the process files point to it by name. Get the facts file right once and every role inherits a consistent world.

---

## How a feature flows

```
Designer · Fable 5         Test-Writer · Sonnet 5      Verifier · Opus 5             Implementer · Codex
(CLAUDE.md, Phase 1)       (CLAUDE.md, Phase 2)        (CLAUDE.md, Phases 3+5)       (AGENTS.md)
──────────────────         ────────────────────        ───────────────────           ───────────────────
1. Analyze requirement
2. Fix signatures, write
   test-case inventory
   {f}.testplan.md ──────► 3. Transcribe tests,
                              one per inventory row
                           4. Verify RED ────────────► 5. Gate: tests vs inventory
                              ◄───── REJECTED(n) ─────    (2nd rejection → Fable 5)
                                                       6. APPROVED → write plan
                                                          {f}.md ──────────────────► 7. Read the plan
                                                                                     8. Minimum code → GREEN
                                                                                     9. Types, lint, format
                                                      10. Review checklist ◄──────── (hand back)
                                                          (Fable 5 on triggers)
                                                      11. Docs impact decision
```

Two artifacts per feature in `.ai/plans/`, and they are the **sole interfaces** between roles:
`{feature}.testplan.md` (the test-case inventory — exact arrange/act/assert values, frozen
signatures, allowed mocks) and `{feature}.md` (the implementation plan, issued by the Verifier
only after the gate passes). If it's not in the artifact, the next role asks instead of guessing.
Run each phase in a **fresh session** — the Verifier judges the tests from the artifacts, not
from the memory of having watched them being written.

## Models & escalation

Opus runs the gate and the review by default; Fable is spent only where a weaker model would
decide worse. Four triggers bring it back in (the full text lives in `CLAUDE.md § Escalation`):

1. **Architectural surface** — new pattern, first materialization of a layer, changed dependency
   direction → Fable also runs the final review.
2. **Double gate rejection** — the same feature is rejected twice at the gate → the gate re-runs
   on Fable.
3. **Post-review bug** — a defect surfaces after a passed review → Fable runs the post-mortem.
4. **ADRs, `/init-architecture`, `/migrate-architecture`** — always Fable.

Two loops close the pipeline: a **gate bounce** (rejection sends the tests back to the
Test-Writer with point-by-point notes), and a **review loop** (a logic issue found in review
becomes new inventory rows and re-enters the pipeline as failing tests — never a hand-patched
fix).

---

## Getting started

**Prerequisites:** [Claude Code](https://www.anthropic.com/claude-code), and a project with a dependency manifest (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`, …).

```bash
# 1. Drop the kit's directories into your project root
cp -r .ai .claude /path/to/your/project/

# 2. From your project, in Claude Code (on Claude Fable 5 — it's an escalation-tier task):
/init-architecture
```

`/init-architecture` walks six phases: **inspect** the repo → **resolve** the decisions it can't derive (it asks you) → **scaffold** the three files → **fill** them from real project facts → **self-check** → **report**. The only point that needs you is the decisions phase — everything else the agent handles.

When it finishes you'll have `CLAUDE.md`, `AGENTS.md`, and `.ai/PROJECT_ARCHITECTURE.md` filled for your project, and `.ai/plans/` ready for the first handoff.

### Migrating from the two-role kit

If a project was bootstrapped with the previous version of this kit (a single **architect** role
plus the implementer — no testplan, no gate), don't re-init it: the filled facts are the
expensive part and `/init-architecture` would rebuild them from scratch. Instead:

```bash
# 1. Re-copy the kit's directories (overwrites templates & commands only — never the live docs)
cp -r .ai .claude /path/to/your/project/

# 2. From your project, in Claude Code (on Claude Fable 5), with a clean working tree:
/migrate-architecture
```

`/migrate-architecture` rebuilds the live docs from the new templates while carrying every
project fact over **unchanged** (architecture model, coverage floor, traps, conventions), and
asks you what to do with in-flight plans: grandfather them as-is, or have the Designer
retro-write their testplan so they re-enter the pipeline through the gate.

---

## What the init asks you

Four things inspection can't settle, so the command stops and asks:

1. **Architecture model** — pick one, applied identically across all three files:
   - **A — Flat MVCS** · single app-wide MVC + Client/Service layer (the default)
   - **B — Domain-partitioned** · split by domain, each re-applying MVCS internally (larger systems)
   - **C — Other** · describe your structure and its dependency rules
2. **Deliberate exclusions** — libraries you're intentionally *not* installing, so they're marked `NOT INSTALLED` rather than silently omitted.
3. **API contract source** — which doc/spec is normative if one exists.
4. **Coverage floor** — the non-negotiable minimum (default 85%).

It recommends an option where it can, but it won't choose your architecture for you.

---

## Template markers

The templates carry their own filling instructions. Three markers, three lifecycles:

| Marker | Meaning | Survives in the finished file? |
|--------|---------|-------------------------------|
| `<!-- FILL: … -->` | Instruction to the filling agent | **No** — removed once satisfied |
| `[[DECISION: … ]]` | A choice to make at init | **No** — resolved to one branch |
| `TODO` | A value genuinely not yet decided | **Yes** — flags an open team decision |

`FILL` is *how to fill* (ephemeral). `TODO` is *not yet decided* (legitimate to keep). The init's self-check greps for surviving `FILL`/`DECISION` markers — `TODO`s are allowed and reported as open decisions.

---

## Consistency rules the files share

`PROJECT_ARCHITECTURE.md` opens with a short **Contract** section the init must honor. These are the seams where the three files can silently drift apart:

1. **Command names are an API.** Every command the process files reference (`test`, `typecheck`, `lint`, `format`, `format:check`, `coverage`) has a matching row in the toolchain table. Rename one and you break the process contract.
2. **The layer map matches the architecture choice** (A/B/C), with real directory paths.
3. **One coverage floor, two files** — identical in `CLAUDE.md` and `PROJECT_ARCHITECTURE.md`.
4. **Fixed layer vocabulary** — Model / View / Controller / Service / Client, verbatim, everywhere.
5. **Secrets boundary is absolute** — no provider keys or credentials in frontend source, env, or bundle.

> The init self-checks these by inspection. If you later want them enforced mechanically in CI, they're written to be greppable — a verification script is a natural addition (intentionally left out here to keep the flow simple).

---

## Layout

```
.ai/
  templates/
    CLAUDE.template.md
    AGENTS.template.md
    PROJECT_ARCHITECTURE.template.md
    test_plan_template.md         # Designer → Test-Writer (test-case inventory)
    plan_template.md              # Verifier → Implementer (implementation plan)
  plans/                          # per-feature artifacts land here
.claude/
  commands/
    init-architecture.md          # the bootstrap slash command
    migrate-architecture.md       # upgrade a two-role-kit project to the pipeline
```

---

## Possible extensions (not implemented)

- **A broad-evaluation reviewer.** A large-context model (e.g. Gemini) could do whole-repo sanity passes that complement the Verifier's focused, checklist-driven review. Deliberately left out — the per-feature review has been enough in practice so far. Add it if your projects grow past what a focused review comfortably covers.
- **A CI verification gate.** Mechanically enforce the Contract invariants on every change, not just at init (see the note above).

---

## License

MIT — see [`LICENSE`](LICENSE).

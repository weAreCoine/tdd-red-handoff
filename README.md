# Multi-Agent TDD Architecture Kit

A small, opinionated convention for running a **two-role, test-driven multi-agent workflow** on a software project: one agent **architects and writes the tests**, another **makes them pass**. The two never trade roles, and a single project-facts file keeps them — and you — honest.

This repo gives you the templates and a single Claude Code slash command to bootstrap the system in any new project.

> **Why this exists.** I've run this flow across many projects, and it's the setup that gives me the most **predictable, consistent** results. The README below is the approach, not just the files.

---

## The idea in one minute

Most "AI writes my code" setups fail the same way: the same agent writes the test *and* the code that satisfies it, so the test quietly bends to match whatever got implemented. The spec stops being a spec.

This kit splits the work into two roles with a hard wall between them:

| Role | File | Does | Must NOT |
|------|------|------|----------|
| **Architect** | `CLAUDE.md` | Designs, writes the tests, writes the handoff plan, reviews the result | Write application code |
| **Implementer** | `AGENTS.md` | Writes the minimum code to make the failing tests pass | Touch the tests, invent patterns, add deps |

Because the implementer **cannot modify the tests**, the specification stays fixed while the code is written against it. That structural guarantee holds **even if both roles run the same model** — it doesn't depend on model diversity to pay off.

Running the two roles on *different* models (e.g. one model as architect, another as implementer) is a well-established and fast-growing practice for reducing the bias an agent has toward rubber-stamping its own work, and for playing to each model's strengths. It's a real benefit — but the separation above is the part that earns its keep on its own.

---

## The three files

The system separates **process** (reusable, project-agnostic) from **facts** (rewritten per project). That separation is the whole trick: you reuse the way-of-working everywhere and only ever re-author the facts.

| File | Role | Nature |
|------|------|--------|
| `CLAUDE.md` | Architect's contract | **Process** — agnostic, reusable as-is |
| `AGENTS.md` | Implementer's contract | **Process** — agnostic, reusable as-is |
| `.ai/PROJECT_ARCHITECTURE.md` | Stack, toolchain, API contract, directory map | **Facts** — specific to one project |
| `.ai/templates/plan_template.md` | The architect → implementer handoff format | **Process** |

`CLAUDE.md` and `AGENTS.md` **deliberately refuse to guess project facts**. Versions, command names, directory layout, the API contract — none of it lives in the process files. It all lives in `PROJECT_ARCHITECTURE.md`, and the process files point to it by name. Get the facts file right once and both agents inherit a consistent world.

---

## How a feature flows

```
Architect (CLAUDE.md)                    Implementer (AGENTS.md)
─────────────────────                    ───────────────────────
1. Analyze the requirement
2. Write tests  →  verify they FAIL
3. Write .ai/plans/{feature}.md  ──────►  4. Read the plan
                                          5. Write minimum code → tests GREEN
                                          6. Type-check, lint, format clean
7. Review against the checklist  ◄──────  (hand back)
8. Docs impact decision
```

The plan in `.ai/plans/` is the **sole interface** between the two roles: exact file paths, signatures with types, which patterns to mirror, explicit "do / do not" constraints. If it's not in the plan, the implementer asks instead of guessing.

---

## Getting started

**Prerequisites:** [Claude Code](https://www.anthropic.com/claude-code), and a project with a dependency manifest (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`, …).

```bash
# 1. Drop the kit's directories into your project root
cp -r .ai .claude /path/to/your/project/

# 2. From your project, in Claude Code:
/init-architecture
```

`/init-architecture` walks six phases: **inspect** the repo → **resolve** the decisions it can't derive (it asks you) → **scaffold** the three files → **fill** them from real project facts → **self-check** → **report**. The only point that needs you is the decisions phase — everything else the agent handles.

When it finishes you'll have `CLAUDE.md`, `AGENTS.md`, and `.ai/PROJECT_ARCHITECTURE.md` filled for your project, and `.ai/plans/` ready for the first handoff.

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
    plan_template.md
  plans/                          # handoff plans land here
.claude/
  commands/
    init-architecture.md          # the bootstrap slash command
```

---

## Possible extensions (not implemented)

- **A third reviewer agent for broad evaluation.** A large-context model (e.g. Gemini) could do whole-repo sanity passes that complement the architect's focused review. Deliberately left out — the two-role loop has been enough in practice so far. Add it if your projects grow past what a focused review comfortably covers.
- **A CI verification gate.** Mechanically enforce the Contract invariants on every change, not just at init (see the note above).

---

## License

MIT — see [`LICENSE`](LICENSE).

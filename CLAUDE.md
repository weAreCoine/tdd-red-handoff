# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is the **Multi-Agent TDD Architecture Kit** — a meta-repository. There is no application code, build system, or test suite. The deliverables are Markdown files:

- `.ai/templates/` — five templates that other projects instantiate
- `.claude/commands/` — four slash commands (`/init-architecture`, `/switch-profile`, `/update-models-roster`, `/verify-kit`) that drive instantiation and upkeep
- `bin/verify-kit.sh` — the kit's test surface (ADR-0006): the mechanical invariant checks, in kit-repo and target-project modes
- `README.md` — the approach itself, kept as a faithful mirror of the templates and commands

Target projects install the kit with `cp -r .ai .claude /path/to/project/`, then run `/init-architecture` (new project — the legacy-kit migration is its appendix path); `/switch-profile` changes the active profile per task, `/update-models-roster` records model changes afterwards.

**Do not confuse this file with `.ai/templates/CLAUDE.template.md`.** That template *becomes* a target project's `CLAUDE.md`; this root file documents the kit repo itself and is never copied out (only `.ai/` and `.claude/` ship).

## The system the kit ships

A TDD pipeline with four roles on different model tiers and a hard wall between design and implementation — the implementer can never touch tests, so the spec cannot bend to match the code:

| Phase | Role | Capability tier | Contract file (in target project) |
|---|---|---|---|
| 1 Design | Designer | strongest reasoning tier | `CLAUDE.md` |
| 2 Test transcription | Test-Writer | cost-efficient tier | `CLAUDE.md` |
| 3 Gate + plan, 5 Review | Verifier | strong review tier (Designer's model on escalation) | `CLAUDE.md` |
| 4 Implementation | Implementer | external code-gen agent | `AGENTS.md` |

Two design principles run through every file:

- **Process vs facts.** `CLAUDE.template.md` and `AGENTS.template.md` are project-agnostic *process* contracts; `PROJECT_ARCHITECTURE.template.md` holds all project-specific *facts* (versions, commands, paths). Process files deliberately refuse to state facts — they point to `PROJECT_ARCHITECTURE.md` sections by name. When editing a template, keep facts out of the process files.
- **Artifacts are the sole interfaces between roles.** Per feature, in the target project's `.ai/plans/`: `{feature}.testplan.md` (Designer → Test-Writer, and the Verifier's gate reference; from `test_plan_template.md`) and `{feature}.md` (Verifier → Implementer, issued only after `Gate: APPROVED`; from `plan_template.md`).

## Marker system (inverted in this repo)

Templates carry three markers: `<!-- FILL: … -->` (instruction to the filling agent, deleted once satisfied), `[[DECISION: … ]]` (resolved to one branch at init), `TODO` (genuinely open value, may survive).

In **target projects** the self-check grep must return nothing. In **this repo** the markers are the product: they must survive in the templates, and their wording is what the filling agent obeys — edit them as carefully as executable code.

```bash
# The self-check pattern the commands rely on (target projects: must be empty)
grep -nE 'FILL:|\[\[DECISION' <file>
```

## Cross-file couplings — edit one file, check its mirrors

The files reference each other by exact strings, section names, phase numbers, and in one case line numbers. These are the seams that break silently:

1. **Migration detection strings.** `migrate-architecture.md` greps `CLAUDE.template.md` for `Test-Writer` (Phase 0, new-kit presence check) and detects old-format live docs via `You are the **architect**`. Its Phase 5 self-check greps `-nwiE 'architect'` — so no template may use the bare word "architect" as a role name ("architecture" is safe, `-w` won't match it).
2. **Line-number coupling.** `migrate-architecture.md` Phase 3 references "template lines 6–8" of `AGENTS.template.md` (the header blockquote). Editing that template's header shifts the numbers — update the command.
3. **Phase numbering** (1 Design · 2 Test Transcription · 3 Gate & Plan · 4 Implementation · 5 Review) is hardcoded in: `CLAUDE.template.md` (role table + § Pipeline), `PROJECT_ARCHITECTURE.template.md` (Contract §1: "Phases 2, 3 and 5"), `AGENTS.template.md`, both plan templates, both commands (including the old→new renumbering map in `migrate-architecture.md` Phase 2), and the README flow diagram.
4. **Escalation triggers 1–4** live in `CLAUDE.template.md § Escalation`, are summarized in README § Models & escalation, and both commands cite "trigger 4" as their own model check.
5. **Toolchain command names are an API**: `test`, `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage`. Referenced by name from `CLAUDE.template.md` Phases 2/3/5 and `AGENTS.template.md` Steps 3–4; defined as rows in `PROJECT_ARCHITECTURE.template.md § Toolchain`, guarded by its Contract §1. Contract rows carry the name **verbatim in the table's first cell** (informational rows keep human labels) — `bin/verify-kit.sh` checks the cells literally.
6. **Status lifecycle vocabulary** `DRAFT → READY → RED → APPROVED / REJECTED(n)` and the `Gate: APPROVED` line: shared verbatim by `CLAUDE.template.md § Artifacts`, `test_plan_template.md`, `plan_template.md` §3, and `AGENTS.template.md` Step 1.
7. **Layer vocabulary** Model / View / Controller (orchestration) / Service / Client — fixed, verbatim, across all three doc templates and both plan templates (Contract §4 of `PROJECT_ARCHITECTURE.template.md`).
8. **Concrete model names live in exactly two places**: the README defaults table and `PROJECT_ARCHITECTURE.template.md § Model Roster` (its Contract §6). Every other file — this one included — refers to models by role ("the Designer's model"). Never inline a model name elsewhere; `/update-models-roster` is the procedure that edits the roster and greps for leaks.
9. **README mirrors everything.** Any change to roles, phases, triggers, markers, or layout must be reflected there (see commit history — README updates ship with the feature).

The `PROJECT_ARCHITECTURE.template.md § Contract` section is a live guard shipped into target projects — never delete it or turn it into scaffolding.

## Verification

No CI. After editing, run the kit's test surface (ADR-0006):

```bash
bin/verify-kit.sh   # kit-repo mode: markers survive, detection strings intact, contract
                    # names pinned, floor anchors present, model names confined (coupling #8)
```

Three states — PASS / FAIL / NOT CHECKED — and a non-zero exit on any FAIL. What it cannot decide
mechanically (README mirror fidelity, the line-number coupling #2, correct *use* of the shared
vocabularies) it lists instead of omitting: for those, walk the couplings list above for
whichever file changed. Commits follow semantic prefixes (`feat:`, `fix:`, `docs:`, `chore:`) on `feature/*` branches.

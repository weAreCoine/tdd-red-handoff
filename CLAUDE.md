# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is the **Multi-Agent TDD Architecture Kit** — a meta-repository. There is no application code, build system, or test suite. The deliverables are Markdown files:

- `.ai/templates/` — five templates that other projects instantiate
- `.ai/process/` — the two process chapters (`two-role.md`, `pipeline.md`): each profile's roles-and-phases contract, shipped **verbatim** (no markers, no project facts, never edited in a target)
- `commands/` — five slash commands (`/init-architecture`, `/switch-profile`, `/update-kit`, `/update-models-roster`, `/verify-kit`) that drive instantiation and upkeep — served to the operator by the plugin, never installed into targets (ADR-0004)
- `.claude-plugin/` — the plugin manifests: `plugin.json` (its `version` is the authoritative kit version — ADR-0005) and `marketplace.json` (the repo is its own marketplace, plugin source `"./"`)
- `bin/verify-kit.sh` — the kit's test surface (ADR-0006): the mechanical invariant checks, in kit-repo and target-project modes; ships inside the plugin, so `/verify-kit` works in any target
- `README.md` — the approach itself, kept as a faithful mirror of the templates and commands

Target projects install the kit as a Claude Code plugin — `/plugin marketplace add weAreCoine/tdd-red-handoff`, then `/plugin install tdd-red-handoff` — and run `/init-architecture` (new project — the legacy-kit migration is its appendix path); `/switch-profile` changes the active profile per task, `/update-kit` realigns the installed kit files when a new plugin version ships, `/update-models-roster` records model changes afterwards.

**Do not confuse this file with `.ai/templates/CLAUDE.template.md`.** That template *becomes* a target project's `CLAUDE.md`; this root file documents the kit repo itself and is never instantiated into a target (targets receive their files through `/init-architecture`, drawn from the plugin's payload).

## The system the kit ships

One kit, two **profiles**, chosen per task (ADR-0001). Both share the hard wall — whoever writes tests never writes application code, and the implementer never touches tests — and differ in how the design side is staffed:

- **two-role** — Architect (design, tests, plan, review; strongest tier, no escalation ladder) + Implementer. One artifact per feature: `{feature}.md`.
- **pipeline** — Designer (strongest tier) / Test-Writer (cost-efficient tier) / Verifier (strong review tier; Designer's model on escalation) + Implementer, with a gate between tests and implementation. Two artifacts: `{feature}.testplan.md` + `{feature}.md`. Phases: 1 Design · 2 Test transcription · 3 Gate + plan · 4 Implementation · 5 Review.

Three design principles run through every file:

- **Shell + chapter.** A target's `CLAUDE.md` is a shell: **line 1** imports the active chapter (`@.ai/process/<profile>.md`), and everything below — shared process sections + project overlay — is identical under both profiles. Switching rewrites the import line and `.ai/kit.json`, nothing else (`/switch-profile`).
- **Process vs facts.** The shell, the chapters, and `AGENTS.template.md` are project-agnostic *process* contracts; `PROJECT_ARCHITECTURE.template.md` holds all project-specific *facts* (versions, commands, paths). Process files deliberately refuse to state facts — they point to `PROJECT_ARCHITECTURE.md` sections by name. When editing, keep facts out of the process files.
- **Artifacts are the sole interfaces between roles.** Per feature, in the target project's `.ai/plans/`: `{feature}.md` (design side → Implementer, from `plan_template.md`; under pipeline, issued only after `Gate: APPROVED`) and — pipeline only — `{feature}.testplan.md` (Designer → Test-Writer, and the Verifier's gate reference; from `test_plan_template.md`). Testplans go **inert** under two-role: never rewritten, moved, or deleted.

## Marker system (inverted in this repo)

Templates carry three markers: `<!-- FILL: … -->` (instruction to the filling agent, deleted once satisfied), `[[DECISION: … ]]` (resolved to one branch at init), `TODO` (genuinely open value, may survive).

In **target projects** the self-check grep must return nothing. In **this repo** the markers are the product: they must survive in the templates, and their wording is what the filling agent obeys — edit them as carefully as executable code.

The process chapters are the exception on both sides: they carry **no markers anywhere**, ever — they ship verbatim (`verify-kit`'s `chapters` check).

```bash
# The self-check pattern the commands rely on (target projects: must be empty)
grep -nE 'FILL:|\[\[DECISION' <file>
```

## Cross-file couplings — edit one file, check its mirrors

The files reference each other by exact strings, section names, and phase numbers. These are the seams that break silently:

1. **The profile triad.** `.ai/kit.json` `profile` ↔ `CLAUDE.md` line-1 import ↔ chapter filename in `.ai/process/`. Set by `/init-architecture` (Phase 3), changed only by `/switch-profile`; nothing else may restate the active profile. `verify-kit` target mode checks it (`kit-manifest`). The manifest's second field, `kitVersion`, is the install stamp: written from `.claude-plugin/plugin.json` `version` — the only place a kit version is stated — at init, restamped by `/update-kit`, which is the procedure that compares the two (ADR-0005).
2. **Detection strings.** `/init-architecture` Phase 0 routes on the absence of `.ai/kit.json` plus `You are the **architect**` in the live `CLAUDE.md` (→ legacy-kit appendix) or pipeline-role text (→ pre-profile re-init). And the pipeline chapter must contain `Test-Writer` and must **never** use the bare word "architect" — that word belongs to `two-role.md` and the roster only (`verify-kit` `chapters` check; in target mode the same grep runs only on pre-profile installs, where the union roster doesn't yet legitimize it).
3. **Phase numbers are confined to the chapters.** Numbering differs per profile (two-role: 1 Analyze · 2 Tests · 3 Plan · 4 Review — pipeline: 1 Design · 2 Transcription · 3 Gate · 4 Implementation · 5 Review), so the profile-agnostic files — shell template, `AGENTS.template.md`, `PROJECT_ARCHITECTURE.template.md`, both plan templates — name phases and never number them. Content grafted during migration converts numbers to names. `verify-kit` enforces it (`phase-numbers`, both modes).
4. **Escalation triggers 1–4** live in `.ai/process/pipeline.md § Escalation` — pipeline only; two-role has no ladder by decision (the Architect already runs the strongest roster tier). The README summarizes them, and `/init-architecture` cites trigger 4 ("ADRs and `/init-architecture`") as its own model check.
5. **Toolchain command names are an API**: `test`, `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage`. Referenced by name from both process chapters, the shell's shared sections (`coverage`), and `AGENTS.template.md` Steps 2–4; defined as rows in `PROJECT_ARCHITECTURE.template.md § Toolchain`, guarded by its Contract §1. Contract rows carry the name **verbatim in the table's first cell** (informational rows keep human labels) — `bin/verify-kit.sh` checks the cells literally (`contract-names`).
6. **Status lifecycle vocabulary is pipeline-only**: `DRAFT → READY → RED → APPROVED / REJECTED(n)` and the `Gate: APPROVED` line are shared verbatim by `pipeline.md § Artifacts`, `test_plan_template.md`, `plan_template.md` §3, and `AGENTS.template.md` Step 1 — but the last two treat them as **conditional** (`Source testplan` / `Gate` rows marked pipeline-only; AGENTS' "a plan without that row comes from a profile with no gate"). Shared files must never assume the lifecycle exists. Distinct from it: the plan file's own two-value status `RED → DONE` (`plan_template.md` header; `DONE` set by the review phase — both chapters instruct it).
7. **Layer vocabulary** Model / View / Controller (orchestration) / Service / Client — fixed, verbatim, across all three doc templates, both plan templates, and both chapters (Contract §4 of `PROJECT_ARCHITECTURE.template.md`).
8. **Concrete model names live in exactly two places**: the README defaults table and `PROJECT_ARCHITECTURE.template.md § Model Roster` (its Contract §6) — the roster is the **union** of both profiles' roles. Every other file — this one included — refers to models by role ("the Designer's model"). Never inline a model name elsewhere; `/update-models-roster` is the procedure that edits the roster and greps for leaks (`verify-kit` `model-roster`).
9. **README mirrors everything.** Any change to profiles, roles, phases, triggers, markers, commands, or layout must be reflected there (see commit history — README updates ship with the feature).

The `PROJECT_ARCHITECTURE.template.md § Contract` section is a live guard shipped into target projects — never delete it or turn it into scaffolding.

## Verification

No CI. After editing, run the kit's test surface (ADR-0006):

```bash
bin/verify-kit.sh   # kit-repo mode: markers survive, chapters verbatim (no markers, detection
                    # strings intact), contract names pinned, floor anchors present, phase
                    # numbers confined to the chapters, model names confined (coupling #8),
                    # plugin manifest sane (version pinned, self-marketplace, commands present)
```

Three states — PASS / FAIL / NOT CHECKED — and a non-zero exit on any FAIL. What it cannot decide
mechanically (README mirror fidelity, correct *use* of the shared vocabularies) it lists instead
of omitting: for those, walk the couplings list above for whichever file changed. Commits follow
semantic prefixes (`feat:`, `fix:`, `docs:`, `chore:`) on `feature/*` branches.

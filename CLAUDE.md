# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is the **Multi-Agent TDD Architecture Kit** — a meta-repository. There is no application code and no build system; the deliverables are Markdown files, plus two shell programs and the behavior suite that pins the second one:

- `.ai/templates/` — five templates that other projects instantiate
- `.ai/process/` — the three process chapters (`two-role.md`, `pipeline.md`, `autopilot.md`): each profile's roles-and-phases contract, shipped **verbatim** (no markers, no project facts, never edited in a target)
- `commands/` — seven slash commands (`/fly`, `/init-architecture`, `/show-profile`, `/switch-profile`, `/update-kit`, `/update-models-roster`, `/verify-kit`) that drive instantiation and upkeep — served to the operator by the plugin, never installed into targets (ADR-0004)
- `.claude-plugin/` — the plugin manifests: `plugin.json` (its `version` is the authoritative kit version — ADR-0005) and `marketplace.json` (the repo is its own marketplace, plugin source `"./"`)
- `bin/verify-kit.sh` — the kit's test surface (ADR-0006): the mechanical invariant checks, in kit-repo and target-project modes; ships inside the plugin, so `/verify-kit` works in any target
- `bin/autopilot-driver.sh` — the autopilot profile's driver (ADR-0008): deterministic dispatch of flight phases 2–9, preflight, the write-set wall (an edge per dispatched phase, measured on each phase's git diff; test paths from the target's versioned `.ai/wall.env`, fail-closed), the phase-8 acceptance stamp (an empty commit with the reserved `Autopilot-Green` trailer — phase 9's entry proof, walked from `HEAD` through artifact-only commits), counters, git/PR ribbon; ships inside the plugin, launched by `/fly`, holds no model names (the machine binding comes from the target's `.ai/autopilot/models.env`)
- `tests/driver/` — the driver's behavior suite (`run.sh`: disposable git repositories, stub harnesses, no network and no real model) and `mutants.sh`, the mutation harness whose rows are exact sed programs — the evidence behind ADR-0008's safety-property table. It rides along in the plugin payload like the rest of the repo, but nothing in it is installed into a target: it tests the kit, it is not part of a target's files
- `README.md` — the approach itself, kept as a faithful mirror of the templates and commands

Target projects install the kit as a Claude Code plugin — `/plugin marketplace add weAreCoine/tdd-red-handoff`, then `/plugin install tdd-red-handoff` — and run `/init-architecture` (new project — the legacy-kit migration is its appendix path); `/switch-profile` changes the active profile per task (`/show-profile` prints it, read-only), `/fly <feature>` opens an autopilot flight, `/update-kit` realigns the installed kit files when a new plugin version ships, `/update-models-roster` records model changes afterwards.

**Do not confuse this file with `.ai/templates/CLAUDE.template.md`.** That template *becomes* a target project's `CLAUDE.md`; this root file documents the kit repo itself and is never instantiated into a target (targets receive their files through `/init-architecture`, drawn from the plugin's payload).

## The system the kit ships

One kit, three **profiles**, chosen per task (ADR-0001, ADR-0008). All share the hard wall — whoever writes tests never writes application code, and the implementer never touches tests — and differ in how the design side is staffed and who supervises the handoffs:

- **two-role** — Architect (design, tests, plan, review; strongest tier, no escalation ladder) + Implementer. One artifact per feature: `{feature}.md`.
- **pipeline** — Designer (strongest tier) / Test-Writer (cost-efficient tier) / Verifier (strong review tier; Designer's model on escalation) + Implementer, with a gate between tests and implementation. Two artifacts: `{feature}.testplan.md` + `{feature}.md`. Phases: 1 Design · 2 Test transcription · 3 Gate + plan · 4 Implementation · 5 Review.
- **autopilot** — the unattended flight (ADR-0008): operator at the two ends only; nine phases chained by `bin/autopilot-driver.sh` (`/fly` opens phase 1). One family designs and judges (Designer + four reviewer roles on the Verifier's tier), the other produces (TestPlan Designer, Test Writer — space, not pipeline's hyphenated role — Handoff Planner, Implementer). Three artifacts: `{feature}.adr.md` + the pipeline pair; caps 2 rejections/gate + 6 backward edges; flight state gitignored in `.ai/autopilot/`. Phases: 1 Design interview · 2 Test inventory · 3 Inventory gate · 4 Test transcription · 5 Test gate · 6 Implementation plan · 7 Plan gate · 8 Implementation · 9 Final review.

Three design principles run through every file:

- **Shell + chapter.** A target's `CLAUDE.md` is a shell: **line 1** imports the active chapter (`@.ai/process/<profile>.md`), and everything below — shared process sections + project overlay — is identical under every profile. Switching rewrites the import line and `.ai/kit.json`, nothing else (`/switch-profile`).
- **Process vs facts.** The shell, the chapters, and `AGENTS.template.md` are project-agnostic *process* contracts; `PROJECT_ARCHITECTURE.template.md` holds all project-specific *facts* (versions, commands, paths). Process files deliberately refuse to state facts — they point to `PROJECT_ARCHITECTURE.md` sections by name. When editing, keep facts out of the process files.
- **Artifacts are the sole interfaces between roles.** Per feature, in the target project's `.ai/plans/`: `{feature}.md` (design side → Implementer, from `plan_template.md`; under the gated profiles authorized by the `Gate: APPROVED` row — written at issue time under pipeline, stamped by the plan gate under autopilot), `{feature}.testplan.md` (gated profiles — design side → transcription, and the gate's reference; from `test_plan_template.md`), and — autopilot only — `{feature}.adr.md`, the flight's design record and autopilot's **provenance signature**. Extended inertness: artifacts produced under another profile are historical records — read, never rewritten, moved, deleted, or retrofitted; a sibling design record marks the whole feature as autopilot's, whatever its statuses say.

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

1. **The profile triad.** `.ai/kit.json` `profile` ↔ `CLAUDE.md` line-1 import ↔ chapter filename in `.ai/process/`. Set by `/init-architecture` (Phase 3), changed only by `/switch-profile`; nothing else may restate the active profile. `verify-kit` target mode checks it (`kit-manifest`). The manifest's second field, `kitVersion`, is the install stamp: written from `.claude-plugin/plugin.json` `version` — the only place a kit version is stated — at init, restamped by `/update-kit`, the procedure that realigns the install; `verify-kit -p <plugin-root>` is the check that compares the two, plus the five installed kit files byte-for-byte (`kit-version` / `install-files`, target mode — ADR-0005).
2. **Detection strings.** `/init-architecture` Phase 0 routes on the absence of `.ai/kit.json` plus `You are the **architect**` in the live `CLAUDE.md` (→ legacy-kit appendix) or pipeline-role text (→ pre-profile re-init). And the pipeline chapter must contain `Test-Writer` and must **never** use the bare word "architect" — that word belongs to `two-role.md` and the roster only; the autopilot chapter must contain `Test Writer` (space — its own role) and never `Test-Writer` (hyphen — pipeline's) nor bare "architect" (`verify-kit` `chapters` check; in target mode the architect grep runs only on pre-profile installs, where the union roster doesn't yet legitimize it).
3. **Phase numbers are confined to the chapters.** Numbering differs per profile (two-role: 1 Analyze · 2 Tests · 3 Plan · 4 Review — pipeline: 1 Design · 2 Transcription · 3 Gate · 4 Implementation · 5 Review — autopilot: 1 Interview · 2 Inventory · 3 Inventory gate · 4 Transcription · 5 Test gate · 6 Plan · 7 Plan gate · 8 Implementation · 9 Final review), so the profile-agnostic files — shell template, `AGENTS.template.md`, `PROJECT_ARCHITECTURE.template.md`, both plan templates — name phases and never number them. Content grafted during migration converts numbers to names. `verify-kit` enforces it (`phase-numbers`, both modes).
4. **Escalation triggers 1–4** live in `.ai/process/pipeline.md § Escalation` — pipeline only; two-role has no ladder by decision (the Architect already runs the strongest roster tier), and autopilot never escalates upward in-flight: preflight failures walk *down* the recorded substitution ladder, caps stop the flight for the operator. The README summarizes them, and `/init-architecture` cites trigger 4 ("ADRs and `/init-architecture`") as its own model check.
5. **Toolchain command names are an API**: `test`, `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage`. Referenced by name from both process chapters, the shell's shared sections (`coverage`), and `AGENTS.template.md` Steps 2–4; defined as rows in `PROJECT_ARCHITECTURE.template.md § Toolchain`, guarded by its Contract §1. Contract rows carry the name **verbatim in the table's first cell** (informational rows keep human labels) — `bin/verify-kit.sh` checks the cells literally (`contract-names`).
6. **Status lifecycle vocabulary belongs to the gated profiles** (pipeline, autopilot): `DRAFT → READY → RED → APPROVED / REJECTED(n)` and the `Gate: APPROVED` line are shared verbatim by `pipeline.md § Artifacts`, `autopilot.md § Artifacts` (with sharpened semantics: `READY` granted by the inventory gate, `Gate: APPROVED` stamped by the plan gate on a plan issued without it), `test_plan_template.md`, `plan_template.md` §3, and `AGENTS.template.md` Step 1 — but the last two treat them as **conditional** (`Source testplan` / `Gate` rows marked gated-profiles-only; AGENTS' "a plan without that row comes from a profile with no gate"). Shared files must never assume the lifecycle exists. Distinct from it: the plan file's own two-value status `RED → DONE` (`plan_template.md` header; `DONE` set by the review phase — every chapter instructs it).
7. **Layer vocabulary** Model / View / Controller (orchestration) / Service / Client — fixed, verbatim, across all three doc templates, both plan templates, and all three chapters (Contract §4 of `PROJECT_ARCHITECTURE.template.md`).
8. **Concrete model names live in exactly two places**: the README defaults table and `PROJECT_ARCHITECTURE.template.md § Model Roster` (its Contract §6) — the roster is the **union** of the profiles' roles (autopilot's reviewer roles resolve to the Verifier row; its production rows and substitution ladder are recorded per project via `/update-models-roster`, the kit ships no default for them; the driver takes its machine binding from the target's gitignored `.ai/autopilot/models.env`, never from this repo). Every other file — this one included — refers to models by role ("the Designer's model"). Never inline a model name elsewhere; `/update-models-roster` is the procedure that edits the roster and greps for leaks (`verify-kit` `model-roster`).
   **Tier substitutions** (a roster tier temporarily unavailable — ADR-0007) are recorded in the roster's `### Tier substitutions (temporary)` prose block, never by editing a `Current model` cell and never as a table column: `roster_models()` extracts the **last cell** of each roster row, so a fourth column would silently become "the models" and the guarded name would stop being guarded — a green run checking the wrong thing. After touching the roster's shape, confirm the extracted set is unchanged. Both chapters read that block (a mismatched session stops *unless* a substitution for its role is recorded), and the per-artifact record lives in `plan_template.md`'s header row and the testplan Log — records, not references, which is why `.ai/plans` stays outside the leak scan.
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

The autopilot driver has a second, behavioral test surface — disposable git repositories and
stub harnesses, no network, no real model:

```bash
sh tests/driver/run.sh          # the driver's behavior suite (scenarios; ~1 min)
sh tests/driver/mutants.sh -j 4 # the mutation table behind ADR-0008 (one exact sed program
                                # per mutant; re-measure after adding or changing scenarios)
```

Three states — PASS / FAIL / NOT CHECKED — and a non-zero exit on any FAIL. What it cannot decide
mechanically (README mirror fidelity, correct *use* of the shared vocabularies) it lists instead
of omitting: for those, walk the couplings list above for whichever file changed. In target mode
the script also accepts `-p <plugin-root>` (install-integrity checks — the plugin commands pass
`${CLAUDE_PLUGIN_ROOT}`; kit mode ignores the flag). Commits follow
semantic prefixes (`feat:`, `fix:`, `docs:`, `chore:`) on `feature/*` branches.

# Multi-Agent TDD Architecture Kit

A small, opinionated convention for running **test-driven agent workflows** on a software project, with a hard wall between design and implementation: whoever writes the tests never writes the application code, and the implementer can never touch the tests — so the specification cannot bend to match whatever got implemented.

One kit, three **profiles**, chosen **per task, not once per project**:

- **two-role** — an **Architect** (one top-tier role: designs, writes the failing tests, plans, reviews) plus the implementer. Fewest sessions, one handoff artifact per feature.
- **pipeline** — a **Designer / Test-Writer / Verifier** trio on three model tiers plus the implementer, with a gate between the tests and the implementation. Tiered cost, two handoff artifacts per feature.
- **autopilot** — a feature crosses the whole wall **unattended**: a design interview at the start, a report and a draft PR at the end, and in between nine phases run as headless sessions chained by a deterministic **driver**. One model family designs and judges, another produces; four cross-family gates. Three artifacts per feature (ADR-0008).

This repo is a **Claude Code plugin** (and its own marketplace): it gives you the templates, the three process chapters, and seven slash commands — `/init-architecture` bootstraps the system in a project (and migrates older installs), `/switch-profile` changes the active profile between tasks, `/show-profile` prints the one currently active, `/fly` opens an autopilot flight, `/update-kit` realigns an installed project to a new kit version, `/update-models-roster` records a model change in the one place model names live, `/verify-kit` runs the kit's mechanical invariant check.

> **Why this exists.** I've run this flow across many projects, and it's the setup that gives me the most **predictable, consistent** results. The README below is the approach, not just the files.

---

## The idea in one minute

Most "AI writes my code" setups fail the same way: the same agent writes the test *and* the code that satisfies it, so the test quietly bends to match whatever got implemented. The spec stops being a spec.

The kit's fix is structural, and it holds under every profile: the design side writes failing tests and hands the implementer a plan; the implementer writes the minimum code to turn them green and **cannot modify the tests**. That guarantee doesn't depend on model diversity to pay off — it's the wall, not the tiers, that keeps the spec fixed.

What the profiles change is how the design side is staffed — and who supervises the handoffs:

| | **two-role** | **pipeline** | **autopilot** |
|---|---|---|---|
| Design side | **Architect** — one role does design, tests, plan, review | **Designer** (spec) → **Test-Writer** (transcription) → **Verifier** (gate, plan, review) | **Designer** (interview) + four reviewer gates; the test inventory, tests and plan are produced across a model-family line |
| Implementer | external code-gen agent (`AGENTS.md`) | same | same contract, flown headless (mid production tier) |
| Handoff artifacts | `{feature}.md` (implementation plan) | `{feature}.testplan.md` (test-case inventory) + `{feature}.md` | `{feature}.adr.md` (design record) + the pipeline pair |
| Sessions per feature | fewest | five fresh sessions | one interactive + eight headless, chained by the driver |
| Supervision | the operator, between phases | the operator, between phases | the driver's gates and caps; the operator at the two ends only |
| Worth it when | small or low-stakes changes | code that holds real data | features you can fully specify up front and want flown while you do something else |

The selection criterion is the **stakes of the work** versus the friction the profile imposes: five fresh sessions and two artifacts per feature earn their keep on code that matters, and cost more than they return on a quick fix; an unattended flight earns its keep when the interview can front-load every decision — nobody attends the later phases, so an ambiguity that surfaces mid-flight is a bounce or a stop, never a question. That judgement changes task by task — so switching is a routine, bidirectional operation (`/switch-profile`), not a migration.

**Why three design roles in the pipeline?** "Writing the tests" packs two very different jobs together: *deciding what to test* — edge cases, failure modes, exact expected values — which is specification work where a weaker model silently makes worse decisions; and *transcribing those cases into code*, which is mechanical, bulky, and exactly what a cheaper model does well from a precise input. Splitting them means the scarce top-tier model is spent **only on the decisions that propagate**, while the bulk of the output tokens moves down-tier. The Verifier's gate is what keeps the cheap transcription honest — it checks the tests against the inventory the Designer wrote, so it's verification against a reference, not open judgment.

---

## Default models

Concrete model names live in exactly two places: this table, and the roster prefilled in `PROJECT_ARCHITECTURE.template.md § Model Roster` — the **union** of the profiles' roles, of which the active profile uses its subset. Everywhere else the files say "the Designer's model": each project resolves roles to models in its own `PROJECT_ARCHITECTURE.md § Model Roster`, so a model release means editing roster cells (`/update-models-roster`), not rewriting the kit.

| Role | Profile | Default model |
|------|---------|---------------|
| Architect | two-role | Claude Fable 5 |
| Designer | pipeline · autopilot | Claude Fable 5 |
| Verifier | pipeline · autopilot | Claude Opus 5 |
| Test-Writer | pipeline | Claude Sonnet 5 |
| Implementer | all | Codex |

Tune the assignments per project, but keep the direction: top tier for spec decisions and escalations only.

The autopilot profile adds roles this table deliberately does **not** default: its four reviewer roles (TestPlan Reviewer, Test Reviewer, Plan Reviewer, Final Reviewer) all resolve to the **Verifier** row, and its production roles (TestPlan Designer / Handoff Planner on a flagship production tier, Test Writer on a cost-efficient production tier, the Implementer on a mid production tier) plus their substitution ladder are recorded **per project** with `/update-models-roster` before the first flight — new names come from you, never from an agent's memory.

**When a tier is unavailable** — quota exhausted, access revoked, provider outage — the roster row stays as it is (it names the tier the project *wants*) and the outage is recorded beside the table, under `### Tier substitutions (temporary)`: which role, which model is actually running, since when, until what lifts it, why. That line is what changes the chapters' behaviour: a role whose session model doesn't match its row **stops**, unless a substitution for that role is recorded — then it proceeds and declares itself, and every artifact it produces records the substitution permanently (a row in the plan header, a note in the testplan Log). An agent never writes the line on its own: an unavailable tier is a fact only you can report, and only you can judge the work worth doing without it (`/update-models-roster`, ADR-0007).

---

## The files

The system separates **process** (reusable, project-agnostic) from **facts** (rewritten per project). That separation is the whole trick: you reuse the way-of-working everywhere and only ever re-author the facts.

In a target project:

| File | Role | Nature |
|------|------|--------|
| `CLAUDE.md` | The shell: line 1 imports the active process chapter; shared process sections + project overlay follow | **Process** shell + **facts** overlay |
| `.ai/process/two-role.md`, `.ai/process/pipeline.md`, `.ai/process/autopilot.md` | The roles-and-phases contract of each profile — all installed, so switching is offline | **Process** — ships verbatim, never edited |
| `AGENTS.md` | Implementer's contract — profile-agnostic, names its counterpart neutrally | **Process** — agnostic, reusable as-is |
| `.ai/PROJECT_ARCHITECTURE.md` | Stack, toolchain, model roster, API contract, directory map | **Facts** — specific to one project |
| `.ai/kit.json` | The kit manifest: which profile is active (and which kit version installed it) | **Manifest** — machine-readable, two fields |
| `.ai/templates/test_plan_template.md` | Design side → transcription handoff: the test-case inventory (gated profiles) | **Process** |
| `.ai/templates/plan_template.md` | Design side → Implementer handoff: the implementation plan (every profile) | **Process** |
| `.ai/autopilot/` | Flight state: verdict JSONs, counters, preflight nonces, logs, report — **gitignored** | **Operational** — never an interface between roles |

The process files **deliberately refuse to guess project facts**. Versions, command names, directory layout, the API contract — none of it lives there. It all lives in `PROJECT_ARCHITECTURE.md`, and the process files point to it by name. Get the facts file right once and every role inherits a consistent world.

The `CLAUDE.md` shell is what makes switching cheap: its **line 1** is `@.ai/process/<profile>.md`, and everything below it — shared process sections, project overlay — is identical under every profile. The import line, the `profile` field of `.ai/kit.json`, and the chapter filename must always agree (the **profile triad**); `/switch-profile` owns all three, and nothing else may restate the active profile.

---

## How a feature flows

### two-role

```
Architect                                     Implementer
(two-role chapter, via CLAUDE.md)             (AGENTS.md)
─────────────────────────────────             ───────────────────────
1. Analyze the requirement
2. Write failing tests, verify RED
3. Write the implementation plan
   {f}.md ──────────────────────────────────► 4. Read the plan
                                              5. Minimum code → GREEN
                                              6. Types, lint, format
7. Review checklist ◄──────────────────────── (hand back)
8. Docs impact decision
```

### pipeline

```
Designer                   Test-Writer                 Verifier                      Implementer
(chapter, Phase 1)         (chapter, Phase 2)          (chapter, Phases 3+5)         (AGENTS.md, Phase 4)
──────────────────         ────────────────────        ───────────────────           ───────────────────
1. Analyze requirement
2. Fix signatures, write
   test-case inventory
   {f}.testplan.md ──────► 3. Transcribe tests,
                              one per inventory row
                           4. Verify RED ────────────► 5. Gate: tests vs inventory
                              ◄───── REJECTED(n) ─────    (2nd rejection → Designer's model)
                                                       6. APPROVED → write plan
                                                          {f}.md ──────────────────► 7. Read the plan
                                                                                     8. Minimum code → GREEN
                                                                                     9. Types, lint, format
                                                      10. Review checklist ◄──────── (hand back)
                                                          (Designer's model on triggers)
                                                      11. Docs impact decision
```

### autopilot

```
Operator ──► /fly {feature} — Phase 1: design interview (Designer, interactive)
             {f}.adr.md · branch from the base branch · issue → in progress · driver launched
                                 │  unattended from here — headless sessions chained by the driver
  ┌──────────────────────────────▼────────────────────────────────────────────┐
  │ 2 TestPlan Designer ──► {f}.testplan.md (DRAFT)                           │
  │ 3 TestPlan Reviewer ──► grants READY ············· reject → back to 2     │
  │ 4 Test Writer       ──► RED tests, testplan → RED                         │
  │ 5 Test Reviewer     ──► APPROVED ····· minor → 4 · structural → 2         │
  │ 6 Handoff Planner   ──► {f}.md (no Gate row yet)                          │
  │ 7 Plan Reviewer     ──► Gate: APPROVED ··········· reject → back to 6     │
  │ 8 Implementer       ──► minimum code → GREEN                              │
  │ 9 Final Reviewer    ──► DONE ········· minor → 8 · structural → 6         │
  │   caps, never reset in-flight: 2 rejections per gate · 6 backward edges   │
  └──────────────────────────────┬────────────────────────────────────────────┘
                                 ▼
             push · draft PR against the base branch · issue → in review · report
```

The intelligence stays in the verdicts, not the plumbing: reviewers emit routed verdicts (`{verdict, route, notes}`), and the **driver** — a deterministic script, `bin/autopilot-driver.sh` — dispatches, counts, and stops. Re-entry always passes the gate again: an amended artifact never skips its judge. One family designs and judges (phases 1, 3, 5, 7, 9), the other produces (2, 4, 6, 8) — no artifact is judged by the family that produced it. Before real work, every headless phase passes a **preflight**: read a driver-written nonce file and open the reply with its content — unforgeable proof its tools work, since the nonce is nowhere in the prompt (fail → 2 retries → the recorded substitution ladder → the operator). A stopped flight pushes nothing: state stays on disk, the dormant interview session presents the exact blocking point, and you amend, relaunch, or abort.

The artifacts in `.ai/plans/` are the **sole interfaces** between roles — if it's not in the artifact, the next role asks instead of guessing. Under the pipeline, run each phase in a **fresh session**: the Verifier judges the tests from the artifacts, not from the memory of having watched them being written.

Switching profiles never destroys another profile's artifacts (**extended inertness**): `{feature}.md` plans are readable everywhere, `{feature}.testplan.md` files go **inert** under two-role — never rewritten, moved, or deleted — and come back to life on the way back to a profile that reads them; artifacts from other eras are historical records, never retrofitted (no design-record backfill, no retroactive `Gate` stamps).

## Escalation (pipeline only)

The Verifier's model runs the gate and the review by default; the Designer's model is spent only where a weaker one would decide worse. Four triggers bring it back in (the full text lives in the pipeline chapter, `§ Escalation`):

1. **Architectural surface** — new pattern, first materialization of a layer, changed dependency direction → the Designer's model also runs the final review.
2. **Double gate rejection** — the same feature is rejected twice at the gate → the gate re-runs on the Designer's model.
3. **Post-review bug** — a defect surfaces after a passed review → the Designer's model runs the post-mortem.
4. **ADRs and `/init-architecture`** — always the Designer's model.

Two loops close the pipeline: a **gate bounce** (rejection sends the tests back to the Test-Writer with point-by-point notes), and a **review loop** (a logic issue found in review becomes new inventory rows and re-enters the pipeline as failing tests — never a hand-patched fix).

The two-role profile has **no escalation ladder** — its Architect already runs on the strongest tier in the roster, so there is no model to escalate to. The autopilot profile has none either, by a different logic: nothing in-flight ever escalates *upward* — a preflight failure walks **down** the recorded substitution ladder, and a cap stops the flight for the operator. The scarce tier appears only in the interview.

**With the Designer's tier substituted, the ladder has no top rung.** The triggers don't lapse, they become explicit calls: 1–3 fire as usual and run on the substitute, logged with the trigger number; 4 is the one to defer while the tier is out, since ADRs and `/init-architecture` propagate the furthest. And when the substitute happens to be the Verifier's own model, Design and gate collapse onto one model: the gate stops being verification against a reference *by a different model*, so an `APPROVED` reached that way carries less weight — the chapter says so, and the testplan Log records it.

---

## Getting started

**Prerequisites:** [Claude Code](https://www.anthropic.com/claude-code), and a project with a dependency manifest (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`, …).

```bash
# 1. In Claude Code, add the kit's marketplace and install the plugin (once per machine)
/plugin marketplace add weAreCoine/tdd-red-handoff
/plugin install tdd-red-handoff

# 2. From your project, in Claude Code (on the roster's top design tier — an escalation-tier task):
/init-architecture
```

`/init-architecture` first routes on what it finds — fresh project, re-init, or an older install (see below) — then walks: **inspect** the repo → **resolve** the decisions it can't derive (it asks you) → **scaffold** the files and wire the profile (line-1 import + `.ai/kit.json`) → **fill** them from real project facts → **self-check** → **report**. The only point that needs you is the decisions phase.

When it finishes you'll have `CLAUDE.md` (importing the chosen profile's chapter), `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`, and `.ai/kit.json` filled for your project, all three chapters in `.ai/process/` and the two per-feature templates in `.ai/templates/` (all committed — the process runs offline, without the plugin), with `.ai/plans/` ready for the first handoff.

> The commands live in the plugin, not in your repo — canonically namespaced (`/tdd-red-handoff:init-architecture`); the kit's docs use the short names. When a new kit version ships, update the plugin from the plugin manager (`/plugin`), then run `/update-kit` in each project: it realigns the installed chapters and per-feature templates and stamps `kit.json`'s `kitVersion`, never touching the docs you filled. Contributors can run a checkout directly with `claude --plugin-dir <path-to-checkout>`.

### Switching profiles

```bash
/switch-profile two-role      # or: pipeline · autopilot
```

Not sure which profile a project is on? `/show-profile` prints it — read-only: it checks the triad agrees and reports drift instead of guessing.

The switch is mechanical, offline, and lossless: all chapters are already installed, so it rewrites exactly **two things** — line 1 of `CLAUDE.md` and the `profile` field of `.ai/kit.json` — and touches nothing else. Two safeguards: when switching **to a profile with no role that continues an in-flight testplan** (today: two-role, and autopilot — a flight starts from a fresh interview and never adopts a half-done testplan), any testplan still **in flight** (`Status` of `DRAFT`, `READY`, `RED`, or `REJECTED(n)`) makes the command stop and ask for explicit confirmation — that's specification work the destination profile would orphan. And leaving autopilot while a driver reports a **running flight** refuses outright — stop or finish the flight first. Switching *to* pipeline never blocks: it revives inert testplans. Switching happens between tasks, so the refusals should be rare.

Flying a feature under autopilot, once the profile is active and the production-role roster rows are recorded:

```bash
/fly checkout-discounts
```

The command runs the design interview — a grill: one question at a time with a recommended answer, glossary and project ADRs maintained as decisions crystallise (it invokes your `grill-with-docs` skill when you have one, and carries an equivalent inline contract when you don't) — then writes the design record, cuts the branch, launches the driver in the background, and goes dormant until the report — or the stop — comes back.

### Migrating an older install

Don't re-init a project that already runs the kit: the filled facts are the expensive part. With the plugin installed, run the command that matches what the project has:

- **Profile-aware install from before the plugin** (`.ai/kit.json` present, `kitVersion: "TODO"`) → `/update-kit`: realigns the installed chapters and per-feature templates to the plugin's and stamps the real version. It also deletes the pre-plugin copies of the kit's commands from `.claude/commands/` — the plugin serves the commands now, and stale copies would shadow it.
- **Legacy two-role kit** (single "architect" role, no testplan, no gate, no `.ai/kit.json`) → `/init-architecture`, which routes to its migration appendix: every project fact is carried over **byte-identical**, the process text is replaced, the union `§ Model Roster` is added, and you decide per in-flight plan whether to grandfather it or have it re-enter through the gate.
- **Pre-profile pipeline install** (pipeline roles but no `.ai/kit.json`) → `/init-architecture`, re-init in place: the profile pieces (import line, `kit.json`) are added as part of the update.

---

## What the init asks you

Five things inspection can't settle, so the command stops and asks:

1. **Profile** — which process contract the first task runs on: **two-role**, **pipeline** or **autopilot**. All three chapters are installed either way; `/switch-profile` changes this per task later.
2. **Architecture model** — pick one, applied identically across all three files:
   - **A — Flat MVCS** · single app-wide MVC + Client/Service layer (the default)
   - **B — Domain-partitioned** · split by domain, each re-applying MVCS internally (larger systems)
   - **C — Other** · describe your structure and its dependency rules
3. **Deliberate exclusions** — libraries you're intentionally *not* installing, so they're marked `NOT INSTALLED` rather than silently omitted.
4. **API contract source** — which doc/spec is normative if one exists.
5. **Coverage floor** — the non-negotiable minimum (default 85%).

It recommends an option where it can, but it won't choose your architecture for you.

The `§ Model Roster` is **not** among the questions: it ships prefilled with the kit's defaults, and `/update-models-roster` changes it whenever a new model generation lands.

---

## Template markers

The templates carry their own filling instructions. Three markers, three lifecycles:

| Marker | Meaning | Survives in the finished file? |
|--------|---------|-------------------------------|
| `<!-- FILL: … -->` | Instruction to the filling agent | **No** — removed once satisfied |
| `[[DECISION: … ]]` | A choice to make at init | **No** — resolved to one branch |
| `TODO` | A value genuinely not yet decided | **Yes** — flags an open team decision |

`FILL` is *how to fill* (ephemeral). `TODO` is *not yet decided* (legitimate to keep). The init's self-check greps for surviving `FILL`/`DECISION` markers — `TODO`s are allowed and reported as open decisions.

The process chapters in `.ai/process/` are **not** templates: they carry no markers, state no project facts, and are never edited — at init or later. That's what makes the profile switch a one-line operation.

---

## Consistency rules the files share

`PROJECT_ARCHITECTURE.md` opens with a short **Contract** section the init must honor. These are the seams where the files can silently drift apart:

1. **Command names are an API.** Every command the process files reference (`test`, `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage`) has a matching row in the toolchain table, and the row's first cell carries the name **verbatim** — the contract name is the label, not a description of it. Rename one and you break the process contract.
2. **The layer map matches the architecture choice** (A/B/C), with real directory paths.
3. **One coverage floor, two files** — identical in `CLAUDE.md` and `PROJECT_ARCHITECTURE.md`, each on a fixed **Project floor** anchor line.
4. **Fixed layer vocabulary** — Model / View / Controller / Service / Client, verbatim, everywhere.
5. **Secrets boundary is absolute** — no provider keys or credentials in frontend source, env, or bundle.
6. **Model names live only in the roster** — every other file refers to models by role ("the Designer's model"); `/update-models-roster` edits the roster and greps for leaked names. A temporarily unavailable tier is recorded as a **substitution line** beside the table, never by overwriting a `Current model` cell — the cell is the tier the project wants, the line is what's running instead.

And one rule the profiles add: the **profile triad** — `.ai/kit.json` `profile`, the `CLAUDE.md` line-1 import, and the chapter filename must name the same profile. `/switch-profile` is the only procedure that changes it.

> These are enforced mechanically: `bin/verify-kit.sh` (also wrapped as `/verify-kit`) checks the greppable invariants — including the triad and the confinement of phase numbers to the chapters — and reports three states: PASS, FAIL, and **NOT CHECKED** for what a grep cannot decide (the layer map matching the real tree, vocabulary used *correctly*, the secrets boundary being *true*). Green means the mechanical checks pass, not that everything is verified. The script ships inside the plugin, and `/verify-kit` runs it from there — no kit-repo checkout needed in a target project. With `-p <plugin-root>` (the plugin commands pass `${CLAUDE_PLUGIN_ROOT}`) target mode also verifies **install integrity**: the five installed kit files byte-identical to the plugin's copies, and the `kitVersion` stamp equal to the plugin's version — so `/init-architecture`, `/switch-profile` and `/update-kit` end on a check that compares the install against the payload that produced it. Without `-p` those checks are listed under NOT CHECKED.

---

## Layout

```
.ai/
  process/
    two-role.md                   # Architect + Implementer — roles & phases, ships verbatim
    pipeline.md                   # Designer / Test-Writer / Verifier + Implementer — ships verbatim
    autopilot.md                  # the unattended nine-phase flight — ships verbatim (ADR-0008)
  templates/
    CLAUDE.template.md            # the shell: line-1 profile import + shared sections + overlay
    AGENTS.template.md
    PROJECT_ARCHITECTURE.template.md
    test_plan_template.md         # design side → transcription (test-case inventory, gated profiles)
    plan_template.md              # design side → Implementer (implementation plan, every profile)
  plans/                          # per-feature artifacts land here
.claude-plugin/
  plugin.json                     # name + version — the authoritative kit version (ADR-0005)
  marketplace.json                # the repo is its own plugin marketplace (ADR-0004)
commands/                         # served by the plugin — never installed into targets
  fly.md                          # <feature> — autopilot phase 1: the interview, then launch the driver
  init-architecture.md            # bootstrap; absorbs the legacy-kit migration as its appendix
  show-profile.md                 # read-only — print the active profile from the triad
  switch-profile.md               # <two-role|pipeline|autopilot> — rewrites the import line + kit.json
  update-kit.md                   # realign installed chapters/templates to the plugin version
  update-models-roster.md         # record a model change in the roster (the only concrete-name location)
  verify-kit.md                   # run bin/verify-kit.sh and report its three-state output
bin/
  verify-kit.sh                   # the kit's mechanical invariant check (kit-repo + target modes;
                                  # -p <plugin-root> adds the install-integrity checks)
  autopilot-driver.sh             # the flight driver: dispatch, preflight, counters, git/PR ribbon
```

---

## One measured run (2026-08-11) — field notes, not statistics

Both profiles ran the **same frozen feature request** once each — a dashboard weather
card deliberately isomorphic to a card precedent already in the repo — in twin worktrees
of the same Laravel app, same Implementer CLI, phases driven by frozen prompts. Method,
raw data and the full comparison: `docs/design/bench/` (`protocol.md`, `results.md`).

**Read the limits before the numbers.** This is one run on one task: it shows the shape
of the profiles' overhead, not averages. The task's isomorphy to an existing precedent
is what makes the runs comparable — and also caps how much design-quality difference
*could* have shown. Both runs happened to hit the no-rework path (the gate approved
first pass), so the pipeline paid its coordination overhead without ever exercising the
thing the gate exists for — rejecting a bad testplan before implementation is where it
would earn its cost back. The Test-Writer tier was measured at introductory pricing.
Nothing below generalizes beyond "this is what one clean run costs".

Cost (USD) and active time by bucket:

| Bucket | two-role | pipeline | Δ cost |
|---|---:|---:|---:|
| Design | 3.66 · 4m05s | 6.07 · 9m36s | +66% |
| Tests | 3.76 · 6m25s | 2.70 · 7m39s | −28% |
| Plan/Gate | 1.84 · 2m33s | 5.28 · 10m23s | +187% |
| Implementation | 3.11 · 8m50s | 3.05 · 8m23s | −2% |
| Review | 3.69 · 3m14s | 3.45 · 6m19s | −7% |
| **Total** | **16.06 · 25m07s** | **20.55 · 42m20s** | **+28%** |

Token consumption by model — rows name roles; the *Default models* table above resolves
them (token counts cross-checked to the unit against an independent accounting tool):

| Run | Model (by role) | input | output | cache read | cache write | Cost USD |
|---|---|---:|---:|---:|---:|---:|
| two-role | Architect's (all four phases) | 135 | 74.6k | 3,696k | 276k | 12.95 |
| two-role | Implementer CLI | 3,536k¹ | 15.0k | — | — | 3.11 |
| pipeline | Designer's (Design only) | 16 | 46.5k | 831k | 146k | 6.07 |
| pipeline | Test-Writer's | 70 | 35.6k | 4,314k | 129k | 1.73 |
| pipeline | Verifier's (Gate+Plan, Review, advisor calls²) | 573k | 82.5k | 4,135k | 271k | 9.70 |
| pipeline | Implementer CLI | 3,381k¹ | 17.1k | — | — | 3.05 |

¹ The CLI's log folds cached reads into `input`.
² Harness-billed advisor iterations inside the Test-Writer's session run on the
  Verifier's tier and are counted there.

The row to read: the top design tier goes from $12.95 / ~4.0M processed tokens
(two-role, where it carries everything) to $6.07 / ~1.0M (pipeline, Design only).

What the one run showed, in decreasing confidence:

- **The top-tier saving is real and large.** Under two-role the Architect's model
  carries everything: $12.95 and ~4.0M processed tokens. Under pipeline the same tier
  does only Design: $6.07 and ~1.0M — **−53% cost, −75% token throughput** on the tier
  with the least availability. That is the pipeline's core trade delivered as designed.
- **Where the saving lands matters.** It shifts almost 1:1 onto the Verifier's tier
  (≈$9.70), not onto the cheap Test-Writer tier ($1.73). This placement is deliberate
  and, per our experience, sound: the Verifier executes a written gate checklist against
  a written testplan — a role for a model that performs when told exactly what to do,
  not one asked to design in the open.
- **The overhead concentrates in Plan/Gate** (+187%): a fresh Verifier session re-reads
  testplan, tests and repo cold, where the Architect issues the plan from a warm
  session. Same-session cache reuse is the two-role profile's structural advantage; the
  pipeline's serialization of everything into artifacts is what its role isolation costs.
- **The cheap-tier saving is smaller than it looks**: a third of the pipeline's Tests
  bucket was advisor iterations the harness itself billed on a stronger tier, and the
  rest rides introductory pricing.

Both implementations shipped green (115/115 vs 108/108 tests) and converged to
near-identical code — same layering, same caching flow, UI markup identical to the CSS
class — confirming that the shared precedent plus `PROJECT_ARCHITECTURE.md` do most of
the design steering in either profile. The differences that remain are process
signatures, worth knowing when choosing a profile:

- **Initiative lives only on the design side of the wall.** The Architect wrote 25
  tests, two beyond its own analysis — including a cross-card independence test the
  pipeline run lacks. The Test-Writer transcribed the testplan's 23 rows exactly, 1:1:
  under pipeline, a test the Designer didn't inventory doesn't exist.
- **The testplan's rigor cuts the other way too**: its inventory caught a
  negative-zero rendering edge the Architect's run missed. Externalizing every case
  into a reviewed artifact is slower and costs more Design output — and catches more.
- **The profile does not decide semantics.** Facing the same ambiguous sentence in the
  frozen request, the two runs shipped two defensible contracts (partial upstream data
  tolerated and windowed vs. rejected as malformed). Neither process surfaced the
  ambiguity to the human; that remains model judgment, in both profiles.

---

## Possible extensions (not implemented)

- **A broad-evaluation reviewer.** A large-context model (e.g. Gemini) could do whole-repo sanity passes that complement the Verifier's focused, checklist-driven review. Deliberately left out — the per-feature review has been enough in practice so far. Add it if your projects grow past what a focused review comfortably covers.
- **A CI verification gate.** `bin/verify-kit.sh` already enforces the mechanical invariants on demand; wiring it into CI so every commit runs it is the missing piece.

---

## License

MIT — see [`LICENSE`](LICENSE).

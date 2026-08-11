---
description: Bootstrap (or migrate) the architecture-doc system for this project — inspect the repo, choose the profile, resolve the architecture decisions with the user, fill the templates, write kit.json, self-check.
---

# /init-architecture

Bootstrap the architecture-doc system for **this** repository from the templates and process
chapters the plugin ships (`${CLAUDE_PLUGIN_ROOT}/.ai/templates/`,
`${CLAUDE_PLUGIN_ROOT}/.ai/process/`). Work the phases **in order** —
later ones depend on earlier output. Projects on the legacy two-role kit are migrated in place:
Phase 0 routes them to the **Appendix — legacy-kit migration**.

> **Model check first.** This command is an escalation-tier task: it must run on the roster's
> **top design tier** — the Designer's row (the Architect's row is the same tier by default).
> Resolve it from the live `.ai/PROJECT_ARCHITECTURE.md § Model Roster` if it exists (re-init),
> otherwise from the prefilled roster the plugin ships in
> `${CLAUDE_PLUGIN_ROOT}/.ai/templates/PROJECT_ARCHITECTURE.template.md` — pre-init the target
> has no `.ai/` yet, so a project-relative path would resolve to nothing. If the session is on
> another model, tell the user and stop before Phase 0.

The templates carry their own instructions as markers. Treat them as binding:

- `<!-- FILL: … -->` — an instruction to you. Satisfy it, then **delete the comment**. None may survive.
- `[[DECISION: … ]]` — a choice to resolve at init (e.g. architecture A/B/C). Resolve to one branch,
  delete the others. None may survive.
- `TODO` — a value genuinely not yet decided. It **may** survive: it flags an open decision to the team.
  Use it only where the fact truly isn't settled — never as a substitute for reading it.

The process chapters in `.ai/process/` are **not** templates: they carry no markers, state no
project facts, and are never edited — here or later.

## Phase 0 — Preconditions & routing

- Check the plugin's payload: `${CLAUDE_PLUGIN_ROOT}/.ai/templates/` has `CLAUDE.template.md`,
  `AGENTS.template.md`, `PROJECT_ARCHITECTURE.template.md`, `plan_template.md`,
  `test_plan_template.md`, and `${CLAUDE_PLUGIN_ROOT}/.ai/process/` has **both** `two-role.md`
  and `pipeline.md`. If any is missing the installation is broken: STOP and tell the user to
  reinstall the plugin.
- Route on the live docs (`CLAUDE.md`, `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`):
  - **None exist** → fresh init: continue with Phase 1.
  - **They exist and `.ai/kit.json` exists** → re-init: ask whether to update in place or abort.
    **Never overwrite a filled file blindly.** (If the goal is only to pick up a newer kit
    version, `/update-kit` is the lighter path — it never touches the live docs.)
  - **They exist, no `.ai/kit.json`, and `CLAUDE.md` contains `You are the **architect**`** →
    legacy two-role kit: go to the **Appendix** (facts survive, process is replaced).
  - **They exist, no `.ai/kit.json`, and `CLAUDE.md` describes the pipeline roles** →
    pre-profile pipeline install: treat as re-init, and add the profile pieces (import line,
    `kit.json`) as part of the update.

## Phase 1 — Inspect (read-only; write nothing yet)

Gather the facts the templates demand. Do not guess — read:

- **Manifest + lockfile** (`package.json`/`composer.json`/`pyproject.toml`/`go.mod` + lock): real
  dependency names and **exact installed versions**. Note declared-vs-installed.
- **Scripts**: the real command strings for test, build, lint, typecheck, format, coverage.
- **Source tree** (`src/` or equivalent): flat, or already partitioned by domain/feature? This informs
  the architecture decision.
- **Backend/API docs** if present (consumer docs, OpenAPI): the API Contract codes against these.
- **Config**: import aliases, test-runner config, env-var conventions.

Summarize what you found before moving on. If a critical fact is unreadable (no lockfile, no scripts),
say so — that section gets an honest `TODO`, not a fabricated value.

## Phase 2 — Resolve decisions (INTERACTIVE — the only human gate)

Present the choices that inspection **cannot** settle, and wait for the user. Do not pick for them.

1. **Profile** — which process contract the first task runs on:
   **two-role** (Architect + Implementer: one top-tier design role, fewest sessions) ·
   **pipeline** (Designer / Test-Writer / Verifier + Implementer: tiered cost, gate between
   tests and implementation). Both chapters are installed either way, and `/switch-profile`
   changes this per task later — this only sets the starting value.
2. **Architecture model** — the `[[DECISION A/B/C]]` shared by CLAUDE.md and AGENTS.md:
   **A** flat MVCS · **B** domain-partitioned (MVCS within each domain) · **C** other.
   Recommend one from the Phase-1 tree shape, but let the user decide. **Apply the same choice
   identically in CLAUDE.md, AGENTS.md, and the PROJECT_ARCHITECTURE layer map.** If their choice fights
   the repo shape you observed, say so before accepting it.
3. **Deliberate exclusions** — libraries intentionally *not* installed, so the Stack table marks them
   `NOT INSTALLED` rather than omitting them.
4. **API Contract normative source** — which doc/spec wins on conflict, if one exists.
5. **Coverage floor** — confirm the project floor (default 85%). It goes **identically** onto the
   two anchors: the **Project floor** row in CLAUDE.md § Coverage Targets and the
   **Project floor:** line in PROJECT_ARCHITECTURE § Testing.

## Phase 3 — Scaffold

Install the kit files and instantiate the doc templates (edit the copies, never the plugin's
own files):

```bash
mkdir -p .ai/plans .ai/process .ai/templates
# process chapters + per-feature templates: installed into the project (committed),
# so switching profile and writing plans work offline, without the plugin
cp "${CLAUDE_PLUGIN_ROOT}"/.ai/process/two-role.md "${CLAUDE_PLUGIN_ROOT}"/.ai/process/pipeline.md .ai/process/
cp "${CLAUDE_PLUGIN_ROOT}"/.ai/templates/plan_template.md "${CLAUDE_PLUGIN_ROOT}"/.ai/templates/test_plan_template.md .ai/templates/
# doc templates: instantiated, not installed — their filled copies BECOME the live docs
cp "${CLAUDE_PLUGIN_ROOT}"/.ai/templates/CLAUDE.template.md               ./CLAUDE.md
cp "${CLAUDE_PLUGIN_ROOT}"/.ai/templates/AGENTS.template.md               ./AGENTS.md
cp "${CLAUDE_PLUGIN_ROOT}"/.ai/templates/PROJECT_ARCHITECTURE.template.md ./.ai/PROJECT_ARCHITECTURE.md
```

Then wire the profile:

1. In `CLAUDE.md`, replace the FILL comment at the top so that **line 1** is the import for the
   Phase-2 profile: `@.ai/process/two-role.md` or `@.ai/process/pipeline.md`. Nothing above it.
2. Write `.ai/kit.json`:
   ```json
   { "profile": "<two-role|pipeline>", "kitVersion": "<version>" }
   ```
   `<version>` is read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` — the
   authoritative kit version (ADR-0005). Never invent the number; `/update-kit` restamps it on
   later kit updates.
3. If `.claude/commands/` contains pre-plugin copies of the kit's own commands —
   `init-architecture.md`, `migrate-architecture.md`, `switch-profile.md`, `update-kit.md`,
   `update-models-roster.md`, `verify-kit.md` — delete them: the plugin serves the commands
   now, and stale copies would shadow it. Touch nothing else in `.claude/`.

`plan_template.md` and `test_plan_template.md` are the only templates **installed** into the
project's `.ai/templates/` — the roles reference them per feature at runtime. The three doc
templates are not installed: their filled copies are the live docs.

## Phase 4 — Fill (the work)

Edit the **live** files (never the templates, never `.ai/process/`). Section by section, replace
`FILL` / `[[DECISION]]` / `TODO` with real facts from Phases 1–2, deleting each `FILL` block once
satisfied. Hold these invariants as you go — they're the consistency rules the files depend on:

1. **Command names are an API.** Every command the process files reference by name — `test`,
   `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage` — has a row in
   § Toolchain whose **first cell is the contract name verbatim** (never a human relabel like
   "Type-check"), with the real command string.
2. **Layer map matches the architecture choice** from Phase 2, with real paths. Mark not-yet-existing
   layers `(future) <path>`.
3. **One coverage floor, two files, two anchors** — the CLAUDE.md **Project floor** row and the
   PROJECT_ARCHITECTURE **Project floor:** line carry the identical number.
4. **Layer vocabulary verbatim** — Model / View / Controller / Service / Client across all three files;
   no synonyms.
5. **Secrets boundary asserted** — § Auth & Secrets states the no-secret-in-frontend rule concretely.
6. **The profile triad agrees** — `.ai/kit.json` `profile`, the `CLAUDE.md` line-1 import, and the
   chapter filename name the same profile. Only `/switch-profile` changes them afterwards.

Inherited rules worth restating (this is where agents slip):
- **Versions come from the lockfile, never memory.** Undecided version → `TODO`, not a plausible guess.
- **`NOT INSTALLED` is a valid, useful Status** — it tells the implementer not to import it yet.
- **Runtime Wiring is the highest-risk section**: name the construct actually used AND the tempting-wrong
  default to avoid. Paste the real adapter/handler signature once it exists.
- **Keep the PROJECT_ARCHITECTURE "Contract" section in place** — it's a live guard, not scaffolding.
- **§ Model Roster keeps its prefilled kit defaults** — the union of both profiles' roles; don't
  blank them into `TODO`s and don't ask; changing them later is `/update-models-roster`'s job.

## Phase 5 — Self-check

Run these; the greps must return **nothing**:

```bash
grep -nE 'FILL:|\[\[DECISION' CLAUDE.md AGENTS.md .ai/PROJECT_ARCHITECTURE.md
grep -nE 'Phase(s)? [0-9]' CLAUDE.md      # the shell stays number-free; numbers live in the chapter
head -n 1 CLAUDE.md                        # must print the import matching .ai/kit.json "profile"
```

Any hit = an unresolved marker or a leak. Fix it and re-run. Then eyeball the six invariants above —
especially that the two floor anchors match and every contract name sits verbatim in a Toolchain
first cell. Surviving `TODO`s are fine; report them as open decisions. For the full mechanical
pass run the script the plugin ships — `"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" .` — which
reports all of this as PASS/FAIL/NOT CHECKED.

## Phase 6 — Report

Tell the user:
- The active profile, and that `/switch-profile <other>` changes it per task.
- The architecture model set (A/B/C) and where it's reflected.
- Any `TODO`s left open, with why (deferred decision vs unreadable fact).
- That `.ai/plans/` is ready and work can start per the active chapter's roles
  (models: `PROJECT_ARCHITECTURE.md § Model Roster`).

---

## Appendix — legacy-kit migration (absorbed from the old /migrate-architecture)

Entered from Phase 0 when live docs exist, `.ai/kit.json` does not, and `CLAUDE.md` contains
`You are the **architect**`. The rule of the whole path: **facts survive byte-identical, process
text is replaced.** If a fact changes during migration, that is a bug, not an improvement.
Require a clean working tree and recommend a dedicated branch — one reviewable diff.

- **M1 — Inventory (read-only).** List every fact section in the live docs: `CLAUDE.md`
  § Architecture (resolved A/B/C branch), § Non-Obvious Traps, § What NOT to Test exclusions,
  § Coverage Targets (record the floor explicitly), § Conventions, § Reference doc sources;
  `AGENTS.md` § Code Conventions, § Layered Architecture branch, § Non-Obvious Traps, § Reference;
  any user-added heading with no template counterpart (carry it verbatim — it exists because
  someone needed it). Classify `.ai/plans/*.md`: **done** vs **in-flight** (old-format plans have
  no sibling testplan and no `Gate:` row). Then run Phases 1–2 above (inspection may be light —
  the facts exist; the **profile question is mandatory**).
- **M2 — Rebuild `CLAUDE.md`.** Run the Phase 3 install block first (chapters + per-feature
  templates into `.ai/` — a legacy target has no `.ai/process/`). Then replace `CLAUDE.md` with
  the shell template, set the line-1 import for the chosen profile, and graft each M1 fact
  section into its overlay counterpart, resolving that section's markers exactly as the old file
  had — verbatim, not paraphrased. Grafted content that cites phases by number switches to phase
  names (the shell is number-free).
- **M3 — `AGENTS.md` / `.ai/PROJECT_ARCHITECTURE.md` (targeted edits, from the plugin's current
  templates, not from memory).** AGENTS: neutral counterpart header, the conditional `Gate:` qualifier in
  Step 1, "the design side's principle" in § Layered Architecture. PROJECT_ARCHITECTURE: neutral
  header; Contract references by phase name; insert the union § Model Roster (prefilled defaults)
  and Contract §6; relabel the § Toolchain first cells to the **contract names verbatim**
  (this clears the drift the old kit allowed); add the `**Project floor:**` anchor line in
  § Testing with the M1 floor.
- **M4 — In-flight plans (INTERACTIVE).** Never silently rewrite a plan. Under **two-role**, old
  plans are already the native shape — no action. Under **pipeline**, per in-flight feature ask:
  **(a) grandfather** (implementer proceeds on the old plan; no gate guarantee — recommend when
  implementation is underway) or **(b) re-enter** (Designer retro-writes the testplan, Verifier
  gates it — recommend when tests exist but implementation hasn't started). The user decides.
- **M5 — Wire and check.** Write `.ai/kit.json` and delete stale pre-plugin command copies
  (Phase 3 steps 2–3), then run Phase 5 in full, plus:
  `grep -nwiE 'architect' CLAUDE.md AGENTS.md .ai/PROJECT_ARCHITECTURE.md` must be empty (the
  Architect role name lives in the roster and the two-role chapter, not in hand-written live
  text), and diff every fact against the M1 inventory — byte-identical, floor included. Report
  per M1/M4: what was carried, what was replaced, the plan decision log.

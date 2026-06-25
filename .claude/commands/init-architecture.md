---
description: Bootstrap CLAUDE.md / AGENTS.md / PROJECT_ARCHITECTURE.md for this project — inspect the repo, resolve the architecture decisions with the user, fill the templates, self-check.
---

# /init-architecture

Bootstrap the three-file architecture-doc system for **this** repository from the templates in
`.ai/templates/`. Work the phases **in order** — later ones depend on earlier output.

The templates carry their own instructions as markers. Treat them as binding:

- `<!-- FILL: … -->` — an instruction to you. Satisfy it, then **delete the comment**. None may survive.
- `[[DECISION: … ]]` — a choice to resolve at init (e.g. architecture A/B/C). Resolve to one branch,
  delete the others. None may survive.
- `TODO` — a value genuinely not yet decided. It **may** survive: it flags an open decision to the team.
  Use it only where the fact truly isn't settled — never as a substitute for reading it.

## Phase 0 — Preconditions

- Check `.ai/templates/` has `CLAUDE.template.md`, `AGENTS.template.md`,
  `PROJECT_ARCHITECTURE.template.md`, `plan_template.md`. If any is missing, STOP and tell the user.
- Check the live docs don't already exist (`CLAUDE.md`, `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`).
  If they do, this is a re-init: ask whether to update in place or abort. **Never overwrite a filled file
  blindly.**

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

1. **Architecture model** — the `[[DECISION A/B/C]]` shared by CLAUDE.md and AGENTS.md:
   **A** flat MVCS · **B** domain-partitioned (MVCS within each domain) · **C** other.
   Recommend one from the Phase-1 tree shape, but let the user decide. **Apply the same choice
   identically in CLAUDE.md, AGENTS.md, and the PROJECT_ARCHITECTURE layer map.** If their choice fights
   the repo shape you observed, say so before accepting it.
2. **Deliberate exclusions** — libraries intentionally *not* installed, so the Stack table marks them
   `NOT INSTALLED` rather than omitting them.
3. **API Contract normative source** — which doc/spec wins on conflict, if one exists.
4. **Coverage floor** — confirm the project floor (default 85%). It goes **identically** into CLAUDE.md
   § Coverage Targets and PROJECT_ARCHITECTURE § Toolchain / § Testing.

## Phase 3 — Scaffold

Copy the templates to their live locations (do **not** edit the templates themselves):

```bash
mkdir -p .ai/plans
cp .ai/templates/CLAUDE.template.md            ./CLAUDE.md
cp .ai/templates/AGENTS.template.md            ./AGENTS.md
cp .ai/templates/PROJECT_ARCHITECTURE.template.md ./.ai/PROJECT_ARCHITECTURE.md
```

`plan_template.md` stays in `.ai/templates/` — it's referenced there, not copied to root.

## Phase 4 — Fill (the work)

Edit the **live** files (never the templates). Section by section, replace `FILL` / `[[DECISION]]` /
`TODO` with real facts from Phases 1–2, deleting each `FILL` block once satisfied. Hold these invariants
as you go — they're the consistency rules the three files depend on:

1. **Command names are an API.** Every command CLAUDE/AGENTS reference by name — `test`, `test (focused)`,
   `typecheck`, `lint`, `format`, `format:check`, `coverage` — has a row in § Toolchain with the real
   command. Don't rename them.
2. **Layer map matches the architecture choice** from Phase 2, with real paths. Mark not-yet-existing
   layers `(future) <path>`.
3. **One coverage floor, two files** — identical in CLAUDE.md and PROJECT_ARCHITECTURE.md.
4. **Layer vocabulary verbatim** — Model / View / Controller / Service / Client across all three files;
   no synonyms.
5. **Secrets boundary asserted** — § Auth & Secrets states the no-secret-in-frontend rule concretely.

Inherited rules worth restating (this is where agents slip):
- **Versions come from the lockfile, never memory.** Undecided version → `TODO`, not a plausible guess.
- **`NOT INSTALLED` is a valid, useful Status** — it tells the implementer not to import it yet.
- **Runtime Wiring is the highest-risk section**: name the construct actually used AND the tempting-wrong
  default to avoid. Paste the real adapter/handler signature once it exists.
- **Keep the PROJECT_ARCHITECTURE "Contract" section in place** — it's a live guard, not scaffolding.

## Phase 5 — Self-check

Run this grep. It must return **nothing**:

```bash
grep -nE 'FILL:|\[\[DECISION' CLAUDE.md AGENTS.md .ai/PROJECT_ARCHITECTURE.md
```

Any hit = an unresolved marker. Fix it and re-run. Then eyeball the five invariants above — especially
that the coverage floor matches and every referenced command name has a Toolchain row. Surviving `TODO`s
are fine; report them as open decisions.

## Phase 6 — Report

Tell the user:
- The architecture model set (A/B/C) and where it's reflected.
- Any `TODO`s left open, with why (deferred decision vs unreadable fact).
- That `.ai/plans/` is ready and the architect/implementer TDD loop can start.

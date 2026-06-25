# PROJECT_ARCHITECTURE.md

> Project-specific facts. The agnostic *process* contract lives in `CLAUDE.md` (architect) and `AGENTS.md` (implementer).
> This file is the single source of truth for everything those two files deliberately refuse to guess:
> stack versions, commands, API contract, runtime wiring, directory map.

<!-- =============================================================
     THIS IS A TEMPLATE. You (the filling agent) turn it into the real
     PROJECT_ARCHITECTURE.md for one concrete project.

     CONVENTIONS:
       <!-- FILL: ... -->   instruction TO YOU. Obey it, then DELETE the
                            comment. No <!-- FILL --> may survive in the
                            finished file.
       TODO                 a value not yet decided. It MAY survive — it
                            signals an open decision to the team — but only
                            where the fact genuinely isn't settled yet.
       Plain text / tables  STRUCTURE. Keep it. Fill rows, don't redraw
                            schemas. Table header columns are fixed.

     WHEN DONE, verify nothing template-only is left:
       grep -nE 'FILL:|\[\[' PROJECT_ARCHITECTURE.md   # must be empty
       grep -n 'TODO' PROJECT_ARCHITECTURE.md          # only genuine open decisions
     ============================================================= -->

## Contract with CLAUDE.md / AGENTS.md — DO NOT VIOLATE

<!-- FILL: this section is the set of cross-file invariants. Read it, enforce it
     while filling the rest, then LEAVE IT IN PLACE (it stays — it's not scaffolding,
     it's a live guard). Verify each invariant holds before declaring the file done. -->

1. **Command names are an API.** `CLAUDE.md` Phase 4 and `AGENTS.md` Steps 3–4 reference toolchain commands **by name**:
   `test`, `test (focused)`, `typecheck`, `lint`, `format`, `format:check`, `coverage`. The § Toolchain table below
   MUST define every one of these names. If you rename one, you break the process contract. If a tool genuinely
   doesn't exist for this stack, keep the row and mark it `TODO` / `N/A` with a reason — never silently drop it.
2. **The structural model must match CLAUDE.md.** § Conventions (Layering) below realizes the architecture decision
   `[[DECISION A/B/C]]` taken in `CLAUDE.md § Architecture`. The layer→directory map must reflect the **same** chosen
   branch (flat MVCS / domain-partitioned / other). A divergence here silently misroutes every file the implementer
   creates.
3. **Coverage floor appears once, here, and matches CLAUDE.md.** The floor in § Toolchain (coverage row) and § Testing
   MUST equal the "Project floor" in `CLAUDE.md § Coverage Targets`. One number, two files — keep them identical.
4. **Layer names are fixed vocabulary.** Model / View / Controller(orchestration) / Service / Client are used verbatim
   across all three files. Don't introduce synonyms here ("presenter", "gateway", "repository") without updating the
   other two — prefer not to.
5. **Secrets boundary is absolute.** § Auth & Secrets must restate the no-secret-in-frontend rule; it is asserted in
   both `CLAUDE.md` and `AGENTS.md` and cannot be relaxed by a project fact.

## Overview

<!-- FILL: 3–6 bullets establishing what this project IS, before any version detail.
     Required points to cover (drop any that don't apply, add none that aren't architectural):
       - app type / shape (SPA, API, monolith, CLI, worker…) and what it consumes/serves
       - the primary UI / domain library, if one defines the project, with a one-line "why headless/why this"
       - the secrets/trust boundary in one sentence (who holds credentials, what proxies through what)
     Keep it factual. No roadmap, no sales copy. -->

- **Type:** TODO
- **Primary library / framework:** TODO
- **Secrets boundary:** TODO

## Stack

<!-- FILL: one row per real dependency, pinned from the manifest (package.json / composer.json /
     pyproject / go.mod — whatever this stack uses). Rules:
       - "Version" is copied from the lockfile/manifest, not remembered. If not installed, leave Version=TODO.
       - "Status" is one of: installed | NOT INSTALLED | TODO(decide). Be honest — "NOT INSTALLED"
         is a valid, useful state and tells the implementer not to import it yet.
       - Pin EXACT (no caret) any library whose API drifts across minors, and say so in Status.
       - Do not invent versions to look complete. An empty Version with Status=TODO is correct when undecided.
     Keep the four columns. Add rows; don't add columns. -->

Pinned from the manifest:

| Concern         | Choice | Version | Status |
|-----------------|--------|---------|--------|
| Build tool      | TODO   | TODO    | TODO   |
| Language        | TODO   | TODO    | TODO   |
| UI framework    | TODO   | TODO    | TODO   |
| Lint            | TODO   | TODO    | TODO   |
| Formatter       | TODO   | TODO    | TODO   |
| Schema/validation | TODO | TODO    | TODO   |
| Test runner     | TODO   | TODO    | TODO   |
| State (server)  | TODO   | TODO    | TODO   |
| State (client)  | TODO   | TODO    | TODO   |
| Package manager | TODO   | —       | —      |

<!-- FILL: if a non-obvious install/exclusion decision was made (e.g. a styling lib deliberately
     NOT installed, a test env opted-in per-file rather than globally), write ONE note here in prose
     explaining the choice and pointing to the ADR that records it. Delete this block if no such
     decision exists yet. -->

## Toolchain

<!-- FILL: this table is referenced BY NAME from CLAUDE.md / AGENTS.md (see Contract §1).
     Every contract command MUST have a row. Fill the real command string for this stack
     (npm/pnpm/yarn/bun/composer/uv/go…). Status: ✅ if the script exists, TODO if not yet wired.
     Keep the three columns. The "focused test" form is what the TDD RED loop uses — make sure it
     accepts a pattern/path argument. -->

> `CLAUDE.md` and `AGENTS.md` reference this section by name. Keep command names exact (Contract §1).

| Action          | Command | Status |
|-----------------|---------|--------|
| Install         | TODO    | TODO   |
| Dev server      | TODO    | TODO   |
| Build           | TODO    | TODO   |
| Lint            | TODO    | TODO   |
| Type-check      | TODO    | TODO   |
| Test (all)      | TODO    | TODO   |
| Test (focused)  | TODO    | TODO   |
| Test (watch)    | TODO    | TODO   |
| Coverage        | TODO    | TODO   |
| Format          | TODO    | TODO   |
| Format (check)  | TODO    | TODO   |

<!-- FILL: note any scope caveat that affects how a command behaves — e.g. formatter ignores docs,
     coverage excludes scaffold files, focused-test filters by path substring. One line each.
     These prevent the implementer from misreading a green/clean result. Delete if none. -->

## Open Follow-ups (deferred — don't forget)

<!-- FILL: toolchain/testing/infra gaps left open ON PURPOSE. Each entry: what's missing, why it's
     deferred, and what resolving it will touch. This is where a TODO from the tables above gets its
     explanation so it doesn't get lost. Mark resolved items ✅ inline rather than deleting — the
     history is useful. Delete the placeholder bullet once real ones exist. -->

- TODO — none yet recorded.

## Runtime Wiring (CRITICAL)

<!-- FILL: how the app is actually wired at runtime — the single most error-prone, least-greppable
     fact in the project. This is the "silent failure" zone flagged in § Non-Obvious Traps.
     Cover, in prose + a code/signature block:
       - the runtime/entrypoint construct actually used, and the WRONG-but-tempting default to avoid
         (state it explicitly as "DO NOT use X" — the trap is usually choosing the obvious default)
       - which layer the orchestration construct fulfils (Controller role) and what it must NOT hold
         (transport, domain logic) — must agree with § Conventions
       - any order-sensitive / hand-rolled protocol (stream/SSE/event mapping), with the event vocabulary
       - the exact adapter/handler signature, pasted verbatim once it exists, so the implementer copies it
     If a decision here was contested, record it as an ADR and link it.
     Delete this whole section ONLY if the project has no non-trivial runtime wiring (rare). -->

> The single most error-prone fact in the project. Get this wrong and it fails silently.

- **DO use:** TODO
- **DO NOT use:** TODO — and why it's tempting but wrong.
- **Order-sensitive protocol (if any):** TODO

```
TODO: paste the actual adapter/handler signature + mapping contract here once it
exists, so the implementer follows it verbatim instead of reconstructing it.
```

## API Contract

<!-- FILL: the backend contract the client codes against. The implementer branches on this, so be
     precise and machine-followable. Cover only what applies:
       - normative source (hand-written consumer docs? OpenAPI URL?) and which wins on conflict
       - base URL + the env var that carries it (must be a NON-secret, framework-public-prefixed var)
       - auth scheme: token type, required headers, expiry/revocation model, the re-auth trigger
       - primary endpoints: method + path + request/response shape, one line each
       - streaming event schema IF streaming: every event, which are terminal, what a dropped stream means,
         whether the vocabulary is open (ignore-unknown) or closed
       - error shape: the stable machine field to branch on (a `code`, NOT a human `message`) + the code list
         with HTTP statuses
       - success/collection envelope + pagination shape
       - tool-call protocol or explicit N/A
     Branch on STABLE codes, never on prose messages — state that rule here. -->

> **Normative source:** TODO (which doc/spec wins on conflict).

- **Base URL / env var:** TODO (non-secret, public-prefixed var).
- **Auth:** TODO (scheme, required headers, expiry/revocation, re-auth trigger).
- **Primary endpoints:** TODO.
- **Streaming event schema (if any, order-sensitive):** TODO — list events, mark terminal ones, define dropped-stream behavior, state whether vocabulary is open.
- **Error shape:** TODO — `{ ... }`; branch on the **stable code**, never the message. Codes: TODO.
- **Success / collection envelope:** TODO (wrapper key, pagination params).
- **Tool-call protocol:** TODO or **N/A**.

## Testing

<!-- FILL: the concrete testing facts CLAUDE.md's Test Philosophy assumes but doesn't pin. Cover:
       - co-location convention (the exact filename pattern)
       - which units are the priority (must match the coverage table's high-target rows in CLAUDE.md)
       - what's EXCLUDED from coverage and why (must match CLAUDE.md's "What NOT to Test")
       - runner config: where it lives, default environment, globals on/off, the coverage provider + FLOOR
         (the floor MUST equal CLAUDE.md's project floor — Contract §3)
       - any per-file environment opt-in mechanism (DOM/integration), and where setup/polyfills live
     Numbers here must not contradict CLAUDE.md § Coverage Targets. -->

- Co-locate tests: TODO (pattern, e.g. `Foo.x` → `Foo.test.x`).
- Priority units: TODO (must match CLAUDE.md high-coverage rows).
- Excluded from coverage: TODO (must match CLAUDE.md "What NOT to Test").
- Runner config: TODO (location, default env, globals, coverage provider, **floor = CLAUDE.md floor**).
- Integration/DOM env opt-in: TODO (mechanism + setup file location), or N/A.

## Auth & Secrets

<!-- FILL: restate and make concrete the secrets boundary (Contract §5). This section cannot RELAX
     the rule, only specify HOW it's honored here. Cover:
       - the exhaustive list of places a secret must NEVER appear (source, exposed env, built bundle)
       - which prefix/marker makes an env var client-public, and that ONLY non-secret config may use it
       - where real secrets live instead (which backend/service)
       - TODO the concrete auth flow against the backend if not yet documented -->

- No provider key, credential, or secret in: frontend source, client-exposed env vars, or the built bundle.
- Only public-prefixed **non-secret** config (base URL, public flags) may live in client env.
- Secrets live only on: TODO (backend/service).
- Auth flow detail: TODO.

## Conventions

<!-- FILL: the concrete directory map — the payoff section. This REALIZES the architecture decision
     from CLAUDE.md (Contract §2). Rules:
       - keep the layer rows verbatim (Model / View / Controller(orchestration) / Service / Client);
         fill "Lives in" with REAL paths for this project and "Holds" with what belongs there
       - a layer may legitimately not exist yet — mark its path "(future) <path>" so the implementer
         knows it's planned, not missing
       - if the project chose domain-partitioning (CLAUDE decision B), the map is per-domain: show the
         domain root and the within-domain layer layout
       - state the file-placement rule explicitly: how does the implementer decide which folder a new
         file goes in? (by role? by service? by domain?) This is what stops layer-guessing.
       - state the import-alias convention if one exists
     Keep the three table columns. -->

- **Layering.** Realizes `CLAUDE.md § Architecture` (decision A/B/C — keep in sync). Concrete map:

  | Layer                      | Lives in | Holds |
  |----------------------------|----------|-------|
  | Model                      | TODO     | domain types, schemas, client/server state |
  | View                       | TODO     | presentational primitives + wrappers — no logic/fetch |
  | Controller (orchestration) | TODO     | intent → Service → Model glue; the runtime adapter/hooks |
  | Service                    | TODO     | business logic: composes Client calls, maps errors to the domain |
  | Client (transport)         | TODO     | requests, stream parsing, schema validation, error decoding |

  Dependency direction `View → Controller → Service → Client → backend`; never skip or invert an existing layer.

- **File-placement rule:** TODO — how the implementer picks the folder for a new file (by role / by service / by
  domain). Make it deterministic enough that "STOP and ask" is rarely needed.
- **Import alias:** TODO (the alias + what it maps to), or N/A.
- **Other project conventions:** TODO (naming, codegen output locations, anything sibling-files can't reveal).

## Non-Obvious Traps

<!-- FILL: mirror CLAUDE.md § Non-Obvious Traps and AGENTS.md § Non-Obvious Traps — same traps, but
     here with the ACTUAL detail (the other two only name them). Each: what the trap is, where it
     bites, and the correct move. These are the footguns not discoverable from one file. Keep this
     list and the two pointer-lists consistent. -->

- TODO.

## Documentation

<!-- FILL: where docs/ADRs live and the registration rule, matching CLAUDE.md Phase 4 step 6.
     If ADRs are used, name the directory and the index file they must be registered in. -->

- ADRs: TODO (directory), registered in TODO (index).
- TODO: record the first architectural decision (e.g. runtime wiring) as ADR-0001.

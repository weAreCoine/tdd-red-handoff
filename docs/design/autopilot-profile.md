# Autopilot profile — design

Designed 2026-08-14 in a grill session; implemented the same day (kit v1.4.0). Companion ADR:
`docs/adr/0008-autopilot-a-third-profile-that-flies-unattended.md`.

Implementation notes (decisions taken at build time, within this design):

- The phase-1 launch command is **`/fly <feature>`** (`commands/fly.md`); the driver is
  `bin/autopilot-driver.sh`, plugin-served like `verify-kit.sh`, POSIX sh, no dependencies
  beyond git, `gh` (push + draft PR ribbon), and the two headless harness CLIs.
- The driver never reads the roster: the machine binding (CLI model identifiers per tier,
  ladder included) lives in the target's gitignored `.ai/autopilot/models.env`, written by
  `/fly` from the roster with the operator confirming. The roster stays the human record.
- The four reviewer roles resolve to the roster's **Verifier** row; the production roles get
  their own rows, recorded per project via `/update-models-roster` (the kit ships no default).
- `/switch-profile`'s refusal rule now also covers **autopilot as destination** (a flight never
  adopts a half-done testplan), refuses outright to leave autopilot while a driver reports a
  `RUNNING` flight, and asks explicit confirmation for `STOPPED`/`PUSHED` ones (switching
  abandons them; their artifacts go inert under the other chapters).
- Provenance beats status everywhere: the sibling `{feature}.adr.md` is the autopilot
  signature all three chapters and AGENTS use to keep flight artifacts inert — in particular,
  an autopilot plan without its `Gate: APPROVED` row is never implementable under any profile.
- Post-review hardening (decisions in ADR-0008 § Amendments): fixed `develop`, guarded
  permission policy with bypass-by-record, config files parsed as data (strict grammars, never
  sourced), persisted dispatch counter + verdict pre-delete (no stale-verdict reuse), verdict
  enum + verdict/route coherence enforced per gate, canonical `> **Status:**` /
  `- **Gate:** APPROVED` rows checked exactly, tracker reference required in phase commit
  messages, third terminal state `PUSHED`, event-stream scan dropped (watch item).
- Producer phases can take their backward edge (4 → 2, 8 → 6) by writing a `blocked` routed
  verdict — same file contract as the reviewers, counted against the global edge cap only,
  never against a gate's rejection cap.
- "The grill" of phase 1 is the `grill-with-docs` skill, composing `grilling` +
  `domain-modeling` (public source: `mattpocock/skills` on GitHub). Decided 2026-08-14: the
  three skills are **required dependencies** of the profile — `/fly` checks them as a
  preflight precondition and refuses to open a flight without them; there is no fallback
  interview. The kit does not vendor them; they install user-level via the skills CLI
  (`npx skills add`).

Concrete model names are deliberately absent from this document (coupling #8: names live in
the README defaults table and the roster template only). Roles are named by capability tier;
the implementation records the actual assignments through `/update-models-roster`.

## Goal

A feature crosses the whole TDD wall unattended. The operator appears exactly twice: a
design interview at the start (the grill), a report plus a draft PR at the end. In between,
nine phases run as headless sessions chained by a deterministic driver. One flight = one
feature = one PR. No continuous loop: the process terminates at phase 9.

## The nine phases

| # | Phase | Tier (see roster) | Harness | Output | Backward edge |
|---|-------|-------------------|---------|--------|---------------|
| 1 | Designer | Anthropic top tier | interactive session with the operator | branch from `develop`, tracker issue → in progress, `{feature}.adr.md`, commit | — |
| 2 | TestPlan Designer | OpenAI flagship tier | `codex exec`, agentic | `{feature}.testplan.md` (`DRAFT`), commit | — (receives bounces from 3, 4, 5) |
| 3 | TestPlan Reviewer | Anthropic review tier | `claude -p` | routed verdict; approval grants `READY` | reject → 2 |
| 4 | Test Writer | OpenAI cost-efficient tier | `codex exec`, agentic | RED tests, commit; RED output fenced on the Log; testplan → `RED` | plan unworkable → 2 |
| 5 | Test Reviewer | Anthropic review tier | `claude -p` | routed verdict → `APPROVED`/`REJECTED(n)` | minor → 4 · structural → 2 |
| 6 | Handoff Planner | OpenAI flagship tier | `codex exec`, agentic | `{feature}.md` (implementation plan), commit | — (receives bounces from 7, 8, 9) |
| 7 | Plan Reviewer | Anthropic review tier | `claude -p` | `Gate: APPROVED` on the plan | reject → 6 |
| 8 | Implementer | OpenAI mid tier | `codex exec`, agentic | minimum code until GREEN + narrative Log entry, commit; the driver stamps the acceptance | plan unworkable → 6 |
| 9 | Final Reviewer | Anthropic review tier | `claude -p` | judges against **plan + design record**; `DONE`, last commit, push, draft PR, issue → in review when the reviewer has tracker tools (else proposed in its notes), report | minor → 8 · structural → 6 |

Topology invariant: one family designs and judges (1, 3, 5, 7, 9), the other produces
(2, 4, 6, 8). Four produced artifacts, four cross-family gates. No artifact is ever judged
by the family that produced it. The scarcest tier appears only in phase 1.

## Direction: deterministic driver, routed verdicts

- The Designer session launches the driver in the background as its last act, then stays
  open, dormant; when the flight ends it relays the report. The operator experiences a
  single session; no model change ever happens inside it — the session delegates to
  subprocesses running other models.
- Reviewers emit `{verdict, route, notes}` as structured JSON (both headless harnesses
  support schema-constrained output). The driver reads `route`, relaunches the target phase
  with the notes, and holds the counters. It decides nothing.
- Re-entry always passes the gate: an amended testplan re-passes phase 3, an amended plan
  re-passes phase 7. No amended artifact reaches its consumer ungated.

## Caps (never reset in-flight)

- **Per gate: 2 rejections.** The third rejection on the same gate stops the flight.
- **Global: 6 backward edges** per flight, catching ping-pong across different gates.
- On stop: state persisted, no push, the dormant session presents the exact blocking point
  and the last verdict; the operator amends, relaunches, or aborts.

## Preflight: a worker proves it can work

Generic per phase, model-agnostic, harness-agnostic:

1. The driver writes a probe file with a fresh random nonce (regenerated per attempt).
2. Every phase prompt opens with the standard preamble: read the probe file and start your
   output with `PREFLIGHT: <content>`; if your tools do not work, output
   `PREFLIGHT: FAIL <reason>` and stop.
3. The nonce is nowhere in the prompt: producing it proves tool access. Wrong or missing
   line = failed attempt.
4. **2 retries** with the same model, then the recorded substitution ladder, then the
   operator. A substitute passes its own preflight.
5. Backstops for mid-session degradation: end of every phase requires the expected artifact
   on disk (non-trivial, carrying the canonical state its route claims) and a clean tree
   after commit. The JSON event-stream scan designed here was dropped at build time —
   unreliable in text-mode harness output (ADR-0008 § Amendments); revisit with `--json`.

Known motivating bug: the OpenAI flagship tier currently has an open issue in the headless
harness (tool schemas invisible on some turns). The preflight absorbs it without any
model-specific code, and self-heals when the fix ships.

**Substitution ladders** (recorded per ADR-0007 — plan header row, testplan Log):
phases 2 and 6: flagship → previous-generation flagship (stronger on pure reasoning than
the current mid tier, and verified working in the headless harness) → mid tier → operator.
When the previous-generation model is retired, update the ladder via `/update-models-roster`.

## Artifact mapping (all additive)

| Concept | In the kit | Notes |
|---------|-----------|-------|
| Design record (phase 1) | `.ai/plans/{feature}.adr.md` — **new** | Lives beside its siblings; `.ai/plans` is already outside the model-name leak scan, and the record will name models (substitutions). |
| Test inventory (phase 2) | `{feature}.testplan.md` | Reused unchanged. |
| Implementation plan (phase 6) | `{feature}.md` | Contractual name; the *role* is "Handoff Planner", the artifact keeps the kit name. |
| Gate 3 outcome | `READY` on the testplan | No new vocabulary: under pipeline the design side self-declares `READY`; under autopilot the TestPlan Reviewer grants it. Same string, stronger semantics. |
| Gate 5 outcome | `APPROVED`/`REJECTED(n)` | Exactly pipeline's gate. |
| Gate 7 outcome | `Gate: APPROVED` on the plan | Uniform reading across profiles: "the approval that authorizes implementation". Who stamped it is in the Log. |
| Gate 9 outcome | `DONE` on the plan | The plan's own two-value status, already stamped by the review phase in both existing chapters. |
| Phase-8 completion (entry to 9) | The driver's **acceptance stamp**: an empty commit with the reserved `Autopilot-Green: {feature} <sha>` trailer — **new** | Written by the driver itself, only after every check on the phase-8 attempt passed; the trailer names the accepted commit, which is the stamp's own parent (ADR-0008 § Amendments, eighth review / R8-M1 — it replaced the positional Log row of the third-through-seventh rounds, whose medium the append-only Log contradicted). Phase 9's entry requires the stamp reachable from `HEAD` through artifact-only commits; a phase commit carrying the key fails the attempt. The Log keeps a narrative GREEN row, and its shape guard (one heading, no section after it, no container left open, refuse-not-guess) still gates every phase that reads or appends it. |
| Flight state | `.ai/autopilot/{feature}/`, gitignored | Verdict JSONs, counters, preflight nonces, event logs, `report.md`. Operational, not an interface between roles: the durable record is in the artifacts. |

**Backward compatibility** is by addition: a plan without a `Gate` row comes from a profile
with no gate (existing idiom); the presence of `{feature}.adr.md` is autopilot's signature;
`READY` means "ready for transcription" in every era, the Log says who granted it. Extended
inertness: artifacts produced under other profiles are historical records — read, never
rewritten, moved, deleted, or retrofitted (no ADR backfill, no retroactive Gate stamps).

## Git / tracker ribbon

All repos carry a `develop` branch; `main`/`master` tracks production (Coolify / Laravel
Forge deploys). The flight: phase 1 updates `develop` and branches `feature/{feature}` from
it (**fail-fast** with a clear message if `develop` is missing — its creation is a human
act); every file-producing phase ends committed and clean, every commit carrying the tracker reference in the
message; a successful phase 9 pushes and opens a **draft PR against `develop`** with a
compiled body (summary from the plan, flight counters, final-review notes, tracker
reference — the suite evidence lives in the phase-9 commits and the testplan Log, not
in the PR body). The Final Reviewer moves the issue to review when it has tracker
tools; otherwise the DONE report names the move and the issue ↔ PR cross-link as the
operator's residual step (ADR-0008 § Amendments 2026-08-15). Promotion from draft, merge (typically
deleting the remote branch), and closure are human. Post-merge, the operator runs the
personal `/mark-done` command (outside the kit: deletes the local branch, realigns
`develop`, closes the issue, runs the personal checkpoint skill). Issues for problems
*discovered* during the flight are **proposed** in the report with ready-to-paste title and
body, never created.

## Implementation map (kit repo)

- `.ai/process/autopilot.md` — new chapter: no markers, exact-string role names, phase
  numbers confined here, re-entry-through-the-gate rule, extended inertness, preflight
  preamble contract, roster/substitution reading as in the other chapters.
- `bin/` — the driver (dispatch, counters, preflight, git/tracker ribbon; the event-log
  scan was dropped at build time — ADR-0008 § Amendments).
- `tests/driver/` — the driver's behavior suite (`run.sh`: disposable repos, stub harnesses)
  and `mutants.sh`, the mutation harness whose rows are exact sed programs (ADR-0008 § the
  behavior suite as a safety case).
- `commands/` — `init-architecture`, `switch-profile`, `show-profile`, `verify-kit` learn
  the third triad value; new command to open phase 1 (name to be chosen).
- `.ai/templates/` — `plan_template.md` and `AGENTS.template.md`: "pipeline-only" wording
  on `Source testplan`/`Gate` rows generalizes to "gated profiles"; `test_plan_template.md`:
  conditional caption on who grants `READY`; `PROJECT_ARCHITECTURE.template.md § Model
  Roster`: union grows with the new roles (via `/update-models-roster` mechanics).
- `bin/verify-kit.sh` — `kit-manifest` accepts `autopilot`; `chapters` checks extend to the
  new chapter; `.gitignore` gains `.ai/autopilot/` in targets.
- `README.md` mirror + root `CLAUDE.md` couplings + plugin version bump.
- `CONTEXT.md` — glossary entries (done with this design).
- Outside the repo: `~/.claude/commands/mark-done.md` (personal).

## Watch items

- Retirement of the previous-generation flagship (substitution ladder rung): a
  `/update-models-roster` run when it happens.
- Subscription usage caps on long overnight flights: observe during the first real flights.
- Pinning of the interview skills (`mattpocock/skills` unpinned — drift risk on future
  installs; ADR-0008 § Amendments).
- The driver's event-stream scan, dropped in text mode: revisit with `--json` /
  `--output-schema` when it pays.
- ~~False refusals from the positional proof~~ (seventh review): resolved by R8-M1 — the proof
  left the Markdown for the driver's acceptance stamp, so a trailing note after the narrative
  row, or a spliced last line, no longer refuses anything.
- ~~Name of the phase-1 launch command~~: resolved — `/fly`.

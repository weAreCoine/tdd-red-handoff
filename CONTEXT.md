# Multi-Agent TDD Architecture Kit

The kit is a set of Markdown process contracts and slash commands that other repositories
install. This glossary fixes the words the kit uses about *itself* — not the words a target
project uses about its own domain.

## Language

**Kit**:
The distributable product of this repository: the templates plus the slash commands that
install and maintain them.
_Avoid_: framework, boilerplate, scaffold

**Profile**:
A self-consistent set of process contracts — roles, templates and commands — that a target
project runs on. Exactly one profile is active at any time, but the active profile is chosen
per task, not once per project: a project switches between profiles as the work in front of
it changes. The three values are `two-role`, `pipeline` and `autopilot`.
_Avoid_: variant, preset, mode, flavour

**two-role**:
The profile with an Architect (design, tests, review) and an Implementer. One handoff
artifact per feature: the implementation plan.

**pipeline**:
The profile with a Designer, a Test-Writer, a Verifier and an Implementer. Two handoff
artifacts per feature: the test-case inventory and the implementation plan, separated by
the Verifier's gate.

**autopilot**:
The profile that flies a feature unattended between two human touchpoints: a design
interview at the start, a report and a draft PR at the end. Nine phases — a design side, a
production side and four cross-family gates — chained by the driver. Three artifacts per
feature: the design record, the test-case inventory and the implementation plan.

**Process chapter**:
The roles-and-phases text of one profile, shipped verbatim to `.ai/process/{profile}.md` in a
target project. It carries no fill markers and no project facts, so it is never edited and can
be swapped mechanically.
_Avoid_: process template, role file

**Project overlay**:
The fact-bearing half of a target project's `CLAUDE.md` — architecture model, layer constructs,
traps, coverage floor, test exclusions, doc sources. It does not vary by profile and survives
every switch untouched.
_Avoid_: fills, project section

**Target project**:
The repository the kit is installed into. Distinct from this repository, which produces the
kit.
_Avoid_: host project, consumer

**Contract name**:
The exact string a process file uses to refer to a toolchain command — `typecheck`, `test
(focused)`, `format:check`. It is the name itself, not a description of it, so a target project's
Toolchain table carries it verbatim in its first cell rather than a human label like "Type-check".
Rows that are not part of the contract keep human labels.
_Avoid_: alias, action, label

**Kit manifest**:
`.ai/kit.json` in a target project: the single machine-readable record of which profile the
project runs and which kit version installed it. The installer and the migration command read
it; no other file restates those two facts.
_Avoid_: lockfile, config, metadata

**Live docs**:
The filled, project-specific files that exist in a target project: `CLAUDE.md`, `AGENTS.md`,
`.ai/PROJECT_ARCHITECTURE.md`. Distinct from the templates they were filled from.
_Avoid_: generated files, output

**Flight**:
One unattended run of the autopilot profile over a single feature: from the design interview
to the draft PR, or to a stopped state. One flight, one feature, one PR; the process
terminates at the final review — there is no continuous loop.
_Avoid_: run, job, batch

**Driver**:
The deterministic script that chains autopilot phases. It launches headless sessions, reads
routed verdicts, holds the bounce counters, and stops at the caps or on a failed preflight.
It holds no intelligence: routing decisions belong to the reviewers.
_Avoid_: orchestrator, director, agent

**Routed verdict**:
The machine-readable outcome an autopilot reviewer emits — verdict, route, notes. The
reviewer decides where the flow goes next; the driver only executes that routing. An amended
artifact always re-enters through its gate, never past it.
_Avoid_: review result, gate output

**Preflight**:
The unforgeable tool-access probe every autopilot phase passes before real work: read a
driver-written nonce file and open the output with its content. The nonce exists nowhere in
the prompt, so producing it proves the tools work. Failure → bounded retries → the recorded
substitution ladder → the operator.
_Avoid_: health check, smoke test

**Extended inertness**:
Artifacts produced under a profile other than the active one are historical records: read,
never rewritten, moved, deleted, or retrofitted. Generalizes the rule that testplans go
inert under two-role. No design-record backfill, no retroactive gate stamps, no status
promotion.
_Avoid_: read-only mode, freezing

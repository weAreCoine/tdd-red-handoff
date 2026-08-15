# Autopilot: a third profile that flies unattended

The two existing profiles assume a human between every handoff: the operator reads each
artifact, judges it, and opens the next session. That supervision is the profiles' real
safety net — `REJECTED(n)` exists, but the loop it bounds is driven by a person. The kit
needed a profile where a feature crosses the whole wall — design, test inventory, tests,
plan, implementation, review — with the operator present only at the two ends: a design
interview at the start, a report and a draft PR at the end. Decided 2026-08-14; the full
design is `docs/design/autopilot-profile.md`.

## A third profile, not an execution mode of pipeline

Unattended execution changes the contract, not just the cadence. Two reviewer roles appear
that pipeline does not have, artifacts gain an upstream per-feature design record, and every
handoff needs a machine-readable verdict instead of an operator's judgment. That is a third
process chapter, selected per task like the other two — not a flag on pipeline. The name
`autopilot` is lexically disjoint from `two-role` and `pipeline` on purpose: the kit's
couplings are exact-string greps, and a name containing an existing profile name as a
substring would turn every such grep into a silent false positive.

## The driver is deterministic; the intelligence lives in the verdicts

Nothing routes the flow by reasoning about it mid-flight. Reviewers emit routed verdicts —
`{verdict, route, notes}` — and a driver script dispatches, counts and stops. Two caps,
never reset in-flight: 2 rejections on the same gate, 6 backward edges per flight. Hitting
either stops the flight with all state on disk and escalates to the operator. Re-entry
always passes the gate again: an amended artifact never skips its judge. The alternative —
a model as director — would spend the scarcest tier on dispatching work that requires no
intelligence, and was rejected for exactly that reason.

## Producers and judges never share a model family

One vendor family designs (the interview) and judges (all four gates); another produces
(test inventory, tests, plan, code). Every artifact crosses a family line before it is
consumed, so a family's shared blind spots cannot approve their own output. The plan was
the one ungated artifact in the original eight-phase draft — a Plan Reviewer gate was added
between planner and implementer, completing the symmetry: four produced artifacts, four
cross-family gates. With that gate in place, planner and implementer may share a family:
the protection lives in the gate, not in the producers' diversity.

## A worker must prove it can work: the preflight is generic

A known provider bug (tool schemas invisible on some turns of the headless harness) would
have silently degraded the two flagship-tier phases. The countermeasure is deliberately not
model-specific. Before real work, every phase must read a driver-written nonce file and open
its output with the nonce — unforgeable proof that its tools actually work, since the nonce
exists nowhere in the prompt. Failure → 2 retries, then the recorded substitution ladder
(ADR-0007 mechanics), then the operator. An end-of-phase artifact check backs it up
against mid-session degradation (the event-log scan originally designed alongside it was
dropped at build time — unreliable in text-mode harness output; see Amendments 2026-08-15). Nothing in the mechanism names a model, so
a future roster changes nothing here — and when the provider bug is fixed, the preflight
simply starts passing, with no baked-in workaround to notice and remove.

## Artifacts map onto the existing lifecycle by addition

One new artifact: the per-feature design record `{feature}.adr.md`, sitting beside its
siblings in `.ai/plans/`. Everything else reuses pipeline vocabulary with sharpened
semantics: `READY` is granted by the test-inventory gate instead of self-declared; the
plan's `Gate` row uniformly means "the approval that authorizes implementation" (the
testplan's gate under pipeline, the plan's own gate under autopilot); `DONE` is stamped by
the final review. Flight state — verdicts, counters, preflight nonces, event logs — lives
in `.ai/autopilot/{feature}/`, gitignored: the durable record stays in the artifacts.
Artifacts produced under other profiles are historical records — read, never retrofitted:
the testplan-inertness rule, generalized ("extended inertness").

## The flight ends at the draft PR

One flight, one feature, one PR — no continuous loop. The branch opens from `develop`
(fail-fast if the repo has none), every file-producing phase commits atomically, and a
successful flight ends with a push and a draft PR against `develop`; the tracker issue is
moved to review and cross-linked with the PR when the final review has tracker tools —
otherwise that move is proposed in its notes and stays an operator residual. Promotion
from draft, merge, and issue closure stay human; a personal post-merge command outside the kit cleans up. A stopped or
rejected flight pushes nothing: local commits and a report of the exact blocking point.

## Amendments (2026-08-14 — post-implementation review)

An independent implementation review (flagship production tier, 2026-08-14) surfaced
decisions this ADR had left implicit. Resolved with the operator:

- **The interview skills are hard dependencies.** Phase 1's grill runs through the
  `grill-with-docs` skill (composing `grilling` + `domain-modeling`; public source
  `mattpocock/skills` on GitHub), installed user-level via the skills CLI. `/fly` checks them
  as a preflight precondition; there is no fallback interview. The source is not pinned —
  accepted risk, tracked as a watch item while the flow is single-operator.
- **Permission policy: guarded by default, bypass by record.** Producers run in the codex
  workspace-write sandbox with automatic approvals; reviewers run under the project's Claude
  Code sandbox with auto-accepted edits. A full bypass exists only as an explicit per-project
  line in the machine binding, written by the operator with the cost stated — never as a
  default, never inferred from launching a flight.
- **The base branch stays `develop`, fixed.** The implementation briefly generalized it to a
  configurable value; reverted — a variable able to point a flight at a production branch buys
  nothing this kit wants.
- **Preflight scope: headless phases.** Phase 1 is human-attended; a nonce probe there proves
  nothing the operator cannot see directly. "Every phase" in this ADR reads as "every headless
  phase" (2–9).
- **A third terminal state.** DONE/STOPPED cannot truthfully describe a flight whose push
  succeeded but whose PR creation failed: **PUSHED** names it, and the report hands the
  operator the compiled PR body and the remaining publication steps.
- **The event-stream scan is dropped for now.** In text-mode harness output it either misses
  (JSON markers absent) or false-positives (test output contains error strings). The backstops
  that hold are: preflight nonce, canonical status/gate rows on the artifact, HEAD advanced
  with the tracker reference in the message, clean tree. Revisit with `--json` /
  `--output-schema` — watch item.

## Amendments (2026-08-15 — second implementation review)

A second independent review (same flagship tier) re-examined the delta. Its blockers were
implementation defects, fixed in place; three of its findings touched this ADR's contract and
are resolved as follows:

- **The tracker close-out is best-effort in-flight.** "A successful flight ends with the
  tracker issue moved to review" reads as: the Final Reviewer moves it when it has tracker
  tools; otherwise the DONE report names the move and the issue ↔ PR cross-link as the
  operator's residual step. The driver never talks to the tracker itself — that would add a
  per-tracker dependency and a new way to fail after publication. The suite evidence lives in
  the phase-9 commits and the testplan Log, not in the PR body.
- **"Commits atomically" means committed and clean at phase end — not one commit.** The
  enforced grammar is per commit: every commit a phase produces carries the semantic prefix
  and the tracker reference. A phase splitting its work into two well-formed commits is not a
  fault; a single unreferenced commit is.
- **Gate soundness is enforced as entry preconditions, not a resume whitelist.** Before any
  phase launch — normal flow or `-s` relaunch — the artifacts on disk must justify entering
  it (phase 8 requires the testplan APPROVED, the plan RED, and exactly one canonical approved
  Gate row). This closes the review's relaunch-bypass finding while leaving the operator free
  to re-enter *upstream* of the stop when the amendment is deeper; a persisted single resume
  point would forbid exactly that legitimate case.

## Amendments (2026-08-15 — third implementation review)

A third independent review confirmed the previous rounds' fixes and found the remaining
defects to be driver implementation faults (bounded counter grammar, closed verdict grammar,
branch integrity, complete entry matrix — fixed in place, covered by the behavior suite).
One finding touched this ADR's contract:

- **Phase 8 leaves a durable completion signal.** Phases 8 and 9 shared the same observable
  entry state (testplan APPROVED + gated RED plan), because implementation produces only
  code — so a direct `-s 9` relaunch could skip implementation entirely and publish. Now the
  Implementer, once green, appends the canonical row
  `- **Implementation:** GREEN — <YYYY-MM-DD>, full suite + typecheck (Implementer)` to the
  testplan Log and commits it with the code; entering phase 9 requires that row. This is an
  artifact-level entry precondition, consistent with the gate-soundness amendment above —
  not a persisted resume whitelist: the flight state stays operational and gitignored. Known
  residual, accepted: the row is append-only, so after a phase-9 reject that rewrites the
  plan, a row from the previous attempt still satisfies a *direct* `-s 9`; the normal routed
  path re-runs phase 8 regardless.

## Amendments (2026-08-15 — fourth implementation review)

A fourth independent review re-verified the third round's fixes and found four of them only
partially closed, plus one suite-level blind spot. Two were publication-safety failures and
blocked merge; all are fixed in place and covered by the behavior suite.

- **The GREEN row counts only from the Log.** The completion signal above was checked with a
  whole-file grep, so the same bytes anywhere in the testplan — an inventory row, an example,
  a hand-placed line — authorized phase 9. The predicate is now scoped: exactly one canonical
  `## 6. Log (append-only)` heading (the shipped template's), and the canonical rows below it.
  The predicate also counts, which narrows — but does not close — the residual accepted in
  the third round: **a phase-8 run must add a new row**, so an earlier attempt's row no
  longer satisfies a re-run of implementation.
  Beyond the review's ask, and recorded as such: phase 2's backstop now requires that
  canonical heading to exist exactly once, so a testplan whose Log drifted from the template
  stops the flight where it was written, not at phase 9's door with the implementation
  already paid for.
- **The ribbon publishes the reviewed commit, by object.** Branch integrity was checked when
  each harness returned, but publication re-checked only the branch *name*: a child process
  outliving the harness could move `feature/<f>` afterwards, and the driver pushed whatever
  the name then pointed at while reporting `DONE`. The driver now records the accepted
  phase-9 `HEAD` and, immediately before pushing, requires the exact branch, a clean tree,
  `HEAD` and the branch ref both equal to that commit, and the phase snapshot still an
  ancestor — then pushes that sha explicitly (`<sha>:refs/heads/feature/<f>`). Upstream
  tracking is set afterwards and is never a flight outcome.
- **A blocked producer is judged on its inputs.** `blocked` was an unconditional success for
  phases 4 and 8: a producer could truncate or downgrade the artifact it consumed and still
  be logged `ok`. Precisely at a stop — when the artifacts become the operator's recovery
  interface — they must still say what the lifecycle says. A blocked phase 4 must leave the
  testplan's Status row exactly as it found it; a blocked phase 8 must leave the testplan
  APPROVED and the plan RED with its one canonical Gate; neither may add a GREEN row.
- **The verdict grammar is byte-closed.** The single full-string ERE ran on a shell variable,
  and command substitution silently drops NUL — so a NUL inside `notes`, or inside a routing
  token, vanished before the control-byte ban could fire. The raw file is now rejected
  byte-for-byte before it is read.
- **The suite binds phases to harness families and model ids.** The stubs accepted any model
  id and ran any phase for either harness: a mutant sending all eight phases through the
  producer harness passed 132/132. Each stub now declares its identity, the actor refuses a
  phase that does not belong to its family and a model id that is not the one that phase's
  roster tier defines (read from the flight's own `models.env`, by key — never a literal),
  every dispatch is recorded, and a scenario asserts the exact eight-phase sequence. The same
  mutant now fails loudly (see the fifth round's table for the counts, which are only
  meaningful against a stated suite size).

Known residuals, accepted at this round:

- The Log scope is a heading range: a canonical GREEN row written *inside* the Log but within
  a fenced block still counts. The realistic misplacements the review reproduced (inventory,
  prose, a fence before the Log, a missing or duplicated heading) are all refused.
- The third round's residual stands, narrowed. Entering phase 9 still asks only whether at
  least one canonical row is on the Log, and on disk a stale row is indistinguishable from a
  fresh one — so a *direct* `-s 9` after a plan rewrite can still ride the previous attempt's
  row. The routed path cannot: it re-runs phase 8, which must add one. Closing it outright
  would mean persisting the last-seen count in the flight state — the persisted resume
  whitelist the third round rejected — and is left to the operator.
- The publication window between the driver's last check and git's own refspec resolution
  cannot be closed from the outside; it is narrowed by pushing the reviewed object rather
  than the branch name, and the behavior suite asserts the invariant that survives either
  way — origin carries the reviewed commit, or nothing was published.

## Amendments (2026-08-15 — fifth implementation review)

A fifth independent review re-verified the fourth round: four findings fixed, two partially.
One was a blocker of the same family as the one it replaced, and the other two were suite
blind spots — the round's real subject was whether the behavior suite can carry the safety
case it is being asked to carry.

- **The Log is a Markdown section, and it is last.** The scoped predicate started at the Log
  heading and scanned to end of file, so a canonical row under a later `## 7. …` still
  authorized phase 9 — the same publication bypass, one heading further down. The scan now
  ends at the next H1/H2; deeper headings (`###`) stay inside, so a phase may structure its
  own entries. Because the scope now has an end, the Log being the testplan's **last** section
  is load-bearing: the chapter's phase-2 instruction and the template's Log comment say so,
  and phase 8 is told to append inside that section, never after a heading of its own.
- **A wrong nonce is now rejected on its own evidence.** The suite's only preflight scenario
  used a worker that answered wrongly *and produced nothing*, so the flight stopped on the
  missing artifact even with the nonce check deleted — the ratified preflight property was
  green for the wrong reason. A second seam makes the named model ids answer wrongly while
  doing their canonical work; the attempt now stops for `preflight line missing or wrong` and
  nothing else.
- **The substitution ladder is exercised, not just declared.** The test actor accepted only
  each tier's primary id, so a configured rung was rejected before it could work: no scenario
  could show a fallback completing a phase, and a driver that tried its rungs *first* passed
  unnoticed. The actor now accepts the primary or a rung of that tier's configured ladder,
  refuses a rung that arrives before the primary, and a scenario drives the primary to
  exhaustion and asserts the exact primary-then-rung dispatch order through a completed flight.
- **Mutation counts are stated against a suite size.** The fourth round recorded a count taken
  before two scenarios were added; measured again on the current suite it differs. Counts are
  now recorded as a table with the suite size, and re-measured whenever scenarios change. The
  publication mutant is named exactly (the push line, not the whole pre-fix block, which is a
  different mutant), and the delayed-reset assertion is documented as race-dependent and
  therefore not part of any exact count.

Mutation evidence for that round was taken against a 177-assertion suite; the sixth round
re-measured the whole table on the suite as it stands. The current numbers are below.

## Amendments (2026-08-15 — sixth implementation review)

A sixth independent review reproduced the fifth round's mutation table exactly — no differing
counts — and confirmed the preflight and ladder fixes. It left one blocker in the same family
as the round-5 blocker, and five findings that were all about the suite rather than the driver.
The family is the finding: for four rounds the same safety property — *durable proof that phase
8 ran* — was patched wherever the reviewer's reproduction pointed (the row is anywhere in the
file → require it after the heading; the scope runs to EOF → end it at the next `## `), while
the invariant the contract had stated from the start, "the Log is the file's **last** section",
was never checked by anything.

- **The Log's scope is now decided by refusal, not by detection.** Markdown opens a section
  with more than a column-zero `## `: an ATX heading may be indented up to three spaces, and a
  Setext heading is a text line underlined with `---` or `===`. Every form the predicate did
  not know was another way to sit outside the Log while counting as inside it, so the reader
  stopped looking for the end: it reads the Log from its heading to end of file and **refuses**
  a testplan that has any H1/H2 after it. Missing a boundary would be a bypass; seeing one that
  is not there is a stop the operator can read. The same predicate — one awk pass, one place
  where the canonical strings live — is used by phase 2's artifact backstop (the shape is
  checked where the artifact is *produced*, not only where it is consumed), by the blocked
  producers' input check, and by the entry preconditions of phases 8 and 9, whose refusal now
  names the shape violation instead of blaming a missing row.
- **Pasted output is fenced, and fences are opaque.** Making a ruler line a heading is only
  safe if honest content cannot contain one: real test output does (`unittest` prints a rule of
  dashes before its summary). So phase 4's contract, the template's Log and the driver's phase-4
  prompt now require the RED output **inside a fenced block**, and inside a fence nothing counts
  — not a heading, not the GREEN row. That closes the round-4 residual (a fenced canonical row
  counted as proof) in the same pass, and phase 8 is told the row must never be fenced.
- **The suite now names routing, caps, entry, config, lock and report.** Six one-line mutants
  survived 177 green assertions: an implementation-plan bounce could be routed back to test
  inventory, the edge cap could refuse the last edge the operator configured, `flight.env` could
  go unvalidated, the artifact floors could degrade to existence checks, phases 3 and 7 could
  judge without the design record, a second driver could walk through an existing lock, a
  completed flight could leave one behind, and the operator's report could lose its counters,
  its journey and the verdict that explains the stop. Each is now killed by a scenario that
  asserts the specific thing: the route token's destination (`8 -> 6`), edge N taken and edge
  N+1 refused *by number*, `flight.env` duplicates/unknown keys/malformed lines, non-empty
  artifacts below their floor, `-s 3` and `-s 7` without an ADR, a pre-existing lock, the lock's
  absence after DONE / STOPPED / interruption, and the report's exact counter line, journey
  lines and verdict bytes.
- **The publication-time clean-tree recheck is tested, and the declared gap was wrong.** It was
  recorded as untestable without concurrency. It is not: a `git` on `PATH` that delegates every
  call to the real one and dirties the tree once, at the first call after the driver logs
  "phase 9 approved", hits the seam deterministically with a command count and no timing. The
  flight stops, nothing is published, and removing the recheck flips exactly that scenario.
- **The test actor's ladder order was scoped to the flight instead of the invocation.** The stub
  compared each dispatch with the last model that phase had *ever* used, so a routed re-entry —
  which the driver always starts from the primary again — was refused as a rank decrease: a
  false failure that also hid the re-entry from the recorded sequence. It now compares only
  while the phase is the one running, and a scenario drives a phase-5 bounce back through
  phases 2 and 3 and asserts the whole 18-dispatch sequence across the bounce.

### What the behavior suite is a safety case for

Mutation testing over a 650-line script does not converge: a survivor exists for every line no
assertion pins, so each round can produce a fresh table indefinitely. The suite is therefore
declared complete against **six safety properties**, each of which must carry at least one
mutation-killing assertion: publication integrity, entry preconditions, caps and routing,
terminal state and lock, configuration fail-fast, and report honesty. Survivors outside those
six are recorded here as known-unprotected lines, not as open findings.

Mutation evidence, all against the current suite — **247 assertions**, 0 failures unmutated.
Each mutant is a single change to `bin/autopilot-driver.sh` (the last row mutates the test
actor instead), run against the unmodified suite in a full copy of the tracked tree (a partial
copy of `bin/` + `tests/` alone breaks the scenario that reads `.ai/templates/`, and every
mutant then appears to gain one detection it has not earned):

| Mutant | Property | Failures |
|---|---|---:|
| `phase_harness` returns the producer harness for every phase | entry/dispatch | 80 |
| the Log scan back to end-of-file (fifth-round defect) | publication | 12 |
| the preflight nonce check replaced by `:` | entry | 7 |
| `flight.env` no longer validated | config fail-fast | 6 |
| the raw-file NUL rejection removed | entry | 5 |
| Setext headings no longer close the Log (sixth-round defect) | publication | 5 |
| `route_phase` sends `plan` to phase 2 instead of 6 | routing | 5 |
| `impl_green` back to a whole-file grep (fourth-round defect) | publication | 4 |
| `nontrivial` degraded to an existence check | entry | 4 |
| phase 2's canonical Log shape requirement removed | publication | 4 |
| the publication-time clean-tree recheck removed | publication | 4 |
| a failed lock acquisition ignored | terminal state/lock | 4 |
| the journey dropped from the report | report honesty | 4 |
| indented ATX headings no longer close the Log | publication | 3 |
| fenced blocks read as Markdown (headings and rows count) | publication | 3 |
| the reviewer ladder tried before the primary | entry | 3 |
| the lock never released | terminal state/lock | 3 |
| the report counters forced to zero | report honesty | 3 |
| `artifact_ok` phase 8 back to its pre-fix form | publication | 2 |
| the edge cap refuses edge N instead of N+1 | caps | 2 |
| phase 3's `adr_ok` entry requirement removed | entry | 2 |
| phase 7's `adr_ok` entry requirement removed | entry | 2 |
| phase 8's entry Log-shape check removed | entry | 2 |
| the test actor's ladder order scoped to the flight | *(test harness)* | 2 |
| the push reverted to `git push -u origin "feature/<f>"` | publication | 1 |
| `artifact_ok` phase 4 back to its pre-fix form | publication | 1 |
| the last verdict dropped from the report | report honesty | 1 |
| the `RUNNING` → `STOPPED` conversion on an abnormal exit | terminal state | 0 — declared gap |

Known residuals and declared gaps:

- A *direct* `-s 9` can still ride an earlier attempt's in-Log row (see the fourth round).
- The window between the driver's last pre-push check and git's own refspec resolution.
- `cleanup`'s `RUNNING` → `STOPPED` arm has no faithful injection: an untrapped fatal signal
  terminates the shell **without** running the EXIT trap, and every in-driver exit path after
  `RUNNING` is written goes through `stop_flight`, which writes its own terminal status. So the
  arm only fires for a shell-level abort no test can produce without mutating the driver. What
  *is* tested is everything around it: the lock is exclusive, it is released after DONE, after
  STOPPED and after an interruption, and `SIGTERM` mid-flight leaves `STOPPED` and nothing
  pushed. That scenario carries no timing assumption either: the stub holds the driver in the
  foreground until the test has sent the signal — a trap runs only after the foreground child
  returns — so the ordering is explicit instead of a race against a fixed sleep.

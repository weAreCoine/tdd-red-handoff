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

Mutation evidence, all against the current suite — **177 assertions**, 0 failures unmutated.
Each mutant is a single-line change to `bin/autopilot-driver.sh`, run against the unmodified
suite in a full copy of the tracked tree (`git archive HEAD`; a partial copy of `bin/` +
`tests/` alone breaks the scenario that reads `.ai/templates/`, and every mutant then appears
to gain one detection it has not earned):

| Mutant | Failures |
|---|---:|
| `phase_harness` returns the producer harness for every phase | 57 |
| `impl_green` back to a whole-file grep (fourth-round defect) | 6 |
| the preflight nonce check replaced by `:` | 6 |
| the raw-file NUL rejection removed | 5 |
| `artifact_ok` phase 8 back to its pre-fix form | 5 |
| the Log scan back to end-of-file (fifth-round defect) | 2 |
| the reviewer ladder tried before the primary | 2 |
| the push reverted to `git push -u origin "feature/<f>"` | 1 |
| `artifact_ok` phase 4 back to its pre-fix form | 1 |
| phase 2's canonical Log heading requirement removed | 1 |
| the publication-time clean-tree recheck removed | 0 — declared gap |

Known residuals, carried forward and added to:

- A canonical GREEN row inside a fenced block *within* the Log section still counts.
- A *direct* `-s 9` can still ride an earlier attempt's in-Log row (see the fourth round).
- The window between the driver's last pre-push check and git's own refspec resolution.
- The publication-time clean-tree recheck has no deterministic test: between phase 9's own
  clean-tree check and the push, nothing in the driver writes to the tree, so dirtying it
  requires concurrency — the same class as the refspec window. With `HEAD` pinned to the
  accepted commit, a dirty tree cannot change *what* is published, only the honesty of the
  report; the recheck stays as defence in depth, untested by construction.

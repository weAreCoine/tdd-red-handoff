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
re-measured the whole table on the suite as it stands. Both are superseded by the
harness-produced table below — introduced in the seventh round and re-measured whenever the
suite changes, last in the eighth.

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

## Amendments (2026-08-15 — seventh implementation review)

A seventh independent review confirmed every sixth-round fix (routing destinations, the
inclusive edge cap, `flight.env` parsing, the artifact floors, the lock, the report, the
publication-time clean-tree recheck, the actor's ladder scope) and reproduced the round-6
blocker in three new forms: the canonical GREEN row inside an HTML comment, inside a four-
backtick fence that a three-backtick line appeared to close, and under a closing fence carrying
an info string. CommonMark renders all three as hidden or code text; all three reached `DONE`
and pushed a branch. Fourth round, same family — the completion proof was recognized by
*reading Markdown*, and each round the reader met a construct it did not model.

- **The proof is positional first, and read second.** Phase 8 is the last phase that writes
  before phase 9 reads, so the contract can demand *where* the row goes: the canonical row must
  be the testplan's **last non-blank line**. A row nothing follows cannot be inert text — every
  construct that could hide it has to be closed after it, and a closer is itself a line, so the
  row would not be last. This condition does not depend on how much Markdown the reader knows,
  and it is what ends the family: all three published fixtures fail it without modelling
  anything. It is stated in the chapter's phase 8, in the phase-8 prompt and in the template,
  and it is enforced at both ends — phase 9's entry precondition, and phase 8's own artifact
  backstop, so a phase that writes past its proof fails its attempt instead of handing phase 9
  an artifact that cannot authorize it.
- **The reader is bounded, and says so.** It models exactly two opaque containers — fenced
  blocks (closed only by CommonMark's rule: same character, at least as long as the opener,
  nothing but whitespace after) and HTML comments (`<!-- … -->`, modelled rather than refused
  because the shipped template's own Log carries them) — plus ATX headings (0-3 space indent,
  at most six `#`) and Setext underlines as section bounds. Everything else that could hide
  text is **refused**: a line starting with `<` (raw HTML), and a fence or comment left open at
  end of file. The refusal names the shape. The residual is stated instead of denied: a
  construct outside that enumeration is refused, never silently counted, and the positional
  condition covers what the enumeration does not.
- **A refused Log has a documented repair, and no migration mode.** The contract change refuses
  an old testplan whose phase-4 output was pasted unfenced (real `unittest` output carries a
  `======` ruler, which Markdown reads as a heading). The population that would need converting
  is empty — the autopilot profile has never shipped: it exists only on this branch, so no
  target holds an artifact written under the old rule. Building a versioned migration mode for
  zero artifacts is the abstraction YAGNI names; what was missing is the operator's repair path,
  and that is now written down (`autopilot.md § Repairing a refused Log`, which the driver's own
  refusal names): fence the pasted bytes where they are, changing none of them, record the
  repair in the **commit message** rather than in a new Log entry (which would be written past
  the proof), relaunch at the phase the stop named. The refusal itself now points at the line
  where the problem starts and names the repair section, so the stop is a work order rather
  than a diagnosis. A behavior scenario walks it end to end — refused, repaired, `DONE`,
  with the RED evidence still in the file verbatim.
- **The per-commit audit grammar and the retry's workspace are now part of the safety case.**
  Two one-line survivors of the round-6 suite: replacing the semantic-prefix ERE with `.*`, and
  replacing the failed attempt's `git clean -fd` with `:`. Both were live contract text that no
  assertion pinned. A scenario now commits an otherwise-valid artifact under a non-semantic
  prefix and asserts the stop **names the offending commit by sha**, and another leaves an
  untracked file behind on a failed attempt and asserts the retry starts from a clean tree.
  They are a seventh safety property, not a footnote: the six-property partition did not cover
  them, which is why they survived.
- **The mutation table is reproducible or it is not evidence.** Four rows of the round-6 table
  could not be reproduced: their counts depended on which line the reader picked, and prose
  names like "the lock never released" do not pick one. The mutants now live in
  `tests/driver/mutants.sh` — id, file, **the exact sed program**, property — and the harness
  copies the whole tracked working tree per mutant, applies the edit, and reports observed
  failures. It fails loudly instead of quietly: a sed program that no longer matches (the file
  moved under it) reads `did-not-apply`, a mutant that stops parsing reads `does-not-parse`, an
  incomplete tree copy reads `copy-failed`, and a row with no measurement at all is printed as
  `NOT RUN` rather than dropped. That last one earned itself: the round's first two measurements
  lost three rows, because the dispatch loop ran inside a pipeline's subshell — the final,
  partial batch's jobs were that subshell's children, nothing waited for them, and the EXIT trap
  deleted the tree under them mid-copy. The loop now runs in the harness's own shell, and a lost
  row is printed instead of omitted; a silently missing row is the same defect class as an
  unreproducible count. The table below is one run of that script; reproducing a row is running
  `sh tests/driver/mutants.sh <id>`.

## Amendments (2026-08-20 — eighth implementation review)

The eighth independent review confirmed the seventh round's fixes and closed the
publication-proof family for good: four consecutive rounds (R4→R7) found no remaining bypass
of the completion proof in the code as it stands. Its blocker sat somewhere new — on the
profile's founding invariant itself.

- **The wall is now measured on the write-set (R8-B1).** The driver checked every formal
  property of a phase's output — commits, prefixes, tracker references, statuses, the Log's
  shape — but never **which paths** the phase touched. The review's fixture: the Final
  Reviewer edits `src.txt`, self-approves, and the flight ends `rc=0 status=DONE
  pushed_refs=1` — reviewer-authored code, published, that no independent family ever judged.
  Worse than unverified, it was permitted by construction: the default reviewer policy is
  `acceptEdits` over the whole repository. The fork was decided with the operator
  (2026-08-20): enforce **three edges** mechanically, rather than declare the wall procedural
  in v1 and lean on the human who promotes the draft PR. After every attempt the driver
  measures the write-set — the `git diff` between the phase snapshot and `HEAD`; the
  clean-tree backstop makes that diff the attempt's whole write-set — and refuses: a reviewer
  (3/5/7/9) that touched anything besides the testplan and the plan, a Test Writer (4) that
  touched anything besides test paths and the testplan, an Implementer (8) that touched a
  test path. A refusal is a **failed attempt** — reset to the snapshot, retry, ladder, stop —
  so a violating edit never survives into the flight, and the refusal names the role and the
  path. No general ACL mechanism: three edges, and nothing else. *(The ninth review disproved
  the "nothing else": phases 2 and 6 had no edge at all — see Amendments 2026-08-21, ninth
  review. The wall now carries an edge for every dispatched phase.)*
- **What counts as a test path is a project fact — so it is versioned config, not driver
  code.** The paths live in `.ai/wall.env` (`AP_WALL_TESTS`): entries `dir/` (prefix),
  `*suffix`, or an exact path, parsed like the machine binding — strict grammar, fail-fast —
  and **fail-closed** both ways: no `wall.env`, no takeoff; a path git has to quote is
  refused, never guessed. `models.env` was rejected as its home (a repository fact in a
  gitignored machine file — two machines could silently enforce different walls) and so was
  `kit.json` (JSON read with sed is the exact pattern this same review criticized).
- **The permission policy does not carry the wall — and now says so.** Restricting
  `AP_CLAUDE_ARGS` so reviewers cannot write outside `.ai/plans/` was considered and
  dropped: every reviewer needs the shell (phase 9 runs the full suite, typecheck, lint),
  and a session with a shell can write anywhere regardless of the edit-permission surface —
  a path-scoped policy would be a fence with an open gate, and the argument grammar
  deliberately cannot even express one. Enforcement lives in the driver's own measurement,
  harness-independent; the policy stays what it is, a sandbox default.
- **`green-whole-file` was a live mutant, not an equivalent survivor (R8-M2).** The seventh
  round's explanation claimed the mutant strictly more refusing than the shipped predicate;
  the review disproved it with a re-entry fixture — a stale in-Log row still last, the new
  row inserted *above* the Log heading. Current code refuses (phase 8 added no new **in-Log**
  row); the mutant counts the outside row as new and publishes on the stale proof. The
  explanation below is withdrawn, the exact fixture is now a behavior scenario, and the
  mutant is killed instead of explained.

The wall is the **eighth safety property** of the partition below, with its own mutants: the
check disabled, each of the three edges disabled, each entry form (prefix, suffix) disabled,
the quote-refusal disabled, the config made optional — and, on the harness side, the review's
own one-line actor mutant (the default final review appends a line to `src.txt`), which
previously survived the whole suite and now fails it wholesale.

## Amendments (2026-08-21 — R8-M1: the completion proof leaves the Markdown)

The eighth review's last open finding (R8-M1) was a contradiction, not a bypass: phase 8's
proof had to be the testplan's **last non-blank line**, yet the same contract makes the Log
append-only and instructs phase 9 — like every gate — to append its notes there. The design
held together only because the entry check runs before phase 9's own writes: any stop between
phase 9's Log commit and the end of the flight left an artifact that refused re-entry
(`-s 9`: "the GREEN row is not the last non-blank line") and that the repair section's own
rules — never delete an entry, never write past the last line — could not repair; the only
exit was rerunning a whole implementation phase for nothing. The symmetric defect was the
fourth round's residual: the row is forever, so a cold `-s 9` after manual code commits could
ride a proof whose code had changed underneath it. Both defects share one root: an
append-only text file cannot host a positional proof.

The fork was decided with the operator (2026-08-21): the proof moves to a **commit** — the
one construct nothing can be written after — and the **driver writes it**, not the
Implementer. When the driver accepts phase 8 (verdict, backstops, wall, per-commit audit all
passed) it commits an **empty acceptance stamp** whose trailer block carries
`Autopilot-Green: <feature> <sha>`, with `<sha>` the accepted phase-8 tip — the stamp's own
parent, so a stamp transplanted elsewhere in history proves nothing. Phase 9's entry walks
first-parent history from `HEAD` toward a stamp (bounded: `AP_MAX_PROOF_WALK`, default 64):
every commit before the stamp must have touched **nothing but the two flight artifacts**; a
merge, a quoted path, any other path, or an exhausted bound refuses with the commit named.
Trailers are read back with `git interpret-trailers --parse` — the porcelain parser — so a
lookalike line in prose or in the Log proves nothing; and the key is **reserved**: any commit
a phase produces whose trailer block carries it fails the attempt. An Implementer-written
trailer was rejected at the fork: a driver crash between the model's commit and the driver's
checks would leave a trailer in history that no wall ever measured — the stamp must attest
the **driver's acceptance**, not the model's claim, and it exists only if every check passed
(a crash before it leaves no proof: fail-closed, rerun `-s 8`). A gitignored state file was
rejected too: it would reopen R3-B3 — the proof must travel with the branch.

What this dissolves: phase 9's notes no longer consume the proof (artifact-only commits walk
through — the false refusal above is gone), one manual **code** commit past the stamp now
refuses a cold `-s 9` (the code-drift half of the round-4 residual; its plan-rewrite half
survives the walk by design — the walk is transparent to artifact commits — and returns to
the residual list below, per the ninth review's R9-3), and the Implementer's GREEN row in the Log
becomes what it always looked like — the narrative record, every positional instruction
deleted from the chapter, the template, and the phase-8 prompt. The Log's **shape guard**
stays in full (one canonical heading, last section, no open containers, refuse-not-guess): it
now guards the append interface every phase relies on, and entries 8 and 9 still refuse a
malformed Log. The GREEN scanning in the reader — the canonical-row regex, the row count, the
last-line bit — is deleted outright, along with the battery of row-hiding scenarios it
required; their successors pin the stamp instead (no text authorizes phase 9; the walk
survives artifact appends and refuses code commits, transplants, prose lookalikes, merges,
and the bound; the reserved key is refused on producer and reviewer commits alike).

## Amendments (2026-08-21 — ninth review: the wall covers every dispatched phase)

The ninth review was an exit review: a judgment on the declared perimeter — the eight safety
properties, the mutation table, the declared gaps — rather than an open hunt. It confirmed
the whole completion-proof family (suite re-run, the eight proof/stamp mutation rows
re-measured exactly, every R8-M1 claim checked against code and template) and found the
eighth round's own property incomplete on a side no round had considered:

- **The producer phases had no edge (R9-1, blocker).** `wall_ok`'s selector exempted phases 2
  and 6 outright, on the recorded — and wrong — theory that their artifact backstops already
  pinned them: the backstops check the artifact, never the write-set. The review's fixture
  needed no `-s` and no operator: a routed flight in which phase 6, after the test gate,
  replaces the gated RED tests with a vacuous assertion — which phase 9's full-suite run then
  *certifies*: `DONE`, pushed, zero refusals. That is the founding invariant (no artifact
  judged by the family that produced it) broken in the normal flow. The wall now carries an
  edge for every dispatched phase: the TestPlan Designer (2) writes only the testplan, the
  Handoff Planner (6) only the plan and the testplan; the exempting selector is gone. The
  eighth round's "three edges, and nothing else" is superseded — the "nothing else" was the
  hole. Eight rounds missed it for a structural reason worth recording: no mutant can exist
  for an edge that does not exist.
- **The Implementer could rewrite its own judging criteria (R9-2).** Phase 8's edge refused
  only test paths; the gated plan and the design record — the two documents phase 9 judges
  the implementation against — were writable, and `artifact_ok 8` pins their statuses and
  Gate row, never their content. Alone this is bounded (the RED tests still constrain the
  code); compounded with R9-1 nothing mechanical survives — phase 6 neuters the tests, phase
  8 rewrites the criterion. The edge now also refuses the plan and the design record: the
  Implementer's only artifact write is the testplan Log, exactly what the chapter always
  stated.
- **One closure was overstated (R9-3).** The R8-M1 amendment declared the round-4 residual
  closed; only its code-drift half is. The residual's own named scenario — a plan rewritten
  after the stamp, then a cold `-s 9` — still rides the previous implementation's stamp,
  because the proof walk is deliberately transparent to artifact-only commits. The claim is
  reworded above and the surviving half returns to the residual list below: it needs a
  deliberate `-s 9` (the routed path re-runs phase 8 after any plan rewrite), so it is
  recovery surface, not a publication defect.

The two new edges and the narrowed phase-8 edge are pinned like the rest of the wall:
behavior scenarios shaped like the review's own fixtures (phase 6 rewriting the gated tests
inside a full routed flight; phase 2 committing code; phase 8 rewriting the plan and the
design record) and one mutant per edge — `wall-planner-edge`, `wall-designer-edge`,
`wall-implementer-plan-edge` — in the re-measured table below.

Re-measuring exposed one interaction inside the harness itself: the retry-hygiene scenario's
retry committed with `git add -A`, and under the new phase-2 edge that commit — now carrying
the surviving leftover — was refused by the wall, whose snapshot reset then removed the
leftover that `git clean` had been the only remover of. `retry-clean` briefly measured 0 — a
survivor made, not found. The scenario now commits only the testplan, so the leftover stays
untracked and only the clean path can remove it; the mutant is killed again, by exactly the
line it was written to pin.

### What the behavior suite is a safety case for

Mutation testing over a 780-line script does not converge: a survivor exists for every line no
assertion pins, so each round can produce a fresh table indefinitely. The suite is therefore
declared complete against **eight safety properties**, each of which must carry at least one
mutation-killing assertion: publication integrity (which since R8-M1 includes the completion
proof — the acceptance stamp, its walk, and the reserved trailer key), entry preconditions,
caps and routing,
terminal state and lock, configuration fail-fast, report honesty, audit grammar and workspace
hygiene (added in the seventh round: every commit of a phase carries the semantic prefix and
the tracker reference; a failed attempt leaves nothing behind for the retry), and — added in
the eighth round, completed in the ninth — the **hard wall** (an edge per dispatched phase:
reviewers write only the two flight artifacts, the TestPlan Designer only the testplan, the
Handoff Planner only the plan and the testplan, the Test Writer only test paths and the
testplan, the Implementer neither a test path nor the plan or design record; the wall config
is fail-closed). Survivors outside those eight are recorded here as known-unprotected lines,
not as open findings.

One property named by the seventh review is deliberately **outside** this partition: artifact
inertness across `/switch-profile`. It is a kit-level rule carried by the chapters and by
`/switch-profile`'s refusal to move a testplan in flight, not by the driver — the driver never
reads a foreign-profile artifact, because a flight requires a fresh feature name. `verify-kit`
does not check it either, and no mutant here can. It belongs to the kit's own review surface.

Mutation evidence, all against the current suite — **345 assertions**, 0 failures unmutated
— produced by `tests/driver/mutants.sh` (one exact sed program per row; the two `actor-…`
rows mutate the test actor instead of the driver):

| Mutant (`tests/driver/mutants.sh` id) | Property | Failures |
|---|---|---:|
| `harness-one-family` | entry/dispatch | 96 |
| `stamp-not-written` | publication | 47 |
| `actor-final-review-writes-code` | hard wall | 46 |
| `entry9-log-shape` | entry | 34 |
| `wall-check-off` | hard wall | 31 |
| `log-tail-ignored` | publication | 22 |
| `proof-vacuous` | publication | 16 |
| `log-tail-setext` | publication | 15 |
| `wall-reviewer-edge` | hard wall | 8 |
| `log-tail-atx` | publication | 7 |
| `nonce-check` | entry | 7 |
| `wall-implementer-edge` | hard wall | 6 |
| `flightenv-unvalidated` | config fail-fast | 6 |
| `log-fence-transparent` | publication | 5 |
| `reserved-key-off` | publication | 5 |
| `nul-rejection` | entry | 5 |
| `route-plan-to-2` | routing | 5 |
| `lock-release` | terminal state/lock | 5 |
| `report-journey` | report honesty | 5 |
| `wall-implementer-plan-edge` | hard wall | 5 |
| `log-fence-infostring` | publication | 4 |
| `log-html-allowed` | publication | 4 |
| `phase2-log-shape` | publication | 4 |
| `publication-clean-tree` | publication | 4 |
| `nontrivial-existence` | entry | 4 |
| `lock-acquire` | terminal state/lock | 4 |
| `commit-prefix-grammar` | audit/hygiene | 4 |
| `wall-planner-edge` | hard wall | 4 |
| `log-fence-length` | publication | 3 |
| `log-atx-max-six` | publication | 3 |
| `log-comment-not-opaque` | publication | 3 |
| `proof-walk-any-path` | publication | 3 |
| `ladder-before-primary` | entry | 3 |
| `wall-test-writer-edge` | hard wall | 3 |
| `wall-designer-edge` | hard wall | 3 |
| `retry-clean` | audit/hygiene | 3 |
| `log-indented-atx` | publication | 2 |
| `artifact8-proceed` | publication | 2 |
| `proof-any-parent` | publication | 2 |
| `proof-merge-allowed` | publication | 2 |
| `proof-unbounded` | publication | 2 |
| `entry3-adr` | entry | 2 |
| `entry7-adr` | entry | 2 |
| `entry8-log-shape` | entry | 2 |
| `edge-cap-off-by-one` | caps | 2 |
| `wall-prefix-entry` | hard wall | 2 |
| `wall-suffix-entry` | hard wall | 2 |
| `wall-quote-guard` | hard wall | 2 |
| `report-counters` | report honesty | 2 |
| `artifact4-shape` | publication | 1 |
| `artifact8-shape` | publication | 1 |
| `proof-body-grep` | publication | 1 |
| `push-by-name` | publication | 1 |
| `wall-env-optional` | hard wall | 1 |
| `report-verdict` | report honesty | 1 |
| `cleanup-arm` | terminal state/lock | 0 — survivor |
| `actor-ladder-scope` | (test harness) | 0 — survivor |

Two mutants survive, and each is a statement, not an omission:

- **`cleanup-arm`** — the `RUNNING` → `STOPPED` conversion on an abnormal exit: the declared gap
  below, unchanged.
- **`actor-ladder-scope`** — the test actor's per-invocation ladder ordering. The sixth round
  recorded 2 failures for it; the harness measures 0, and the reason is structural rather than a
  regression: a producer dispatch always separates two reviewer dispatches, so the unscoped
  `PREV` is never a model in the running phase's allowed list and the rank check never fires.
  It is a **harness** invariant — it exists to keep a legitimate re-entry from being read as a
  rank decrease (a false failure), not to catch a driver defect — and no current scenario
  distinguishes it. Recorded here rather than renumbered silently.

`green-whole-file` — the eighth round's re-litigated row-count mutant — no longer exists: the
ninth round (R8-M1) deleted the row count itself along with the positional proof it guarded,
so the mutant, its fixture, and the two rounds of argument about its equivalence retired with
the code they measured. One mutant earned its row the honest way in the eighth round and
keeps it: `wall-suffix-entry` initially survived because `wall_is_test` expanded the entry
list unquoted, handing `*suffix` entries to the shell's globber — matching whatever files
happened to exist instead of the entry itself. The matcher now walks the list as a string,
and the scenario plants a root file the glob would have eaten, so the survivor was a live
defect found by its own mutant.

Known residuals and declared gaps:

- ~~A *direct* `-s 9` can still ride an earlier attempt's in-Log row~~ — closed by R8-M1: the
  proof walk refuses any code commit between `HEAD` and the acceptance stamp.
- A cold `-s 9` after a plan rewrite still rides the previous implementation's stamp (the
  surviving half of the round-4 residual, restored by R9-3): the proof walk is deliberately
  transparent to artifact-only commits, so rewriting the plan does not invalidate the stamped
  implementation — phase 9 then judges old code against a new criterion. Reaching it requires
  a deliberate `-s 9`; the routed path re-runs phase 8 after any plan rewrite, so this is
  recovery surface, like the `-s 2` entry below.
- A direct `-s 2` relaunch aimed at a **historical** feature overwrites its artifacts (R8-M3):
  the fresh-name check of extended inertness lives in `/fly`, the only entry of a *new*
  flight, and the driver cannot tell a stopped flight from a closed one — it only sees that
  the phase's entry precondition holds. Accepted as manual-recovery surface only: `-s` exists
  for an operator amending a stopped flight, and reaching a historical feature needs that
  operator to aim it there deliberately (a leftover — or hand-written — gitignored
  `flight.env`, which `/fly` would never write for a non-fresh name). The driver is unchanged.
- The window between the driver's last pre-push check and git's own refspec resolution.
- The Log reader is bounded by enumeration (above): a Markdown construct it does not model is
  refused, not read — the failure mode is a stopped flight the operator can fix, never a
  misread Log.
- `cleanup`'s `RUNNING` → `STOPPED` arm has no faithful injection: an untrapped fatal signal
  terminates the shell **without** running the EXIT trap, and every in-driver exit path after
  `RUNNING` is written goes through `stop_flight`, which writes its own terminal status. So the
  arm only fires for a shell-level abort no test can produce without mutating the driver. What
  *is* tested is everything around it: the lock is exclusive, it is released after DONE, after
  STOPPED and after an interruption, and `SIGTERM` mid-flight leaves `STOPPED` and nothing
  pushed. That scenario carries no timing assumption either: the stub holds the driver in the
  foreground until the test has sent the signal — a trap runs only after the foreground child
  returns — so the ordering is explicit instead of a race against a fixed sleep.

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
(ADR-0007 mechanics), then the operator. An end-of-phase artifact check and an event-log
scan back it up against mid-session degradation. Nothing in the mechanism names a model, so
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
successful flight ends with a push, a draft PR against `develop`, and the tracker issue
moved to review with PR and issue cross-linked. Promotion from draft, merge, and issue
closure stay human; a personal post-merge command outside the kit cleans up. A stopped or
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

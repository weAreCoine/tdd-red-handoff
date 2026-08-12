# A tier substitution is recorded, not applied

Both chapters opened the same way: check that the session's model matches your role's row in the
roster, and *"if it doesn't, say so and stop rather than working on the wrong tier."* That
sentence assumed a mismatch could only be an accident — the wrong session, the wrong window. It
had no branch for the case that actually happened: the tier is **unavailable**. A weekly quota
runs out, access is revoked, a provider has an outage; the roster still names the tier the project
wants, the user has nothing better, and the work has to continue anyway.

Left as written, the kit's answer to that is to refuse. What follows in practice is worse than a
refusal: the user overrides the contract verbally, the session works below tier with no trace, and
a rule the rest of the kit relies on gets normalized as ignorable.

## The substitution is state, so it lives in the roster — beside the table, not inside it

A substitution is not a new lineup. The roster's `Current model` cell answers *which tier does this
project want for this role*; overwriting it to silence the check would answer a different question
and destroy the first — leaving no record that a design decision was taken below the tier the
project had chosen. So the cell stays, and a prose block under the table (`### Tier substitutions
(temporary)`) records what is actually running, since when, until what lifts it, and why.

Prose, not a fourth column, and not a second table. `verify-kit`'s `roster_models()` extracts the
**last cell** of every table row under `## Model Roster`: a `Fallback` column would silently become
"the models", and the name in `Current model` would stop being guarded — a green run checking the
wrong thing. The prose block is invisible to that extraction, which was verified by comparing the
extracted set before and after.

## The check keeps its teeth by inverting the default

The chapters no longer stop unconditionally; they stop **unless** the roster records a substitution
for that role and this session's model is the substitute. The authority moves to a written project
fact instead of the user's word in a session, and the agent may never write that fact on its own —
an unavailable tier is a fact only the user can report, and only they can judge the work worth
doing without it. This is the same doctrine as `/update-models-roster`: model facts come from the
user, never from an agent's memory.

## Per-artifact record, because the cost is per-artifact

Project-level state says what is running *now*; it is deleted when the quota returns. What a
post-mortem needs months later is the tier a specific design was produced on, so the plan header
carries a substitution row and the testplan Log takes a per-phase note. Those are records, not
references — the reason `.ai/plans` is deliberately outside `verify-kit`'s model-leak scan.

## Consequences

The two-role chapter's *"no escalation ladder"* rationale is corrected, not merely reworded: it read
as a statement about ranking that quietly assumed availability too. Being the top of the roster and
being reachable are different properties, and only the first one holds unconditionally. Under a substitution
there is no rung above either, so the chapter asks for explicit design assumptions and deferral of
architectural decisions where deferral is possible.

The pipeline's four escalation triggers keep firing with no top rung to escalate to: 1–3 run on the
substitute and are logged with their trigger number, 4 (ADRs and `/init-architecture`) is the one to
defer. The sharpest consequence is structural: when the substitute *is* the reviewing role's model,
Design and gate collapse onto one model and the gate stops being verification against a reference by
a different model. The chapter now names that and downgrades the weight of an `APPROVED` reached
that way, rather than letting it read as a normal pass.

`verify-kit` is unchanged: the invariants it enforces are untouched by this: no new concrete names
outside the two allowed locations, no markers in the chapters, the extracted roster set identical.
Installed projects need `/update-kit` to receive the amended chapters and templates.

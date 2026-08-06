# Both `two-role` and `pipeline` are first-class profiles

The kit's two-role assetto (Architect + Implementer) and its four-role pipeline (Designer /
Test-Writer / Verifier / Implementer) both stay supported and both stay maintained: a new
project picks one at install time rather than inheriting the newest one.

The selection criterion is the **stakes of the work**, plus the friction the pipeline imposes:
five fresh sessions and two handoff artifacts per feature earn their keep on code that holds
real data, and cost more than they return on a small or throwaway change.

Crucially, that judgement is made **per task, not once per project**. The same repository
runs `two-role` for a quick fix and `pipeline` for a feature that touches money. Switching is
therefore a routine, bidirectional, everyday operation — not a migration — and must be cheap
enough to do without thinking about it.

## Consequences

Every future change to shared process text must land in both profiles, and this repo has no
CI to catch divergence. That cost is the reason the template layout deliberately minimises
duplicated surface (ADR-0002). The invariant `grep -nwiE 'architect' .ai/templates/*.md`
must be re-scoped: "architect" is legitimate vocabulary again, but only inside the two-role
role chapter.

Because switching is routine, artifacts of the other profile are never destroyed or rewritten
on a switch: `{feature}.testplan.md` files simply go inert under `two-role` and become live
again on the way back.

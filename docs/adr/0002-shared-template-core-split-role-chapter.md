# One shared core; only the process chapter is per-profile

Measured across the two branches, the profiles share ~94% of their template text verbatim
(600 of 639 lines): `PROJECT_ARCHITECTURE.template.md` differs by 3 lines, `AGENTS.template.md`
by 4, `plan_template.md` by 8. The real divergence is one thing: the roles-and-phases chapter.
So the kit ships **one** of every file except that chapter, which exists once per profile as a
ready-to-use process chapter (no fill markers) in `.ai/process/`.

Everything else is made **profile-agnostic** rather than branched:

- phases are referenced by name ("the review phase"), never by number — the two profiles
  number them differently, and a number is what made `PROJECT_ARCHITECTURE.md` and
  `plan_template.md` profile-bound in the first place;
- the Model Roster carries the union of all roles the kit knows; the active profile uses the
  subset it needs;
- `AGENTS.md` names its counterpart neutrally ("the design side, governed by `CLAUDE.md`") and
  treats the `Gate:` line as conditional. This one matters twice over: `AGENTS.md` is read by
  an external implementer agent that has no import mechanism, so it must never need swapping;
- `plan_template.md` carries `Source testplan` and `Gate` as optional rows.

## Considered options

- **Two duplicated trees** (`.ai/templates/two-role/`, `.ai/templates/pipeline/`) — readable,
  but ~600 lines to keep aligned by hand with no CI. Rejected.
- **Inline `[[DECISION: profile]]` branches in shared files** — rejected once ADR-0001 fixed
  that switching is per-task: `[[DECISION]]` markers are resolved *once at init and deleted*,
  so a branched file would need re-resolving on every switch, which is exactly the agentic
  rewrite ADR-0003 exists to avoid.

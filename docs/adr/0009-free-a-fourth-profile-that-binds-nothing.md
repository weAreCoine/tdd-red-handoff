# `free`: a fourth profile that binds no role, phase, wall or TDD order

An operator running the kit in a target project wanted to try other ways of working — with
Claude Code, with another agent CLI — for a while. The three profiles all bind roles, phases,
the hard wall and the TDD order, and the kit offered no way to step outside that without
breaking something: editing a chapter fails `verify-kit` (chapters ship verbatim), replacing
the `CLAUDE.md` shell throws away the project facts and the shared sections, and a hand-kept
second `AGENTS.md` for the other tool drifts the moment one file is updated and the other is
not. None of those has a clean way back. Decided 2026-09-08 (COINE-81).

## A profile, not a switch-off

`free` is a **fourth profile** in every mechanical sense: a chapter file, a legal value of the
manifest's `profile` field, the same triad (`kit.json` ↔ line-1 import ↔ chapter file name).
That choice buys the whole existing machinery for nothing: `/switch-profile` enters and
leaves it, `/show-profile` reports it, `kit-manifest` verifies it, `/update-kit` installs its
chapter into older projects. A "kit disabled" flag would have needed all of that written a
second time, and would have had no place to state what *still* binds.

The chapter is small and declarative. Under `free` nothing of the method is imposed — no role,
no phase, no wall, no TDD order, no roster model check — and everything below line 1 of
`CLAUDE.md` plus the facts contract in `.ai/PROJECT_ARCHITECTURE.md` stays binding. The other
three chapters are named by file name as reference material, applied only on the operator's
explicit request. The chapter uses no role name, so the `chapters` vocabulary greps keep
telling the four chapters apart. The name `free` is lexically disjoint from the other three,
for the reason ADR-0008 gave for `autopilot`: the couplings are exact-string greps.

## Entry and exit only through `/switch-profile`

`free` is a per-task deviation from a method the project already has, so `/init-architecture`
installs four chapters but still offers three profiles: a fresh project starts on a method.
Entering `free` obeys the refusal rules of entering `two-role` — an in-flight testplan asks
for confirmation, a `RUNNING` flight refuses outright — because `free` has no role that
continues anything. Under it `.ai/plans/` is inert in full (extended inertness) and never
written: that directory keeps meaning "produced by a profile with roles".

## One instruction file for every tool: `AGENTS.md → CLAUDE.md`

Under `free` the design side and the implementer read one and the same file. The switch makes
`AGENTS.md` a symlink to `CLAUDE.md` — always in that direction in targets, because the real
file is the one that carries the line-1 import and the shell below it. Two tools reading one
inode cannot drift.

The kit repo's own arrangement (commit `6943c06`: `CLAUDE.md → AGENTS.md`) points the other
way. That is this repository's convenience for serving its own instructions, unrelated to
targets, and it stays as it is.

## The implementer contract is parked, versioned — never deleted, never regenerated

The `AGENTS.md` a target holds is not the template: it was filled at init and possibly edited
since. Deleting it on entry and re-instantiating it on exit would lose those edits silently.
So the switch **moves** it, as a tracked move, to `.ai/AGENTS.parked.md` — versioned, so it
survives a clone, a branch switch and a machine change — and moves it back on the way out.

Both directions fail closed. Entering `free` stops when a parked file already exists or when
`AGENTS.md` is already a symlink: an earlier parked contract is never overwritten. Leaving
`free` stops when the parked file is missing: the kit never regenerates `AGENTS.md` from the
template on that path; the user recovers the file from git and reruns.

## `free-shape` is the mechanical guarantee

The commands are executed by a model; what pins their outcome is `verify-kit`, not their
text (ADR-0006). A new target-mode check, `free-shape`, is reported whenever the manifest
exists: under `free`, `AGENTS.md` must be a symlink resolving to `CLAUDE.md` and
`.ai/AGENTS.parked.md` a regular file; under any other profile `AGENTS.md` must be a regular
file and no parked file may exist. A half-done switch in either direction is a FAIL that names
the leftover. The check has its own behavior suite, `tests/verify-kit/run.sh`, on disposable
fixtures — the first test surface for the script's target mode.

## No convention for the method under test

The chapter deliberately proposes nothing about where the experiment's own instructions live:
that is the operator's choice, and the kit does not want to know. It states one warning — do
not write the method under test below line 1 of `CLAUDE.md` — because text added there would
follow the project back into the other profiles and the switch back would stop being a
one-line operation.

## Consequences

The profile vocabulary is four values everywhere it is enumerated: the commands, the
README, the glossary, the plugin description. The installed kit file set is six files
(`install-files`, `/update-kit`, the `verify-kit` messages). `/fly` needs nothing: it already
refuses unless the manifest says `autopilot`. The doc templates and the per-feature templates
are untouched, as are the driver and its suite. Installed projects receive `free.md` through
`/update-kit`; the plugin version moves to 1.6.0 in its own `chore:` commit.

# Process chapter — `free` profile

> This file is the chapter of the **free** profile. It ships verbatim with the kit: it carries
> no fill markers and no project facts, and a target project never edits it. Switching profiles
> repoints the import on line 1 of `CLAUDE.md` and the `profile` field of `.ai/kit.json` —
> and, for this profile only, parks the implementation-side contract (see below). Project facts
> live in `.ai/PROJECT_ARCHITECTURE.md`; the shared process sections and the project overlay
> follow this import in `CLAUDE.md`.

## What this profile is

Under `free` **nothing of the kit's method is imposed**: no role, no phase, no wall between
whoever writes tests and whoever writes application code, no TDD order, no roster model check.
Do not go looking for a role to play — there is none. The session works the way the operator
asks it to, in this conversation, and that is the whole contract.

The profile exists so that an operator can try other ways of working — with Claude Code, with
another agent CLI, with anything else — for a while, without uninstalling the kit and without
editing any file the kit ships. It is entered and left only through `/switch-profile`, like every other
profile change, and it is a per-task deviation from a method the project already has: a fresh
project never starts on it.

## What stays binding

- **Everything below line 1 of `CLAUDE.md`.** The shared process sections and the project
  overlay are identical under every profile, and they still apply here in full: test
  philosophy, architecture and layer rules, conventions, traps, coverage targets.
- **The facts contract.** `.ai/PROJECT_ARCHITECTURE.md` is read in full before working: stack
  and exact versions, the toolchain commands, the layer map, the API contract, the secrets
  boundary. Whatever method is being tried, it runs on the real project.
- **One instruction file for every tool.** Under this profile `AGENTS.md` is a symlink to
  `CLAUDE.md`, so every tool that reads either file reads the same text. The contract `AGENTS.md`
  normally holds is parked, versioned, at `.ai/AGENTS.parked.md`; `/switch-profile` puts it back
  on the way out. Do not edit the parked file and do not replace the symlink with a file.

## What is not imposed, and how to borrow it deliberately

The other three chapters — `two-role.md`, `pipeline.md`, `autopilot.md`, all in
`.ai/process/` — stay installed as **reference material**. Nothing in them applies by default
under `free`. When the operator explicitly asks for one of their phases or rules ("run the
review checklist from `two-role.md`", "write the test inventory the way `pipeline.md` does"),
apply exactly what was asked, from the named file, and nothing more. Never adopt a chapter,
or a part of one, on your own initiative: borrowing is the operator's decision, every time.

## Artifacts

`.ai/plans/` is **inert** under this profile. Existing plans, testplans and design records are
historical records of the profile that produced them: read them when useful, never rewrite,
move, delete or retrofit them — no status change, no backfill, no stamp. Write **no new file**
there: that directory keeps meaning "produced by a profile with roles", and a session under
`free` is not one. Notes, drafts and plans for the method being tried live wherever the
operator decides, outside `.ai/plans/`.

## Where the method under test lives

This chapter proposes no convention for that: it is the operator's choice, and the kit does
not want to know. One warning only: **do not write the method under test below line 1 of
`CLAUDE.md`.** The shell below the import is identical under every profile by design; text
added there would follow the project back into `two-role`, `pipeline` or `autopilot`, and the
switch back would stop being a one-line operation. Keep the experiment in its own files.

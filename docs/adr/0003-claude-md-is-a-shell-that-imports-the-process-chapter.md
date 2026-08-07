# `CLAUDE.md` is a shell that imports the profile's process chapter

Switching profile must be near-free (ADR-0001: it happens per task). Today it is not: the live
`CLAUDE.md` mixes pure process with six spots of hand-authored project fact — the architecture
model and the concrete constructs that fulfil each layer, the trap list, the coverage floor, the
excluded test primitives, the doc sources. KeyFuture's is 259 lines and names `ErpClient`,
`app/Clients/`, ADR-0002, Filament and Livewire. Regenerating that file on every switch would
have a model rewrite hand-authored content weekly, and it would drift.

So `CLAUDE.md` becomes a shell: a single `@.ai/process/{profile}.md` import line, followed by the
project overlay (the six fact-bearing sections, which do not vary by profile and are therefore
never touched). Switching rewrites that one line and the `profile` field of `.ai/kit.json`. Both
process chapters are installed, so a switch is mechanical, offline, and lossless.

Claude Code's `@path` import is the enabling mechanism: relative to the importing file, up to
four hops, ignored inside backticks.

**Precondition — verified 2026-08-07.** The documentation states that a project-root `CLAUDE.md`
is re-read from disk and re-injected after `/compact`, but is silent on whether its imports are
re-expanded. Verified empirically in this repo with a blind-marker test: a throwaway
`@.ai/compact-import-probe.md` import on line 1 carried a random marker the model had never seen
(generated with `openssl rand` redirected straight to the file). After `/compact` the model quoted
the marker from context alone, and `/context` listed the probe among the loaded memory files —
imports **are** re-expanded after compaction. The design's worst failure mode (process chapter
vanishing mid-session) does not occur; the shell design stands.

The fallback, recorded in case the behaviour ever regresses, costs nothing structural: `CLAUDE.md`
becomes a **generated** file (`cat .ai/process/{profile}.md .ai/overlay.md > CLAUDE.md`), the
switch stays mechanical, one command, no model in the loop. Only the seam moves.

## Consequences

`CLAUDE.md` is no longer readable as a single self-contained file — the process half lives one
hop away. In exchange the kit finally honours its own stated rule that process files state no
project facts: the process chapter is 100% agnostic and ships verbatim, with no fill markers at
all, which also means it is the one file a target project must never edit.

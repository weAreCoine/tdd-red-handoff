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

**Unverified precondition.** The documentation states that a project-root `CLAUDE.md` is re-read
from disk and re-injected after `/compact`, but does not say whether its imports are re-expanded.
If they are not, the process chapter would vanish mid-session — the design's worst failure mode,
and a silent one. Verify empirically before building on it (add a throwaway import, `/compact`,
check `/context`). The fallback costs nothing structural: `CLAUDE.md` becomes a **generated** file
(`cat .ai/process/{profile}.md .ai/overlay.md > CLAUDE.md`), the switch stays mechanical, one
command, no model in the loop. Only the seam moves.

## Consequences

`CLAUDE.md` is no longer readable as a single self-contained file — the process half lives one
hop away. In exchange the kit finally honours its own stated rule that process files state no
project facts: the process chapter is 100% agnostic and ships verbatim, with no fill markers at
all, which also means it is the one file a target project must never edit.

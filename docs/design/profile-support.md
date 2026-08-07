# Profile support and plugin distribution — target state

The design agreed in the grilling session of 2026-08-06. Decisions and their reasons live in
`docs/adr/0001`–`0006`; this file is the shape they add up to and the order of work. Vocabulary:
`CONTEXT.md`.

## What changes, in one paragraph

`main` and `feature/multi-model-pipeline` stop being two branches and become two **profiles** of
one kit. A target project keeps a `CLAUDE.md` whose process half is a one-line import of
`.ai/process/{profile}.md`; switching profile rewrites that line and `.ai/kit.json`, and nothing
else. The kit itself stops being copied by hand and becomes a Claude Code plugin installed from
this repo.

## Kit repo layout

```
.claude-plugin/
  plugin.json            # name, version (authoritative kit version)
  marketplace.json       # this repo is its own marketplace
commands/
  init-architecture.md   # bootstrap; also absorbs the legacy-kit migration path
  switch-profile.md      # <two-role|pipeline>
  update-kit.md          # realign .ai/process + .ai/templates to the plugin version
  update-models-roster.md
.ai/
  process/
    two-role.md          # roles + phases, ships verbatim, no markers
    pipeline.md          # roles + phases, ships verbatim, no markers
  templates/
    CLAUDE.template.md            # the shell: import line + project overlay
    AGENTS.template.md            # profile-agnostic
    PROJECT_ARCHITECTURE.template.md  # profile-agnostic
    plan_template.md              # profile-agnostic
    test_plan_template.md         # used only under pipeline, but agnostic as a file
```

## Target project layout (all committed)

```
CLAUDE.md                     # @.ai/process/{profile}.md  +  project overlay
AGENTS.md
.ai/
  kit.json                    # { "profile": …, "kitVersion": … }
  PROJECT_ARCHITECTURE.md
  process/{two-role,pipeline}.md   # both installed, so switching is offline
  templates/{plan_template,test_plan_template}.md
  plans/                      # per-feature artifacts
```

The commands do **not** land in the target project — they serve the operator and live in the
plugin (ADR-0004).

## Switching

```
/switch-profile two-role
  → CLAUDE.md line 1:  @.ai/process/two-role.md
  → .ai/kit.json:      "profile": "two-role"
```

Nothing else is touched. `{feature}.testplan.md` files go inert under `two-role` and become live
again on the way back; they are never rewritten, moved, or deleted (ADR-0001).

**Refusal rule.** If any testplan is in flight — `Status` of `DRAFT`, `READY`, `RED` or
`REJECTED(n)`, with no implementation plan issued — the switch stops, names the feature and its
status, and asks for an explicit confirmation. Switching happens between tasks, so the refusal is
rare; when it fires it is protecting specification work that the destination profile has no role
to read.

## Making the shared files profile-agnostic

The one thing that bound shared files to a profile was **phase numbers** (`two-role`: 1 Analyze ·
2 Tests · 3 Plan · 4 Review — `pipeline`: 1 Design · 2 Transcription · 3 Gate · 4 Implementation ·
5 Review). Of 79 `Phase N` references in the repo, only 8 must go: 5 in `plan_template.md`, 2 in
`PROJECT_ARCHITECTURE.template.md`, 1 in `test_plan_template.md`. The rest sit inside process
chapters — where a number is legitimate, because the chapter *is* the profile — or inside
commands.

Alongside that:

- **Model Roster** carries the union of roles (Architect, Designer, Test-Writer, Verifier,
  Implementer); the active profile uses its subset.
- **`AGENTS.md`** names its counterpart neutrally and treats the `Gate:` line as conditional.
  This is non-negotiable: it is read by an external implementer agent with no import mechanism,
  so it must never need swapping.
- **`plan_template.md`** carries `Source testplan` and `Gate` as optional rows.

## Couplings: what happens to each

The nine in the root `CLAUDE.md` do not survive unchanged.

| # | Today | After |
|---|---|---|
| 1 | Migration detected by grepping `You are the **architect**`; templates must contain no `architect` | Detected by absence of `.ai/kit.json`; the grep re-scopes to `.ai/process/pipeline.md` only |
| 2 | `migrate-architecture.md` cites "template lines 6–8" | Dies with the command's absorption; replace with a content-based reference |
| 3 | Phase numbers hardcoded in 8 files | Confined to process chapters; agnostic files name phases instead |
| 4 | Escalation triggers 1–4 in `CLAUDE.template.md` | Move into the pipeline process chapter; README mirrors both profiles |
| 5 | Toolchain command names are an API | Enforced instead of asserted: contract-name rows carry the name verbatim in the table's first cell, so `verify-kit` can check it (ADR-0006) |
| 6 | `DRAFT → READY → RED → APPROVED/REJECTED(n)` shared verbatim | Pipeline-only vocabulary; shared files must not assume it |
| 7 | Layer vocabulary fixed | Unchanged |
| 8 | Model names only in the roster | Unchanged; roster becomes the union of roles |
| 9 | README mirrors everything | Must now cover two profiles and plugin installation |

One coupling is **new**: `kit.json`'s `profile`, the import line in `CLAUDE.md`, and the chapter
filename must agree. `/switch-profile` owns all three; nothing else may restate the active profile.

## Order of work

1. **Verify the `@path` import survives `/compact`** (ADR-0003). Everything downstream assumes it;
   the fallback is a generated `CLAUDE.md`, but it needs to be chosen before, not after.
   *Done 2026-08-07: blind-marker test passed, imports are re-expanded after compaction — no
   fallback needed (details in ADR-0003).*
2. **Build `verify-kit` first** (ADR-0006), in kit-repo mode: pin the checkable shape (contract
   names in the Toolchain table's first cell, a stable coverage-floor anchor), then write
   `bin/verify-kit.sh` and `/verify-kit`. Everything below rewrites eight of nine couplings on a
   Kit whose only verification today is twelve greps that disagree with each other — do this
   first and each later step is checkable, do it last and each one is merely believed.
   *Done 2026-08-07: shape pinned (contract names verbatim in the Toolchain first cells,
   `**Project floor**` anchors in both files), `bin/verify-kit.sh` + `/verify-kit` written;
   kit-repo mode passes on this repo, target mode exercised on synthetic installations
   (pre-profile drift FAILs as expected, kit.json triad and phase-number checks already active).*
3. **Extract `main`'s role chapter** into `.ai/process/two-role.md`. This is not a merge: the rest
   of `main` duplicates what the feature branch already has. Feature branch is the base.
   *Done 2026-08-07. Chapter = roles-and-phases only (ADR-0002); no § Escalation — decided with
   the user: the Architect already runs on the strongest roster tier, there is no model to
   escalate to. Three modernizations over `main`'s text, all forced by the no-facts rule:
   the implementer is referenced by role instead of by its concrete model name (roster
   discipline), test co-location → deferred to `PA § Testing`, doc/ADR paths → deferred to
   `PA § Documentation`. verify-kit gained the `chapters` check (no markers in
   `.ai/process/`, pipeline detection strings ready).*
4. **Extract the pipeline chapter** out of `CLAUDE.template.md` into `.ai/process/pipeline.md`;
   what remains becomes the shell (import line + overlay).
   *Done 2026-08-07. Chapter = Your Role, Artifacts & Status, the five phases, § Escalation
   (trigger 4 drops the migration command, absorbed at the commands step) and the
   Test-Philosophy binding note. The shell keeps the shared process sections (Toolchain
   pointer, Test Philosophy de-role-ified, Conventions) alongside the overlay markers —
   duplicating them per chapter would be the small version of the "two duplicated trees"
   ADR-0002 rejected. Line 1 of the shell is a FILL that becomes the profile import.
   verify-kit re-scoped: 'Test-Writer' and the no-'architect' rule now guard the pipeline
   chapter (chapters check), not the templates — the union roster names the Architect
   legitimately.*
5. **De-number and neutralise** the three agnostic files (8 sites), union the roster.
6. **Plugin packaging**: `.claude-plugin/`, move commands, `${CLAUDE_PLUGIN_ROOT}` references.
7. **Commands**: `/switch-profile` and `/update-kit` new; `/init-architecture` gains the
   legacy-kit path and writes `kit.json`; `/migrate-architecture` deleted. Every path in every
   command must be re-rooted to `${CLAUDE_PLUGIN_ROOT}` — the sharpest case is
   `/init-architecture`'s opening model check, which pre-init reads the roster from
   `.ai/templates/PROJECT_ARCHITECTURE.template.md`: under the plugin there is no `.ai/` in the
   target project yet, so that project-relative path resolves to nothing, silently.
8. **Rewrite the root `CLAUDE.md`** couplings section and the README (two profiles, plugin install,
   switching).
9. **Live projects** — *separate authorization, not part of this branch*: restructure KeyFuture and
   Paddock into shell + overlay; Paddock also crosses from the old kit. Both already carry copied
   `.claude/commands/*.md` from the old install — those become stale duplicates of the plugin's
   commands and must be deleted, not left to shadow them. This is work in two other repositories,
   one of which has a 45k facts file under active edit; it belongs to whoever owns those trees, on
   their say-so.

## Open

- Whether `two-role` gets escalation triggers of its own, or none — its process chapter is the
  only place that could hold them, and nothing forces the answer yet.

No unverified preconditions remain: the `/compact` import survival is verified (2026-08-07,
ADR-0003); `${CLAUDE_PLUGIN_ROOT}` in commands, and plugins carrying arbitrary directories, are
confirmed against the official `plugin-dev` reference.

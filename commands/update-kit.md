---
description: Realign this project's installed kit files (.ai/process chapters + per-feature templates) to the plugin's version and stamp kit.json's kitVersion — live docs, plans, and the active profile are never touched.
---

# /update-kit

Bring **this** project's installed kit files up to the plugin's version. The kit installs four
files into a target — `.ai/process/two-role.md`, `.ai/process/pipeline.md`,
`.ai/templates/plan_template.md`, `.ai/templates/test_plan_template.md` — and this command
replaces them with the plugin's current copies, then stamps `.ai/kit.json` `kitVersion`
(ADR-0005: `plugin.json` `version` is what the kit *is*, `kitVersion` is what was *installed*;
this command is the procedure that compares them). Everything the project authored —
`CLAUDE.md`, `AGENTS.md`, `.ai/PROJECT_ARCHITECTURE.md`, `.ai/plans/*` — is out of scope and
never touched.

> **No model check.** This command makes no spec decision: it compares versions, copies files,
> and runs checks. Any model tier can run it.

## Phase 0 — Preconditions

1. **Profile-aware installation.** `.ai/kit.json` exists. If not, there is nothing here to
   update: STOP and point the user to `/init-architecture` (a fresh init installs the current
   kit; a legacy or pre-profile install is upgraded by its Phase 0 routing).
2. **Versions.** Read `version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and
   `kitVersion` from `.ai/kit.json`:
   - Equal → report "already current" and STOP — do not rewrite files to their own content.
   - `kitVersion` is `"TODO"` → a pre-plugin install: proceed; this run stamps the first real
     version.
   - Plugin version **lower** than the stamp → the plugin cache is stale: STOP and tell the
     user to update the plugin first. Never realign a project backwards silently.
3. **Clean seam.** The four kit files and `.ai/kit.json` carry no uncommitted changes in git —
   the update should land as one reviewable diff. Dirty → show what is dirty and ask before
   proceeding.

## Phase 1 — Diff (read-only)

`diff` each of the four files against its `${CLAUDE_PLUGIN_ROOT}` counterpart and report per
file: **identical** or **changed** (one line on what changed). A local delta surfaces here too:
chapters and templates ship verbatim, so a hand-edit in the target is drift the update will
overwrite — show it *before* replacing it, never after. It stays recoverable from git, but the
user must see it exists.

## Phase 2 — Apply

1. Copy the four files from `${CLAUDE_PLUGIN_ROOT}/.ai/…` over the project's copies.
2. `.ai/kit.json` → `"kitVersion": "<plugin version>"`. The `profile` field is untouched —
   changing profile is `/switch-profile`'s job, and an update never switches profile.
3. **Pre-plugin installs only, once:** if `.claude/commands/` still carries copies of the kit's
   own commands (`init-architecture.md`, `migrate-architecture.md`, `switch-profile.md`,
   `update-kit.md`, `update-models-roster.md`, `verify-kit.md`), delete them — the plugin
   serves the commands now, and stale copies would shadow it. Touch nothing else in `.claude/`.

Nothing else is written.

## Phase 3 — Self-check

```bash
grep '"kitVersion"' .ai/kit.json   # must print the plugin's version
"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" -p "${CLAUDE_PLUGIN_ROOT}" .
```

The script's `install-files` and `kit-version` checks verify exactly what this update just did —
the four files byte-identical to the plugin's copies, the stamp equal to the plugin's version —
so a FAIL on either means the update itself went wrong. Do not reconstruct the comparisons by
hand: the script is their single source of truth (ADR-0006).

## Phase 4 — Report

- Old `kitVersion` → new.
- If the amended chapters mention a roster subsection this project's `PROJECT_ARCHITECTURE.md`
  does not have yet (`### Tier substitutions (temporary)`), say so and say it is benign: no
  substitution recorded is the normal state, and `/update-models-roster` creates the subsection the
  first time one is. This command does not touch live docs.
- Per file: replaced (what changed) or already identical; any overwritten local drift from
  Phase 1, quoted.
- The boundary, restated: live docs never change here. If the new kit version changed the
  **doc templates** (`CLAUDE.template.md`, `AGENTS.template.md`,
  `PROJECT_ARCHITECTURE.template.md`), those are instantiated at init, not installed — adopting
  such changes into the live docs is a deliberate re-init decision for the user
  (`/init-architecture`, re-init path), never a side effect of an update.

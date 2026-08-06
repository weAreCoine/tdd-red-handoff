# The kit is distributed as a Claude Code plugin

This repository doubles as its own plugin marketplace: `/plugin marketplace add
weAreCoine/tdd-red-handoff` followed by `/plugin install`. That satisfies the "one command, no
cloning, no copying files by hand" requirement without adding a package manifest, JavaScript, or
a publish pipeline to a repo that is otherwise pure Markdown — a new toolchain would be a
dependency decision in its own right, and the plugin route costs nothing but a git tag.

The split it implies: the **commands** (`init`, `switch`, `update`) live in the plugin, because
they serve the operator; the **artifacts** (`CLAUDE.md`, `AGENTS.md`,
`.ai/PROJECT_ARCHITECTURE.md`, `.ai/kit.json`, both `.ai/process/*.md` chapters, the plan
templates) are written into the target repo and committed, because they serve the project.
Plugin commands reach their own files through `${CLAUDE_PLUGIN_ROOT}` — verified against the
official `plugin-dev` reference: the variable is available *in commands*, not only in hooks, and
a command may `@`-import a plugin file directly (`@${CLAUDE_PLUGIN_ROOT}/templates/report.md`).
Plugins carry arbitrary directories alongside their commands and skills.

## Consequences

The kit only works from inside Claude Code — which is where it is used anyway, and is now a hard
dependency rather than a convention: `CLAUDE.md`'s `@path` import (ADR-0003) is a Claude Code
feature. Someone who clones a target repo gets the docs, the process chapters and the templates,
so the process is fully runnable; but to change profile or update the kit they must install the
plugin themselves.

npm names `tdd-red-handoff`, `create-tdd-red-handoff`, `tdd-kit` and `agents-config-template`
were checked and are free, should a terminal-side installer ever be wanted as a second channel.

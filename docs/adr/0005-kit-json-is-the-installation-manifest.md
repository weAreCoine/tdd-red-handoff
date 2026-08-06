# `.ai/kit.json` is the installation manifest

A target project records which profile it runs and which kit version installed it in
`.ai/kit.json` — the first non-Markdown file the kit ships, and the single source for both facts.

Before this, the only way to tell what a project was running was to grep its live docs. That
worked while `You are the **architect**` meant exactly one thing: *old kit, needs upgrading*.
With `two-role` a supported profile (ADR-0001), the same string also means *deliberately on
two-role, already current*, and the two are indistinguishable by content — a migration run
against the second would rewrite docs that are already correct. The version field carries the
other half: after the merge, "on two-role" no longer implies "up to date", because the profile
inherits shared improvements.

`plugin.json`'s `version` is authoritative for what the kit *is*; `kit.json`'s `kitVersion` is
the stamp of what was *installed*. `/update-kit` compares them.

## Consequences

Three facts must agree and are owned by `/switch-profile` alone: `kit.json`'s `profile`, the
`@.ai/process/{profile}.md` import line in `CLAUDE.md`, and the chapter file that line names.
Nothing else may restate the active profile.

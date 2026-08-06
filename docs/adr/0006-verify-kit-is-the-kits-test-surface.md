# `verify-kit` is the Kit's test surface

The Kit's invariants were enforced by prose: twelve hand-written self-checks spread across eight
files, using **six different regexes** for the same question — `'\[\[DECISION|FILL:'` in the doc
templates, `'FILL:|\[\['` in `PROJECT_ARCHITECTURE.template.md`, `'FILL:|\{[a-z-]+\}'` in the plan
templates, `'FILL:|\[\[DECISION'` in the commands. None identical, none runnable.

They now collapse into one POSIX shell module, `bin/verify-kit.sh`, shipped in the plugin and
called by every command's self-check phase and by a `/verify-kit` command of its own. Shell, not
Node: grep and sed cover every check once the data has a fixed shape, and a JavaScript toolchain
is precisely the dependency the plugin route (ADR-0004) was chosen to avoid.

## The prose adapts to the check, not the reverse

Probing a real installation showed Contract §1 — *"command names are an API"*, the Kit's
most-cited invariant — was already in drift inside itself: the Contract names `typecheck`,
`test (focused)`, `format:check`, while a live Toolchain table labels the same rows `Type-check`,
`Test (all)`, `Format (check)`. A human reconciles them by reading; a check cannot, and a check
that normalises labels until they match is guessing — the one behaviour the Kit forbids every
role. So Toolchain rows that are part of the contract now carry the **contract name** verbatim in
their first cell; informational rows keep human labels. The coverage floor gets a stable anchor in
both files.

## Green must mean something exact

Seven checks are mechanical: markers, contract names, coverage floor, model names outside the
roster, the `kit.json` ↔ import line ↔ chapter triad, phase numbers in the profile-agnostic files,
role vocabulary confined to its chapter. Three are not — §2 (the layer map describes the real
repo), §4 (vocabulary used correctly, as opposed to synonyms merely absent), §5 (the secrets
boundary is true, as opposed to stated). The module reports three states, listing what it did not
check rather than omitting it. A verifier that silently skipped what it cannot decide would commit
the same sin the Kit spends its whole surface forbidding: versions come from the lockfile, model
names come from the user, `TODO` beats a plausible guess.

## Consequences

The README called a verification script "a natural addition (intentionally left out here to keep
the flow simple)"; the profile work adds a seventh invariant and doubles the surface the greps
must cover, which is what reopens it.

On first run the module reports FAIL on §1 for both live installations, whose tables predate the
contract-name rule. That red is correct — it is the drift, made visible. Clearing it means editing
two other repositories, which is separate work on separate authorization.

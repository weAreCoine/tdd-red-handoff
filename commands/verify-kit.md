---
description: Run the kit's mechanical invariant check (bin/verify-kit.sh) and report its three-state output verbatim — never turn a FAIL green silently.
---

# /verify-kit

Run the Kit's test surface — one POSIX script, grep/sed only, no other dependencies (ADR-0006 in
the kit repo). No model requirement: this is a mechanical check, not a judgment task (escalation
trigger 4 does not apply).

## Run

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" -p "${CLAUDE_PLUGIN_ROOT}" .
                                              # the copy the plugin ships — works in any target;
                                              # -p adds the install-integrity checks
bin/verify-kit.sh                             # kit repo checkout: prefer the tree's own copy
                                              # (it is the version under edit; kit mode ignores -p)
```

- Mode is auto-detected: a live `.ai/PROJECT_ARCHITECTURE.md` → **target** mode (markers must be
  gone, contract names verbatim in the live Toolchain, one floor in two files, no model-name
  leaks); otherwise the templates → **kit** mode (markers must *survive*, detection strings
  intact, contract names pinned, model names confined to README + template roster).
- `-p <plugin-root>` (target mode) enables the **install-integrity** checks: the five installed
  kit files (`.ai/process/two-role.md`, `.ai/process/pipeline.md`, `.ai/process/autopilot.md`,
  `.ai/templates/plan_template.md`, `.ai/templates/test_plan_template.md`) byte-identical to the
  plugin's copies (`install-files`), and `.ai/kit.json` `kitVersion` equal to the plugin's
  `version` (`kit-version`, ADR-0005). Without `-p` — the script run by hand or in CI, where
  `${CLAUDE_PLUGIN_ROOT}` does not exist — those checks are listed under NOT CHECKED, never
  silently skipped.
- Override with `-m kit|target`; point it at another tree with a directory argument:
  `"${CLAUDE_PLUGIN_ROOT}/bin/verify-kit.sh" -p "${CLAUDE_PLUGIN_ROOT}" /path/to/project`.
- Do **not** reconstruct the checks by hand, whatever happens to the script: it is the single
  source of truth for them.

## Report

Paste the script's output **verbatim**, then:

- **FAIL lines** — explain each against the invariant it enforces (`PROJECT_ARCHITECTURE.md
  § Contract` in a target project; the couplings list in the kit repo's root `CLAUDE.md`).
  Propose the fix, but NEVER edit a file to turn a FAIL green without saying what changed and
  why: the prose adapts to the check only by deliberate decision, not silently.
- **NOT CHECKED block** — report it in full. It is part of the result: green means "the
  mechanical checks pass", never "everything is verified".
- **Exit code** — `0` no FAIL · `1` at least one FAIL · `2` not a kit tree / usage error.

A `contract-names` FAIL in a project installed before the contract-name rule is **expected drift
made visible**, not a script bug: the fix is relabeling that project's Toolchain first cells — a
change in that repository, on its owner's say-so.

The install-integrity FAILs come in two kinds, told apart by the version stamp — read the
check's own message before proposing a fix:

- **Versions differ** (`kit-version` FAIL, possibly `install-files` too): the plugin moved on
  since the install. Benign drift; the fix is `/update-kit`, which realigns the five files and
  restamps `kitVersion`.
- **Same version, bytes differ** (`install-files` FAIL alone): a shipped file was edited in the
  target. This is the serious case — chapters and per-feature templates ship verbatim.
  `/update-kit` restores the file; anything project-specific it carried belongs in the live
  docs (`PROJECT_ARCHITECTURE.md`), never in shipped files.

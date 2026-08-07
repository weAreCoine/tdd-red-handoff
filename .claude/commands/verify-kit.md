---
description: Run the kit's mechanical invariant check (bin/verify-kit.sh) and report its three-state output verbatim — never turn a FAIL green silently.
---

# /verify-kit

Run the Kit's test surface — one POSIX script, grep/sed only, no other dependencies (ADR-0006 in
the kit repo). No model requirement: this is a mechanical check, not a judgment task (escalation
trigger 4 does not apply).

## Run

```bash
bin/verify-kit.sh
```

- Mode is auto-detected: a live `.ai/PROJECT_ARCHITECTURE.md` → **target** mode (markers must be
  gone, contract names verbatim in the live Toolchain, one floor in two files, no model-name
  leaks); otherwise the templates → **kit** mode (markers must *survive*, detection strings
  intact, contract names pinned, model names confined to README + template roster).
- Override with `-m kit|target`; point it at another tree with a directory argument:
  `bin/verify-kit.sh /path/to/project`.
- If `bin/verify-kit.sh` does not exist here (a target project installed with
  `cp -r .ai .claude`, which does not ship `bin/`): tell the user to run it from the kit
  repository against this project — `<kit-repo>/bin/verify-kit.sh .` — and stop. Do **not**
  reconstruct the checks by hand; the script is the single source of truth for them.

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

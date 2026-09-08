#!/bin/sh
# tests/verify-kit/run.sh — behavior tests for bin/verify-kit.sh (target mode, plus the
# kit-mode chapter invariants that guard the free chapter).
#
# The seam is the script's command-line interface: its exit code and its
# PASS/FAIL/NOT CHECKED lines, addressed by check name. Each scenario builds a
# disposable directory shaped like a kit target (live docs, kit.json, the six
# installed kit files copied from this checkout) and asserts what the script
# reports for that shape — never how it computes it. No network, no model; the
# fixture roster names an opaque string, never a real model name (the
# model-roster check greps untracked files too).
#
# Exit 0 only if every assertion passes. TAP-ish output, one line per check.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/../.." && pwd)
VK=$KIT/bin/verify-kit.sh
BASE=$(mktemp -d "${TMPDIR:-/tmp}/verify-kit-tests.XXXXXX")
trap 'rm -rf "$BASE"' EXIT

KITVER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$KIT/.claude-plugin/plugin.json" | head -n 1)
[ -n "$KITVER" ] || { echo "cannot read the plugin version from $KIT/.claude-plugin/plugin.json" >&2; exit 2; }

PASSED=0; FAILED=0
chk() { d=$1; shift; if "$@" >/dev/null 2>&1; then PASSED=$((PASSED+1)); echo "ok   - $d"; else FAILED=$((FAILED+1)); echo "FAIL - $d"; fi; }
chknot() { d=$1; shift; if "$@" >/dev/null 2>&1; then FAILED=$((FAILED+1)); echo "FAIL - $d"; else PASSED=$((PASSED+1)); echo "ok   - $d"; fi; }

# A target fixture whose every check passes on its own: the scenarios then
# break exactly one shape at a time. $1 = name, $2 = profile -> T (its path).
make_target() {
  T=$BASE/$1
  mkdir -p "$T/.ai/process" "$T/.ai/templates" "$T/.ai/plans"
  for c in two-role pipeline autopilot free; do
    cp "$KIT/.ai/process/$c.md" "$T/.ai/process/" || exit 2   # a chapter missing from the checkout is not a fixture
  done
  cp "$KIT/.ai/templates/plan_template.md" "$KIT/.ai/templates/test_plan_template.md" "$T/.ai/templates/"
  printf '{ "profile": "%s", "kitVersion": "%s" }\n' "$2" "$KITVER" > "$T/.ai/kit.json"
  {
    printf '@.ai/process/%s.md\n\n# Project — fixture\n\n## Coverage Targets\n\n' "$2"
    printf '| Scope | Target |\n|---|---|\n| **Project floor** | **85%%** |\n'
  } > "$T/CLAUDE.md"
  printf '# Implementer contract — fixture\n\nThe implementation-side contract, as filled at init.\n' > "$T/AGENTS.md"
  {
    printf '# Project architecture — fixture\n\n## Toolchain\n\n| Name | Command |\n|---|---|\n'
    printf '| test | run-tests |\n| test (focused) | run-tests --filter |\n| typecheck | run-types |\n'
    printf '| lint | run-lint |\n| format | run-format |\n| format:check | run-format --check |\n| coverage | run-coverage |\n'
    printf '\n## Testing\n\n**Project floor:** 85%%\n\n## Model Roster\n\n'
    printf '| Role | Current model |\n|---|---|\n| Designer | roster-model-alpha |\n\n## Documentation\n\nnone.\n'
  } > "$T/.ai/PROJECT_ARCHITECTURE.md"
}

# Move the fixture into the shape a finished switch into free leaves behind.
park_agents() { # cwd-independent; $1 = fixture path; $2 = symlink target (default CLAUDE.md)
  mv "$1/AGENTS.md" "$1/.ai/AGENTS.parked.md"
  ln -s "${2:-CLAUDE.md}" "$1/AGENTS.md"
}

run_vk() { # $1 = dir, then the script's options (they must precede the dir); sets OUT and RC
  OUT=$BASE/last.out
  dir=$1; shift
  "$VK" "$@" "$dir" > "$OUT" 2>&1
  RC=$?
}
status_line() { grep -Eq "^$1 +$2( |$)" "$OUT"; }   # status_line PASS free-shape
out_has() { grep -qF -- "$1" "$OUT"; }

# ---------------------------------------------------------------- free, well-formed --
make_target free-ok free; park_agents "$T"
run_vk "$T"
chk 'free well-formed: exit 0' test "$RC" -eq 0
chk 'free well-formed: free-shape PASS' status_line PASS free-shape
chk 'free well-formed: kit-manifest PASS' status_line PASS kit-manifest
chk 'free well-formed: live-docs PASS through the symlink' status_line PASS live-docs

# ------------------------------------------------- free, absolute symlink target --
make_target free-abs free; park_agents "$T" "$T/CLAUDE.md"
run_vk "$T"
chk 'free, absolute symlink to CLAUDE.md: free-shape PASS' status_line PASS free-shape

# ---------------------------------------------------- free, AGENTS.md a regular file --
make_target free-regular free
cp "$T/AGENTS.md" "$T/.ai/AGENTS.parked.md"
run_vk "$T"
chk 'free, AGENTS.md regular file: non-zero exit' test "$RC" -ne 0
chk 'free, AGENTS.md regular file: free-shape FAIL' status_line FAIL free-shape
chk 'free, AGENTS.md regular file: the missing symlink is named' out_has 'AGENTS.md is not a symlink'

# ---------------------------------------------------- free, symlink but no parked file --
make_target free-noparked free
rm "$T/AGENTS.md"; ln -s CLAUDE.md "$T/AGENTS.md"
run_vk "$T"
chk 'free, no parked file: free-shape FAIL' status_line FAIL free-shape
chk 'free, no parked file: the parked file is named' out_has '.ai/AGENTS.parked.md'
chk 'free, no parked file: non-zero exit' test "$RC" -ne 0

# ---------------------------------------------------- free, symlink pointing elsewhere --
make_target free-elsewhere free; park_agents "$T" .ai/PROJECT_ARCHITECTURE.md
run_vk "$T"
chk 'free, symlink elsewhere: free-shape FAIL' status_line FAIL free-shape
chk 'free, symlink elsewhere: the wrong target is named' out_has ".ai/PROJECT_ARCHITECTURE.md"

# ---------------------------------------------------- free, dangling symlink --
make_target free-dangling free; park_agents "$T" no-such-file.md
run_vk "$T"
chk 'free, dangling symlink: free-shape FAIL' status_line FAIL free-shape
chk 'free, dangling symlink: the target is named' out_has 'no-such-file.md'

# ---------------------------------------------------- free, parked file is a symlink --
make_target free-parked-symlink free
rm "$T/AGENTS.md"; ln -s CLAUDE.md "$T/AGENTS.md"; ln -s CLAUDE.md "$T/.ai/AGENTS.parked.md"
run_vk "$T"
chk 'free, parked file a symlink: free-shape FAIL' status_line FAIL free-shape
chk 'free, parked file a symlink: named as a symlink, not as missing' out_has '.ai/AGENTS.parked.md is a symlink'

# ------------------------------------------------------ pipeline, leftover parked file --
make_target pipeline-parked pipeline
cp "$T/AGENTS.md" "$T/.ai/AGENTS.parked.md"
run_vk "$T"
chk 'pipeline, leftover parked file: free-shape FAIL' status_line FAIL free-shape
chk 'pipeline, leftover parked file: the file is named' out_has '.ai/AGENTS.parked.md'
chk 'pipeline, leftover parked file: non-zero exit' test "$RC" -ne 0

# ------------------------------------------------------ pipeline, symlinked AGENTS.md --
make_target pipeline-symlink pipeline
rm "$T/AGENTS.md"; ln -s CLAUDE.md "$T/AGENTS.md"
run_vk "$T"
chk 'pipeline, symlinked AGENTS.md: free-shape FAIL' status_line FAIL free-shape
chk 'pipeline, symlinked AGENTS.md: the symlink is named' out_has 'AGENTS.md is a symlink'

# ------------------------------------------------------------------- pipeline, clean --
make_target pipeline-clean pipeline
run_vk "$T"
chk 'pipeline clean: exit 0' test "$RC" -eq 0
chk 'pipeline clean: free-shape PASS' status_line PASS free-shape
chk 'pipeline clean: install integrity NOT CHECKED without -p' out_has 'no plugin root given'

# ---------------------------------------------------------- two-role and autopilot too --
make_target two-role-clean two-role
run_vk "$T"
chk 'two-role clean: free-shape PASS' status_line PASS free-shape
make_target two-role-parked two-role
cp "$T/AGENTS.md" "$T/.ai/AGENTS.parked.md"
run_vk "$T"
chk 'two-role, leftover parked file: free-shape FAIL' status_line FAIL free-shape

# --------------------------------------- pre-profile install: no manifest, no free-shape --
make_target pre-profile pipeline
rm "$T/.ai/kit.json"
run_vk "$T"
chknot 'pre-profile install (no kit.json): free-shape not reported' grep -Eq 'free-shape' "$OUT"

# ----------------------------------------------- install integrity: -p against the kit --
make_target install-six pipeline
run_vk "$T" -p "$KIT"
chk 'six identical files: install-files PASS' status_line PASS install-files
chk 'six identical files: the count says 6' grep -Eq '^PASS +install-files +all 6 ' "$OUT"
chk 'six identical files: kit-version PASS' status_line PASS kit-version

make_target install-nofree pipeline
rm "$T/.ai/process/free.md"
run_vk "$T" -p "$KIT"
chk 'free.md missing: install-files FAIL' status_line FAIL install-files
chk 'free.md missing: free.md is named' out_has '.ai/process/free.md: missing from the project'
chk 'free.md missing: non-zero exit' test "$RC" -ne 0

make_target install-edited-free pipeline
printf '\nlocal edit\n' >> "$T/.ai/process/free.md"
run_vk "$T" -p "$KIT"
chk 'free.md edited at the same version: install-files FAIL' status_line FAIL install-files
chk 'free.md edited at the same version: named as a shipped-file edit' out_has '.ai/process/free.md: differs from the plugin'"'"'s copy at the SAME version'

# -------------------------------------------- kit mode: the free chapter's invariants --
make_kit_copy() { # $1 = name -> K
  K=$BASE/$1; mkdir -p "$K"
  cp -R "$KIT/.ai" "$KIT/.claude-plugin" "$KIT/commands" "$KIT/bin" "$K/"
  cp "$KIT/README.md" "$K/"
}
make_kit_copy kit-asis
run_vk "$K"
chk 'kit copy as shipped: chapters PASS' status_line PASS chapters
chk 'kit copy as shipped: exit 0' test "$RC" -eq 0

make_kit_copy kit-rolename
printf '\nThe Architect decides.\n' >> "$K/.ai/process/free.md"
run_vk "$K"
chk 'free.md with a role name: chapters FAIL' status_line FAIL chapters
chk 'free.md with a role name: the word is named' out_has "bare 'architect' in the free chapter"

make_kit_copy kit-testwriter
printf '\nAsk the Test Writer.\n' >> "$K/.ai/process/free.md"
run_vk "$K"
chk 'free.md with Test Writer: chapters FAIL' status_line FAIL chapters
make_kit_copy kit-testhyphen
printf '\nAsk the Test-Writer.\n' >> "$K/.ai/process/free.md"
run_vk "$K"
chk 'free.md with Test-Writer: chapters FAIL' status_line FAIL chapters

make_kit_copy kit-nofree
rm "$K/.ai/process/free.md"
run_vk "$K"
chk 'free.md removed: chapters FAIL' status_line FAIL chapters
chk 'free.md removed: the kit ships four chapters' out_has 'free.md missing — the kit ships four chapters'

# ------------------------------------------------------------------- result --
echo
echo "verify-kit tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

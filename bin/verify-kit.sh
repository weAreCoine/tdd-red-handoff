#!/bin/sh
# verify-kit.sh — the Kit's test surface (ADR-0006).
#
# One POSIX shell module, grep/sed only — no other dependencies, by design:
# a JavaScript toolchain is precisely what the plugin route was chosen to avoid.
#
# Two modes, auto-detected (override with -m):
#   kit      this repository, the kit producer. The markers ARE the product: they
#            must SURVIVE in the templates. Detection strings intact, contract
#            names pinned in the Toolchain first cells, coverage-floor anchors
#            present, model names confined to README + template roster.
#   target   a project the kit is installed into. Markers must be GONE from the
#            live docs, contract names verbatim in the live Toolchain, one floor
#            in two files on fixed anchors, no model-name leaks outside the roster.
#
# Three result states — green must mean something exact:
#   PASS / FAIL      per mechanical check.
#   NOT CHECKED      what a grep cannot decide. Listed, never omitted: a verifier
#                    that silently skipped what it cannot check would commit the
#                    same sin the Kit forbids every role.
#
# Exit codes: 0 = no FAIL · 1 = at least one FAIL · 2 = usage / not a kit tree.
#
# Usage: verify-kit.sh [-m kit|target] [dir]

set -u

usage() { echo "usage: $0 [-m kit|target] [dir]" >&2; exit 2; }

MODE=auto
while getopts m:h opt; do
  case $opt in
    m) MODE=$OPTARG ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))
ROOT=${1:-.}

[ -d "$ROOT" ] || { echo "verify-kit: no such directory: $ROOT" >&2; exit 2; }
cd "$ROOT" || exit 2

if [ "$MODE" = auto ]; then
  if [ -f .ai/PROJECT_ARCHITECTURE.md ]; then
    MODE=target
  elif [ -f .ai/templates/PROJECT_ARCHITECTURE.template.md ]; then
    MODE=kit
  else
    echo "verify-kit: not a kit tree (no .ai/PROJECT_ARCHITECTURE.md, no .ai/templates/PROJECT_ARCHITECTURE.template.md)" >&2
    exit 2
  fi
fi
case $MODE in kit|target) ;; *) usage ;; esac

PASSES=0
FAILS=0
pass() { PASSES=$((PASSES + 1)); printf 'PASS  %-15s %s\n' "$1" "$2"; }
fail() { FAILS=$((FAILS + 1)); printf 'FAIL  %-15s %s\n' "$1" "$2"; }
detail() { sed 's/^/        /'; }

# The seven contract names (PROJECT_ARCHITECTURE Contract §1). One per line —
# names contain spaces, so iteration always sets IFS to newline first.
CONTRACT_NAMES='test
test (focused)
typecheck
lint
format
format:check
coverage'

NL='
'

# First cell of every markdown table row in a file, trimmed.
first_cells() {
  sed -n 's/^|[[:space:]]*\([^|]*\)|.*$/\1/p' "$1" | sed 's/[[:space:]]*$//'
}

# --- contract-names: every contract name sits verbatim in a Toolchain first cell.
check_contract_names() { # $1 = file
  cells=$(first_cells "$1")
  missing=''
  OLDIFS=$IFS; IFS=$NL
  for name in $CONTRACT_NAMES; do
    printf '%s\n' "$cells" | grep -Fxq "$name" || missing="$missing, $name"
  done
  IFS=$OLDIFS
  missing=${missing#, }
  if [ -z "$missing" ]; then
    pass contract-names "all 7 contract names verbatim in first cells of $1"
  else
    fail contract-names "$1 — missing from table first cells: $missing"
    echo "the first cell of a contract row is the name itself, not a human label (Contract §1)" | detail
  fi
}

# --- coverage-floor anchors.
floor_row()  { sed -n 's/.*\*\*Project floor\*\*.*\*\*\([0-9][0-9]*%\)\*\*.*/\1/p' "$1" | head -n 1; }
floor_line() { sed -n 's/.*\*\*Project floor:\*\*[[:space:]]*\([0-9][0-9]*%\).*/\1/p' "$1" | head -n 1; }

# --- model names: the roster's "Current model" column (last cell of its table rows).
roster_models() { # $1 = file containing § Model Roster
  sed -n '/^## Model Roster/,/^## /p' "$1" \
    | sed -n 's/^|.*|\([^|]*\)|[[:space:]]*$/\1/p' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -v -e '^Current model$' -e '^-\{1,\}$' -e '^$' \
    | sort -u
}

check_model_leaks() { # $1 = roster file, $2 = allowed-paths regex, $3... = scan roots/files for find
  rosterfile=$1; allowed=$2; shift 2
  models=$(roster_models "$rosterfile")
  if [ -z "$models" ]; then
    fail model-roster "$rosterfile — could not extract any model from § Model Roster"
    return
  fi
  leaks=''
  OLDIFS=$IFS; IFS=$NL
  for m in $models; do
    IFS=$OLDIFS
    hits=$(find "$@" -name '*.md' -not -path '*/.git/*' -not -path '*/node_modules/*' \
             -exec grep -lwF -- "$m" {} + 2>/dev/null || true)
    bad=$(printf '%s\n' "$hits" | grep -vE "$allowed" | grep -v '^$' || true)
    [ -n "$bad" ] && leaks="$leaks$NL  $m -> $(printf '%s' "$bad" | tr '\n' ' ')"
    IFS=$NL
  done
  IFS=$OLDIFS
  if [ -z "$leaks" ]; then
    pass model-roster "roster models ($(printf '%s' "$models" | tr '\n' ',' | sed 's/,/, /g')) appear nowhere else"
  else
    fail model-roster "model name(s) leaked outside the allowed files:"
    printf '%s\n' "$leaks" | grep -v '^$' | detail
  fi
}

printf 'verify-kit — mode: %s — root: %s\n\n' "$MODE" "$(pwd)"

# =====================================================================
if [ "$MODE" = kit ]; then
  T=.ai/templates

  # markers — in the kit repo the markers ARE the product: they must survive.
  problems=''
  need() { grep -Eq "$2" "$1" || problems="$problems$NL  $1: missing $3"; }
  need "$T/CLAUDE.template.md"               'FILL:'        'FILL markers'
  need "$T/CLAUDE.template.md"               '\[\[DECISION' '[[DECISION]] markers'
  need "$T/AGENTS.template.md"               'FILL:'        'FILL markers'
  need "$T/AGENTS.template.md"               '\[\[DECISION' '[[DECISION]] markers'
  need "$T/PROJECT_ARCHITECTURE.template.md" 'FILL:'        'FILL markers'
  need "$T/plan_template.md"                 'FILL:'        'FILL markers'
  need "$T/plan_template.md"                 '\{[a-z-]+\}'  '{placeholder} markers'
  need "$T/test_plan_template.md"            'FILL:'        'FILL markers'
  need "$T/test_plan_template.md"            '\{[a-z-]+\}'  '{placeholder} markers'
  if [ -z "$problems" ]; then
    pass markers "all five templates still carry their markers (the product is intact)"
  else
    fail markers "template markers missing — the product has been eroded:"
    printf '%s\n' "$problems" | grep -v '^$' | detail
  fi

  # (No templates-wide 'architect' grep: with the union roster, Architect is a first-class
  #  role name in shared files. The surviving invariant — the pipeline chapter never uses
  #  the word, and keeps 'Test-Writer' — lives in the chapters check below.)

  # chapters — process chapters ship verbatim: no fill markers, ever. The pipeline
  # chapter also keeps its detection string and never uses the two-role role word
  # ('Architect' is legitimate only in two-role.md).
  if [ -d .ai/process ] && ls .ai/process/*.md >/dev/null 2>&1; then
    problems=''
    ch=$(grep -nE 'FILL:|\[\[DECISION' .ai/process/*.md || true)
    [ -n "$ch" ] && problems="$problems$NL  fill markers in chapters:$NL$(printf '%s' "$ch" | sed 's/^/    /')"
    if [ -f .ai/process/pipeline.md ]; then
      grep -q 'Test-Writer' .ai/process/pipeline.md \
        || problems="$problems$NL  .ai/process/pipeline.md: 'Test-Writer' not found"
      arch=$(grep -nwi 'architect' .ai/process/pipeline.md || true)
      [ -n "$arch" ] && problems="$problems$NL  bare 'architect' in the pipeline chapter:$NL$(printf '%s' "$arch" | sed 's/^/    /')"
    fi
    if [ -z "$problems" ]; then
      pass chapters "process chapters carry no markers (they ship verbatim)"
    else
      fail chapters "process chapter invariants broken:"
      printf '%s\n' "$problems" | grep -v '^$' | detail
    fi
  fi

  # contract-names — pinned in the template's Toolchain first cells.
  check_contract_names "$T/PROJECT_ARCHITECTURE.template.md"

  # coverage-floor — both anchors present (the template PA value is legitimately TODO).
  cf=$(floor_row "$T/CLAUDE.template.md")
  pf_anchor=$(grep -c 'Project floor:' "$T/PROJECT_ARCHITECTURE.template.md" || true)
  if [ -n "$cf" ] && [ "$pf_anchor" -gt 0 ]; then
    pass coverage-floor "anchors in place (CLAUDE template floor: $cf; PA template anchor present)"
  else
    fail coverage-floor "anchor missing — CLAUDE '**Project floor**' row: '${cf:-none}'; PA '**Project floor:**' lines: $pf_anchor"
  fi

  # phase-numbers — profile-agnostic files reference phases by name, never by number;
  # numbers are legitimate only inside the process chapters.
  ph=$(grep -nE 'Phase(s)? [0-9]' "$T"/*.md || true)
  if [ -z "$ph" ]; then
    pass phase-numbers "no 'Phase N' outside the process chapters"
  else
    fail phase-numbers "hardcoded phase numbers in profile-agnostic templates:"
    printf '%s\n' "$ph" | detail
  fi

  # model-roster — names allowed only in README.md and the template roster (coupling #8).
  check_model_leaks "$T/PROJECT_ARCHITECTURE.template.md" \
    '^\./README\.md$|^\./\.ai/templates/PROJECT_ARCHITECTURE\.template\.md$' .

  # printf, not a heredoc: heredocs need a temp file, and the script must also
  # run with a read-only working directory (sandboxed shells, CI checkouts).
  printf '%s\n' \
    '' \
    'NOT CHECKED (mechanically undecidable — verify by reading):' \
    '  - README mirror fidelity (coupling #9): roles, phases, triggers, markers, layout.' \
    '  - The line-number coupling (#2): migrate-architecture cites AGENTS.template.md lines 6-8.' \
    '  - Status-lifecycle and layer vocabulary USED correctly across files (#6, #7):' \
    '    presence is greppable, correct use is not.'

# =====================================================================
else # target

  LIVE_CLAUDE=CLAUDE.md
  LIVE_AGENTS=AGENTS.md
  LIVE_PA=.ai/PROJECT_ARCHITECTURE.md

  missing=''
  for f in "$LIVE_CLAUDE" "$LIVE_AGENTS" "$LIVE_PA"; do
    [ -f "$f" ] || missing="$missing $f"
  done
  if [ -n "$missing" ]; then
    fail live-docs "missing live doc(s):$missing"
  else
    pass live-docs "CLAUDE.md, AGENTS.md, .ai/PROJECT_ARCHITECTURE.md all present"
  fi

  # markers — in a target project the self-check must return NOTHING.
  hits=$(grep -nE 'FILL:|\[\[DECISION' $LIVE_CLAUDE $LIVE_AGENTS $LIVE_PA 2>/dev/null || true)
  planhits=''
  if [ -d .ai/plans ] && ls .ai/plans/*.md >/dev/null 2>&1; then
    planhits=$(grep -nE 'FILL:|\{[a-z-]+\}' .ai/plans/*.md 2>/dev/null || true)
  fi
  if [ -z "$hits" ] && [ -z "$planhits" ]; then
    pass markers "no FILL / [[DECISION]] in live docs; no FILL / {placeholder} in plans"
  else
    fail markers "unresolved template markers survive in filled files:"
    printf '%s\n%s\n' "$hits" "$planhits" | grep -v '^$' | detail
  fi

  # contract-names — the live Toolchain carries the names verbatim.
  [ -f "$LIVE_PA" ] && check_contract_names "$LIVE_PA"

  # coverage-floor — one number, two files, two fixed anchors.
  if [ -f "$LIVE_CLAUDE" ] && [ -f "$LIVE_PA" ]; then
    cf=$(floor_row "$LIVE_CLAUDE")
    pf=$(floor_line "$LIVE_PA")
    if [ -z "$cf" ] || [ -z "$pf" ]; then
      fail coverage-floor "anchor missing or non-numeric — CLAUDE.md '**Project floor**' row: '${cf:-none}'; PROJECT_ARCHITECTURE '**Project floor:**' line: '${pf:-none}'"
    elif [ "$cf" = "$pf" ]; then
      pass coverage-floor "one floor, two files: $cf"
    else
      fail coverage-floor "floors diverge: CLAUDE.md says $cf, PROJECT_ARCHITECTURE.md says $pf (Contract §3)"
    fi
  fi

  # model-roster — names allowed only inside the live roster file (Contract §6).
  if [ -f "$LIVE_PA" ]; then
    scan="$LIVE_CLAUDE $LIVE_AGENTS"
    [ -d .ai/plans ] && scan="$scan .ai/plans"
    # shellcheck disable=SC2086
    check_model_leaks "$LIVE_PA" "^\./?\.ai/PROJECT_ARCHITECTURE\.md$|^\.ai/PROJECT_ARCHITECTURE\.md$" $scan
  fi

  # role-vocab — pre-profile installations only: there, bare 'architect' in live docs is
  # old-kit vocabulary. Post-profile the union roster legitimately names the Architect role,
  # so the grep would only produce false positives — correct USE is not greppable (§4).
  if [ ! -f .ai/kit.json ]; then
    arch=$(grep -nwi 'architect' $LIVE_CLAUDE $LIVE_AGENTS $LIVE_PA 2>/dev/null || true)
    if [ -z "$arch" ]; then
      pass role-vocab "no bare 'architect' in live docs (pre-profile installation)"
    else
      fail role-vocab "bare 'architect' found — old-kit vocabulary in a pipeline installation:"
      printf '%s\n' "$arch" | detail
    fi
  fi

  # kit-manifest — the profile triad (kit.json <-> import line <-> chapter file).
  if [ -f .ai/kit.json ]; then
    profile=$(sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .ai/kit.json | head -n 1)
    line1=$(head -n 1 "$LIVE_CLAUDE" 2>/dev/null)
    problems=''
    [ -n "$profile" ] || problems="$problems$NL  .ai/kit.json: no \"profile\" field"
    [ "$line1" = "@.ai/process/$profile.md" ] \
      || problems="$problems$NL  CLAUDE.md line 1 is '$line1', expected '@.ai/process/$profile.md'"
    [ -f ".ai/process/$profile.md" ] \
      || problems="$problems$NL  chapter file .ai/process/$profile.md not found"
    if [ -z "$problems" ]; then
      pass kit-manifest "triad agrees: profile '$profile' in kit.json, CLAUDE.md import, chapter file"
    else
      fail kit-manifest "kit.json / import line / chapter file disagree:"
      printf '%s\n' "$problems" | grep -v '^$' | detail
    fi

    # phase-numbers — profile-agnostic files must not hardcode phase numbers. The CLAUDE.md
    # file on disk is the shell (the chapter with its numbers arrives via the import).
    ph=$(grep -nE 'Phase(s)? [0-9]' $LIVE_CLAUDE $LIVE_AGENTS $LIVE_PA .ai/templates/plan_template.md .ai/templates/test_plan_template.md 2>/dev/null || true)
    if [ -z "$ph" ]; then
      pass phase-numbers "no 'Phase N' outside the process chapters"
    else
      fail phase-numbers "hardcoded phase numbers in profile-agnostic files:"
      printf '%s\n' "$ph" | detail
    fi
    NOTE_PROFILE=''
  else
    NOTE_PROFILE="  - kit-manifest triad and phase-number confinement: pre-profile installation
    (no .ai/kit.json yet) — these checks activate with profile support."
  fi

  # printf, not a heredoc — see the kit-mode block for why.
  printf '%s\n' \
    '' \
    'NOT CHECKED (mechanically undecidable — verify by reading):' \
    '  - Contract §2: the layer map describes the REAL repository tree.' \
    '  - Contract §4: layer vocabulary USED correctly (synonyms merely absent is not enough).' \
    '  - Contract §5: the secrets boundary is TRUE in the code, not just stated.'
  if [ -n "$NOTE_PROFILE" ]; then printf '%s\n' "$NOTE_PROFILE"; fi

fi

# =====================================================================
printf '\nResult: '
if [ "$FAILS" -eq 0 ]; then
  printf 'PASS — %d check(s) passed, 0 failed.\n' "$PASSES"
  printf 'The NOT CHECKED list above is part of the result: green means "the mechanical checks pass",\nnot "everything is verified".\n'
  exit 0
else
  printf 'FAIL — %d check(s) failed, %d passed.\n' "$FAILS" "$PASSES"
  exit 1
fi

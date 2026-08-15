#!/bin/sh
# tests/driver/mutants.sh — the mutation harness behind ADR-0008's table.
#
# A mutation row is only evidence if someone else can reproduce it. Through six
# rounds the table named its mutants in prose ("the lock never released"), and
# the seventh review could not reconstruct four of them: the counts differed
# because the line chosen differed. So the mutant IS its edit here — an exact
# sed program — and the table in the ADR quotes the id, not a description.
#
# Each mutant runs against a full copy of the tracked WORKING tree (not
# `git archive HEAD`: the point is to measure the code as it stands, including
# what is not committed yet). A partial copy of bin/ + tests/ would break the
# scenario that reads .ai/templates/, and every mutant would then appear to
# gain a detection it has not earned.
#
# Usage: sh tests/driver/mutants.sh [-j N] [id ...]
#   no ids  -> the baseline plus every mutant, in table order
#   ids     -> only those (the baseline always runs first)
#
# Output: one row per mutant — id, property, observed failures out of the
# suite's assertion count. "did-not-apply" means the sed program matched
# nothing: the file moved under the mutant, and the row must be rewritten.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
KIT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/autopilot-mutants.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

JOBS=1
while getopts j: opt; do case $opt in j) JOBS=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1))
WANT=$*

copy_tree() { # $1 = destination; tracked files, working-tree content. Returns 1 on
              # a partial copy — a mutant measured against half a tree is a wrong number,
              # and three rows of the seventh round's first measurement were exactly that.
  mkdir -p "$1" || return 1
  (cd "$KIT" && git ls-files) | while IFS= read -r f; do
    mkdir -p "$1/${f%/*}" || exit 1
    cp -p "$KIT/$f" "$1/$f" || exit 1
  done || return 1
  want=$( (cd "$KIT" && git ls-files) | wc -l )
  got=$( (cd "$1" && find . -type f | wc -l) )
  [ "$want" -eq "$got" ]
}

run_suite() { # $1 = tree -> "<passed> <failed>" or "" when the suite died
  out=$( (cd "$1" && sh tests/driver/run.sh) 2>&1 )
  printf '%s' "$out" | sed -n 's/^driver tests: \([0-9]*\) passed, \([0-9]*\) failed$/\1 \2/p'
}

mutate() { # $1 = id, $2 = file, $3 = sed program, $4 = property
  d=$WORK/$1
  if ! copy_tree "$d"; then
    printf '%s\t%s\t%s\n' "$1" "$4" 'copy-failed' > "$WORK/res.$1"; return
  fi
  before=$(cksum < "$d/$2")
  sed "$3" "$d/$2" > "$d/$2.mut" && mv "$d/$2.mut" "$d/$2"
  chmod +x "$d/$2"
  if [ "$(cksum < "$d/$2")" = "$before" ]; then
    printf '%s\t%s\t%s\n' "$1" "$4" 'did-not-apply' > "$WORK/res.$1"; return
  fi
  if ! sh -n "$d/$2" 2>/dev/null; then
    printf '%s\t%s\t%s\n' "$1" "$4" 'does-not-parse' > "$WORK/res.$1"; return
  fi
  r=$(run_suite "$d")
  if [ -z "$r" ]; then
    printf '%s\t%s\t%s\n' "$1" "$4" 'suite-died' > "$WORK/res.$1"
  else
    printf '%s\t%s\t%s/%s\n' "$1" "$4" "${r#* }" "$(( ${r% *} + ${r#* } ))" > "$WORK/res.$1"
  fi
  rm -rf "$d"
}

# --- the mutants: id, file, sed program, property ----------------------------
# Tab-separated. One exact edit each. The property column is the safety
# property of ADR-0008 § "What the behavior suite is a safety case for"; a
# mutant with no property is a harness-level check.
mutants() { cat <<'TABLE'
harness-one-family	bin/autopilot-driver.sh	/^phase_harness()/s@.*@phase_harness() { echo codex; }@	entry/dispatch
log-tail-ignored	bin/autopilot-driver.sh	/else if (tail) {/s@shape = "tail"@shape = "ok"@	publication
log-tail-atx	bin/autopilot-driver.sh	/else if (head > 0) {/s@tail = 1@tail = 0@	publication
log-tail-setext	bin/autopilot-driver.sh	/^    if (head > 0) {/s@tail = 1@tail = 0@	publication
log-indented-atx	bin/autopilot-driver.sh	/^  if (ind <= 3) {$/s@ind <= 3@ind == 0@	publication
log-fence-transparent	bin/autopilot-driver.sh	/^  if (fence != "") {$/s@fence != ""@0@	publication
log-fence-length	bin/autopilot-driver.sh	/if (n >= flen && blank(substr(body, n + 1)))/s@n >= flen@n >= 3@	publication
log-fence-infostring	bin/autopilot-driver.sh	/if (n >= flen && blank(substr(body, n + 1)))/s@ && blank(substr(body, n + 1))@@	publication
log-atx-max-six	bin/autopilot-driver.sh	/if (hn > 6) hn = 0/s@if (hn > 6) hn = 0@@	publication
log-comment-not-opaque	bin/autopilot-driver.sh	/substr(body, 1, 4) == "<!--"/s@substr(body, 1, 4) == "<!--"@0@	publication
log-html-allowed	bin/autopilot-driver.sh	/ch == "<") {/s@html = 1@html = 0@	publication
log-last-line	bin/autopilot-driver.sh	/-ge 1 \] && \[ "\$LOG_LAST" -eq 1 \]/s@ && \[ "\$LOG_LAST" -eq 1 \]@@	publication
green-whole-file	bin/autopilot-driver.sh	/if (head > 0 && line ~ GRX) green++/s@head > 0 && @@	publication
phase2-log-shape	bin/autopilot-driver.sh	/# the Log every later phase appends to/s@log_shape_ok@:@	publication
artifact4-prefix	bin/autopilot-driver.sh	/^    4) if/,/^    5)/s@&& log_shape_ok "\$TESTPLAN" && \[ "\$(impl_green_count "\$TESTPLAN")" -eq "\$ENTRY_GREEN" \]@\&\& :@	publication
artifact8-prefix	bin/autopilot-driver.sh	/^    8) if/,/^    9)/s@&& log_shape_ok "\$TESTPLAN" && \[ "\$(impl_green_count "\$TESTPLAN")" -eq "\$ENTRY_GREEN" \]@\&\& :@	publication
artifact8-no-new-row	bin/autopilot-driver.sh	/-gt "\$ENTRY_GREEN" \] && impl_green/s@.*@            status_line_is "\$TESTPLAN" APPROVED; fi ;;@	publication
artifact8-position	bin/autopilot-driver.sh	/-gt "\$ENTRY_GREEN" \] && impl_green/s@ && impl_green "\$TESTPLAN"@@	publication
publication-clean-tree	bin/autopilot-driver.sh	/working tree not clean at publication time/s@stop_flight@:@	publication
push-by-name	bin/autopilot-driver.sh	/^git push origin/s@origin "\$ACCEPTED_HEAD:refs/heads/feature/\$FEATURE"@-u origin "feature/\$FEATURE"@	publication
nonce-check	bin/autopilot-driver.sh	/grep -qF "PREFLIGHT: \$nonce"/s@grep -qF "PREFLIGHT: \$nonce" "\$logf"@:@	entry
nul-rejection	bin/autopilot-driver.sh	/LC_ALL=C tr -d/s@.*@  :@	entry
nontrivial-existence	bin/autopilot-driver.sh	/^nontrivial()/s@.*@nontrivial() { [ -f "\$1" ]; }@	entry
entry3-adr	bin/autopilot-driver.sh	/^    3) adr_ok &&/s@adr_ok && @@	entry
entry7-adr	bin/autopilot-driver.sh	/^    7) adr_ok &&/s@adr_ok && @@	entry
entry8-log-shape	bin/autopilot-driver.sh	/^    8) if/,/^    9) if/s@elif ! log_shape_ok@elif ! : @	entry
ladder-before-primary	bin/autopilot-driver.sh	/echo "\$MODEL_REVIEW \$LADDER_REVIEW"/s@\$MODEL_REVIEW \$LADDER_REVIEW@\$LADDER_REVIEW \$MODEL_REVIEW@	entry
route-plan-to-2	bin/autopilot-driver.sh	/^route_phase()/s@plan) echo 6@plan) echo 2@	routing
edge-cap-off-by-one	bin/autopilot-driver.sh	/global cap: backward edge/s@-le "\$MAX_EDGES"@-lt "\$MAX_EDGES"@	caps
flightenv-unvalidated	bin/autopilot-driver.sh	/^cfg_validate "\$FLIGHT_ENV"/s@^@#@	config fail-fast
lock-acquire	bin/autopilot-driver.sh	/another driver may be flying/s@|| die@|| :@	terminal state/lock
lock-release	bin/autopilot-driver.sh	/^  rm -rf "\$S\/lock"$/s@.*@  :@	terminal state/lock
cleanup-arm	bin/autopilot-driver.sh	/= RUNNING \]; then$/s@.*@  if false; then@	terminal state/lock
commit-prefix-grammar	bin/autopilot-driver.sh	/--format=%s "\$c" | grep -qE/s@.*@          git log -1 --format=%s "\$c" | grep -qE '.*' \\@	audit/hygiene
retry-clean	bin/autopilot-driver.sh	/^      git clean -fd >\/dev\/null 2>&1$/s@.*@      :@	audit/hygiene
report-counters	bin/autopilot-driver.sh	/^      "\$(show_int edges)" "\$MAX_EDGES"/s@.*@      0 0 0 0 0 0@	report honesty
report-journey	bin/autopilot-driver.sh	/printf '## Journey/s@.*@    :@	report honesty
report-verdict	bin/autopilot-driver.sh	/printf 'Last verdict/s@.*@      :@	report honesty
actor-ladder-scope	tests/driver/stubs/phase-actor.sh	/if (lp == p) print lm/s@if (lp == p) print lm@print lm@	(test harness)
TABLE
}

# --- run ---------------------------------------------------------------------
base=$WORK/baseline
copy_tree "$base" || { echo "could not copy the tree" >&2; exit 1; }
r=$(run_suite "$base")
[ -n "$r" ] || { echo "baseline suite did not report a result" >&2; exit 1; }
BASE_TOTAL=$(( ${r% *} + ${r#* } ))
echo "baseline: ${r% *} passed, ${r#* } failed"
[ "${r#* }" -eq 0 ] || { echo "baseline is not green — measure nothing until it is" >&2; exit 1; }
rm -rf "$base"
echo

# The loop must run in THIS shell, not in a pipeline's subshell: background jobs
# started inside a subshell are ITS children, the subshell exits without waiting
# for the last, partial batch, and the EXIT trap then deletes the tree under
# them — which is how the first two measurements of this round lost three rows.
n=0
while IFS='	' read -r id file prog prop; do
  case $WANT in ''|*"$id"*) ;; *) continue ;; esac
  mutate "$id" "$file" "$prog" "$prop" &
  n=$((n + 1))
  [ "$((n % JOBS))" -eq 0 ] && wait
done <<EOF
$(mutants)
EOF
wait

printf '%-24s %-20s %s\n' 'mutant' 'property' "failures/$BASE_TOTAL"
mutants | while IFS='	' read -r id file prog prop; do
  case $WANT in ''|*"$id"*) ;; *) continue ;; esac
  if [ -f "$WORK/res.$id" ]; then
    IFS='	' read -r rid rprop rres < "$WORK/res.$id"
    printf '%-24s %-20s %s\n' "$rid" "$rprop" "$rres"
  else   # never silently drop a row: a missing measurement is a result too
    printf '%-24s %-20s %s\n' "$id" "$prop" 'NOT RUN'
  fi
done

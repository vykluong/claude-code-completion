#!/usr/bin/env zsh
# Golden-file test suite for src/_claude.
#
# Usage:  zsh tests/run-tests.zsh            # run every case
#         zsh tests/run-tests.zsh 'mcp-*'    # run a subset (glob on case name)
#
# Each file in tests/cases/ describes one completion buffer and the candidates
# the script must offer for it:
#
#     buffer='claude mcp add -'     <- line 1, quoted so trailing spaces survive
#     # mode: contains              <- optional; default is 'exact'
#     # double-tab                  <- optional; presses TAB twice
#     --callback-port               <- remaining lines: expected candidates
#     --client-id
#
# Modes:
#   exact     harness output must equal the expected list exactly. Use for
#             closed sets (command rosters, enums, leaf option lists).
#   contains  every expected line must appear; extras are allowed. Use where
#             _files or _message hints add unstable noise.
#
# Candidates are compared as sets: both sides are re-sorted with `LC_ALL=C
# sort -u`, so a case never fails just because the runner's locale collates
# differently from the machine the goldens were generated on.
#
# Only the static script is exercised; the `claude` binary is never invoked.
# Exits 0 when every case passes, 1 otherwise.

set -u

TESTS_DIR=${0:A:h}
REPO_DIR=${TESTS_DIR:h}
HARNESS=$TESTS_DIR/zcomp-runner.zsh
CASES_DIR=$TESTS_DIR/cases
SCRIPT=$REPO_DIR/src/_claude
PATTERN=${1-*}

[[ -r $HARNESS ]]    || { print -u2 "run-tests: missing harness: $HARNESS"; exit 1 }
[[ -d $CASES_DIR ]]  || { print -u2 "run-tests: missing cases dir: $CASES_DIR"; exit 1 }
[[ -r $SCRIPT ]]     || { print -u2 "run-tests: missing script: $SCRIPT"; exit 1 }

WORK=$(mktemp -d) || exit 1
trap 'rm -rf $WORK' EXIT INT TERM

# --- preflight: a syntax error would make every case fail with empty output --
if ! zsh -n $SCRIPT; then
  print -u2 "FAIL preflight: 'zsh -n src/_claude' reported a syntax error"
  exit 1
fi

# --- case selection ----------------------------------------------------------
typeset -a CASE_FILES
CASE_FILES=()
for f in $CASES_DIR/*.txt(N); do
  [[ ${f:t:r} == ${~PATTERN} || ${f:t} == ${~PATTERN} ]] && CASE_FILES+=($f)
done
if (( ${#CASE_FILES} == 0 )); then
  print -u2 "run-tests: no cases matched pattern '$PATTERN'"
  exit 1
fi

# --- case file parsing -------------------------------------------------------
# Sets CASE_BUFFER / CASE_MODE / CASE_DOUBLE_TAB / CASE_EXPECTED, or PARSE_ERR
# plus a non-zero return. The error is returned rather than printed so the
# caller can emit it under the case's own FAIL heading.
typeset CASE_BUFFER CASE_MODE PARSE_ERR
typeset -i CASE_DOUBLE_TAB
typeset -a CASE_EXPECTED

parse_case() {
  local file=$1 line
  local -i first=1
  CASE_BUFFER=''; CASE_MODE=exact; CASE_DOUBLE_TAB=0; CASE_EXPECTED=(); PARSE_ERR=''

  while IFS= read -r line || [[ -n $line ]]; do
    if (( first )); then
      first=0
      if [[ $line != buffer=* ]]; then
        PARSE_ERR="line 1 must be buffer='...', got: $line"
        return 1
      fi
      CASE_BUFFER=${line#buffer=}
      # Strip one layer of surrounding quotes; they exist only to protect
      # trailing whitespace from editors that trim it.
      if [[ ${#CASE_BUFFER} -ge 2 && ( $CASE_BUFFER == \'*\' || $CASE_BUFFER == \"*\" ) ]]; then
        CASE_BUFFER=${CASE_BUFFER[2,-2]}
      fi
      continue
    fi
    case $line in
      '# double-tab')  CASE_DOUBLE_TAB=1 ;;
      '# mode: '*)     CASE_MODE=${line#'# mode: '} ;;
      '#'*|'')         ;;
      *)               CASE_EXPECTED+=("$line") ;;
    esac
  done < $file

  if [[ $CASE_MODE != exact && $CASE_MODE != contains ]]; then
    PARSE_ERR="unknown mode: $CASE_MODE (expected 'exact' or 'contains')"
    return 1
  fi
  if [[ -z $CASE_BUFFER ]]; then
    PARSE_ERR="empty buffer"
    return 1
  fi
  if (( ${#CASE_EXPECTED} == 0 )); then
    PARSE_ERR="no expected candidates"
    return 1
  fi
  return 0
}

# --- run ---------------------------------------------------------------------
zmodload zsh/datetime 2>/dev/null
integer passed=0 failed=0
integer start=${EPOCHSECONDS:-0}

print "running ${#CASE_FILES} case(s) against $SCRIPT"

for case_file in $CASE_FILES; do
  name=${case_file:t:r}

  if ! parse_case $case_file; then
    print "FAIL $name  (malformed case file)"
    print "  $case_file"
    print "  $PARSE_ERR"
    (( failed++ ))
    continue
  fi

  if (( CASE_DOUBLE_TAB )); then
    DOUBLE_TAB=1 zsh $HARNESS "$CASE_BUFFER" > $WORK/raw 2>/dev/null
  else
    DOUBLE_TAB=0 zsh $HARNESS "$CASE_BUFFER" > $WORK/raw 2>/dev/null
  fi
  LC_ALL=C sort -u $WORK/raw > $WORK/actual
  print -rl -- "$CASE_EXPECTED[@]" | LC_ALL=C sort -u > $WORK/expected

  typeset -a actual missing
  actual=("${(@f)$(<$WORK/actual)}")
  [[ -s $WORK/actual ]] || actual=()

  ok=1
  missing=()
  if [[ $CASE_MODE == exact ]]; then
    cmp -s $WORK/expected $WORK/actual || ok=0
  else
    for want in $CASE_EXPECTED; do
      (( ${actual[(Ie)$want]} )) || missing+=("$want")
    done
    (( ${#missing} == 0 )) || ok=0
  fi

  if (( ok )); then
    print "PASS $name"
    (( passed++ ))
    continue
  fi

  (( failed++ ))
  print "FAIL $name  (mode: $CASE_MODE)"
  print "  buffer: '$CASE_BUFFER'"
  if (( ${#actual} == 0 )); then
    print "  harness produced NO candidates (script error, or the buffer offers nothing)"
  fi
  if [[ $CASE_MODE == exact ]]; then
    diff -u --label expected --label actual $WORK/expected $WORK/actual | sed 's/^/  /'
  else
    print "  missing from output:"
    print -rl -- "$missing[@]" | sed 's/^/    /'
    print "  actual output was:"
    if (( ${#actual} == 0 )); then
      print "    (empty)"
    else
      sed 's/^/    /' $WORK/actual
    fi
  fi
done

integer elapsed=$(( ${EPOCHSECONDS:-0} - start ))
print ""
print "${#CASE_FILES} case(s): $passed passed, $failed failed (${elapsed}s)"
(( failed == 0 )) || exit 1
exit 0

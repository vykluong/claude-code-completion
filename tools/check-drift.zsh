#!/usr/bin/env zsh
#
# check-drift.zsh — detect drift between the installed Claude Code CLI and the
# CLI surface that this repo's completion script (src/_claude) is written
# against.
#
# MAINTAINERS: rerun `zsh tools/check-drift.zsh` after every `claude update`.
# A non-zero exit means the CLI moved; read the diff, update src/_claude and
# tests/ to match, then re-snapshot with `zsh tools/check-drift.zsh snapshot`
# and commit tools/cli-surface.txt alongside the script change.
#
# Usage:
#   zsh tools/check-drift.zsh [check]     # default: regenerate + diff, exit 1 on drift
#   zsh tools/check-drift.zsh snapshot    # overwrite tools/cli-surface.txt
#   zsh tools/check-drift.zsh dump        # write the dump to stdout, no diff
#
# Exit codes: 0 = no drift, 1 = drift, 2 = the tool itself could not run
# (no `claude` on PATH, or a roster entry that no longer exists).
#
# What it records (tools/cli-surface.txt), all sorted and byte-stable:
#   version       the `claude --version` string (so diffs are self-describing)
#   usage         the `Usage:` line of every walked command
#   opt           option flag names + value placeholders, descriptions stripped
#                 (descriptions get reworded/rewrapped constantly and diff badly)
#   choices       commander enum choices, e.g.
#                 `--input-format = text stream-json` — enum drift is silent in
#                 --help prose but breaks the script's completion value lists
#   sub           the `Commands:` roster of every walked command, aliases split
#   registration  `.command("...")` literals mined out of the native binary —
#                 this is how commands hidden from --help get discovered
#   probe-command invokability verdict for registrations we do not already walk
#                 (plus a hardcoded watch list of known feature-gated commands)
#   probe-flag    recognized/unrecognized verdict for undocumented top-level flags
#   unwalked      subcommands the CLI advertises that COMMANDS below does not
#                 walk — i.e. this tool's own roster has fallen behind
#
# Scope: this tool inspects the CLI only. Whether src/_claude still matches is
# the test suite's job (tests/). Together: check-drift says "the CLI changed",
# the tests say "the script no longer matches what we encode".
#
# Deliberate normalizations:
#   * option/command descriptions are dropped entirely (too noisy to diff)
#   * `daemon` and `remote-control` print hand-rolled help, not commander's
#     layout; they are parsed heuristically and their `sub` entries keep the
#     full entry head (e.g. `run [json-path]`) rather than just the name
#   * commander's built-in `help` subcommand is recorded but never walked

emulate -L zsh
setopt extended_glob no_unset pipe_fail
export LC_ALL=C

# Capture at file scope: inside a function, $0 is the function's name.
typeset -g SCRIPT_PATH=${0:A}
typeset -g SNAPSHOT=${SCRIPT_PATH:h}/cli-surface.txt

# ---------------------------------------------------------------------------
# Roster: the commands we walk with `--help`. Hardcoded on purpose — it IS the
# thing under test. If a command disappears from the CLI we want a loud failure
# here, not a silently shorter dump. Entries are invocation paths; '' = top level.
#
# zsh gotcha, do not "fix" this: unquoted $c does NOT word-split in zsh, so
# `claude $c --help` for c="mcp add" runs `claude "mcp add" --help`, which
# prints TOP-LEVEL help and silently poisons the dump. Always use ${=c}.
# ---------------------------------------------------------------------------
typeset -ga COMMANDS=(
  ''
  'agents'
  'auth' 'auth login' 'auth logout' 'auth status'
  'auto-mode' 'auto-mode config' 'auto-mode critique' 'auto-mode defaults' 'auto-mode reset'
  'doctor'
  'gateway'
  'install'
  'setup-token'
  'update'
  'mcp' 'mcp add' 'mcp add-from-claude-desktop' 'mcp add-json' 'mcp get'
  'mcp list' 'mcp login' 'mcp logout' 'mcp remove' 'mcp reset-project-choices' 'mcp serve'
  'plugin' 'plugin details' 'plugin disable' 'plugin enable' 'plugin eval'
  'plugin eval init' 'plugin init' 'plugin install' 'plugin list' 'plugin prune'
  'plugin tag' 'plugin uninstall' 'plugin update' 'plugin validate'
  'plugin marketplace' 'plugin marketplace add' 'plugin marketplace list'
  'plugin marketplace remove' 'plugin marketplace update'
  'project' 'project purge'
  'ultrareview'
  # Hidden from top-level `--help`, but invokable and completed by src/_claude.
  'import-conversations'
)

# Hidden commands whose `--help` is hand-rolled rather than commander-generated.
typeset -ga RAW_COMMANDS=(
  'daemon'
  'remote-control'
)

# Feature-gated as of 2.1.220: present in the binary, NOT invokable (they fall
# back to parent help). Probed every run — one of these going live is exactly
# the drift signal this tool exists for.
typeset -ga GATED_WATCHLIST=(
  'mcp xaa' 'mcp xaa setup' 'mcp xaa show'
  'import' 'import codex' 'import gemini'
)

# Undocumented top-level flags. Mining flags out of `strings` is too noisy, so
# this list is hand-curated; the probe below proves whether each still exists.
typeset -ga FLAG_WATCHLIST=(
  '--system-prompt-file'
  '--append-system-prompt-file'
)

# Subcommand names that appear in every commander roster and are not worth walking.
typeset -ga UNWALKED_IGNORE=( 'help' )

typeset -ga OUT_COMMANDS=() OUT_RAW=() OUT_REG=() OUT_PROBE_CMD=() OUT_PROBE_FLAG=() OUT_UNWALKED=()
typeset -gA SEEN_SUBNAMES=()
# Canonical (first-alias) child names from the most recent parse_commander call.
# A global, not a return value: capturing it via $(...) would run the parser in
# a subshell and throw away everything it appends to OUT_COMMANDS.
typeset -ga LAST_SUBS=()

typeset -ga _TMPFILES=()

_cleanup() { (( ${#_TMPFILES} )) && rm -f -- "${_TMPFILES[@]}"; return 0 }
trap _cleanup EXIT INT TERM

die() { print -ru2 -- "check-drift: $*"; exit 2 }

# Sets $REPLY to a fresh temp file, registered for cleanup on any exit.
# `REPLY=$(mktemp)` keeps the assignment in the current shell — a `$(...)`
# wrapper around the whole helper would lose the _TMPFILES append to a subshell.
new_tmpfile() {
  REPLY=$(mktemp) || die "mktemp failed"
  _TMPFILES+=("$REPLY")
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# Longest quoted-string list inside a commander `(choices: "a", "b")` blob.
extract_choices() {
  local d=$1
  [[ $d == *choices:* ]] || return 0
  local seg=${d#*choices:}
  seg=${seg%%\)*}
  seg=${seg%%, preset:*}
  local -a toks
  local rest=$seg
  while [[ $rest == *\"*\"* ]]; do
    rest=${rest#*\"}          # step past the opening quote
    toks+=("${rest%%\"*}")    # everything up to the closing quote is the value
    rest=${rest#*\"}          # step past the closing quote
  done
  (( ${#toks} )) || return 0
  print -r -- "${toks[*]}"
}

# Canonical key for an option spec: its last long form, else its first token.
flag_key() {
  local spec=${1//,/ } t k=''
  for t in ${(s: :)spec}; do
    [[ $t == --* ]] && k=$t
  done
  [[ -n $k ]] || k=${${(s: :)spec}[1]}
  print -r -- $k
}

# Run a command with a wall-clock cap, combining stdout+stderr. Returns 124 on
# timeout. Needed because a *boolean* hidden flag, if one is ever added to
# FLAG_WATCHLIST, would launch an interactive session instead of erroring out.
run_capped() {
  local secs=$1; shift
  local tmp; new_tmpfile; tmp=$REPLY
  _TMPFILES+=("$tmp.done")
  { "$@" </dev/null >|"$tmp" 2>&1; print -n x >|"$tmp.done" } &!
  local waited=0
  while (( waited < secs * 10 )) && [[ ! -e $tmp.done ]]; do
    sleep 0.1
    (( waited += 1 ))
  done
  local rc=0
  [[ -e $tmp.done ]] || rc=124
  cat -- "$tmp"
  rm -f -- "$tmp" "$tmp.done"
  return $rc
}

# NOTE: never name a local `path` in this file — zsh ties `path` to `PATH`, so a
# `local path=...` silently wipes the command search path for that function's
# whole dynamic scope (grep/head/sed all vanish). Use `cmdpath`.

# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

# parse_commander <label> <help-text>
# Appends `<label> | usage|opt|choices|sub | ...` lines to OUT_COMMANDS and sets
# LAST_SUBS to this command's canonical child names.
parse_commander() {
  local label=$1
  local -a lines
  lines=("${(@f)2}")
  LAST_SUBS=()

  local line stripped t indent head rest section='' name a
  local cur_spec='' cur_desc=''
  local -a entry_out=() aliases=()

  _flush_opt() {
    [[ -n $cur_spec ]] || return 0
    entry_out+=("$label | opt | $cur_spec")
    local ch
    ch=$(extract_choices "$cur_desc")
    [[ -n $ch ]] && entry_out+=("$label | choices | $(flag_key "$cur_spec") = $ch")
    cur_spec='' cur_desc=''
  }

  for line in "${lines[@]}"; do
    stripped=${line##[[:space:]]##}
    t=${stripped%%[[:space:]]##}
    indent=$(( ${#line} - ${#stripped} ))

    if (( indent == 0 )) && [[ -n $t ]]; then
      _flush_opt
      case $t in
        Usage:*)    entry_out+=("$label | usage | ${${t#Usage:}##[[:space:]]##}"); section='' ;;
        Options:)   section=opt ;;
        Commands:)  section=cmd ;;
        Arguments:) section=arg ;;
        *)          section='' ;;
      esac
      continue
    fi

    [[ -n $t ]] || continue

    head=${t%%  *}
    head=${head%%[[:space:]]##}
    rest=''
    [[ $t != "$head" ]] && rest=${${t#"$head"}##[[:space:]]##}

    case $section in
      opt)
        if (( indent == 2 )) && [[ $t == -* ]]; then
          _flush_opt
          cur_spec=$head
          cur_desc=$rest
        elif [[ -n $cur_spec ]]; then
          cur_desc="$cur_desc $t"
        fi
        ;;
      cmd)
        (( indent == 2 )) || continue
        name=${head%% *}
        # Guard against prose that commander embeds inside a command's
        # description at the same indent (e.g. `Examples:` under `mcp add`).
        [[ $name == [A-Za-z][A-Za-z0-9_.\|-]# ]] || continue
        aliases=(${(s:|:)name})
        for a in "${aliases[@]}"; do
          entry_out+=("$label | sub | $a")
          SEEN_SUBNAMES[$a]=1
        done
        # Only the first alias is walked; the rest resolve to the same command.
        LAST_SUBS+=("${aliases[1]}")
        ;;
    esac
  done
  _flush_opt
  unfunction _flush_opt

  OUT_COMMANDS+=("${(@)entry_out}")
}

# parse_raw <label> <help-text>
# Hand-rolled help (daemon, remote-control): keep the usage line, anything that
# looks like a flag, and any `<head><2+ spaces><description>` entry; drop prose.
parse_raw() {
  local label=$1
  local cmdpath=${label#claude}
  cmdpath=${cmdpath##[[:space:]]##}
  local -a lines
  lines=("${(@f)2}")

  local line stripped t indent head name
  local usage_seen=0

  for line in "${lines[@]}"; do
    stripped=${line##[[:space:]]##}
    t=${stripped%%[[:space:]]##}
    [[ -n $t ]] || continue
    indent=$(( ${#line} - ${#stripped} ))

    if (( ! usage_seen )); then
      if [[ $t == (#i)usage:[[:space:]]#claude[[:space:]]* ]]; then
        OUT_RAW+=("$label | usage | ${${t#[Uu]sage:}##[[:space:]]##}")
        usage_seen=1
        continue
      elif [[ $t == "claude $cmdpath"(|" "*) ]]; then
        OUT_RAW+=("$label | usage | $t")
        usage_seen=1
        continue
      fi
    fi

    head=${t%%  *}
    head=${head%%[[:space:]]##}

    # `- prose bullet` must not be mistaken for a flag: require -x / --x / --[no-]x
    if [[ $t == (#b)(-[-a-zA-Z\[]*) ]]; then
      OUT_RAW+=("$label | opt | $head")
    elif [[ $t != "$head" ]]; then
      name=${head%% *}
      [[ $name == [A-Za-z][A-Za-z0-9_.\|-]# ]] && OUT_RAW+=("$label | sub | $head")
    fi
  done
}

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------

# Live if the command's own usage line appears; otherwise it fell back to the
# parent's / top-level help, which is how commander presents a gated command.
probe_command() {
  local cmdpath=$1 out line t first='' live=0
  out=$(claude ${=cmdpath} --help 2>&1)
  for line in "${(@f)out}"; do
    t=${${line##[[:space:]]##}%%[[:space:]]##}
    [[ -n $t ]] || continue
    [[ -n $first ]] || first=$t
    # Its own usage line, in either commander (`Usage: claude x`) or the
    # hand-rolled (`claude x` under a USAGE header) layout.
    if [[ $t == (Usage:[[:space:]]##|)claude" $cmdpath"(|[[:space:]]*) ]]; then
      live=1
      break
    fi
  done
  if (( live )); then
    OUT_PROBE_CMD+=("probe-command | $cmdpath | invokable")
  else
    OUT_PROBE_CMD+=("probe-command | $cmdpath | not-invokable (got: $first)")
  fi
}

# `claude <flag>` with no value: commander answers
#   "option '--x <val>' argument missing"  -> recognized, and reveals the placeholder
#   "unknown option '--x'"                 -> not present in this build
probe_flag() {
  local flag=$1 out rc
  out=$(run_capped 15 claude "$flag"); rc=$?
  out=${out//$'\n'/ }
  if (( rc == 124 )); then
    OUT_PROBE_FLAG+=("probe-flag | $flag | inconclusive (no error within timeout; boolean flag?)")
  elif [[ $out == *"unknown option"* ]]; then
    OUT_PROBE_FLAG+=("probe-flag | $flag | unrecognized")
  elif [[ $out == (#b)*"option '"([^\']##)"' argument missing"* ]]; then
    OUT_PROBE_FLAG+=("probe-flag | $flag | recognized ${match[1]}")
  else
    OUT_PROBE_FLAG+=("probe-flag | $flag | inconclusive (${out[1,120]})")
  fi
}

# ---------------------------------------------------------------------------
# Dump builder
# ---------------------------------------------------------------------------

build_dump() {
  local version bin c s label help
  local -a walked=() subs

  command -v claude >/dev/null 2>&1 || die "no 'claude' on PATH"
  version=$(claude --version 2>&1 | head -1)
  bin=$(readlink -f "$(command -v claude)" 2>/dev/null) || bin=''
  [[ -n $bin ]] || bin=$(command -v claude)

  # --- walk the roster -----------------------------------------------------
  typeset -A CHILDREN=()
  for c in "${COMMANDS[@]}"; do
    label="claude${c:+ $c}"
    walked+=("$c")
    help=$(claude ${=c} --help 2>&1)
    # A subcommand that silently fell back to top-level help would poison the
    # dump (this is the ${=c} bug's signature). Catch it instead.
    if [[ -n $c ]] && ! print -r -- "$help" | grep -q "^Usage: claude ${c%% *}"; then
      die "'claude $c --help' did not print help for that command; roster is stale or the walk is broken"
    fi
    parse_commander "$label" "$help"
    for s in "${LAST_SUBS[@]}"; do
      [[ -n $s ]] && CHILDREN[${c:+$c }$s]=1
    done
  done

  for c in "${RAW_COMMANDS[@]}"; do
    walked+=("$c")
    parse_raw "claude $c" "$(claude ${=c} --help 2>&1)"
  done

  # --- roster gaps: children the CLI advertises but we never walk -----------
  local child
  for child in ${(k)CHILDREN}; do
    [[ ${UNWALKED_IGNORE[(Ie)${child##* }]} -gt 0 ]] && continue
    [[ ${walked[(Ie)$child]} -gt 0 ]] && continue
    OUT_UNWALKED+=("unwalked | $child")
  done

  # --- registrations mined from the native binary --------------------------
  local -a regs=()
  if [[ -r $bin ]]; then
    regs=("${(@f)$(strings -n 8 "$bin" 2>/dev/null |
                    grep -oE '\.command\("[^"]+"\)' |
                    sed -e 's/^\.command("//' -e 's/")$//' |
                    sort -u)}")
  fi
  local r
  for r in "${regs[@]}"; do
    [[ -n $r ]] && OUT_REG+=("registration | $r")
  done

  # --- probe registrations we do not already know about --------------------
  local -a candidates=()
  for r in "${regs[@]}"; do
    [[ -n $r ]] || continue
    local n=${r%% *}
    [[ -n ${SEEN_SUBNAMES[$n]-} ]] && continue
    [[ ${walked[(Ie)$n]} -gt 0 ]] && continue
    [[ ${candidates[(Ie)$n]} -gt 0 ]] && continue
    candidates+=("$n")
  done
  local p
  for p in ${(o)candidates}; do probe_command "$p"; done
  for p in "${GATED_WATCHLIST[@]}"; do
    [[ ${candidates[(Ie)$p]} -gt 0 ]] && continue
    probe_command "$p"
  done

  for p in "${FLAG_WATCHLIST[@]}"; do probe_flag "$p"; done

  # --- emit ----------------------------------------------------------------
  print -r -- "# Claude Code CLI surface — generated by tools/check-drift.zsh"
  print -r -- "# Do not hand-edit; regenerate with: zsh tools/check-drift.zsh snapshot"
  print -r -- "version | $version"
  print -r --
  print -r -- "# --- commands (commander-generated help) ---"
  print -rl -- "${(@)OUT_COMMANDS}" | sort
  print -r --
  print -r -- "# --- commands (hand-rolled help; heuristic parse) ---"
  print -rl -- "${(@)OUT_RAW}" | sort
  print -r --
  print -r -- "# --- .command() registrations mined from the binary ---"
  print -rl -- "${(@)OUT_REG}" | sort
  print -r --
  print -r -- "# --- probes: commands registered but not walked above ---"
  if (( ${#OUT_PROBE_CMD} )); then
    print -rl -- "${(@)OUT_PROBE_CMD}" | sort
  else
    print -r -- "probe-command | (none)"
  fi
  print -r --
  print -r -- "# --- probes: undocumented top-level flags ---"
  print -rl -- "${(@)OUT_PROBE_FLAG}" | sort
  print -r --
  print -r -- "# --- subcommands advertised by the CLI but not walked by this tool ---"
  if (( ${#OUT_UNWALKED} )); then
    print -rl -- "${(@)OUT_UNWALKED}" | sort
  else
    print -r -- "unwalked | (none)"
  fi
}

# Strip trailing whitespace so the dump can never carry invisible churn.
# build_dump is deliberately NOT piped into sed: it calls die() on a fatal
# error, and an `exit` inside a pipeline segment only kills that subshell —
# the script would report the problem and then exit 0 anyway.
build_dump_clean() {
  local raw; new_tmpfile; raw=$REPLY
  build_dump >|"$raw"
  sed -e 's/[[:space:]]*$//' -- "$raw"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local mode=${1:-check}
  case $mode in
    -h|--help|help)
      sed -n '3,40p' "$SCRIPT_PATH" | sed -e 's/^# \{0,1\}//'
      return 0
      ;;
    dump)
      build_dump_clean
      return 0
      ;;
    snapshot)
      local tmp; new_tmpfile; tmp=$REPLY
      build_dump_clean >|"$tmp"
      cp -- "$tmp" "$SNAPSHOT"
      chmod 644 "$SNAPSHOT"   # mktemp gives 0600; this file gets committed (BSD chmod rejects --)
      print -r -- "check-drift: wrote $SNAPSHOT ($(wc -l <"$SNAPSHOT" | tr -d ' ') lines)"
      return 0
      ;;
    check)
      [[ -r $SNAPSHOT ]] || die "no snapshot at $SNAPSHOT — run: zsh tools/check-drift.zsh snapshot"
      local tmp; new_tmpfile; tmp=$REPLY
      build_dump_clean >|"$tmp"
      if diff -u --label "$SNAPSHOT (committed)" --label "installed CLI (now)" \
             -- "$SNAPSHOT" "$tmp"; then
        print -r -- "check-drift: no drift — installed CLI matches ${SNAPSHOT:t}"
        return 0
      fi
      print -ru2 -- ""
      print -ru2 -- "check-drift: DRIFT DETECTED. Update src/_claude and tests/ to match,"
      print -ru2 -- "             then re-snapshot: zsh tools/check-drift.zsh snapshot"
      return 1
      ;;
    *)
      die "unknown mode '$mode' (expected: check | snapshot | dump)"
      ;;
  esac
}

main "$@"

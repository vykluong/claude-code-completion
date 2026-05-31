#!/usr/bin/env zsh
# completions.test.zsh — regression tests for the Claude Code zsh completion.
#
# The guarantee this enforces: `claude <TAB>` (and each subcommand's <TAB>)
# offers EVERY command/subcommand the live binary actually accepts — not just
# the subset shown in `claude --help`. This is the exact class of bug that
# shipped once (daemon and the other hidden-but-real commands were missing
# from the bare-TAB list); this test fails if it ever regresses.
#
# Oracle: zsh's own `compadd -O` test mode (deterministic, prefix-aware) driven
# through a zpty. We deliberately do NOT screen-scrape a rendered menu — that
# method silently drops entries from multi-column lists and gave false
# confidence before.
#
# Usage:  zsh test/completions.test.zsh
# Exit:   0 = all pass, 1 = a failure (prints what's missing).

emulate -L zsh
setopt no_unset
zmodload zsh/zpty

local SCRIPT_DIR=${0:A:h}
local SRC=${SCRIPT_DIR:h}/src
[[ -r $SRC/_claude ]] || { print -u2 "FATAL: $SRC/_claude not found"; exit 2; }
(( $+commands[claude] )) || { print -u2 "FATAL: 'claude' binary not on PATH"; exit 2; }

# Set up mock configuration directory to ensure isolated, portable tests (F3)
local MOCK_CLAUDE_DIR=$(mktemp -d)
export CLAUDE_CONFIG_DIR=$MOCK_CLAUDE_DIR

mkdir -p "$MOCK_CLAUDE_DIR/plugins"
cat >"$MOCK_CLAUDE_DIR/plugins/installed_plugins.json" <<EOF
{
  "plugins": {
    "test-installed-plugin": {}
  }
}
EOF

cat >"$MOCK_CLAUDE_DIR/plugins/plugin-catalog-cache.json" <<EOF
{
  "catalog": {
    "plugins": {
      "test-available-plugin": {}
    }
  }
}
EOF

cat >"$MOCK_CLAUDE_DIR/plugins/known_marketplaces.json" <<EOF
{
  "test-marketplace": {}
}
EOF

# ---- candidate capture via compadd -O ---------------------------------------
local INNER=$(mktemp); local ZDUMP=$(mktemp -u)
cat >$INNER <<INNEREOF
emulate zsh
setopt no_beep
fpath=($SRC \$fpath)
autoload -Uz compinit; compinit -u -d $ZDUMP
_audit_compadd() {
  local -a _m; builtin compadd -O _m "\$@" 2>/dev/null
  local v; for v in "\${_m[@]}"; do print -r -- "CAND:\$v"; done
  builtin compadd "\$@"
}
functions[compadd]=\$functions[_audit_compadd]
_audit_run() { print -r -- BEGIN; zle list-choices 2>/dev/null; print -r -- END; zle kill-whole-line 2>/dev/null }
zle -N _audit_run; bindkey '^X^A' _audit_run
PROMPT='R> '; print -r -- READY
INNEREOF

# complete_for "claude mcp " -> prints offered candidates, one per line
complete_for() {
  local buffer=$1 out acc='' ; integer n=0
  zpty CT zsh -f
  zpty -w CT "source $INNER"
  while (( n++ < 300 )); do zpty -r CT out 2>/dev/null || break; acc+=$out; [[ $acc == *READY* ]] && break; done
  zpty -w -n CT "$buffer"; zpty -w -n CT $'\C-x\C-a'
  acc=''; n=0
  while (( n++ < 800 )); do zpty -r CT out 2>/dev/null || break; acc+=$out; [[ $acc == *END* ]] && break; done
  zpty -d CT 2>/dev/null
  print -r -- $acc | tr -d '\r' | awk '/BEGIN/{o=1;next}/END/{o=0}o&&/^CAND:/{sub(/^CAND:/,"");if($0&&$0!="nosort"&&$0!~/^_tmp/&&$0!~/:[|]/&&!s[$0]++)print}'
}

# ---- assertion helpers ------------------------------------------------------
integer FAILS=0 CHECKS=0
have() { (( ${offered[(I)$1]} )) }   # is $1 in the $offered array?

assert_offers() {  # assert_offers "<label>" "<buffer>" expected1 expected2 ...
  local label=$1 buffer=$2; shift 2
  local -a offered; offered=( ${(f)"$(complete_for "$buffer")"} )
  local -a missing; local e
  for e in "$@"; do have "$e" || missing+=$e; done
  (( CHECKS++ ))
  if (( ${#missing} )); then
    (( FAILS++ ))
    print -r -- "FAIL  $label"
    print -r -- "      buffer : [$buffer]"
    print -r -- "      missing: ${missing}"
    print -r -- "      offered: ${offered}"
  else
    print -r -- "ok    $label  (${#offered} offered)"
  fi
}

# ---- ground truth: real top-level commands, straight from the binary --------
# A name is a real command iff `claude <name> --help` echoes its own usage.
binary_has_command() {
  local c=$1 u
  u=$(timeout 12 claude "$c" --help </dev/null 2>&1 | grep -m1 -iE '^usage:|^USAGE')
  # remote-control/rc use an uppercase custom "USAGE" banner with no name line
  [[ $u == *"claude $c"* || ( $c == (remote-control|rc) && -n $u ) || $c == (remote-control|rc) ]]
}

print -r -- "== Claude Code zsh completion — regression tests =="
print -r -- "src: $SRC   binary: $(claude --version 2>/dev/null)"
print -r -- ""

# 1) TOP-LEVEL: every real command must be offered by bare `claude <TAB>`.
local -a expect_cmds
local cand
for cand in agents auth auto-mode doctor install mcp plugin project setup-token \
            ultrareview update remote-control import-conversations daemon \
            attach logs respawn rm stop ; do
  binary_has_command $cand && expect_cmds+=$cand
done
assert_offers "top-level lists every real command" "claude " $expect_cmds

# 2) Subcommand listings must match each parent's `--help`.
assert_offers "mcp subcommands"     "claude mcp "     serve add add-json add-from-claude-desktop get list remove reset-project-choices
assert_offers "auth subcommands"    "claude auth "    login logout status
assert_offers "auto-mode subcommands" "claude auto-mode " config critique defaults
assert_offers "plugin subcommands"  "claude plugin "  details disable enable init install list marketplace prune tag uninstall update validate
assert_offers "plugin marketplace"  "claude plugin marketplace " add list remove update
assert_offers "daemon subcommands"  "claude daemon "  run status logs uninstall stop

# 3) Spot-check option presence (the variadic + bg-session -h fixes).
assert_offers "mcp add options"     "claude mcp add -" --callback-port --client-id --client-secret --env --header --scope --transport --help
assert_offers "attach offers -h"    "claude attach -"  --help
assert_offers "global tool options" "claude -"         --tools --allowedTools --disallowedTools --model --permission-mode

# 4) Value enums resolve.
assert_offers "permission-mode enum" "claude --permission-mode " acceptEdits auto bypassPermissions default dontAsk plan
assert_offers "transport enum"       "claude mcp add --transport " stdio sse http

# 5) Dynamic value completions & option fixes.
assert_offers "plugin disable offers installed plugins" "claude plugin disable " test-installed-plugin
assert_offers "plugin install offers available plugins" "claude plugin install " test-available-plugin
assert_offers "marketplace remove offers configured marketplaces" "claude plugin marketplace remove " test-marketplace
assert_offers "daemon stop options" "claude daemon stop -" --any --keep-workers --help
assert_offers "daemon status options" "claude daemon status -" --help
assert_offers "setting-sources completion" "claude --setting-sources " user project local
assert_offers "tools comma completion" "claude --tools Bash," Edit

# 6) MCP dynamic completion tests (creating temporary .mcp.json)
cat >.mcp.json <<EOF
{
  "mcpServers": {
    "test-mcp-server-a": {},
    "test-mcp-server-b": {}
  }
}
EOF
assert_offers "mcp get offers local mcp servers" "claude mcp get " test-mcp-server-a test-mcp-server-b
rm -f .mcp.json

# 7) Session dynamic completion tests
local mock_session_dir="$CLAUDE_CONFIG_DIR/sessions"
mkdir -p "$mock_session_dir"
cat >"$mock_session_dir/999999.json" <<EOF
{"pid":999999,"sessionId":"test-session-uuid-123","cwd":"/tmp","startedAt":1780000000000,"kind":"bg","name":"test-session-name","status":"idle"}
EOF
assert_offers "attach offers active sessions" "claude attach " test-session-uuid-123
rm -f "$mock_session_dir/999999.json"

rm -f $INNER
rm -rf "$MOCK_CLAUDE_DIR"
print -r -- ""
print -r -- "== $((CHECKS-FAILS))/$CHECKS checks passed =="
(( FAILS == 0 )) || { print -u2 -r -- "REGRESSION: $FAILS check(s) failed."; exit 1 }
print -r -- "All completion regression checks passed."

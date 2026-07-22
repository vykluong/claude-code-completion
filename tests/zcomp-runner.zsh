#!/usr/bin/env zsh
# Capture the completion candidates _claude offers for a given buffer.
# Usage:  zsh tests/zcomp-runner.zsh 'claude '           # single TAB (default)
#         DOUBLE_TAB=1 zsh tests/zcomp-runner.zsh 'claude '   # press TAB twice
# Output: sorted unique candidates, one per line. `_message` hints print as "MSG: <text>".
# Exit is always 0; assert on output content.
set -u
BUF=$1
REPO=${0:A:h:h}
WORK=$(mktemp -d)
LOG=$WORK/cap.log
mkdir -p $WORK/home
cat > $WORK/home/.zshrc <<EOF
fpath=($REPO/src \$fpath)
autoload -U compinit
compinit -u -d $WORK/home/zcompdump
compadd() { local -a m; builtin compadd -O m "\$@" 2>/dev/null; (( \$#m )) && print -rl -- "\$m[@]" >> \$CAPLOG; builtin compadd "\$@"; }
_message() { print -r -- "MSG: \$*" >> \$CAPLOG }
unset zle_bracketed_paste
PS1='ZC> '
EOF
zmodload zsh/zpty

wait_prompt() {
  local chunk out="" i=0
  while (( i++ < 50 )); do
    sleep 0.1
    while zpty -r -t Z chunk 2>/dev/null; do out+=$chunk; done
    [[ $out == *"ZC>"* ]] && return 0
  done
  return 1
}

attempt() {
  : > $LOG
  zpty -b Z "TERM=xterm ZDOTDIR=$WORK/home CAPLOG=$LOG zsh -i"
  wait_prompt || { zpty -d Z 2>/dev/null; return 1 }
  local chunk
  zpty -n -w Z $'\n'
  wait_prompt
  zpty -n -w Z "$BUF"
  sleep 0.3
  zpty -n -w Z $'\t'
  sleep 1
  if [[ ${DOUBLE_TAB:-0} == 1 ]]; then
    zpty -n -w Z $'\t'
    sleep 1
  fi
  while zpty -r -t Z chunk 2>/dev/null; do :; done
  zpty -d Z 2>/dev/null
}

for i in {1..8}; do
  attempt
  [[ -s $LOG ]] && break
done
sort -u $LOG
rm -rf $WORK

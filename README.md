# Zsh Completion for Claude Code

[![CI](https://github.com/vykluong/claude-code-completion/actions/workflows/ci.yml/badge.svg)](https://github.com/vykluong/claude-code-completion/actions/workflows/ci.yml)

A Zsh completion script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/cli-usage), written by Claude Code. Generated against Claude Code CLI 2.1.220.

## Install with Claude Code

Clone the repository and start a session in it:

```bash
git clone https://github.com/vykluong/claude-code-completion
cd claude-code-completion
claude
```

Then ask Claude Code to "install the zsh completion script in `src/_claude` for me." It will read the script and run the manual steps below on your behalf — no project configuration required.

## Install manually

[`src/_claude`](src/_claude) is a standard Zsh completion script, installed like any other:

```zsh
mkdir -p ~/.zsh/completions
cp src/_claude ~/.zsh/completions/
# in ~/.zshrc, BEFORE compinit:
fpath=(~/.zsh/completions $fpath)
autoload -U compinit && compinit
```

If `claude <TAB>` completes nothing afterwards, the cause is usually a stale completion cache rather than the script itself — common with oh-my-zsh, which manages its own `.zcompdump`. Clear it and restart your shell:

```zsh
rm -f ~/.zcompdump*
exec zsh
```

## Usage

### Command discovery

Press TAB after `claude ` (with a trailing space) to list every command and subcommand.

![Pressing TAB after `claude ` lists all top-level commands](img/list_opt.svg)

### Context-aware completion

Press TAB partway through a command — `claude mcp re`, say — to narrow the list to matches valid in that context.

![Pressing TAB after `claude mcp re` filters to remove and reset-project-choices](img/comp_words.svg)

### Option discovery

Press TAB after `claude -` to list the flags and options available on the current command.

![Pressing TAB after `claude -` lists all available flags](img/comp_flags.svg)

## Testing

Run `zsh tests/zcomp-runner.zsh 'claude '` to print the candidates the script offers for a given buffer.

## License

MIT — see [LICENSE](LICENSE).

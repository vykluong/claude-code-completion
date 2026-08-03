# Zsh Completion for Claude Code

[![CI](https://github.com/vykluong/claude-code-completion/actions/workflows/ci.yml/badge.svg)](https://github.com/vykluong/claude-code-completion/actions/workflows/ci.yml)

A Zsh shell completion script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/cli-usage), created by Claude Code.

## Compatibility

Generated against Claude Code CLI 2.1.220.

## Install with Claude Code

Clone this repository, then open Claude Code in the project directory and ask it to install the completion for you.

```bash
git clone https://github.com/vykluong/claude-code-completion
cd claude-code-completion
claude
```

Once inside the session, ask Claude Code to "install the zsh completion script in `src/_claude` for me." No project configuration file is required — Claude Code will read the script and follow the manual install steps below on your behalf.

## Install Manually

This is a standard Zsh [completion script](src/_claude) that can be installed like any other completion script.

```zsh
mkdir -p ~/.zsh/completions
cp src/_claude ~/.zsh/completions/
# in ~/.zshrc, BEFORE compinit:
fpath=(~/.zsh/completions $fpath)
autoload -U compinit && compinit
```

**Troubleshooting:** if `claude <TAB>` completes nothing after installing, it's usually a stale completion cache rather than a problem with the script (this is common with oh-my-zsh, which manages its own `.zcompdump`). Delete the cache and restart your shell:

```zsh
rm -f ~/.zcompdump*
exec zsh
```

See also: [Installing Zsh Completions](https://apple.github.io/swift-argument-parser/documentation/argumentparser/installingcompletionscripts#Installing-Zsh-Completions)

## Usage

### Command Discovery
Press TAB after `claude ` (with trailing whitespace) to see all available commands and subcommands.
![Tab to list options](img/list_opt.svg)

### Context-Aware Completion
Press TAB while typing a partial command (e.g., `claude mcp re`) to see filtered options that match your input within that context.
![Tab to complete options](img/comp_words.svg)

### Option Discovery
Press TAB after `claude -` to display all available flags and options for the current command.
![Tab to list flags](img/comp_flags.svg)

## Testing

Run `zsh tests/zcomp-runner.zsh 'claude '` to print the completion candidates the script currently offers for a given buffer.

## License

MIT — see [LICENSE](./LICENSE).

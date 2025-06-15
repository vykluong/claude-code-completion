# Zsh Completion for Claude Code

A Zsh shell completion script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/cli-usage), created by Claude Code.

## Install with Claude Code

Clone this repository and run Claude Code in the project directory.

```bash
git clone https://github.com/vyluong/claude-code-completion
cd claude-code-completion
claude init
```
Claude Code will automatically read the [CLAUDE.md](./CLAUDE.md) file and set up shell completion with your guidance.

## Install Manually

This is a standard Zsh [completion script](src/_claude) that can be installed like any other completion script. 

Example: [Installing Zsh Completions](https://apple.github.io/swift-argument-parser/documentation/argumentparser/installingcompletionscripts#Installing-Zsh-Completions)


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

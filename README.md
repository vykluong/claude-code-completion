# Zsh Completion for Claude Code

A Zsh shell completion script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/cli-usage), created by Claude Code.

![Demo usage](demo.gif)

## Install with Claude Code

Clone this repository and run Claude Code in the project directory.

```bash
git clone https://github.com/vyluong/claude-code-completion
cd claude-code-completion
claude
```
Claude Code will automatically read the [CLAUDE.md](./CLAUDE.md) file and set up shell completion for you.

## Install Manually

This is a standard Zsh [completion script](src/_claude) that can be installed like any other completion script. 

Example: [Installing Zsh Completions](https://apple.github.io/swift-argument-parser/documentation/argumentparser/installingcompletionscripts#Installing-Zsh-Completions)

## Usage

After installation, use tab completion by typing `claude` followed by a space and pressing `<TAB>`:

```bash
claude <TAB>        # Shows available commands
claude config <TAB> # Shows config subcommands  
claude -<TAB>       # Shows available flags
```

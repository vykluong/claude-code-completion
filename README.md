# Zsh Completion for Claude Code

A Zsh shell completion script for [Claude Code](https://code.claude.com/docs/en/cli-usage).

---

**Command Discovery.** Press TAB after `claude ` (with trailing whitespace) to see all available commands and subcommands.
![Tab to list options](img/list_opt.svg)

**Context-Aware Completion**. Press TAB while typing a partial command (e.g., `claude mcp re`) to see filtered options that match your input within that context.
![Tab to complete options](img/comp_words.svg)

**Option Discovery**. Press TAB after `claude -` to display all available flags and options for the current command.
![Tab to list flags](img/comp_flags.svg)

**Hidden Command Discovery**. Autocompletes functional commands and flags hidden from `claude --help` (e.g., `rc`, `daemon`, `import-conversations`, background-session commands, and experimental flags)

**Dynamic completion**: 
* *Active Sessions.* Autocompletes active background session IDs, short names, and statuses by querying the Claude daemon
* *Plugin & Marketplace*: Autocompletes names for plugin and marketplace operations
* *Comma-Separated Multi-Values*: Supports comma-separated completions for multi-value options

## Install

*(Optional)* **Recommended dependencies** to enable advanced dynamic completions:
* *[jq](https://jqlang.github.io/jq/)*
* *[git](https://git-scm.com/)*

---

This is a standard Zsh [completion script](src/_claude) that can be installed like any other completion script. 

Example: [Installing Zsh Completions](https://apple.github.io/swift-argument-parser/
documentation/argumentparser/installingcompletionscripts#Installing-Zsh-Completions)
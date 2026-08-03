# Changelog

All notable changes to the `_claude` zsh completion script are documented in
this file, one section per `cli-<version>` tag.

## Release process

1. `claude update` — pull the latest Claude Code CLI.
2. `zsh tools/check-drift.zsh` — detect drift between the installed CLI and
   the committed CLI-surface snapshot (`tools/cli-surface.txt`); rerun with
   `snapshot` to accept the new surface.
3. Fix `src/_claude` to close any gaps found.
4. Run the test suite: `zsh tests/run-tests.zsh` (golden files in
   `tests/cases/`; regenerate changed expectations with
   `zsh tests/zcomp-runner.zsh '<buffer>'`).
5. Bump the target-version header comment in `src/_claude` (currently line 4).
6. Update this CHANGELOG with a new section.
7. Tag the release: `git tag -a cli-<version> -m "verified against Claude Code <version>"`.
8. Push the tag: `git push origin cli-<version>`.
9. Create a GitHub release from the tag.

## [cli-2.1.220] - 2026-08-02

Verified against Claude Code CLI 2.1.220.

- `--tmux` now completes an optional `=classic` value (the CLI accepts the
  value only in the `--tmux=classic` form).
- Added hidden flags `--system-prompt-file` and `--append-system-prompt-file`
  (probe-verified; absent from `claude --help`).
- Added help dispatch for `auto-mode config` and `auth logout`.
- `--model` (top-level and `agents`) now also completes full model names and
  the `haiku` alias.
- New tooling: golden-file test suite (`tests/run-tests.zsh`, 32 cases),
  CLI drift checker (`tools/check-drift.zsh`), GitHub Actions CI.

[cli-2.1.220]: https://github.com/vykluong/claude-code-completion/releases/tag/cli-2.1.220

## [cli-2.1.217] - Regenerate _claude completions against CLI 2.1.217 and add zcomp test runner

Verified against Claude Code CLI 2.1.217. Regenerated the command/option
tables from `claude --help` (and per-subcommand `--help` output) and added
the `tests/zcomp-runner.zsh` test harness.

[cli-2.1.217]: https://github.com/vykluong/claude-code-completion/commit/1833ca5b1559c9350e5a6718aefbeffd56db4b6b

## [Initial release] - Add README and completion script

First published version of the `_claude` zsh completion script and README.

[Initial release]: https://github.com/vykluong/claude-code-completion/commit/5222b457ae3af2d7ed25bb54d45cfca9ff2d5e93

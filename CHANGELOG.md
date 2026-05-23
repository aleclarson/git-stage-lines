# Changelog

All notable changes to this project will be documented in this file.

## 0.2.2 - 2026-05-23

### Documentation

- Added concrete range and line-ref examples to the CLI help output for AI agents and other automation users.

## 0.2.1 - 2026-04-25

### Added

- Bundled native npm package binaries for macOS, Linux, and Windows on x64 and arm64.
- Added an npm CLI shim that dispatches to the bundled native binary.

## 0.2.0 - 2026-04-25

### Added

- Added the JavaScript/TypeScript npm adapter for Node.js and Bun-compatible runtimes.
- Exported `stageLines`, `stageLinesSync`, `checkStageLines`, `dryRunStageLines`, `findBinary`, public result types, and `GitStageLinesError`.
- Added native binary discovery for explicit `binaryPath`, `GIT_STAGE_LINES_BINARY`, bundled package paths, `git-stage-lines` on `PATH`, and `git stage-lines` fallback.
- Added `git stage-lines diff [FILE...]` to print unstaged changes with stageable `+N:` and `-N:` line references.
- Added `FILE:REFS` shorthand, where positive refs select new-side lines and negative refs select old-side deletion lines.
- Added shell completion generation for Bash, Zsh, and Fish.
- Added `git stage-lines man` to print a generated manual page.
- Added a disposable `playground/` repo fixture with commands for trying the tool safely.
- Added patch behavior corpus docs under `docs/corpus/`.

### Changed

- Staging now uses zero-context patches internally with `git apply --cached --unidiff-zero`.
- `FILE:REFS` staging can select individual added or deleted lines from a contiguous change block.
- `FILE RANGES` staging uses replacement-aware selection for mixed removal/addition blocks.
- Removed `--context N` from the CLI and npm adapter.
- CLI JSON results may report `selected_changes` at a finer granularity than before because selected changed lines are counted more precisely.

### Tests

- Added Vitest coverage for the npm adapter API, binary discovery, argument construction, JSON parsing, and error handling.
- Added Zig coverage for range parsing, file-ref parsing, patch building, generated output commands, and line-number stability.
- Added an end-to-end Zig test that stages a later hunk first, then confirms earlier line numbers remain valid for subsequent staging.

### Documentation

- Updated the README with npm installation and API usage.
- Documented `diff`, `FILE:REFS`, shell completions, man-page generation, and the patch behavior corpus.
- Expanded agent workflow guidance in the README and CLI help.

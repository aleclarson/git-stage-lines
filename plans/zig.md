## Goal

Build a deterministic, agent-friendly Git subcommand that stages selected line ranges from a file’s working-tree changes.

The tool should be invokable as:

```bash
git stage-lines FILE RANGES [options]
```

Example:

```bash
git stage-lines src/app.ts 10-15,22,40-45 --json
```

The tool should stage only the changes that overlap the requested line ranges, without modifying the working tree.

---

## Feature Requirements

### Core command

```bash
git stage-lines FILE RANGES
```

Where:

```text
FILE    One file path
RANGES  Comma-separated 1-based line ranges
```

Supported range forms:

```text
10        single line
10-15     inclusive range
10,15-20  mixed ranges
```

Default behavior:

```text
Stage changes whose working-tree line numbers overlap the requested ranges.
```

---

## Line Selection Modes

The tool should support explicit line-number interpretation modes:

```bash
--mode new
--mode old
--mode both
```

### `--mode new`

Default.

Select changes based on line numbers in the working tree.

Best for:

```text
“Stage lines 10-15 as they appear in the current file.”
```

### `--mode old`

Select changes based on line numbers in the index / preimage side.

Useful for deletions.

### `--mode both`

Select changes if either the old-side or new-side line numbers overlap the requested ranges.

Recommended for agents when they are unsure whether a range includes additions, deletions, or modifications.

---

## Output Modes

### Human-readable output

Default output should be concise:

```text
Staged 3 changes from src/app.ts matching lines 10-15.
```

### JSON output

Required for agents:

```bash
git stage-lines src/app.ts 10-15 --json
```

Example:

```json
{
  "status": "staged",
  "file": "src/app.ts",
  "ranges": ["10-15"],
  "mode": "new",
  "selected_changes": 3,
  "skipped_changes": 8,
  "patch_applied": true
}
```

JSON output should be stable and machine-readable.

---

## Dry Run

The tool should support:

```bash
--dry-run
```

Behavior:

```text
Print the patch that would be staged.
Do not modify the Git index.
```

With `--json`, return structured metadata and include whether the patch would apply cleanly.

---

## Validation

The tool should validate:

```text
- The command is run inside a Git repository.
- FILE refers to exactly one path.
- RANGES are syntactically valid.
- The file has unstaged changes.
- The requested ranges overlap at least one change.
- The generated patch is valid before staging.
```

Invalid input should fail safely with clear errors.

Example JSON error:

```json
{
  "status": "error",
  "reason": "range_does_not_overlap_any_change",
  "file": "src/app.ts",
  "ranges": ["10-15"]
}
```

---

## Supported Change Types

Initial supported scope:

```text
- Modified tracked files
- Added lines
- Deleted lines
- Replaced lines
- Multiple hunks in one file
- Partially staged files
```

Recommended early exclusions:

```text
- Binary files
- Renames
- Copies
- Mode-only changes
- Submodules
- Multiple files in one invocation
```

These can be added later if needed.

---

## Agent-Facing Contract

Agents should be able to rely on this command:

```bash
git stage-lines FILE RANGES --mode both --json
```

The command should:

```text
- Never prompt interactively
- Never open an editor
- Never modify the working tree
- Return nonzero on failure
- Emit valid JSON when --json is provided
- Avoid ambiguous success states
```

Recommended agent default:

```bash
git stage-lines path/to/file 10-15 --mode both --json
```

---

## Tech Stack

### Project Layout

Zig CLI source should live under `src/cli`:

```text
src/
  cli/
    main.zig
    args.zig
    ranges.zig
    diff.zig
    patch.zig
    json.zig
    errors.zig
```

CLI tests and fixtures should live under `test/cli`:

```text
test/
  cli/
    ranges.test.zig
    fixtures/
```

Keep the TypeScript npm adapter under `src/npm` so CLI behavior and adapter behavior stay separate.

---

### Language

```text
Zig
```

Rationale:

```text
- Single native binary
- Good fit for deterministic CLI tools
- Strong control over parsing and memory
- Good long-term maintainability for diff-processing logic
- Easy distribution as a Git subcommand
```

### Git integration

Use the installed `git` executable as the backend for repository operations.

Required Git commands:

```bash
git diff --no-ext-diff -- FILE
git apply --cached --check PATCH
git apply --cached PATCH
```

Git remains responsible for:

```text
- Repository discovery
- Diff generation
- Index mutation
- Patch validation
- Patch application
- Git attributes and normalization behavior
```

Zig owns:

```text
- CLI behavior
- Argument parsing
- Range parsing
- Diff parsing
- Change selection
- Patch reconstruction
- JSON output
- Error classification
```

---

## Dependencies

### Required runtime dependencies

```text
- git
```

The tool should assume the system has a compatible Git executable available on `PATH`.

### Zig dependencies

Recommended:

```text
- Zig standard library only
```

Avoid external dependencies for v1.

Reasons:

```text
- Easier distribution
- Smaller supply-chain surface
- More predictable agent environments
- Simpler static binary releases
```

### Not recommended for v1

```text
- libgit2
- tree-sitter
- language-specific parsers
- shell scripts
- Python helper scripts
```

The tool should operate on Git diffs, not language syntax.

---

## CLI Options

Recommended v1 options:

```text
--mode new|old|both
--dry-run
--json
--context N
--check
--allow-empty
--verbose
```

### `--context N`

Controls how much context to include around selected changes.

Default:

```text
3
```

### `--check`

Validate that the selected patch applies cleanly, but do not stage it.

### `--allow-empty`

Return success if no matching changes are found.

Useful for agents that may issue idempotent staging commands.

### `--verbose`

Include extra human-readable diagnostics.

Should not affect JSON schema.

---

## Exit Codes

Recommended exit-code contract:

```text
0  success
1  user/input error
2  no matching changes
3  generated patch failed validation
4  git command failed
5  unsupported file/change type
```

With `--json`, errors should still return structured JSON.

---

## Recommendations

### Use Git subprocesses, not libgit2

For v1, use the installed `git` executable.

This is the most reliable choice because the tool should match the behavior of the user’s actual Git installation.

### Keep the tool file-scoped

Do not support multiple files in a single invocation initially.

A one-file command is easier for agents to reason about and easier to recover from when something fails.

### Make `--json` first-class

The tool is agent-facing, so structured output should be treated as a core feature rather than an afterthought.

### Default to `--mode new`

For humans, current working-tree line numbers are the most intuitive default.

For agents, recommend `--mode both`.

### Be conservative with unsupported cases

The tool should refuse complex cases rather than stage something surprising.

Unsupported cases should produce clear, structured errors.

### Do not attempt syntax-aware staging

The tool should stage line ranges, not AST nodes or language constructs.

Syntax-aware behavior can be a separate future tool.

### Prioritize determinism over convenience

The tool should avoid prompts, editor flows, fuzzy matching, and implicit multi-file behavior.

Agents need stable, repeatable commands.

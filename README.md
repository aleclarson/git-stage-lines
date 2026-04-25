# git-stage-lines

Stage only the changed lines you want.

`git-stage-lines` is a small Git subcommand for precise, line-based staging. It is useful when one file has several unrelated edits and `git add -p` is more interaction than you want.

## Install

```sh
brew install aleclarson/tap/git-stage-lines
```

Then run it as a Git command:

```sh
git stage-lines --version
```

## Quick Start

Stage line 42 from one file:

```sh
git stage-lines src/app.ts 42
```

Stage a few ranges:

```sh
git stage-lines src/app.ts 12-18,27,45-50
```

Review what was staged:

```sh
git diff --cached
```

Commit normally:

```sh
git commit -m "feat: update app behavior"
```

## Tip For Coding Agents

If you use Codex or another coding agent, add a global `AGENTS.md` instruction so it does not stage unrelated edits from the same file.

For agents, prefer the direct binary name: `git-stage-lines`. This avoids Git's special `--help` handling for subcommands and avoids confusion if Git ever adds an official `stage-lines` command.

Copy-paste this prompt:

```text
Update my global AGENTS.md to include this Git instruction:

When staging partial changes, prefer `git-stage-lines FILE RANGES` so only the intended line ranges are staged. Use `git add` only when the whole file should be staged.
```

## What It Does

- Reads the unstaged diff for one file.
- Builds a smaller patch containing only changes that touch your line ranges.
- Applies that patch to the Git index with `git apply --cached`.

Your working tree is left alone. Only the index changes.

## Usage

```text
git stage-lines FILE RANGES [options]
```

`RANGES` is a comma-separated list:

```text
10
10-15
10,14,20-25
```

By default, line numbers refer to the new working-tree version of the file.

## Common Commands

Preview the exact patch without staging it:

```sh
git stage-lines src/app.ts 12-18 --dry-run
```

Check whether the patch would apply, without staging it:

```sh
git stage-lines src/app.ts 12-18 --check
```

Use old file line numbers instead:

```sh
git stage-lines src/app.ts 12-18 --mode old
```

Use either old or new line numbers:

```sh
git stage-lines src/app.ts 12-18 --mode both
```

Emit JSON for scripts and editor integrations:

```sh
git stage-lines src/app.ts 12-18 --json
```

## Options

| Option | Purpose |
| --- | --- |
| `--mode new` | Match ranges against new working-tree line numbers. This is the default. |
| `--mode old` | Match ranges against old index line numbers. Useful for deletions. |
| `--mode both` | Match either old or new line numbers. Useful when you do not want to think about it. |
| `--dry-run` | Print the patch that would be staged. |
| `--check` | Validate the generated patch without staging it. |
| `--json` | Print machine-readable output. |
| `--context N` | Ask Git for `N` context lines. Default: `3`. |
| `--allow-empty` | Exit successfully when no matching changes are found. |
| `--version` | Print the installed version. |
| `-h`, `--help` | Print CLI help. |

## Example

Start with one file that has two edits:

```diff
 one
-two
+TWO
 three
-four
+FOUR
```

Stage only the first edit:

```sh
git stage-lines sample.txt 2
```

Now the index contains `TWO`, while `FOUR` remains unstaged:

```sh
git diff --cached
git diff
```

## Current Limits

- One file per command.
- Works on unstaged text diffs.
- Does not handle binary files.
- Does not handle renames, copies, deleted files, or permission-only changes yet.

## Build From Source

Requires Zig.

```sh
zig build -Doptimize=ReleaseSafe
./zig-out/bin/git-stage-lines --help
```

To use it as `git stage-lines`, put the compiled `git-stage-lines` binary on your `PATH`.

## License

MIT

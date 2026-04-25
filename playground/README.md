# git-stage-lines Playground

This folder creates a disposable nested Git repo at `playground/worktree`. The worktree is ignored by the parent repo, so you can reset it whenever you want.

## Reset

From the project root:

```bash
./playground/reset.sh
cd playground/worktree
TOOL=../../zig-out/bin/git-stage-lines
```

The reset script runs `zig build`, recreates `worktree`, commits baseline files, then leaves several unstaged changes for experiments.

## Inspect The Fixture

```bash
git status --short
$TOOL diff
$TOOL diff src/app.ts
git diff -- src/app.ts
git diff -- docs/notes.md
git diff -- src/config.txt

nl -ba src/app.ts
nl -ba docs/notes.md
nl -ba src/config.txt
```

Refs from `$TOOL diff` remain valid until you edit the working tree. Stage `+N` output as `N`, and stage `-N` output as `-N`.

## Basic Help And Errors

```bash
$TOOL --help
$TOOL completions bash | head
$TOOL man | head
$TOOL src/app.ts
$TOOL src/app.ts bad-range --json
$TOOL src/app.ts:bad-range --json
$TOOL src/app.ts 99 --json
$TOOL src/app.ts 99 --allow-empty --json
```

## Dry Run And Check

```bash
$TOOL src/app.ts:-4,4 --dry-run
$TOOL src/app.ts:-4,4 --dry-run --json
$TOOL src/app.ts:-4,4 --check
$TOOL src/app.ts:-4,4 --check --json

git diff --cached
git diff -- src/app.ts
```

`--dry-run` and `--check` should leave the index untouched.

## Stage One Modified Line

```bash
git reset -q
$TOOL src/app.ts:-4,4 --json

git diff --cached -- src/app.ts
git diff -- src/app.ts
```

This stages the `Queued` to `Waiting` change while leaving the other `src/app.ts` edits unstaged.

## Stage Another Modified Line

```bash
git reset -q
$TOOL src/app.ts:-6,6 --json

git diff --cached -- src/app.ts
git diff -- src/app.ts
```

This stages the `Done` to `Complete` change.

## Stage A Constant Change

```bash
git reset -q
$TOOL src/app.ts:-15,15 --json

git diff --cached -- src/app.ts
git diff -- src/app.ts
```

This stages only the `retryLimit` change.

## Stage Added Lines

```bash
git reset -q
$TOOL docs/notes.md:4 --json

git diff --cached -- docs/notes.md
git diff -- docs/notes.md
```

Try the second added note too:

```bash
git reset -q
$TOOL docs/notes.md:6 --json

git diff --cached -- docs/notes.md
git diff -- docs/notes.md
```

## Stage A Deletion

The `beta=true` line was deleted from `src/config.txt`. It exists only on the old side of the diff.

```bash
git reset -q
$TOOL src/config.txt:-2 --json

git diff --cached -- src/config.txt
git diff -- src/config.txt
```

The `-2` ref comes from `$TOOL diff src/config.txt` output.

## Use Editor Line Ranges

```bash
git reset -q
$TOOL src/config.txt 2 --mode both --json

git diff --cached -- src/config.txt
git diff -- src/config.txt
```

`FILE RANGES --mode both` is useful when an editor or another tool gives you working-tree line ranges instead of exact refs from `$TOOL diff`.

## The Canonical Try-Out Example (Atomic Commits)

If you're wondering how you can use this in your workflow, here is how you can build atomic commits straight from the unstaged changes:

```bash
git reset -q

# Commit 1: Update terminology for status states
$TOOL src/app.ts:-4,4,-6,6
git commit -m "refactor: update status display labels"

# Commit 2: Increase retry limit
$TOOL src/app.ts:-15,15
git commit -m "fix: increase retry limit from 2 to 3"

# Commit 3: Remove beta configuration
$TOOL src/config.txt:-2
git commit -m "chore: remove beta flag from config"

# Commit 4: Disable delta configuration
$TOOL src/config.txt:-3,3
git commit -m "config: disable delta flag"

# Commit 5: Add release note for staged line selection
$TOOL docs/notes.md:4
git commit -m "docs: add release note for staged line selection"

# Commit 6: Add release note for JSON output
$TOOL docs/notes.md:6
git commit -m "docs: add release note for JSON output"
```

## Stage Multiple Ranges

```bash
git reset -q
$TOOL src/app.ts 4,15 --mode both --json

git diff --cached -- src/app.ts
git diff -- src/app.ts
```

This form stages by working-tree line ranges. Prefer `FILE:REFS` when you are working from `$TOOL diff` output.

## Human Output

```bash
git reset -q
$TOOL src/app.ts 4

git diff --cached -- src/app.ts
```

## Start Over

From inside `playground/worktree`:

```bash
cd ..
./reset.sh
cd worktree
TOOL=../../zig-out/bin/git-stage-lines
```

From the project root:

```bash
./playground/reset.sh
cd playground/worktree
TOOL=../../zig-out/bin/git-stage-lines
```

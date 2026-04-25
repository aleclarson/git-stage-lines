Yes. I’d build a tool around this shape:

```bash
git-stage-lines <file> <ranges> [--mode new|old|both] [--dry-run] [--json]
```

Example:

```bash
git-stage-lines src/foo.py 10-15,22,40-45
```

Under the hood, it should **not** drive `git add -p` or `git add -e` unless used as a fallback. Git’s interactive patch mode is designed for humans to choose hunks interactively, and `git add -e` works by opening an editable patch that Git later applies to the index; the Git docs explicitly warn that arbitrary patch edits can fail or have confusing results. ([Kernel.org][1])

The cleaner design is:

```text
git diff -- <file>
        ↓
parse unified diff
        ↓
select changes touching requested line ranges
        ↓
emit smaller valid patch
        ↓
git apply --cached
```

`git apply --cached` is the important primitive: official Git docs say it applies a patch only to the index, without touching the working tree. ([Git][2])

## Proposed UX

### Stage working-tree lines

```bash
git-stage-lines app.py 10-15
```

Stages changes whose **new-file / working-tree** line numbers overlap lines 10–15.

### Stage deletions too

```bash
git-stage-lines app.py 10-15 --mode both
```

Because deleted lines do not exist in the working tree, the tool needs a mode:

```text
--mode new    select by working-tree line numbers; best default
--mode old    select by HEAD/index line numbers
--mode both   select if either old or new line range overlaps
```

Default should be `new`, because when an agent says “stage lines 10–15,” it usually means the current file.

### Preview before staging

```bash
git-stage-lines app.py 10-15 --dry-run
```

Prints the exact patch that would be staged.

### Agent-friendly JSON

```bash
git-stage-lines app.py 10-15 --json
```

Example output:

```json
{
  "file": "app.py",
  "ranges": ["10-15"],
  "mode": "new",
  "status": "staged",
  "selected_changes": 3,
  "skipped_changes": 7,
  "patch_applied": true
}
```

For agents, this is much better than parsing human Git output.

## Command behavior I’d want

```bash
git-stage-lines file.py 10-15
git-stage-lines file.py 10-15,20,25-30
git-stage-lines file.py 10-15 --dry-run
git-stage-lines file.py 10-15 --mode both
git-stage-lines file.py 10-15 --context 3
git-stage-lines file.py 10-15 --check
git-stage-lines file.py 10-15 --json
```

`--check` should validate that the generated patch applies cleanly before modifying the index:

```bash
git apply --cached --check /tmp/selected.patch
git apply --cached /tmp/selected.patch
```

## Important implementation detail

The tool must parse unified diff hunks, not just grep line numbers.

A hunk looks like this:

```diff
@@ -8,7 +8,9 @@
 context
-old line
+new line
```

The tool needs to track two counters:

```text
old_line: line number in index / HEAD side
new_line: line number in working-tree side
```

Then classify each diff line:

```text
" " context line: increments old_line and new_line
"-" deletion:     increments old_line
"+" addition:     increments new_line
```

For modifications, this matters:

```diff
-old value
+new value
```

That should generally be treated as one logical change, not as unrelated deletion and addition.

## Recommended safety rules

The tool should be conservative:

1. **Never stage partial syntax blindly unless asked.** It can stage arbitrary lines, but it should report what it did.
2. **Always run `git apply --cached --check` before applying.**
3. **After staging, optionally verify with `git diff --cached -- <file>`.**
4. **Refuse ambiguous binary files, renames, and mode-only changes unless explicitly supported.**
5. **Support new files with `git add -N <file>` first**, then diff against the empty index.
6. **Return machine-readable errors.**

Example error:

```json
{
  "status": "error",
  "reason": "range_does_not_overlap_any_change",
  "file": "app.py",
  "ranges": ["10-15"]
}
```

## MVP algorithm

```text
1. Ensure inside a Git repo.
2. Check file exists or is tracked/untracked.
3. If untracked, optionally run git add -N file.
4. Run git diff -- file.
5. Parse file headers and hunks.
6. Split hunks into logical change groups with surrounding context.
7. Keep change groups overlapping requested line ranges.
8. Rebuild valid unified diff with recalculated hunk headers.
9. Run git apply --cached --check.
10. Run git apply --cached.
11. Print summary or JSON.
```

## Best name

I’d name it something explicit:

```bash
git-stage-lines
```

Then users and agents can call it as a Git-adjacent command:

```bash
git stage-lines app.py 10-15
```

Git automatically supports external subcommands named `git-foo` on `$PATH`, so an executable named `git-stage-lines` can be invoked as:

```bash
git stage-lines ...
```

## My suggested agent contract

Give agents a tiny, stable API:

```bash
git stage-lines FILE RANGES --mode new --json
```

Where:

```text
FILE    = one path only
RANGES  = comma-separated 1-based ranges in the current working-tree file
```

Example:

```bash
git stage-lines src/server.ts 120-138,155 --mode new --json
```

That is the simplest useful abstraction. Internally, use `git diff` and `git apply --cached`; avoid `git add -e` for the core implementation.

[1]: https://www.kernel.org/pub/software/scm/git/docs/git-add.html?utm_source=chatgpt.com "git-add(1) Manual Page"
[2]: https://git-scm.com/docs/git-apply?utm_source=chatgpt.com "Git - git-apply Documentation"

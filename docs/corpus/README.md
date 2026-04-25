# Patch Corpus

This directory is the behavior corpus for `git-stage-lines` patch generation.
Each file describes cases that should either already be covered by tests or become
fixtures when the CLI behavior expands.

The corpus is organized by patch shape:

1. [Addition patches](01-addition-patches.md)
2. [Deletion patches](02-deletion-patches.md)
3. [Replacement patches](03-replacement-patches.md)
4. [Multi-hunk patches](04-multi-hunk-patches.md)
5. [No-final-newline patches](05-no-final-newline-patches.md)

Each case should include:

- Purpose
- Starting file state
- Working-tree change
- Command
- Expected staged patch
- Residual unstaged change, when relevant

## Invariants

- `FILE RANGES` stages changes whose selected side overlaps `RANGES`.
- `FILE:REFS` is exact: positive refs select new-side additions, negative refs select old-side deletions.
- Patch generation uses `git diff --unified=0` and `git apply --cached --unidiff-zero`.
- The working tree must not be modified.
- Unsupported or ambiguous patch shapes should fail rather than stage surprising content.

# Deletion Patches

## Single Deleted Line

Purpose: stage one old-side deletion.

Initial:

```text
alpha
beta
gamma
```

Working tree:

```text
alpha
gamma
```

Command:

```sh
git stage-lines file.txt:-2
```

Expected staged patch:

```diff
@@ -2 +1,0 @@
-beta
```

## One Line From Multiple Deleted Lines

Purpose: exact `FILE:REFS` syntax can stage one deletion from a contiguous deletion block.

Initial:

```text
one
two
three
four
five
```

Working tree:

```text
one
five
```

Command:

```sh
git stage-lines file.txt:-3
```

Expected staged patch:

```diff
@@ -3 +2,0 @@
-three
```

Residual unstaged change should still contain deletions for `two` and `four`.

## Non-Contiguous Deletions

Purpose: separate deletion groups must render as separate zero-context hunks.

Command:

```sh
git stage-lines file.txt:-2,-4
```

Expected staged patch contains two hunks, one for line 2 and one for line 4.

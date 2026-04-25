# Addition Patches

## Single Added Line

Purpose: stage one new line.

Initial:

```text
one
three
```

Working tree:

```text
one
two
three
```

Command:

```sh
git stage-lines file.txt:2
```

Expected staged patch:

```diff
@@ -1,0 +2 @@
+two
```

## One Line From A Contiguous Insertion

Purpose: exact `FILE:REFS` syntax can stage one line from a contiguous insertion block.

Initial:

```text
one
five
```

Working tree:

```text
one
two
three
four
five
```

Command:

```sh
git stage-lines file.txt:3
```

Expected staged patch:

```diff
@@ -1,0 +2 @@
+three
```

Residual unstaged change should still contain `two` and `four`.

## Range From A Contiguous Insertion

Purpose: stage a contiguous subset of inserted lines.

Command:

```sh
git stage-lines file.txt:2-3
```

Expected staged patch:

```diff
@@ -1,0 +2,2 @@
+two
+three
```

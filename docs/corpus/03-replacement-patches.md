# Replacement Patches

## Legacy Range Stages A Replacement

Purpose: preserve the `FILE RANGES` behavior where selecting the new line of a replacement stages the paired removal too.

Initial:

```text
one
two
three
```

Working tree:

```text
one
TWO
three
```

Command:

```sh
git stage-lines file.txt 2
```

Expected staged patch:

```diff
@@ -2 +2 @@
-two
+TWO
```

## Exact Refs Stage A Replacement

Purpose: exact syntax can express both sides of the replacement explicitly.

Command:

```sh
git stage-lines file.txt:-2,2
```

Expected staged patch:

```diff
@@ -2 +2 @@
-two
+TWO
```

## Exact Addition Side Only

Purpose: document that positive refs select only the new side.

Command:

```sh
git stage-lines file.txt:2
```

Expected behavior: stage only an addition-side patch if Git accepts it, or fail validation if the generated patch cannot apply cleanly.

# No-Final-Newline Patches

## Preserve Marker On Selected Old Line

Purpose: when a selected removed line has no trailing newline, the patch must preserve Git's marker.

Diff shape:

```diff
@@ -3 +3 @@
-old
\ No newline at end of file
+new
```

Command:

```sh
git stage-lines file.txt:-3
```

Expected staged patch:

```diff
@@ -3 +2,0 @@
-old
\ No newline at end of file
```

## Preserve Marker On Selected New Line

Purpose: when a selected added line has no trailing newline, the patch must preserve Git's marker.

Command:

```sh
git stage-lines file.txt:3
```

Expected staged patch includes:

```diff
+new
\ No newline at end of file
```

## Bridge Cases

Purpose: if staging a subset around a missing final newline would concatenate content or corrupt the index, validation must fail rather than stage a surprising patch.

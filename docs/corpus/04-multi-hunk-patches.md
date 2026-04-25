# Multi-Hunk Patches

## Stage Two Separate Additions

Purpose: one command can select multiple hunks from one file.

Command:

```sh
git stage-lines file.txt:3,20
```

Expected staged patch contains both selected hunks in file order.

## Stage Later Hunk First

Purpose: staging a later hunk must not prevent staging an earlier hunk in a later command.

Commands:

```sh
git stage-lines file.txt:20
git stage-lines file.txt:3
```

Expected result: both selected changes are staged, regardless of command order.

## Non-Contiguous Deletion Groups

Purpose: deletion groups separated by old-side gaps must be emitted as separate hunks.

Command:

```sh
git stage-lines file.txt:-10,-15
```

Expected result: two deletion hunks.

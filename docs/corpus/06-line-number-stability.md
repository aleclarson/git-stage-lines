# Line-Number Stability

Line references printed by `git stage-lines diff` should remain valid while the
working tree stays unchanged, even if other ranges are staged first.

## Stage Later Addition First

Initial:

```text
one
three
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

Initial command:

```sh
git stage-lines diff file.txt
```

Important output:

```text
file.txt:
  +2:	two

  +4:	four
```

Sequential commands:

```sh
git stage-lines file.txt:4
git stage-lines file.txt:2
```

Expected result:

- Both `two` and `four` are staged.
- No unstaged diff remains for `file.txt`.
- The second command can still use line `2` from the initial `diff` output.

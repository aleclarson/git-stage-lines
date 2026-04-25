#!/usr/bin/env bash
set -euo pipefail

playground_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root_dir="$(CDPATH= cd -- "$playground_dir/.." && pwd)"
worktree="$playground_dir/worktree"

printf 'Building git-stage-lines...\n'
(cd "$root_dir" && zig build >/dev/null)

rm -rf "$worktree"
mkdir -p "$worktree/src" "$worktree/docs"

cd "$worktree"
git init -q
git config user.name "Git Stage Lines Playground"
git config user.email "playground@example.invalid"

cat >src/app.ts <<'EOF'
export type Status = 'queued' | 'running' | 'done'

export function labelStatus(status: Status): string {
  if (status === 'queued') return 'Queued'
  if (status === 'running') return 'Running'
  return 'Done'
}

export function nextStatus(status: Status): Status {
  if (status === 'queued') return 'running'
  if (status === 'running') return 'done'
  return 'done'
}

export const retryLimit = 2
EOF

cat >docs/notes.md <<'EOF'
# Release Notes

- Initial queue view
- Basic retry handling
EOF

cat >src/config.txt <<'EOF'
alpha=true
beta=true
gamma=true
delta=true
EOF

git add .
git commit -qm "seed playground"

cat >src/app.ts <<'EOF'
export type Status = 'queued' | 'running' | 'done'

export function labelStatus(status: Status): string {
  if (status === 'queued') return 'Waiting'
  if (status === 'running') return 'Running'
  return 'Complete'
}

export function nextStatus(status: Status): Status {
  if (status === 'queued') return 'running'
  if (status === 'running') return 'done'
  return 'done'
}

export const retryLimit = 3
EOF

cat >docs/notes.md <<'EOF'
# Release Notes

- Initial queue view
- Added staged line selection
- Basic retry handling
- Documented JSON output
EOF

cat >src/config.txt <<'EOF'
alpha=true
gamma=true
delta=false
EOF

printf 'Playground ready: %s\n' "$worktree"
printf 'Try: cd %s && TOOL=../../zig-out/bin/git-stage-lines\n' "$worktree"

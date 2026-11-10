#!/usr/bin/env bash
# SessionStart hook: sync workflow files from the template repo.
# Runs silently; never blocks session start on failure.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
# Skip if we're inside a worktree (lanes don't sync)
[[ "$root" == */.worktrees/* ]] && exit 0
# Skip if sync script doesn't exist (not a consuming repo)
[[ -x "$root/scripts/sync-workflow.sh" ]] || exit 0

# Run sync in background so it doesn't delay session start.
# stdout/stderr to /dev/null — the sync is quiet or noisy, either way don't block.
bash "$root/scripts/sync-workflow.sh" >/dev/null 2>&1 &

echo "sync-workflow.sh running in background"

#!/usr/bin/env bash
# Stop hook: nudge to update memory if files changed but memory wasn't recently touched
# Non-blocking — always exits 0

cat > /dev/null  # consume stdin

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ "$root" == */.worktrees/* ]] && exit 0

changed=$(git -C "$root" diff --name-only HEAD 2>/dev/null)
[ -z "$changed" ] && exit 0

# Derive memory dir from project path: /abs/path → ~/.claude/projects/-abs-path/memory
safe_root="${root//\//-}"
memory_dir="$HOME/.claude/projects/${safe_root}/memory"

if [ -d "$memory_dir" ]; then
  recent=$(find "$memory_dir" -name "*.md" -mmin -240 2>/dev/null | head -1)
  [ -n "$recent" ] && exit 0
fi

echo "Files changed — consider updating memory."
exit 0

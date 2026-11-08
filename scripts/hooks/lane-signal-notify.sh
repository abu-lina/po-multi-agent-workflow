#!/usr/bin/env bash
# Stop hook: deliver .lane-signal to the foreman's Rex pane and delete it.
# Non-blocking — always exits 0.

cat > /dev/null  # consume stdin

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ "$root" == */.worktrees/* ]] || exit 0
[[ -f "$root/.env.lane" ]] || exit 0

# shellcheck source=/dev/null
source "$root/.env.lane"
[[ -f "$root/.lane-signal" ]] || exit 0

signal="$(< "$root/.lane-signal")"
rex send -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" "Lane #$ISSUE: $signal" 2>/dev/null || true
rm -f "$root/.lane-signal"

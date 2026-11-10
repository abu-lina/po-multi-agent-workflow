#!/usr/bin/env bash
# PreToolUse gate: block writing lane-brief*.md unless ui-taste was invoked.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
basename_path="$(basename "$file_path")"

# Only gate lane-brief*.md files
printf '%s' "$basename_path" | grep -qE '^lane-brief.*\.md$' || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo_name="$(basename "$root")"
repo_name="${repo_name//[^a-zA-Z0-9_-]/}"
sentinel="/tmp/.${repo_name}-ui-taste-invoked"

[[ -f "$sentinel" ]] && exit 0

jq -n --arg r "$repo_name" \
  '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":("ui-taste must be invoked before writing a lane brief. Run the ui-taste skill first, then: touch /tmp/." + $r + "-ui-taste-invoked")}}'
exit 0

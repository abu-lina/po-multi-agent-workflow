#!/usr/bin/env bash
# PreToolUse: strip AI attribution trailers before git commit and gh pr commands run.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -n "$cmd" ]] || exit 0

strip_coauthored() {
  # Remove any line matching Co-Authored-By: (case-insensitive) and trailing blank lines
  printf '%s' "$1" | grep -viE '^[[:space:]]*Co-Authored-By:' | sed 's/[[:space:]]*$//' | sed -e :a -e '/^\s*$/{ $d; N; ba' -e '}'
}

strip_robot_footer() {
  # Remove any line matching the 🤖 Generated with pattern
  printf '%s' "$1" | grep -v '🤖 Generated with'
}

new_cmd="$cmd"

# AC1: git commit -m "..." containing Co-Authored-By
if printf '%s' "$cmd" | grep -qiE '\bgit commit\b' && printf '%s' "$cmd" | grep -qiE 'Co-Authored-By:'; then
  # Extract the -m value (content between outermost quotes in the -m argument)
  # Strategy: strip the trailer from the whole command string directly using sed
  new_cmd=$(printf '%s' "$cmd" | \
    sed -E 's/Co-Authored-By:[^\n"\\]*(\\n)?//gi' | \
    sed -E 's/\\nCo-Authored-By:[^"\\]*(\\n)?//gi')
fi

# AC2: gh pr create/edit --body containing 🤖 Generated with
if printf '%s' "$cmd" | grep -qE '\bgh pr (create|edit)\b' && printf '%s' "$cmd" | grep -q '🤖 Generated with'; then
  new_cmd=$(printf '%s' "$new_cmd" | grep -v '🤖 Generated with' | sed -E 's/\\n🤖 Generated with[^"]*//g')
fi

# Only emit updatedInput if the command actually changed
if [[ "$new_cmd" != "$cmd" ]]; then
  jq -n --arg cmd "$new_cmd" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":$cmd}}}'
fi

exit 0

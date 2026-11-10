#!/usr/bin/env bash
# PreToolUse: strip AI attribution trailers before git commit and gh pr commands run.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -n "$cmd" ]] || exit 0

new_cmd="$cmd"

# AC1: git commit -m "..." containing Co-Authored-By
# Strip both literal-\n-encoded ("\\nCo-Authored-By:...") and real-newline forms.
if printf '%s' "$cmd" | grep -qiE '\bgit commit\b' && printf '%s' "$cmd" | grep -qiE 'Co-Authored-By:'; then
  new_cmd=$(printf '%s' "$cmd" \
    | sed -E 's/\\nCo-Authored-By:[^"\\]*(\\n)?//gi' \
    | sed -E 's/Co-Authored-By:[^\n"\\]*(\\n)?//gi' \
    | grep -viE '^[[:space:]]*Co-Authored-By:' || true)
fi

# AC2: gh pr create/edit --body containing 🤖 Generated with
# Strip both literal-\n-encoded and real-newline forms.
if printf '%s' "$cmd" | grep -qE '\bgh pr (create|edit)\b' && printf '%s' "$cmd" | grep -q '🤖 Generated with'; then
  new_cmd=$(printf '%s' "$new_cmd" \
    | sed -E 's/\\n🤖 Generated with[^"]*//g' \
    | grep -v '🤖 Generated with' || true)
fi

# Only emit updatedInput if the command actually changed
if [[ "$new_cmd" != "$cmd" ]]; then
  jq -n --arg cmd "$new_cmd" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":$cmd}}}'
fi

exit 0

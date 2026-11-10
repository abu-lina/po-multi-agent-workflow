#!/usr/bin/env bash
# PreToolUse: strip AI attribution trailers before git commit and gh pr commands run.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat) || exit 0
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[[ -n "$cmd" ]] || exit 0

new_cmd="$cmd"

# AC1: git commit -m "..." containing Co-Authored-By
# Claude Code serialises the commit message with \n escape sequences inside the -m string.
# Strip the trailer and any orphaned leading \n separators it leaves behind.
# shortcut: assumes -m uses double-quote delimiters; $'...' quoting and heredocs are not handled
if printf '%s' "$cmd" | grep -qiE '\bgit commit\b' && printf '%s' "$cmd" | grep -qiE 'Co-Authored-By:'; then
  new_cmd=$(printf '%s' "$cmd" \
    | sed -E 's/(\\n)*Co-Authored-By:[^"]+"/"/' \
    | sed -E 's/(\\n)+"/"/')
  # Also handle real newlines in case the command contains them
  new_cmd=$(printf '%s' "$new_cmd" | grep -viE '^[[:space:]]*Co-Authored-By:' || true)
fi

# AC2: gh pr create/edit --body containing 🤖 Generated with
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

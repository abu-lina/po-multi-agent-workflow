#!/usr/bin/env bash
# Sentinel writer + "fixed" commit gate (PreToolUse on Bash)
set -euo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo_name="$(basename "$root")"
sentinel="/tmp/.${repo_name}-last-verified"

# Track verification runs: touch sentinel so the gate can see them
if printf '%s' "$cmd" | grep -qE '(npx vitest|npm (run )?(test|type-check|lint|build|check-all))'; then
  touch "$sentinel"
  exit 0
fi

# Gate: only inspect git commit commands
printf '%s' "$cmd" | grep -qiE '\bgit commit\b' || exit 0
# Only gate if the commit message contains "fixed" as a word
printf '%s' "$cmd" | grep -qi '\bfixed\b' || exit 0

# Check sentinel recency (30 min)
if [ -f "$sentinel" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$sentinel") ))
  [ "$age" -lt 1800 ] && exit 0
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Commit says fixed but no test/type-check ran in the last 30 min. Run: npx vitest run  or  npm run type-check  first."}}\n'
exit 0

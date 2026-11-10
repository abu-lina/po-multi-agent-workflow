#!/usr/bin/env bash
# PreToolUse gate (Edit|Write): block the foreman from editing implementation files.
# The foreman runs in the main checkout; lanes run in .worktrees/<issue>-<slug>/.
# If cwd is the main checkout (not a worktree), block writes to anything outside
# the allowed set: docs/agents/, scripts/, .claude/, AGENTS.md, docs/ai/, docs/adr/.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# If we're inside a worktree, this is a lane — allow everything.
[[ "$root" == */.worktrees/* ]] && exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
[[ -z "$file_path" ]] && exit 0

# Resolve to a path relative to the repo root.
# Strip the root prefix; if file_path doesn't start with root, use it as-is.
rel="${file_path#"$root"/}"

# Allowed paths the foreman may edit (docs, scripts, agent config, learnings).
case "$rel" in
  AGENTS.md)                  exit 0 ;;
  docs/agents/*)              exit 0 ;;
  docs/ai/*)                  exit 0 ;;
  docs/adr/*)                 exit 0 ;;
  scripts/*)                  exit 0 ;;
  .claude/*)                  exit 0 ;;
  reference/*)                exit 0 ;;
  .github/*)                  exit 0 ;;
  *.md)                       exit 0 ;;  # any markdown at repo root (README, etc.)
esac

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "FOREMAN GATE: You are running in the main checkout (foreman role). Editing implementation files is not allowed. Use scripts/lane start <issue> <slug> to open a lane, then let the lane agent do the work. Allowed edits: docs/agents/, docs/ai/, docs/adr/, scripts/, .claude/, reference/, .github/, AGENTS.md, and root *.md files."
  }
}'
exit 0

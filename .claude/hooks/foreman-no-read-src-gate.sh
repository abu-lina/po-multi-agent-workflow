#!/usr/bin/env bash
# PreToolUse gate (Read): block the foreman from reading implementation source files.
# The foreman never reads src/, app/, or component files (foreman.md rule).
# Permitted reads: AGENTS.md, docs/agents/, issue bodies, scripts/, .claude/.
set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Inside a worktree = lane agent. Allow everything.
[[ "$root" == */.worktrees/* ]] && exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
[[ -z "$file_path" ]] && exit 0

rel="${file_path#"$root"/}"

# Block implementation source directories.
case "$rel" in
  src/*)        ;;
  app/*)        ;;
  components/*) ;;
  lib/*)        ;;
  utils/*)      ;;
  hooks/*)      ;;
  services/*)   ;;
  pages/*)      ;;
  *)            exit 0 ;;  # everything else is allowed
esac

jq -n '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "FOREMAN GATE: You are the foreman (main checkout). Reading implementation source files (src/, app/, components/, lib/, etc.) is not allowed. The foreman coordinates; it never reads product code. To work on an issue: scripts/lane start <issue> <slug>. Permitted reads: AGENTS.md, docs/agents/, docs/ai/, docs/adr/, scripts/, .claude/, reference/."
  }
}'
exit 0

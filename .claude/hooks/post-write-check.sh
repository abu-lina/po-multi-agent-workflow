#!/usr/bin/env bash
# Post-write anti-pattern scanner (PostToolUse on Write|Edit) — warning only, never blocks
set -euo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_response.filePath // .tool_input.file_path // ""')

# Nothing to scan
[ -z "$file" ] || [ ! -f "$file" ] && exit 0

# Skip non-TS/TSX files
[[ "$file" =~ \.(ts|tsx)$ ]] || exit 0

# Skip test/mock/config files
[[ "$file" =~ \.(test|spec)\.(ts|tsx)$ ]] && exit 0
[[ "$file" =~ __mocks__ ]] && exit 0
[[ "$file" =~ \.config\. ]] && exit 0

warnings=()

grep -qE 'console\.(log|warn|error|debug)\(' "$file" && \
  warnings+=("console.log in production code: $file")

grep -q 'localhost' "$file" && \
  warnings+=("hardcoded localhost: $file")

grep -q '// TODO' "$file" && \
  warnings+=("// TODO left in production code: $file")

if [ ${#warnings[@]} -gt 0 ]; then
  msg="Anti-pattern warning:"
  for w in "${warnings[@]}"; do
    msg+=" | $w"
  done
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
    "$(printf '%s' "$msg" | sed 's/"/\\"/g')"
fi

exit 0

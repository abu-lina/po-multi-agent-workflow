#!/usr/bin/env bash
# Tests for .claude/hooks/ui-taste-gate.sh
# Red/green: pipe JSON into the hook, check deny vs allow output.
set -euo pipefail

HOOK=".claude/hooks/ui-taste-gate.sh"
REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
SENTINEL="/tmp/.${REPO_NAME}-ui-taste-invoked"

pass=0
fail=0

ok()   { echo "  PASS: $1"; (( pass++ )) || true; }
fail() { echo "  FAIL: $1"; (( fail++ )) || true; }

# Cleanup before tests
rm -f "$SENTINEL"

echo "--- ui-taste-gate tests ---"

# 1. Without sentinel: lane-brief*.md must be denied
out=$(printf '{"tool_input":{"file_path":"lane-brief-foo.md"}}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q '"deny"'; then
  ok "without sentinel: lane-brief*.md is denied"
else
  fail "without sentinel: expected deny, got: $out"
fi

# 2. With sentinel: same filename must be allowed (hook exits 0, no deny in output)
touch "$SENTINEL"
out=$(printf '{"tool_input":{"file_path":"lane-brief-foo.md"}}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q '"deny"'; then
  fail "with sentinel: expected allow but got deny: $out"
else
  ok "with sentinel: lane-brief*.md is allowed"
fi
rm -f "$SENTINEL"

# 3. Non-matching filename: always allowed even without sentinel
out=$(printf '{"tool_input":{"file_path":"README.md"}}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q '"deny"'; then
  fail "non-matching file: should always allow, got deny: $out"
else
  ok "non-matching file: always allowed"
fi

# 4. Nested path with matching basename: must deny without sentinel
out=$(printf '{"tool_input":{"file_path":"docs/lane-brief-26.md"}}' | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q '"deny"'; then
  ok "nested path with matching basename: denied without sentinel"
else
  fail "nested path: expected deny for docs/lane-brief-26.md, got: $out"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]

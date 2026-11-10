#!/usr/bin/env bash
# Tests for issue #28: lane_done must unset GH_HOST for all gh calls.
set -euo pipefail

pass=0
fail_count=0

ok()    { echo "  PASS: $1"; (( pass++ )) || true; }
flunk() { echo "  FAIL: $1"; (( fail_count++ )) || true; }

echo "--- lane_done GH_HOST tests ---"

LANE_SH="scripts/lane.sh"

# 1. lane_done gh pr view call must have GH_HOST="" prefix
# AC2: all gh calls inside lane_done must be prefixed with GH_HOST=""
if grep -q 'GH_HOST="" gh pr view' "$LANE_SH"; then
  ok "lane_done: gh pr view is prefixed with GH_HOST=\"\""
else
  flunk "lane_done: gh pr view is NOT prefixed with GH_HOST=\"\" — fix: prefix with GH_HOST=\"\" gh pr view ..."
fi

echo ""
echo "Results: $pass passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]

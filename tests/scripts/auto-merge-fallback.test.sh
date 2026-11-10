#!/usr/bin/env bash
# Tests for issue #31: auto-merge fallback when branch protection is absent.
# Run directly: bash tests/scripts/auto-merge-fallback.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOREMAN_MD="$REPO_ROOT/docs/agents/foreman.md"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2" detail="${3:-}"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label" "$detail"; }

[[ -f "$FOREMAN_MD" ]] || { echo "MISSING: $FOREMAN_MD" >&2; exit 1; }

# AC1: Stage 6 must contain the fallback pattern (|| echo) so the foreman
# continues rather than halting when auto-merge is unavailable.
grep -q '|| echo' "$FOREMAN_MD" && check "Stage 6 has fallback pattern (|| echo)" 1 || check "Stage 6 has fallback pattern (|| echo)" 0 "expected '|| echo' in $FOREMAN_MD"

# AC2: Stage 6 must document the requirement (mention 'required' near the
# auto-merge command) so a reader knows why it can fail.
grep -q 'required' "$FOREMAN_MD" && check "Stage 6 documents required-checks prerequisite" 1 || check "Stage 6 documents required-checks prerequisite" 0 "expected 'required' in $FOREMAN_MD"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

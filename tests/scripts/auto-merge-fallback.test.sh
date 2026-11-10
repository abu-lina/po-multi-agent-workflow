#!/usr/bin/env bash
# Tests for issue #31: auto-merge fallback when branch protection is absent.
# Run directly: bash tests/scripts/auto-merge-fallback.test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOREMAN_MD="$REPO_ROOT/docs/agents/foreman.md"

[[ -f "$FOREMAN_MD" ]] || { echo "MISSING: $FOREMAN_MD" >&2; exit 1; }

# AC1: Stage 6 must contain the fallback pattern so the foreman continues
# rather than halting when auto-merge is unavailable.
awk '/^## Stage 6/,/^## Stage [^6]/' "$FOREMAN_MD" \
  | grep -q '|| echo' \
  || { echo "FAIL: missing '|| echo' fallback in Stage 6 of $FOREMAN_MD" >&2; exit 1; }
echo "PASS: Stage 6 has fallback pattern (|| echo)"

# AC2: Stage 6 must document the required-checks prerequisite.
awk '/^## Stage 6/,/^## Stage [^6]/' "$FOREMAN_MD" \
  | grep -q 'required' \
  || { echo "FAIL: Stage 6 does not document required-checks prerequisite" >&2; exit 1; }
echo "PASS: Stage 6 documents required-checks prerequisite"

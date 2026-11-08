#!/usr/bin/env bash
# Bash tests for scripts/hooks/lane-signal-notify.sh
# Run directly: bash tests/scripts/lane-signal-notify.test.sh

set -euo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/hooks/lane-signal-notify.sh"
[[ -f "$HOOK" ]] || { echo "MISSING: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0

t() {
  local label="$1"; shift
  if "$@" 2>/dev/null; then
    echo "PASS: $label"; ((PASS++))
  else
    echo "FAIL: $label"; ((FAIL++))
  fi
}

# Build a fake rex (records args to rex.log) and a fake git (lets tests
# override show-toplevel via $MOCK_TOPLEVEL without recursion).
tmpbin="$(mktemp -d)"
REAL_GIT="$(command -v git)"
rex_log="$tmpbin/rex.log"

cat > "$tmpbin/rex" <<ENDREX
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$rex_log"
ENDREX
chmod +x "$tmpbin/rex"

cat > "$tmpbin/git" <<ENDGIT
#!/usr/bin/env bash
if [[ "\${1:-}" == "rev-parse" && "\${2:-}" == "--show-toplevel" ]]; then
  printf '%s\n' "\${MOCK_TOPLEVEL:-}"; exit 0
fi
exec "$REAL_GIT" "\$@"
ENDGIT
chmod +x "$tmpbin/git"
trap 'rm -rf "$tmpbin"' EXIT
export PATH="$tmpbin:$PATH"

# ------------------------------------------------------------------

_no_op_no_env_lane() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  local before; before="$(wc -l < "$rex_log" 2>/dev/null || echo 0)"
  MOCK_TOPLEVEL="$d/.worktrees/99-slug" bash "$HOOK" <<< ""
  local after; after="$(wc -l < "$rex_log" 2>/dev/null || echo 0)"
  [[ "$before" == "$after" ]]
}
t "no-op when .env.lane absent" _no_op_no_env_lane

_no_op_no_signal() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d/.env.lane"
  local before; before="$(wc -l < "$rex_log" 2>/dev/null || echo 0)"
  MOCK_TOPLEVEL="$d/.worktrees/42-slug" bash "$HOOK" <<< ""
  local after; after="$(wc -l < "$rex_log" 2>/dev/null || echo 0)"
  [[ "$before" == "$after" ]]
}
t "no-op when .lane-signal absent" _no_op_no_signal

_signal_consumed_and_deleted() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d/.env.lane"
  printf 'handoff: finished feature X' > "$d/.lane-signal"
  rm -f "$rex_log"
  MOCK_TOPLEVEL="$d/.worktrees/42-slug" bash "$HOOK" <<< ""
  local got; got="$(cat "$rex_log" 2>/dev/null)"
  [[ "$got" == "send -s ses1 -b blk1 Lane #42: handoff: finished feature X" ]] \
    && [[ ! -f "$d/.lane-signal" ]]
}
t "signal consumed and file deleted" _signal_consumed_and_deleted

_no_op_main_checkout() {
  local d; d="$(mktemp -d)"; trap 'rm -rf "$d"' RETURN
  printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d/.env.lane"
  printf 'blocked: waiting for schema' > "$d/.lane-signal"
  rm -f "$rex_log"
  MOCK_TOPLEVEL="$d" bash "$HOOK" <<< ""
  local rex_calls; rex_calls="$(cat "$rex_log" 2>/dev/null || echo "")"
  [[ -z "$rex_calls" ]] && [[ -f "$d/.lane-signal" ]]
}
t "no-op in main checkout (no .worktrees/ in path)" _no_op_main_checkout

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

#!/usr/bin/env bash
# Bash tests for scripts/hooks/lane-signal-notify.sh
# Run directly: bash tests/scripts/lane-signal-notify.test.sh

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/hooks/lane-signal-notify.sh"
[[ -f "$HOOK" ]] || { echo "MISSING: $HOOK" >&2; exit 1; }

PASS=0; FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label"; }

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

# Test 1: no-op when .env.lane absent
d1="$(mktemp -d)"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d1/.worktrees/99-slug" bash "$HOOK" <<< ""
check "no-op when .env.lane absent" "$([ ! -f "$rex_log" ] && echo 1 || echo 0)"
rm -rf "$d1"

# Test 2: no-op when .lane-signal absent
d2="$(mktemp -d)"; mkdir -p "$d2/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d2/.worktrees/42-slug/.env.lane"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d2/.worktrees/42-slug" bash "$HOOK" <<< ""
check "no-op when .lane-signal absent" "$([ ! -f "$rex_log" ] && echo 1 || echo 0)"
rm -rf "$d2"

# Test 3: signal consumed and file deleted
d3="$(mktemp -d)"; mkdir -p "$d3/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d3/.worktrees/42-slug/.env.lane"
printf 'handoff: finished feature X' > "$d3/.worktrees/42-slug/.lane-signal"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d3/.worktrees/42-slug" bash "$HOOK" <<< ""
got_rex="$(cat "$rex_log" 2>/dev/null || echo "")"
want_send="send -s ses1 -b blk1 Lane #42: handoff: finished feature X"
want_enter="send-key -s ses1 -b blk1 enter"
want_rex="$want_send
$want_enter"
check "rex send called with correct args" "$([ "$got_rex" = "$want_rex" ] && echo 1 || echo 0)"
check ".lane-signal deleted after delivery" "$([ ! -f "$d3/.worktrees/42-slug/.lane-signal" ] && echo 1 || echo 0)"
rm -rf "$d3"

# Test 4: no-op in main checkout (toplevel path has no .worktrees/)
d4="$(mktemp -d)"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d4/.env.lane"
printf 'blocked: waiting for schema' > "$d4/.lane-signal"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d4" bash "$HOOK" <<< ""
rex_calls="$(cat "$rex_log" 2>/dev/null || echo "")"
check "no-op in main checkout: rex not called" "$([ -z "$rex_calls" ] && echo 1 || echo 0)"
check "no-op in main checkout: .lane-signal preserved" "$([ -f "$d4/.lane-signal" ] && echo 1 || echo 0)"
rm -rf "$d4"

# Test 5: .lane-signal preserved when rex send fails
cat > "$tmpbin/rex" <<ENDREX
#!/usr/bin/env bash
exit 1
ENDREX
chmod +x "$tmpbin/rex"
d5="$(mktemp -d)"; mkdir -p "$d5/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d5/.worktrees/42-slug/.env.lane"
printf 'handoff: done' > "$d5/.worktrees/42-slug/.lane-signal"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d5/.worktrees/42-slug" bash "$HOOK" <<< ""
check ".lane-signal preserved when rex send fails" "$([ -f "$d5/.worktrees/42-slug/.lane-signal" ] && echo 1 || echo 0)"
check "Enter not pressed when rex send fails" "$([ ! -f "$rex_log" ] && echo 1 || echo 0)"
rm -rf "$d5"
# Restore passing rex for any further tests
cat > "$tmpbin/rex" <<ENDREX
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$rex_log"
ENDREX
chmod +x "$tmpbin/rex"

# Test 6: no-op when FOREMAN_BLOCK fails validation (contains newline/spaces via embedded chars)
d6="$(mktemp -d)"; mkdir -p "$d6/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk with space\n' > "$d6/.worktrees/42-slug/.env.lane"
printf 'handoff: done' > "$d6/.worktrees/42-slug/.lane-signal"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d6/.worktrees/42-slug" bash "$HOOK" <<< ""
check "no-op when FOREMAN_BLOCK fails validation" "$([ ! -f "$rex_log" ] && echo 1 || echo 0)"
rm -rf "$d6"

# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

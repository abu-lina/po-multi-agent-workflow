#!/usr/bin/env bash
# Tests for issue #22: lane start fully automated — no human steps required
# Run directly: bash tests/scripts/lane-auto-start.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE_BIN="$REPO_ROOT/scripts/lane"
LANE_SH="$REPO_ROOT/scripts/lane.sh"
[[ -f "$LANE_BIN" ]] || { echo "MISSING: $LANE_BIN" >&2; exit 1; }
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2" detail="${3:-}"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label" "$detail"; }

REAL_GIT="$(command -v git)"

# Build a minimal fake git repo that looks like a main checkout (not a worktree).
# Returns the repo path in $main_dir.
make_main_repo() {
  main_dir="$(mktemp -d)"
  origin_dir="$(mktemp -d)"
  "$REAL_GIT" init -q --bare --initial-branch=main "$origin_dir" 2>/dev/null ||
    "$REAL_GIT" -c init.defaultBranch=main init -q --bare "$origin_dir"
  "$REAL_GIT" clone -q "$origin_dir" "$main_dir"
  (cd "$main_dir" &&
    "$REAL_GIT" checkout -q -b main 2>/dev/null || true &&
    "$REAL_GIT" commit -q --allow-empty -m "initial" &&
    "$REAL_GIT" push -q -u origin main)
}

# Inject a directory of stub binaries into PATH.
# stub_dir must be set by caller. Each stub is a small script.
make_stubs() {
  stub_dir="$(mktemp -d)"

  # gh stub: handles 'issue view', 'issue develop', 'ls-remote'
  cat >"$stub_dir/gh" <<'SH'
#!/usr/bin/env bash
# Minimal gh stub
case "$*" in
  "issue view 42 --json labels --jq"*)
    echo "type:feature"
    ;;
  "issue view 42 --json title,body,labels,comments")
    printf '{"title":"t","body":"b","labels":[{"name":"ready"}],"comments":[]}'
    ;;
  "issue develop 42 --name"*"--base main")
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
  chmod +x "$stub_dir/gh"

  # git stub: delegates real git but intercepts specific subcommands that require
  # a real remote or real worktree infrastructure. Strips leading -C <dir> before matching.
  REAL_GIT_BIN="$(command -v git)"
  cat >"$stub_dir/git" <<SH
#!/usr/bin/env bash
# Strip leading -C <dir> pairs to get the effective subcommand.
args=("\$@")
while [[ "\${args[0]:-}" == "-C" ]]; do
  args=("\${args[@]:2}")
done
case "\${args[*]}" in
  "ls-remote --exit-code --heads origin"*)
    exit 1  # branch does not exist on remote yet
    ;;
  "worktree add"*)
    # Create the dir so .env.lane write succeeds, but skip real worktree add.
    # Last two args are <dir> <branch>; second-to-last is the dir.
    target="\${args[\${#args[@]}-2]}"
    mkdir -p "\$target"
    exit 0
    ;;
  "fetch -q origin"*)
    "$REAL_GIT_BIN" "\$@" 2>/dev/null || exit 0
    ;;
  "branch --set-upstream-to="*)
    exit 0
    ;;
  *)
    exec "$REAL_GIT_BIN" "\$@"
    ;;
esac
SH
  chmod +x "$stub_dir/git"

  cat >"$stub_dir/rex" <<'SH'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
  split)
    printf '{"block_ids":["block:test-abc-123"]}\n'
    ;;
  capture)
    printf '❯\n'
    ;;
  send|send-key)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
  chmod +x "$stub_dir/rex"

  # jq is real — just ensure it's on PATH
  if command -v jq >/dev/null 2>&1; then
    ln -sf "$(command -v jq)" "$stub_dir/jq"
  fi
}

cleanup() {
  rm -rf "${main_dir:-}" "${origin_dir:-}" "${stub_dir:-}"
}

# ------------------------------------------------------------------
# AC: REX_SESSION missing — exits with error before creating anything

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 42 test-slug 2>&1)" || rc=$?
rc="${rc:-0}"
check "REX_SESSION missing: exits non-zero" "$([ "${rc:-1}" -ne 0 ] && echo 1 || echo 0)" "rc=$rc"
check "REX_SESSION missing: error mentions REX_SESSION" \
  "$(echo "$out" | grep -qi 'REX_SESSION' && echo 1 || echo 0)" "out=$out"
check "REX_SESSION missing: no worktree created" \
  "$([ ! -d "$main_dir/.worktrees/42-test-slug" ] && echo 1 || echo 0)"
cleanup

# ------------------------------------------------------------------
# AC: REX_BLOCK missing — exits with error before creating anything

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="" bash "$LANE_BIN" start 42 test-slug 2>&1)" || rc=$?
rc="${rc:-0}"
check "REX_BLOCK missing: exits non-zero" "$([ "${rc:-1}" -ne 0 ] && echo 1 || echo 0)" "rc=$rc"
check "REX_BLOCK missing: error mentions REX_BLOCK" \
  "$(echo "$out" | grep -qi 'REX_BLOCK' && echo 1 || echo 0)" "out=$out"
check "REX_BLOCK missing: no worktree created" \
  "$([ ! -d "$main_dir/.worktrees/42-test-slug" ] && echo 1 || echo 0)"
cleanup

# ------------------------------------------------------------------
# AC: lane start writes LANE_BLOCK to .env.lane (no print-and-paste)

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 42 test-slug 2>&1)" || true
env_file="$main_dir/.worktrees/42-test-slug/.env.lane"
check "LANE_BLOCK written to .env.lane" \
  "$(grep -q '^LANE_BLOCK=' "$env_file" 2>/dev/null && echo 1 || echo 0)" "env=$(cat "$env_file" 2>/dev/null)"
cleanup

# ------------------------------------------------------------------
# AC: REX_SESSION with invalid characters — exits with error before creating anything

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session;bad" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 42 test-slug 2>&1)" || rc=$?
rc="${rc:-0}"
check "REX_SESSION invalid chars: exits non-zero" "$([ "${rc:-1}" -ne 0 ] && echo 1 || echo 0)" "rc=$rc"
check "REX_SESSION invalid chars: mentions REX_SESSION" \
  "$(echo "$out" | grep -qi 'REX_SESSION' && echo 1 || echo 0)" "out=$out"
cleanup

# ------------------------------------------------------------------
# AC: non-numeric issue — exits with error before creating anything

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 'not-a-number' test-slug 2>&1)" || rc=$?
rc="${rc:-0}"
check "non-numeric issue: exits non-zero" "$([ "${rc:-1}" -ne 0 ] && echo 1 || echo 0)" "rc=$rc"
check "non-numeric issue: error mentions issue must be integer" \
  "$(echo "$out" | grep -qi 'integer\|number' && echo 1 || echo 0)" "out=$out"
cleanup

# ------------------------------------------------------------------
# AC: lane start does not print a rex split command (no print-and-paste output)

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 42 test-slug 2>&1)"
check "no rex split command printed to output" \
  "$(echo "$out" | grep -qv 'rex split' && echo 1 || echo 0)" "out=$out"
cleanup

# ------------------------------------------------------------------
# AC: lane start sends the brief via rex send (not just prints it)

make_main_repo
make_stubs
# Replace rex stub with one that records sends
cat >"$stub_dir/rex" <<'SH'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
  split)
    printf '{"block_ids":["block:test-abc-123"]}\n'
    ;;
  capture)
    printf '❯\n'
    ;;
  send|send-key)
    echo "REX_SEND_CALLED" >> "${TMPDIR:-/tmp}/rex-send-calls.txt"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$stub_dir/rex"
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
send_log="${TMPDIR:-/tmp}/rex-send-calls.txt"
rm -f "$send_log"
(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="block:foreman-1" bash "$LANE_BIN" start 42 test-slug 2>&1) || true
check "rex send was called (brief was sent)" \
  "$([ -f "$send_log" ] && grep -q 'REX_SEND_CALLED' "$send_log" && echo 1 || echo 0)"
cleanup

# ------------------------------------------------------------------
# AC1+AC5: bash scripts/lane.sh start ... runs the full sequence (direct invocation)

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
mkdir -p "$main_dir/.worktrees"
out="$(cd "$main_dir" && REX_SESSION="session:foreman-1" REX_BLOCK="block:foreman-1" bash "$LANE_SH" start 42 direct-slug 2>&1)" || true
env_file="$main_dir/.worktrees/42-direct-slug/.env.lane"
check "direct bash scripts/lane.sh: LANE_BLOCK written" \
  "$(grep -q '^LANE_BLOCK=' "$env_file" 2>/dev/null && echo 1 || echo 0)" "out=$out"
check "direct bash scripts/lane.sh: no rex split printed" \
  "$(echo "$out" | grep -qv 'rex split' && echo 1 || echo 0)" "out=$out"
cleanup

# ------------------------------------------------------------------
# AC: lane status and lane done are unaffected (do not require REX_SESSION/REX_BLOCK)
# lane_status() is called by scripts/lane status; test it directly via the lane bin

make_main_repo
make_stubs
export PATH="$stub_dir:$PATH"
out="$(cd "$main_dir" && unset REX_SESSION; unset REX_BLOCK; bash "$LANE_BIN" status 2>&1)" || true
# lane_status exits 0 and prints WORKTREE header even when no worktrees exist.
check "lane status: works without REX_SESSION/REX_BLOCK" \
  "$(echo "$out" | grep -q 'WORKTREE' && echo 1 || echo 0)" "out=$out"
cleanup

# ------------------------------------------------------------------
# AC: direct (bash scripts/lane.sh start) and sourced (source scripts/lane.sh && lane start) follow same code path
# Verified structurally: scripts/lane bin sources lane.sh and calls lane(); both paths go through lane().
# This is a code-path check not an execution check (sourced interactive mode is not testable in CI).

check "code-path: scripts/lane bin sources lane.sh" \
  "$(grep -q 'source.*lane\.sh' "$LANE_BIN" 2>/dev/null && echo 1 || echo 0)" \
  "scripts/lane does not source lane.sh"

# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

#!/usr/bin/env bash
# Tests for the lane prompt poll (#48): the brief goes only into claude's input box,
# never into the folder-trust dialog. Run directly: bash scripts/test-lane-prompt-poll.sh

LANE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane.sh"
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "1" ]]; then pass "$1"; else fail "$1"; fi; }

stub="$(mktemp -d)"
repo="$(mktemp -d)"
trap 'rm -rf "$stub" "$repo"' EXIT
git init -q "$repo"

# Stub rex: split returns a block id, capture prints the canned $MOCK_SCREEN,
# send/send-key are logged so tests can assert nothing was pasted.
cat > "$stub/rex" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  split) printf '{"block_ids":["block:lane1"]}\n' ;;
  capture)
    case "$MOCK_SCREEN" in
      trust) printf ' Quick safety check: Is this a project you created or one you trust?\n ❯ No, exit\n   Yes, I trust this folder\n' ;;
      ready) printf ' Welcome to Claude Code\n────────────\n❯  \n────────────\n  ⏵⏵ bypass permissions on\n' ;;
      *) printf '\n' ;;
    esac ;;
  send) cat > /dev/null; echo "send" >> "$REX_LOG" ;;
  send-key) echo "send-key $*" >> "$REX_LOG" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/rex"

run_open() {
  : > "$stub/rex.log"
  (cd "$repo" && PATH="$stub:$PATH" REX_LOG="$stub/rex.log" MOCK_SCREEN="$1" REX_SESSION=session:test REX_BLOCK=block:foreman \
    bash -c 'source "$1"; sleep() { :; }; _lane_rex_open claude "" "$2" "$2/.env.lane" 48' _ "$LANE_SH" "$repo" 2>&1)
}
sent() { grep -q '^send$' "$stub/rex.log"; }

# AC1: folder-trust dialog -> lane stops naming the dialog and worktree, no brief pasted
out="$(run_open trust)"; rc=$?
check "AC1: trust dialog -> lane returns non-zero" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
check "AC1: trust dialog -> message names the folder-trust dialog" "$(grep -qi 'folder-trust' <<< "$out" && echo 1 || echo 0)"
check "AC1: trust dialog -> message names the worktree" "$(grep -qF "$repo" <<< "$out" && echo 1 || echo 0)"
check "AC1: trust dialog -> no brief pasted" "$(sent && echo 0 || echo 1)"

# AC1 on rerun: re-entering an existing lane (the documented recovery path) also stops non-zero
git -C "$repo" commit -q --allow-empty -m init
git -C "$repo" worktree add -q "$repo/.worktrees/48-trust" -b fix/48-trust
: > "$repo/.worktrees/48-trust/.env.lane"
: > "$stub/rex.log"
out="$(cd "$repo" && PATH="$stub:$PATH" REX_LOG="$stub/rex.log" MOCK_SCREEN=trust REX_SESSION=session:test REX_BLOCK=block:foreman \
  bash -c 'source "$1"; sleep() { :; }; lane 48 "" claude sonnet' _ "$LANE_SH" 2>&1)"; rc=$?
check "AC1: trust dialog on rerun -> lane returns non-zero" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
check "AC1: trust dialog on rerun -> message names the folder-trust dialog" "$(grep -qi 'folder-trust' <<< "$out" && echo 1 || echo 0)"
check "AC1: trust dialog on rerun -> no brief pasted" "$(sent && echo 0 || echo 1)"

# AC2: input box ready -> brief sent as today
out="$(run_open ready)"; rc=$?
check "AC2: input box ready -> lane returns 0" "$([[ $rc -eq 0 ]] && echo 1 || echo 0)"
check "AC2: input box ready -> brief sent" "$(sent && echo 1 || echo 0)"

# AC3: neither dialog nor input box within 30 s -> existing timeout error, no brief pasted
out="$(run_open blank)"; rc=$?
check "AC3: blank screen -> lane returns non-zero" "$([[ $rc -ne 0 ]] && echo 1 || echo 0)"
check "AC3: blank screen -> existing timeout error" "$(grep -q 'timed out waiting for prompt' <<< "$out" && echo 1 || echo 0)"
check "AC3: blank screen -> no brief pasted" "$(sent && echo 0 || echo 1)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

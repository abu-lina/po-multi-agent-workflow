#!/usr/bin/env bash
# Tests for issue #61: no gh call in lane.sh receives an inherited GH_HOST, and a
# failed lane start removes only the remote branch it created.
# Run directly: bash scripts/test-lane-gh-host.sh

LANE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane.sh"
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0
FAIL=0
check() { if [[ "$2" == 1 ]]; then echo "PASS: $1"; PASS=$((PASS + 1)); else echo "FAIL: $1"; FAIL=$((FAIL + 1)); fi; }
yes_if() { if "$@"; then echo 1; else echo 0; fi; }

REAL_GIT="$(command -v git)"

# Stub gh: logs every call, fails like real gh when GH_HOST is set at all (even empty).
stub_dir="$(mktemp -d)"
local_dir="" origin_dir=""
trap 'rm -rf "$stub_dir" "$local_dir" "$origin_dir"' EXIT
cat > "$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s%s\n' "${GH_HOST+GH_HOST=$GH_HOST }" "$*" >> "$GH_LOG"
if [[ -n "${GH_HOST+x}" ]]; then
  echo 'none of the git remotes configured for this repository correspond to the GH_HOST environment variable' >&2
  exit 1
fi
case "$1 $2" in
  "issue view") echo type:bugfix ;;
  "issue develop") git push -q origin "origin/main:refs/heads/$5" ;;
  "pr view")
    case "$*" in
      *statusCheckRollup*) echo '{"state":"OPEN","statusCheckRollup":[]}' ;;
      *) echo MERGED ;;
    esac ;;
esac
EOF
cat > "$stub_dir/rex" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  split) echo '{"block_ids":["block:lane-test"]}' ;;
  capture) echo '❯' ;;
  send) cat >/dev/null ;;
esac
EOF
chmod +x "$stub_dir/gh" "$stub_dir/rex"
export GH_LOG="$stub_dir/gh.log"

make_repos() {
  origin_dir="$(mktemp -d)"
  local_dir="$(mktemp -d)"
  "$REAL_GIT" init -q --bare --initial-branch=main "$origin_dir"
  "$REAL_GIT" clone -q "$origin_dir" "$local_dir" 2>/dev/null
  (cd "$local_dir" &&
    "$REAL_GIT" checkout -q -b main &&
    echo ".worktrees/" > .gitignore &&
    "$REAL_GIT" add .gitignore &&
    "$REAL_GIT" commit -q -m initial &&
    "$REAL_GIT" push -q -u origin main)
  : > "$GH_LOG"
}

remote_has() { "$REAL_GIT" --git-dir="$origin_dir" show-ref --verify -q "refs/heads/$1"; }
remote_lacks() { ! remote_has "$1"; }
no_gh_host_in_log() { [[ -s "$GH_LOG" ]] && ! grep -q 'GH_HOST=' "$GH_LOG"; }

# Runs a lane.sh function in a bash shell with GH_HOST exported, then prints that
# shell's GH_HOST so the test can see it was left alone.
run_lane() {
  (cd "$local_dir" && PATH="$stub_dir:$PATH" REX_SESSION=session:test REX_BLOCK=block:test \
    bash -c 'source "$1"; shift; export GH_HOST=ghe.invalid; "$@"; rc=$?; echo "AFTER_GH_HOST=$GH_HOST"; exit $rc' \
    _ "$LANE_SH" "$@" 2>&1)
}

# ------------------------------------------------------------------
# AC1 + AC6: lane start with a foreign GH_HOST
make_repos
out="$(run_lane lane 9001 ok)"
rc=$?
check "AC1: lane start with GH_HOST set starts the lane" "$([ $rc -eq 0 ] && [ -d "$local_dir/.worktrees/9001-ok" ] && echo 1 || echo 0)"
check "AC1: lane start passes no GH_HOST to gh" "$(yes_if no_gh_host_in_log)"
check "AC6: lane start leaves the shell's GH_HOST unchanged" "$(yes_if grep -q '^AFTER_GH_HOST=ghe.invalid$' <<<"$out")"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC2 + AC6: lane status with GH_HOST set
make_repos
"$REAL_GIT" -C "$local_dir" worktree add -q "$local_dir/.worktrees/9003-st" -b fix/9003-st
out="$(run_lane lane_status)"
check "AC2: lane status with GH_HOST set shows the PR state" "$(yes_if grep -q $'fix/9003-st\tOPEN' <<<"$out")"
check "AC2: lane status passes no GH_HOST to gh" "$(yes_if no_gh_host_in_log)"
check "AC6: lane status leaves the shell's GH_HOST unchanged" "$(yes_if grep -q '^AFTER_GH_HOST=ghe.invalid$' <<<"$out")"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC3 + AC6: lane done with GH_HOST set
make_repos
"$REAL_GIT" -C "$local_dir" worktree add -q "$local_dir/.worktrees/7791-dn" -b fix/7791-dn
printf 'PORT=3791\n' > "$local_dir/.worktrees/7791-dn/.env.lane"
out="$(run_lane lane_done 7791)"
rc=$?
check "AC3: lane done with GH_HOST set removes the lane" "$([ $rc -eq 0 ] && grep -q 'lane #7791 removed' <<<"$out" && echo 1 || echo 0)"
check "AC3: lane done passes no GH_HOST to gh" "$(yes_if no_gh_host_in_log)"
check "AC6: lane done leaves the shell's GH_HOST unchanged" "$(yes_if grep -q '^AFTER_GH_HOST=ghe.invalid$' <<<"$out")"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC4: lane start fails after creating the remote branch → branch deleted
make_repos
mkdir -p "$local_dir/.worktrees"
: > "$local_dir/.worktrees/9002-boom"   # a file in the way makes git worktree add fail
run_lane lane 9002 boom >/dev/null
rc=$?
check "AC4: failed lane start returns non-zero" "$([ $rc -ne 0 ] && echo 1 || echo 0)"
check "AC4: failed lane start called gh issue develop" "$(yes_if grep -q '^issue develop 9002' "$GH_LOG")"
check "AC4: failed lane start deletes the remote branch it created" "$(yes_if remote_lacks fix/9002-boom)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC4: failure after git worktree add → no worktree dir and no remote branch left
make_repos
printf 'node_modules/\n' >> "$local_dir/.git/info/exclude"
mkdir -p "$local_dir/node_modules"
: > "$local_dir/node_modules/unreadable"
chmod 000 "$local_dir/node_modules/unreadable"   # node_modules copy fails after worktree add
out="$(run_lane lane 9005 late)"
chmod 644 "$local_dir/node_modules/unreadable"
check "AC4: late failure came from the node_modules copy" "$(yes_if grep -q 'could not clone node_modules' <<<"$out")"
check "AC4: late failure leaves no worktree dir" "$([ ! -e "$local_dir/.worktrees/9005-late" ] && echo 1 || echo 0)"
check "AC4: late failure leaves no remote branch" "$(yes_if remote_lacks fix/9005-late)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC5: lane start fails on a pre-existing remote branch → branch kept
make_repos
"$REAL_GIT" -C "$local_dir" push -q origin main:refs/heads/fix/9004-kept
mkdir -p "$local_dir/.worktrees"
: > "$local_dir/.worktrees/9004-kept"
out="$(run_lane lane 9004 kept)"
rc=$?
check "AC5: failed lane start on existing branch returns non-zero" "$([ $rc -ne 0 ] && echo 1 || echo 0)"
check "AC5: failure came from the worktree step, not earlier" "$(yes_if grep -q 'already exists' <<<"$out")"
check "AC5: failed lane start leaves the pre-existing remote branch" "$(yes_if remote_has fix/9004-kept)"
rm -rf "$local_dir" "$origin_dir"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

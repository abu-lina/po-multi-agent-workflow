#!/usr/bin/env bash
# Tests for .env.lane and .worktrees/ exclusion from uncommitted-change guards.
# Run directly: bash scripts/test-lane-env-lane.sh

LANE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane.sh"
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label"; }

REAL_GIT="$(command -v git)"

# Helper: create a local clone with an origin so origin/main exists.
make_repos() {
  origin_dir="$(mktemp -d)"
  local_dir="$(mktemp -d)"
  "$REAL_GIT" init -q --bare --initial-branch=main "$origin_dir" 2>/dev/null ||
    "$REAL_GIT" -c init.defaultBranch=main init -q --bare "$origin_dir"
  "$REAL_GIT" clone -q "$origin_dir" "$local_dir"
  (cd "$local_dir" && \
    "$REAL_GIT" checkout -q -b main 2>/dev/null || true && \
    "$REAL_GIT" commit -q --allow-empty -m "initial" && \
    "$REAL_GIT" push -q -u origin main)
}

run_check_main() {
  local dir="$1"
  (cd "$dir" && bash -c "source '$LANE_SH'; _lane_check_main" 2>&1)
}

# ------------------------------------------------------------------
# AC: lane_start succeeds when .worktrees/ is the only untracked item

make_repos
mkdir -p "$local_dir/.worktrees/30-some-slug"
touch "$local_dir/.worktrees/30-some-slug/.gitkeep"
out="$(run_check_main "$local_dir")"
rc=$?
check "lane_start: .worktrees/ only → exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "lane_start: .worktrees/ only → no uncommitted error" "$(echo "$out" | grep -qvi 'uncommitted' && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC: other genuinely uncommitted changes still block lane_start

make_repos
echo "dirty" > "$local_dir/dirty.txt"
out="$(run_check_main "$local_dir")"
rc=$?
check "lane_start: other untracked file → exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
check "lane_start: other untracked file → mentions uncommitted" "$(echo "$out" | grep -qi 'uncommitted' && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC: lane_done succeeds when .env.lane is the only untracked file
#
# lane_done calls `gh pr view` to check state; stub gh on PATH to return MERGED.
# _lane_dir finds a worktree by issue number; set up a fake worktree structure.

stub_dir="$(mktemp -d)"
cat > "$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'MERGED\n'
EOF
chmod +x "$stub_dir/gh"

make_repos
wt_dir="$local_dir/.worktrees/7777-test-slug"
"$REAL_GIT" -C "$local_dir" worktree add -q --orphan "$wt_dir" -b chore/7777-test-slug
printf 'PORT=7777\n' > "$wt_dir/.env.lane"

out="$(cd "$local_dir" && PATH="$stub_dir:$PATH" bash -c "source '$LANE_SH'; lane_done 7777" 2>&1)"
rc=$?
check "lane_done: .env.lane only → exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "lane_done: .env.lane only → no uncommitted error" "$(echo "$out" | grep -qvi 'uncommitted' && echo 1 || echo 0)"

rm -rf "$local_dir" "$origin_dir" "$stub_dir"

# ------------------------------------------------------------------
# AC: other genuinely uncommitted changes still block lane_done

stub_dir="$(mktemp -d)"
cat > "$stub_dir/gh" <<'EOF'
#!/usr/bin/env bash
printf 'MERGED\n'
EOF
chmod +x "$stub_dir/gh"

make_repos
wt_dir="$local_dir/.worktrees/7778-test-slug"
"$REAL_GIT" -C "$local_dir" worktree add -q --orphan "$wt_dir" -b chore/7778-test-slug
printf 'PORT=7778\n' > "$wt_dir/.env.lane"
echo "dirty" > "$wt_dir/untracked.txt"

out="$(cd "$local_dir" && PATH="$stub_dir:$PATH" bash -c "source '$LANE_SH'; lane_done 7778" 2>&1)"
rc=$?
check "lane_done: other untracked file → exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
check "lane_done: other untracked file → mentions uncommitted" "$(echo "$out" | grep -qi 'uncommitted' && echo 1 || echo 0)"

rm -rf "$local_dir" "$origin_dir" "$stub_dir"

# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

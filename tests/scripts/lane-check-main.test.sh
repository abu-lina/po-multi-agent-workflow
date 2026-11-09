#!/usr/bin/env bash
# Tests for _lane_check_main in scripts/lane.sh
# Run directly: bash tests/scripts/lane-check-main.test.sh

LANE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/lane.sh"
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label"; }

REAL_GIT="$(command -v git)"

# Helper: create a bare "origin" repo plus a local clone.
# Sets $local_dir and $origin_dir.
make_repos() {
  origin_dir="$(mktemp -d)"
  local_dir="$(mktemp -d)"
  # Init bare origin with explicit main branch
  "$REAL_GIT" init -q --bare --initial-branch=main "$origin_dir" 2>/dev/null ||
    "$REAL_GIT" -c init.defaultBranch=main init -q --bare "$origin_dir"
  "$REAL_GIT" clone -q "$origin_dir" "$local_dir"
  # Seed a commit so main exists on origin
  (cd "$local_dir" && \
    "$REAL_GIT" checkout -q -b main 2>/dev/null || true && \
    "$REAL_GIT" commit -q --allow-empty -m "initial" && \
    "$REAL_GIT" push -q -u origin main)
}

run_check() {
  # Source lane.sh inside $1, capture stderr; return the exit code.
  local dir="$1"
  (cd "$dir" && bash -c "source '$LANE_SH'; _lane_check_main" 2>&1)
}

# ------------------------------------------------------------------
# AC: origin clean — returns 0, no output

make_repos
out="$(run_check "$local_dir")"
rc=$?
check "clean main: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "clean main: no output" "$([ -z "$out" ] && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC: local only ahead of origin — exits 1 with "push" message (existing behaviour preserved)

make_repos
(cd "$local_dir" && "$REAL_GIT" commit -q --allow-empty -m "local-only commit")
out="$(run_check "$local_dir")"
rc=$?
check "local ahead: exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
check "local ahead: mentions push" "$(echo "$out" | grep -qi 'push' && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC: origin ahead of local — auto-pull --rebase, exits 0, prints pulled N commit(s) notice

make_repos
# Add a commit to origin directly (simulates another PR merging)
(cd "$local_dir" && "$REAL_GIT" commit -q --allow-empty -m "new-on-origin" && "$REAL_GIT" push -q origin main && "$REAL_GIT" reset -q --hard HEAD~1)
out="$(run_check "$local_dir")"
rc=$?
check "origin ahead: exits 0" "$([ $rc -eq 0 ] && echo 1 || echo 0)"
check "origin ahead: prints pulled N commit(s)" "$(echo "$out" | grep -qE 'pulled [0-9]+ commit' && echo 1 || echo 0)"
# Confirm local main now matches origin
local_sha="$(cd "$local_dir" && "$REAL_GIT" rev-parse main)"
origin_sha="$(cd "$local_dir" && "$REAL_GIT" rev-parse origin/main)"
check "origin ahead: local main now matches origin/main" "$([ "$local_sha" = "$origin_sha" ] && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# AC: diverged — exits 1 with clear abort message, no rebase

make_repos
# Local gets one commit, origin gets a different one (neutral commit messages)
(cd "$local_dir" && "$REAL_GIT" commit -q --allow-empty -m "origin-only" && "$REAL_GIT" push -q origin main && "$REAL_GIT" reset -q --hard HEAD~1)
(cd "$local_dir" && "$REAL_GIT" commit -q --allow-empty -m "local-only")
local_sha_before="$(cd "$local_dir" && "$REAL_GIT" rev-parse main)"
out="$(run_check "$local_dir")"
rc=$?
check "diverged: exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
# Must mention diverged/diverge (not just the push-ahead message)
check "diverged: prints diverged message" "$(echo "$out" | grep -qiE 'diverged?' && echo 1 || echo 0)"
# Local HEAD must not have changed (no rebase happened)
local_sha_after="$(cd "$local_dir" && "$REAL_GIT" rev-parse main)"
check "diverged: local main unchanged" "$([ "$local_sha_before" = "$local_sha_after" ] && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# Guard: dirty working tree — exits 1 with uncommitted changes message

make_repos
echo "untracked" > "$local_dir/dirty.txt"
out="$(run_check "$local_dir")"
rc=$?
check "dirty tree: exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
check "dirty tree: mentions uncommitted changes" "$(echo "$out" | grep -qi 'uncommitted' && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------
# Guard: pre-existing REBASE_HEAD — exits 1 with mid-rebase message

make_repos
git_dir="$(cd "$local_dir" && "$REAL_GIT" rev-parse --git-dir)"
touch "$local_dir/$git_dir/REBASE_HEAD"
out="$(run_check "$local_dir")"
rc=$?
check "REBASE_HEAD: exits 1" "$([ $rc -eq 1 ] && echo 1 || echo 0)"
check "REBASE_HEAD: mentions mid-rebase" "$(echo "$out" | grep -qi 'rebase' && echo 1 || echo 0)"
rm -rf "$local_dir" "$origin_dir"

# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

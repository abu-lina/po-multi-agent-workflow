#!/usr/bin/env bash
# Tests for issue #28 (behavioural since #61): lane_done's gh pr view must not
# receive GH_HOST, even an empty one.
set -euo pipefail

LANE_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lane.sh"
REAL_GIT="$(command -v git)"

echo "--- lane_done GH_HOST tests ---"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ -n "${GH_HOST+x}" ]] && { echo "gh got GH_HOST='$GH_HOST'" >&2; exit 1; }
echo MERGED
EOF
chmod +x "$tmp/bin/gh"

"$REAL_GIT" init -q --initial-branch=main "$tmp/repo"
"$REAL_GIT" -C "$tmp/repo" commit -q --allow-empty -m initial
"$REAL_GIT" -C "$tmp/repo" worktree add -q "$tmp/repo/.worktrees/7792-dn" -b fix/7792-dn
printf '.worktrees/\n' > "$tmp/repo/.git/info/exclude"

if out="$(cd "$tmp/repo" && GH_HOST=ghe.invalid PATH="$tmp/bin:$PATH" \
  bash -c 'source "$1"; lane_done 7792' _ "$LANE_SH" 2>&1)"; then
  echo "  PASS: lane_done: gh pr view runs without GH_HOST"
else
  echo "  FAIL: lane_done with GH_HOST set did not remove the lane:"
  echo "$out"
  exit 1
fi

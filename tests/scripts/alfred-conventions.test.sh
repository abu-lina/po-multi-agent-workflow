#!/usr/bin/env bash
# Tests for #42: Alfred conventions (.lane-notes.md, .review-results/, stop hook, brief)
# Run directly: bash tests/scripts/alfred-conventions.test.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/scripts/hooks/lane-signal-notify.sh"
LANE_SH="$ROOT/scripts/lane.sh"
GITIGNORE="$ROOT/.gitignore"

[[ -f "$HOOK" ]] || { echo "MISSING: $HOOK" >&2; exit 1; }
[[ -f "$LANE_SH" ]] || { echo "MISSING: $LANE_SH" >&2; exit 1; }

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label"; }

REAL_GIT="$(command -v git)"

# ------------------------------------------------------------------
# .gitignore: .lane-notes.md and .review-results/ are ignored

check ".gitignore contains .lane-notes.md" \
  "$(grep -qx '.lane-notes.md' "$GITIGNORE" && echo 1 || echo 0)"

check ".gitignore contains .review-results/" \
  "$(grep -qx '.review-results/' "$GITIGNORE" && echo 1 || echo 0)"

# ------------------------------------------------------------------
# Stop hook: appends Final Summary to .lane-notes.md on handoff

tmpbin="$(mktemp -d)"
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

# Test: handoff signal appends Final Summary section to .lane-notes.md
d1="$(mktemp -d)"; mkdir -p "$d1/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d1/.worktrees/42-slug/.env.lane"
printf 'handoff: PR #99 ready for review' > "$d1/.worktrees/42-slug/.lane-signal"
printf '# Lane Notes\n\nSome existing content\n' > "$d1/.worktrees/42-slug/.lane-notes.md"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d1/.worktrees/42-slug" bash "$HOOK" <<< ""
check "handoff appends Final Summary to .lane-notes.md" \
  "$(grep -q '## Final Summary' "$d1/.worktrees/42-slug/.lane-notes.md" && echo 1 || echo 0)"
check "Final Summary contains outcome" \
  "$(grep -q 'handoff' "$d1/.worktrees/42-slug/.lane-notes.md" && echo 1 || echo 0)"
rm -rf "$d1"

# Test: handoff creates .lane-notes.md if it doesn't exist
d2="$(mktemp -d)"; mkdir -p "$d2/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d2/.worktrees/42-slug/.env.lane"
printf 'handoff: PR #100 ready for review' > "$d2/.worktrees/42-slug/.lane-signal"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d2/.worktrees/42-slug" bash "$HOOK" <<< ""
check "handoff skips Final Summary when .lane-notes.md absent" \
  "$([ ! -f "$d2/.worktrees/42-slug/.lane-notes.md" ] && echo 1 || echo 0)"
rm -rf "$d2"

# Test: blocked signal does NOT append Final Summary
d3="$(mktemp -d)"; mkdir -p "$d3/.worktrees/42-slug"
printf 'ISSUE=42\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$d3/.worktrees/42-slug/.env.lane"
printf 'blocked: waiting for schema' > "$d3/.worktrees/42-slug/.lane-signal"
printf '# Lane Notes\n' > "$d3/.worktrees/42-slug/.lane-notes.md"
rm -f "$rex_log"
MOCK_TOPLEVEL="$d3/.worktrees/42-slug" bash "$HOOK" <<< ""
check "blocked signal does not append Final Summary" \
  "$(grep -q '## Final Summary' "$d3/.worktrees/42-slug/.lane-notes.md" && echo 0 || echo 1)"
rm -rf "$d3"

# ------------------------------------------------------------------
# Lane brief template: includes .lane-notes.md instructions

brief="$(bash -c 'source "$1"; _lane_prompt 42' _ "$LANE_SH")"

check "brief mentions .lane-notes.md" \
  "$(echo "$brief" | grep -q '.lane-notes.md' && echo 1 || echo 0)"

check "brief mentions maintaining lane notes" \
  "$(echo "$brief" | grep -qi 'lane.notes\|lane-notes' && echo 1 || echo 0)"

# ------------------------------------------------------------------
# Foreman doc references .review-results/
FOREMAN_DOC="$ROOT/docs/agents/foreman.md"
check "foreman.md Stage 5 references .review-results/" \
  "$(grep -q '\.review-results/' "$FOREMAN_DOC" && echo 1 || echo 0)"

# Lane doc references .lane-notes.md
LANE_DOC="$ROOT/docs/agents/lane.md"
check "lane.md references .lane-notes.md maintenance" \
  "$(grep -q '\.lane-notes\.md' "$LANE_DOC" && echo 1 || echo 0)"

# ------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

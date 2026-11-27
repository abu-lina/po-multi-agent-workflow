#!/usr/bin/env bash
# Tests for the lane Stop hook (#63): real signals always delivered, one fallback per lane.
# Run directly: bash scripts/test-lane-signal-notify.sh

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPTS/hooks/lane-signal-notify.sh"
LANE_SH="$SCRIPTS/lane.sh"
[[ -f "$HOOK" ]] || { echo "MISSING: $HOOK" >&2; exit 1; }

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { if [[ "$2" == "1" ]]; then pass "$1"; else fail "$1"; fi; }

stub="$(mktemp -d)"
tmp="$(mktemp -d)"
trap 'rm -rf "$stub" "$tmp"' EXIT

# Stub rex: log every call as one line.
cat > "$stub/rex" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REX_LOG"
STUB
chmod +x "$stub/rex"
export REX_LOG="$stub/rex.log"

# Fresh lane worktree path (the hook exits outside /.worktrees/).
new_lane() {
  lane="$tmp/$1/.worktrees/63-slug"
  mkdir -p "$lane"
  git -C "$lane" init -q
  git -C "$lane" checkout -q -b fix/63-slug
  git -C "$lane" commit -q --allow-empty -m "last thing"
  printf 'ISSUE=63\nREX_SESSION_ID=ses1\nFOREMAN_BLOCK=blk1\n' > "$lane/.env.lane"
  : > "$REX_LOG"
}
stop() { (cd "$lane" && PATH="$stub:$PATH" bash "$HOOK" < /dev/null); }
sends() { grep -c '^send -s ses1 -b blk1 ' "$REX_LOG"; }
sent_text() { grep -qF -- "send -s ses1 -b blk1 $1" "$REX_LOG"; }

# AC1: turn ends with no signal -> one fallback with the new wording, marker created
new_lane ac1
stop
check "AC1: no signal -> one fallback sent" "$([[ $(sends) -eq 1 ]] && echo 1 || echo 0)"
check "AC1: no signal -> new fallback wording" "$(sent_text 'Lane #63: turn ended, no signal yet (may be waiting on reviewers), branch: fix/63-slug, last commit: last thing' && echo 1 || echo 0)"
check "AC1: no signal -> .lane-signal-fallback created" "$([[ -f "$lane/.lane-signal-fallback" ]] && echo 1 || echo 0)"

# AC2: second turn ends with no signal -> no second fallback
stop
check "AC2: second no-signal turn -> no second fallback" "$([[ $(sends) -eq 1 ]] && echo 1 || echo 0)"

# AC3: fallback sent, then handoff written -> handoff delivered
echo "handoff: PR #99 ready for review" > "$lane/.lane-signal"
stop
check "AC3: handoff after fallback -> delivered" "$(sent_text 'Lane #63: handoff: PR #99 ready for review' && echo 1 || echo 0)"

# AC4: blocked, then later handoff -> both delivered
new_lane ac4
echo "blocked: need a secret" > "$lane/.lane-signal"
stop
echo "handoff: PR #99 ready for review" > "$lane/.lane-signal"
stop
check "AC4: blocked delivered" "$(sent_text 'Lane #63: blocked: need a secret' && echo 1 || echo 0)"
check "AC4: later handoff delivered" "$(sent_text 'Lane #63: handoff: PR #99 ready for review' && echo 1 || echo 0)"

# AC5: Stop runs again after a delivered signal -> nothing sent, no fallback
new_lane ac5
echo "handoff: PR #99 ready for review" > "$lane/.lane-signal"
stop
: > "$REX_LOG"
stop
check "AC5: Stop after delivered signal -> nothing sent" "$([[ ! -s "$REX_LOG" ]] && echo 1 || echo 0)"
check "AC5: Stop after delivered signal -> no fallback marker" "$([[ ! -f "$lane/.lane-signal-fallback" ]] && echo 1 || echo 0)"

# AC6: signal outside the vocabulary -> nothing sent
new_lane ac6
echo "done: all good" > "$lane/.lane-signal"
stop
check "AC6: off-vocabulary signal -> nothing sent" "$([[ ! -s "$REX_LOG" ]] && echo 1 || echo 0)"

# Security (#63 review): a 5000-char signal reaches the foreman pane capped at 200 chars
new_lane cap
printf 'handoff: %s' "$(printf 'x%.0s' {1..5000})" > "$lane/.lane-signal"
stop
line="$(grep '^send -s ses1 -b blk1 ' "$REX_LOG")"
msg="${line#send -s ses1 -b blk1 Lane #63: }"
check "cap: 5000-char signal delivered once" "$([[ $(sends) -eq 1 ]] && echo 1 || echo 0)"
check "cap: delivered signal is 200 chars" "$([[ ${#msg} -eq 200 ]] && echo 1 || echo 0)"

# AC7: handoff with .lane-notes.md -> Final Summary appended with the signal
new_lane ac7
printf '# Notes\n' > "$lane/.lane-notes.md"
echo "handoff: PR #99 ready for review" > "$lane/.lane-signal"
stop
check "AC7: handoff -> Final Summary section appended" "$(grep -q '^## Final Summary$' "$lane/.lane-notes.md" && echo 1 || echo 0)"
check "AC7: handoff -> Final Summary holds the signal" "$(grep -qF 'handoff: PR #99 ready for review' "$lane/.lane-notes.md" && echo 1 || echo 0)"

# AC9: mv after delivery fails -> .lane-signal removed anyway, no redelivery
new_lane ac9
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/mv"
chmod +x "$stub/mv"
echo "handoff: PR #99 ready for review" > "$lane/.lane-signal"
stop
stop
rm -f "$stub/mv"
check "AC9: mv fails -> .lane-signal removed" "$([[ ! -f "$lane/.lane-signal" ]] && echo 1 || echo 0)"
check "AC9: mv fails -> no redelivery on next Stop" "$([[ $(grep -c 'handoff: PR #99' "$REX_LOG") -eq 1 ]] && echo 1 || echo 0)"
check "AC9: mv fails -> no fallback after the real signal" "$([[ $(sends) -eq 1 ]] && echo 1 || echo 0)"

# AC8: rerunning lane <issue> on an existing lane removes .lane-signal-fallback
repo="$tmp/ac8"
git init -q "$repo"
git -C "$repo" commit -q --allow-empty -m init
git -C "$repo" worktree add -q "$repo/.worktrees/63-slug" -b fix/63-slug
wt="$repo/.worktrees/63-slug"
printf 'ISSUE=63\n' > "$wt/.env.lane"
touch "$wt/.lane-signal" "$wt/.lane-signal-sent" "$wt/.lane-signal-fallback"
(cd "$repo" && PATH="$stub:$PATH" REX_SESSION=session:test REX_BLOCK=block:foreman \
  bash -c 'source "$1"; sleep() { :; }; lane 63 "" claude sonnet' _ "$LANE_SH" > /dev/null 2>&1)
check "AC8: lane rerun -> .lane-signal-fallback removed" "$([[ ! -f "$wt/.lane-signal-fallback" ]] && echo 1 || echo 0)"
check "AC8: lane rerun -> .lane-signal and .lane-signal-sent removed" "$([[ ! -f "$wt/.lane-signal" && ! -f "$wt/.lane-signal-sent" ]] && echo 1 || echo 0)"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

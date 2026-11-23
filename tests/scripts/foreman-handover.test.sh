#!/usr/bin/env bash
# Tests for #46: foreman session-end handover and Rex session rotation.
# Run directly: bash tests/scripts/foreman-handover.test.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/foreman-handover"
FOREMAN_MD="$ROOT/docs/agents/foreman.md"

PASS=0; FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
check() { local label="$1" ok="$2"; [[ "$ok" == "1" ]] && pass "$label" || fail "$label"; }
yes_if() { if "$@"; then echo 1; else echo 0; fi; }

REAL_GIT="$(command -v git)"
TODAY="$(date +%F)"
ESC=$'\033'

# ------------------------------------------------------------------
# Fixture: a main checkout, stub gh/rex/claude on PATH, mock data files.

setup() {
  T="$(mktemp -d)"
  repo="$T/repo"; mock="$T/mock"; bin="$T/bin"
  mkdir -p "$repo" "$mock" "$bin" "$T/memory"
  "$REAL_GIT" -c init.defaultBranch=main init -q "$repo"
  (cd "$repo" && mkdir -p docs/ai/learnings && echo x > docs/ai/learnings/41.md &&
    "$REAL_GIT" add docs && "$REAL_GIT" -c user.email=t@t -c user.name=t commit -q -m init)
  printf 'rule\n' > "$T/memory/trap_new-thing.md"
  : > "$mock/rex.log"

  # Default mock data: 3 merged PRs, one open PR, ready issues, one retro issue.
  printf '[{"number":7,"createdAt":"2026-01-01T00:00:00Z","comments":[]}]' > "$mock/handover_issue.json"
  printf '[{"number":11,"title":"feat: a"},{"number":12,"title":"fix: b"},{"number":13,"title":"docs: c"}]' > "$mock/merged.json"
  printf '[{"number":20,"title":"wip thing","headRefName":"feat/20-wip"}]' > "$mock/open.json"
  cat > "$mock/ready.json" <<'EOF'
[{"number":31,"title":"low prio","labels":[{"name":"P3"},{"name":"area:docs"}]},
 {"number":32,"title":"second","labels":[{"name":"P2"},{"name":"area:infra"}]},
 {"number":33,"title":"top","labels":[{"name":"P1"},{"name":"area:auth"}]},
 {"number":34,"title":"same area as top","labels":[{"name":"P1"},{"name":"area:auth"}]}]
EOF
  printf '[{"number":40,"title":"retro: lanes"}]' > "$mock/retro.json"
  printf '{"sessions":[{"session_id":"session:old","label":"foreman-%s-1"}]}' "$TODAY" > "$mock/sessions.json"

  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env bash
m="$MOCK_DIR"; args="$*"
case "$args" in
  "issue list --label handover"*) cat "$m/handover_issue.json" ;;
  "issue view 7"*) cat "$m/handover_issue.json" | jq '.[0]' ;;
  "pr list --state merged"*) cat "$m/merged.json" ;;
  "pr list --state open"*) cat "$m/open.json" ;;
  "issue list --label ready"*) cat "$m/ready.json" ;;
  *"label:retro"*) cat "$m/retro.json" ;;
  "issue comment 7"*) cat > "$m/comment_body"; echo "https://github.com/o/r/issues/7#issuecomment-1" ;;
  *) echo "gh stub: unexpected: $args" >&2; exit 1 ;;
esac
EOF
  cat > "$bin/rex" <<'EOF'
#!/usr/bin/env bash
m="$MOCK_DIR"
printf '%s\n' "$*" >> "$m/rex.log"
case "$1 ${2:-}" in
  "new "*)
    [[ "${MOCK_REX_FAIL:-}" == new ]] && exit 1
    prev=""; for a in "$@"; do [[ "$prev" == "-c" && "$a" != --* ]] && printf '%s' "$a" > "$m/new_cmd"; prev="$a"; done
    echo '{"session_id":"session:new1","initial_windows":[]}' ;;
  "session ls") cat "$m/sessions.json" ;;
  "session inspect") [[ "${MOCK_REX_FAIL:-}" == inspect ]] && exit 1; echo '{"session_id":"session:new1"}' ;;
  "session rename") [[ "${MOCK_REX_FAIL:-}" == rename ]] && exit 1; exit 0 ;;
  "session kill") exit 0 ;;
esac
EOF
  cat > "$bin/claude" <<'EOF'
#!/usr/bin/env bash
pwd > "$MOCK_DIR/claude_cwd"
printf '%s' "$1" > "$MOCK_DIR/claude_arg"
EOF
  chmod +x "$bin/gh" "$bin/rex" "$bin/claude"
}

teardown() { rm -rf "$T"; }

run_script() {
  (cd "$repo" && PATH="$bin:$PATH" MOCK_DIR="$mock" FOREMAN_MEMORY_DIR="$T/memory" \
    REX_SESSION="session:old" bash "$SCRIPT" "$@" 2>&1)
}

# Run the command rex was asked to start, the way bash -c would, from /.
run_new_cmd() {
  (cd / && PATH="$bin:$PATH" MOCK_DIR="$mock" bash -c "$(cat "$mock/new_cmd")")
}

[[ -f "$SCRIPT" ]] || echo "MISSING: $SCRIPT (tests below will fail)"

# ------------------------------------------------------------------
# AC1: 3 merged lanes -> foreman proposes a session end and waits for yes

setup
out="$(run_script check)"
check "AC1: 3 merged lanes -> check proposes a session end" \
  "$(yes_if grep -qi 'propose session end' <<< "$out")"
check "AC1: proposal tells the foreman to wait for the PO's yes" \
  "$(yes_if grep -qi 'yes' <<< "$out")"
printf '[{"number":11,"title":"feat: a"},{"number":12,"title":"fix: b"}]' > "$mock/merged.json"
out="$(run_script check)"
check "AC1: 2 merged lanes -> no proposal" \
  "$(yes_if bash -c '! grep -qi "propose session end" <<< "$1"' _ "$out")"
teardown

# ------------------------------------------------------------------
# AC2: an active lane blocks the session kill and is named

setup
mkdir -p "$repo/.worktrees/50-foo"
out="$(run_script run)"; rc=$?
check "AC2: open worktree -> run refuses (non-zero exit)" "$(yes_if test "$rc" -ne 0)"
check "AC2: open worktree -> names the blocking lane" "$(yes_if grep -q '50-foo' <<< "$out")"
check "AC2: open worktree -> no session spawned or killed" "$(yes_if test ! -s "$mock/rex.log")"
check "AC2: open worktree -> no handover comment posted" "$(yes_if test ! -f "$mock/comment_body")"
out="$(run_script check)"
check "AC2: open worktree -> check reports the block instead of proposing" \
  "$(yes_if grep -q '50-foo' <<< "$out")"
touch "$repo/.worktrees/50-foo/.lane-signal"
out="$(run_script run)"
check "AC2: unread .lane-signal -> named in the refusal" "$(yes_if grep -q '.lane-signal' <<< "$out")"
teardown

# ------------------------------------------------------------------
# AC3: handover comment with all sections, 25 lines or fewer

setup
run_script run --questions "Ship dark mode first?" > /dev/null
body="$(cat "$mock/comment_body" 2>/dev/null)"
check "AC3: comment posted on the handover issue" "$(yes_if test -n "$body")"
check "AC3: lists merged PRs" "$(yes_if grep -q '#11' <<< "$body")"
check "AC3: lists open PRs" "$(yes_if grep -q '#20' <<< "$body")"
check "AC3: next issues in priority order (P1 #33 before P2 #32)" \
  "$(yes_if bash -c '[[ "$1" == *"#33"*"#32"* ]]' _ "$body")"
check "AC3: next issues never share an area:* label (#34 skipped)" \
  "$(yes_if bash -c '! grep -q "#34" <<< "$1"' _ "$body")"
check "AC3: next issues capped at 3" \
  "$(yes_if bash -c '[[ "$1" == *"#31"* ]]' _ "$body")"
check "AC3: includes unanswered PO questions" "$(yes_if grep -q 'Ship dark mode first?' <<< "$body")"
check "AC3: includes learnings written" "$(yes_if grep -q '41.md' <<< "$body")"
check "AC3: includes TRAPs written" "$(yes_if grep -q 'trap_new-thing' <<< "$body")"
check "AC3: includes retro issues filed" "$(yes_if grep -q '#40' <<< "$body")"
check "AC3: 25 lines or fewer" "$(yes_if test "$(printf '%s\n' "$body" | wc -l)" -le 25)"
teardown

# ------------------------------------------------------------------
# AC4: new Rex session foreman-<date>-<n> in the main checkout running claude

setup
run_script run > /dev/null
check "AC4: rex new starts in the main checkout" \
  "$(yes_if grep -q "^new .*--cwd $(cd "$repo" && pwd -P)" "$mock/rex.log")"
check "AC4: session renamed to foreman-<date>-<n> (next free n)" \
  "$(yes_if grep -q "^session rename session:new1 foreman-$TODAY-2$" "$mock/rex.log")"
run_new_cmd
check "AC4: claude runs in the main checkout" \
  "$(yes_if test "$(cat "$mock/claude_cwd" 2>/dev/null)" == "$(cd "$repo" && pwd -P)")"
check "AC4: handover is claude's first message" \
  "$(yes_if grep -q '#11' "$mock/claude_arg")"
teardown

# ------------------------------------------------------------------
# AC5: failed spawn keeps the old session and names the failed step

setup
out="$(MOCK_REX_FAIL=new run_script run)"; rc=$?
check "AC5: spawn failure -> non-zero exit" "$(yes_if test "$rc" -ne 0)"
check "AC5: spawn failure -> error names the spawn step" "$(yes_if grep -qi 'spawn' <<< "$out")"
check "AC5: spawn failure -> old session not killed" "$(yes_if bash -c '! grep -q "^session kill" "$1"' _ "$mock/rex.log")"
: > "$mock/rex.log"
out="$(MOCK_REX_FAIL=inspect run_script run)"
check "AC5: verify failure -> error names the verify step" "$(yes_if grep -qi 'verify' <<< "$out")"
check "AC5: verify failure -> old session not killed" "$(yes_if bash -c '! grep -q "^session kill" "$1"' _ "$mock/rex.log")"
: > "$mock/rex.log"
out="$(MOCK_REX_FAIL=rename run_script run)"
check "AC5: rename failure -> error names the rename step" "$(yes_if grep -qi 'rename' <<< "$out")"
check "AC5: rename failure -> old session not killed" "$(yes_if bash -c '! grep -q "^session kill" "$1"' _ "$mock/rex.log")"
teardown

# ------------------------------------------------------------------
# AC6: old session killed last, after verify and rename

setup
run_script run > /dev/null
order="$(cut -d' ' -f1-2 "$mock/rex.log" | grep -E '^(new|session (inspect|rename|kill))' | tr '\n' ',')"
check "AC6: order is new, inspect, rename, kill" \
  "$(yes_if bash -c '[[ "$1" == new*,"session inspect","session rename","session kill", ]]' _ "$order")"
check "AC6: kill targets the old session and is the last rex call" \
  "$(yes_if test "$(tail -1 "$mock/rex.log")" == "session kill session:old")"
teardown

# ------------------------------------------------------------------
# AC7: hostile git/issue values can't inject commands or keypresses

setup
cat > "$mock/ready.json" <<EOF
[{"number":33,"title":"\$(touch $T/PWNED1) \`touch $T/PWNED2\` '; touch $T/PWNED3; ' ${ESC}[31m\nline2","labels":[{"name":"P1"},{"name":"area:auth"}]}]
EOF
printf '[{"number":20,"title":"x","headRefName":"feat/20-x;touch %s/PWNED4"}]' "$T" > "$mock/open.json"
# jq turns the literal \n above into a real newline; ESC needs JSON escaping.
sed -i '' "s/${ESC}/\\\\u001b/" "$mock/ready.json" 2>/dev/null || sed -i "s/${ESC}/\\\\u001b/" "$mock/ready.json"
run_script run > /dev/null
run_new_cmd
check "AC7: no command substitution or quote break-out executed" \
  "$(yes_if bash -c '! ls "$1"/PWNED* >/dev/null 2>&1' _ "$T")"
check "AC7: escape sequences stripped from the comment" \
  "$(yes_if bash -c 'test -s "$2" && ! grep -q "$1" "$2"' _ "$ESC" "$mock/comment_body")"
check "AC7: escape sequences stripped from claude's first message" \
  "$(yes_if bash -c 'test -s "$2" && ! grep -q "$1" "$2"' _ "$ESC" "$mock/claude_arg")"
check "AC7: newline in an issue title can't add a line" \
  "$(yes_if bash -c 'test -s "$1" && ! grep -q "^line2" "$1"' _ "$mock/comment_body")"
check "AC7: hostile title still present, as inert text" \
  "$(yes_if grep -q 'touch' "$mock/claude_arg")"
teardown

# ------------------------------------------------------------------
# AC8: foreman.md documents session end

check "AC8: foreman.md has a Session end section" "$(yes_if grep -q '^## Session end' "$FOREMAN_MD")"
section="$(sed -n '/^## Session end/,/^## /p' "$FOREMAN_MD")"
check "AC8: section names the trigger (3rd lane merged)" "$(yes_if grep -qi '3rd lane merged' <<< "$section")"
check "AC8: section has a checklist" "$(yes_if grep -q '^- \[ \]' <<< "$section")"
check "AC8: section names the script path" "$(yes_if grep -q 'scripts/foreman-handover' <<< "$section")"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" == "0" ]] || exit 1

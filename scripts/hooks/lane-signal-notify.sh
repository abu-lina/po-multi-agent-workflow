#!/usr/bin/env bash
# Stop hook: deliver .lane-signal to the foreman's Rex pane and delete it.
# Non-blocking — always exits 0.

cat > /dev/null  # consume stdin

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ "$root" == */.worktrees/* ]] || exit 0
[[ -f "$root/.env.lane" ]] || exit 0

_get_env() { grep -m1 "^${1}=" "$2" 2>/dev/null | cut -d= -f2-; }
ISSUE="$(_get_env ISSUE "$root/.env.lane")"
REX_SESSION_ID="$(_get_env REX_SESSION_ID "$root/.env.lane")"
FOREMAN_BLOCK="$(_get_env FOREMAN_BLOCK "$root/.env.lane")"

[[ "$ISSUE" =~ ^[0-9]+$ ]] || exit 0
[[ "$REX_SESSION_ID" =~ ^[a-zA-Z0-9_:-]+$ ]] || exit 0
[[ "$FOREMAN_BLOCK" =~ ^[a-zA-Z0-9_:-]+$ ]] || exit 0

SIGNAL_VOCAB_RE='^(handoff|blocked): '

if [[ ! -f "$root/.lane-signal" ]]; then
  # One fallback per lane, and none after a real signal, so a dead lane still gets reported.
  [[ -f "$root/.lane-signal-fallback" || -f "$root/.lane-signal-sent" ]] && exit 0
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -dc '[:print:]')"
  last_commit="$(git -C "$root" log -1 --format='%s' 2>/dev/null | tr -dc '[:print:]')"
  msg="Lane #$ISSUE: turn ended, no signal yet (may be waiting on reviewers), branch: $branch, last commit: $last_commit"
  rex send -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" "$msg" 2>/dev/null &&
    rex send-key -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" enter 2>/dev/null
  printf 'no-signal fallback delivered\n' > "$root/.lane-signal-fallback" 2>/dev/null
  exit 0
fi

signal="$(tr -dc '[:print:]' < "$root/.lane-signal")"
[[ "$signal" =~ $SIGNAL_VOCAB_RE ]] || exit 0

# On handoff, append a Final Summary section to .lane-notes.md for the foreman.
if [[ "$signal" == handoff:* && -f "$root/.lane-notes.md" ]]; then
  {
    printf '\n## Final Summary\n\n'
    printf -- '- **Outcome:** %s\n' "$signal"
  } >> "$root/.lane-notes.md" 2>/dev/null
fi

rex send -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" "Lane #$ISSUE: $signal" 2>/dev/null &&
  rex send-key -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" enter 2>/dev/null
# Consume the signal regardless of rex success; if mv fails, rm so it never redelivers.
mv "$root/.lane-signal" "$root/.lane-signal-sent" 2>/dev/null || rm -f "$root/.lane-signal"

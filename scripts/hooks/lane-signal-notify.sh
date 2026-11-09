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
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -dc '[:print:]')"
  last_commit="$(git -C "$root" log -1 --format='%s' 2>/dev/null | tr -dc '[:print:]')"
  msg="Lane #$ISSUE: session ended without a signal, branch: $branch, last commit: $last_commit"
  rex send -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" "$msg" 2>/dev/null &&
    rex send-key -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" enter 2>/dev/null
  exit 0
fi

signal="$(tr -dc '[:print:]' < "$root/.lane-signal")"
[[ "$signal" =~ $SIGNAL_VOCAB_RE ]] || exit 0

rex send -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" "Lane #$ISSUE: $signal" 2>/dev/null &&
  { rex send-key -s "$REX_SESSION_ID" -b "$FOREMAN_BLOCK" enter 2>/dev/null; rm -f "$root/.lane-signal"; }

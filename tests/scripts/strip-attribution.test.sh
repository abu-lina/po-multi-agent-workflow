#!/usr/bin/env bash
# Tests for .claude/hooks/strip-attribution.sh
# AC1: strips Co-Authored-By from git commit -m
# AC2: strips 🤖 Generated with from gh pr create/edit --body
# AC3: fail-open when jq absent or input unparseable
set -euo pipefail

HOOK=".claude/hooks/strip-attribution.sh"

if [[ ! -f "$HOOK" ]]; then
  echo "FAIL: $HOOK does not exist"
  exit 1
fi

pass=0
fail_count=0

ok()    { echo "  PASS: $1"; (( pass++ )) || true; }
flunk() { echo "  FAIL: $1"; (( fail_count++ )) || true; }

echo "--- strip-attribution tests ---"

# AC1: Co-Authored-By line stripped from git commit -m (\\n escape form Claude Code emits)
input=$(jq -n --arg cmd 'git commit -m "fix: do the thing\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"' \
  '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
out=$(printf '%s' "$input" | bash "$HOOK" 2>&1)
if printf '%s' "$out" | grep -q '"updatedInput"'; then
  updated_cmd=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command')
  if printf '%s' "$updated_cmd" | grep -qi 'Co-Authored-By'; then
    flunk "AC1: Co-Authored-By still present in rewritten commit command"
  else
    ok "AC1: Co-Authored-By stripped from git commit -m"
  fi
else
  flunk "AC1: expected updatedInput for commit with Co-Authored-By, got: $out"
fi

# AC1b: commit without Co-Authored-By passes through unchanged (no rewrite)
clean_msg='fix: clean commit message'
input_clean=$(jq -n --arg cmd "git commit -m \"$clean_msg\"" \
  '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
out_clean=$(printf '%s' "$input_clean" | bash "$HOOK" 2>&1)
if printf '%s' "$out_clean" | grep -q '"updatedInput"'; then
  flunk "AC1b: clean commit got unexpected rewrite: $out_clean"
else
  ok "AC1b: clean commit passes through unchanged"
fi

# AC2: 🤖 Generated with line stripped from gh pr create --body
pr_body=$(printf 'Closes #34.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')
pr_cmd=$(printf 'gh pr create --draft --title "feat: strip" --body "%s"' "$pr_body")
input_pr=$(jq -n --arg cmd "$pr_cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
out_pr=$(printf '%s' "$input_pr" | bash "$HOOK" 2>&1)
if printf '%s' "$out_pr" | grep -q '"updatedInput"'; then
  updated_pr=$(printf '%s' "$out_pr" | jq -r '.hookSpecificOutput.updatedInput.command')
  if printf '%s' "$updated_pr" | grep -q '🤖 Generated with'; then
    flunk "AC2: 🤖 Generated with still present in rewritten gh pr create command"
  else
    ok "AC2: 🤖 Generated with stripped from gh pr create --body"
  fi
else
  flunk "AC2: expected updatedInput for gh pr create with attribution, got: $out_pr"
fi

# AC2b: gh pr edit --body also stripped
pr_body_edit=$(printf 'Some description.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')
pr_edit_cmd=$(printf 'gh pr edit --body "%s"' "$pr_body_edit")
input_pr_edit=$(jq -n --arg cmd "$pr_edit_cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
out_pr_edit=$(printf '%s' "$input_pr_edit" | bash "$HOOK" 2>&1)
if printf '%s' "$out_pr_edit" | grep -q '"updatedInput"'; then
  updated_edit=$(printf '%s' "$out_pr_edit" | jq -r '.hookSpecificOutput.updatedInput.command')
  if printf '%s' "$updated_edit" | grep -q '🤖 Generated with'; then
    flunk "AC2b: 🤖 Generated with still present in rewritten gh pr edit command"
  else
    ok "AC2b: 🤖 Generated with stripped from gh pr edit --body"
  fi
else
  flunk "AC2b: expected updatedInput for gh pr edit with attribution, got: $out_pr_edit"
fi

# AC3: fail-open when input is unparseable (not valid JSON)
out_bad=$(printf 'not valid json at all' | bash "$HOOK" 2>&1)
exit_code=$?
if [[ "$exit_code" -ne 0 ]]; then
  flunk "AC3: hook must exit 0 on unparseable input (fail open), exited $exit_code"
elif printf '%s' "$out_bad" | grep -q '"deny"'; then
  flunk "AC3: hook must not deny on unparseable input"
else
  ok "AC3: fail-open on unparseable input (exits 0, no deny)"
fi

# AC3b: fail-open when jq is absent (simulate by temporarily shadowing it)
tmpdir=$(mktemp -d)
printf '#!/bin/sh\nexit 1\n' > "$tmpdir/jq"
chmod +x "$tmpdir/jq"
out_nojq=$(PATH="$tmpdir:$PATH" printf '{}' | bash "$HOOK" 2>&1) || true
rm -rf "$tmpdir"
if printf '%s' "$out_nojq" | grep -q '"deny"'; then
  flunk "AC3b: hook must not deny when jq absent"
else
  ok "AC3b: fail-open when jq absent"
fi

# AC1c: Co-Authored-By on a real newline (not \n escape) also stripped
# This covers the form produced when Claude Code uses heredoc-style serialisation.
real_newline_cmd=$(printf 'git commit -m "fix: thing\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"')
input_rn=$(jq -n --arg cmd "$real_newline_cmd" '{"tool_name":"Bash","tool_input":{"command":$cmd}}')
out_rn=$(printf '%s' "$input_rn" | bash "$HOOK" 2>&1)
if printf '%s' "$out_rn" | grep -q '"updatedInput"'; then
  updated_rn=$(printf '%s' "$out_rn" | jq -r '.hookSpecificOutput.updatedInput.command')
  if printf '%s' "$updated_rn" | grep -qi 'Co-Authored-By'; then
    flunk "AC1c: Co-Authored-By still present after stripping real-newline form"
  else
    ok "AC1c: Co-Authored-By stripped when embedded as real newline"
  fi
else
  flunk "AC1c: expected updatedInput for commit with real-newline Co-Authored-By, got: $out_rn"
fi

echo ""
echo "Results: $pass passed, $fail_count failed"
[[ "$fail_count" -eq 0 ]]

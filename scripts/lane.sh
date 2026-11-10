# shellcheck shell=bash
# Lane helpers for the foreman + crew workflow (docs/agents/foreman.md).
# Source from ~/.zshrc:  source ~/your-project/scripts/lane.sh
#
#   lane <issue> [slug] [claude|copilot|devin|opencode] [model|effort]
#   lane_done <issue> [--force]           remove a merged lane
#   lane_status                           one line per lane: branch + PR state + CI
#
# Sourced by zsh, this file defines only thin wrappers that run scripts/lane,
# so all logic runs under bash. scripts/lane sources it under bash for the
# real functions below.

if [ -n "${ZSH_VERSION:-}" ]; then
  # The zsh-only expansion lives in eval so bash and shellcheck never parse it.
  _lane_wrapper_bin="$(eval 'print -r -- ${${(%):-%x}:A:h}')/lane"
  function lane { "$_lane_wrapper_bin" start "$@"; }
  function lane_done { "$_lane_wrapper_bin" 'done' "$@"; }
  function lane_status { "$_lane_wrapper_bin" status "$@"; }
  return 0
fi

_lane_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

_lane_dir() {
  local root="$1" issue="$2" lane_dir
  for lane_dir in "$root/.worktrees/$issue-"*/; do
    [[ -d "$lane_dir" ]] || continue
    printf '%s\n' "${lane_dir%/}"
    return 0
  done
}

_lane_port() {
  echo $((3000 + $1 % 1000))
}

_lane_base() {
  git fetch -q origin main || return 1
  printf '%s\n' origin/main
}

_lane_check_main() {
  local unpushed behind git_dir
  git_dir="$(git rev-parse --git-dir)" || return 1
  if [[ -f "$git_dir/REBASE_HEAD" || -f "$git_dir/MERGE_HEAD" ]]; then
    printf 'main checkout is in mid-rebase/merge state; resolve it before starting a lane\n' >&2
    return 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    printf 'main checkout has uncommitted changes; commit or stash before starting a lane\n' >&2
    return 1
  fi
  unpushed="$(git log --oneline origin/main..main)" || return 1
  behind="$(git log --oneline main..origin/main)" || return 1
  if [[ -n "$unpushed" && -n "$behind" ]]; then
    printf 'local main and origin/main have diverged; resolve manually before starting a lane\n' >&2
    return 1
  fi
  if [[ -n "$behind" ]]; then
    local n
    n="$(printf '%s\n' "$behind" | wc -l | tr -d ' ')"
    if ! git pull --rebase origin main >/dev/null; then
      printf 'git pull --rebase origin main failed; resolve manually\n' >&2
      return 1
    fi
    printf 'pulled %s commit(s) from origin/main\n' "$n"
    return 0
  fi
  [[ -z "$unpushed" ]] && return 0
  printf 'local main is ahead of origin/main; push these commits before starting a lane:\n%s\n' "$unpushed" >&2
  return 1
}

# A relative core.hooksPath (husky: .husky/_) resolves against each worktree root, and the
# generated hooks directory is git-ignored, so a new worktree needs its own copy.
_lane_setup_hooks() {
  local root="$1" dir="$2" hooks
  hooks="$(git -C "$root" config --get core.hooksPath)" || return 0
  [[ -n "$hooks" && "$hooks" != /* && -d "$root/$hooks" ]] || return 0
  case "/$hooks/" in
    */./* | */../*)
      echo "skipping git hooks copy: core.hooksPath '$hooks' must not contain . or .. segments" >&2
      return 0
      ;;
  esac
  [[ -e "$dir/$hooks" ]] && return 0
  mkdir -p "$dir/$(dirname -- "$hooks")" || return 1
  cp -R "$root/$hooks" "$dir/$hooks"
}

_lane_type() {
  case "$(gh issue view "$1" --json labels --jq '[.labels[].name|select(startswith("type:"))][0]')" in
    type:feature) echo feat ;;
    type:bugfix | type:hotfix | type:security) echo fix ;;
    type:refactor) echo refactor ;;
    *) echo chore ;;
  esac
}

_lane_prompt() {
  local issue="$1"
  printf 'You are a lane. Read AGENTS.md, then docs/agents/lane.md, then work on GitHub issue #%s.

AUTO-SKILLS — load these before writing any code, no exceptions:
- mattpocock-skills:tdd — every feature lane, before the first test
- supabase + supabase-postgres-best-practices — any DB, schema, or RLS work
- self-improving-agent — after any command failure or owner correction

REVIEW-SKILLS — run these on every PR before marking it ready:
- impeccable — code quality pass
- mattpocock-skills:code-review — standards + spec
- security-audit — PRs touching auth, payments, or user data

FALLBACK — if no skill above clearly covers a step: /using-agent-skills, then stop and ask the owner.

Start with step 0 of lane.md and stop at any "stop and ask" condition. Before stopping, comment on the issue so the foreman is notified.' "$issue"
}

# Build the agent CLI command string for use inside a rex pane.
# Side effect for devin: writes a temp sandbox config.
_lane_agent_cmd() {
  local agent="$1" model="${2:-}" dir="$3"
  local model_flag=""

  case "$agent" in
    claude)
      [[ -n "$model" ]] && model_flag=" --model $(printf '%q' "$model")"
      printf 'cd %q && claude%s' "$dir" "$model_flag"
      ;;
    copilot)
      local -a flags=(
        --allow-tool=write
        '--allow-tool=shell(npm:*)'
        '--allow-tool=shell(npx:*)'
        '--allow-tool=shell(git:*)'
        '--allow-tool=shell(gh issue:*)'
        '--allow-tool=shell(gh pr create)'
        '--allow-tool=shell(gh pr checks)'
        '--allow-tool=shell(pwd:*)'
        '--allow-tool=shell(ls:*)'
        '--allow-tool=shell(cat:*)'
        '--allow-tool=shell(head:*)'
        '--allow-tool=shell(tail:*)'
        '--allow-tool=shell(wc:*)'
        '--allow-tool=shell(command -v:*)'
        '--allow-tool=shell(which:*)'
        '--allow-tool=shell(diff:*)'
        '--allow-tool=shell(grep:*)'
        '--allow-tool=shell(gh pr view:*)'
        '--allow-tool=shell(gh pr diff:*)'
        '--allow-tool=shell(gh run view:*)'
        '--deny-tool=shell(git merge)'
        '--deny-tool=shell(git rebase)'
        '--deny-tool=shell(pass-cli:*)'
        '--deny-tool=write(.env.local)'
        '--deny-tool=shell(gh pr merge)'
      )
      if [[ -n "$model" ]]; then
        case "$model" in
          none|minimal|low|medium|high|xhigh|max) flags+=(--reasoning-effort "$model") ;;
          *) flags+=(--model "$model") ;;
        esac
      fi
      local quoted_flags
      quoted_flags="$(printf '%q ' "${flags[@]}")"
      printf 'cd %q && copilot %s' "$dir" "$quoted_flags"
      ;;
    devin)
      local root git_common_dir config_dir config_file
      root="$(git rev-parse --show-toplevel)" || return 1
      git_common_dir="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir)" ||
        { echo "could not resolve the repository's git common directory" >&2; return 1; }
      config_dir="$(mktemp -d "${TMPDIR:-/tmp}/lane-config.XXXXXX")" || return 1
      config_file="$config_dir/lane.json"
      (umask 077 && jq -n --arg git_common_dir "$git_common_dir" '{
        "permissions": {
          "allow": ["Write(\($git_common_dir))"]
        },
        "sandbox": {
          "excluded": {
            "allow": [
              "Exec(gh issue comment)",
              "Exec(gh pr create --draft)",
              "Exec(gh pr checks)",
              "Exec(gh pr view)"
            ]
          }
        }
      }' > "$config_file") ||
        { echo "could not write Devin lane sandbox config" >&2; return 1; }
      local -a flags=(--permission-mode accept-edits --sandbox --config "$config_file")
      [[ -n "$model" ]] && flags+=(--model "$model")
      local quoted_flags
      quoted_flags="$(printf '%q ' "${flags[@]}")"
      printf 'cd %q && devin %s' "$dir" "$quoted_flags"
      ;;
    opencode)
      # shortcut: opencode CLI flags TBD; update once opencode CLI stabilises
      [[ -n "$model" ]] && model_flag=" --model $(printf '%q' "$model")"
      printf 'cd %q && opencode%s' "$dir" "$model_flag"
      ;;
  esac
}

# Open a rex pane for the given agent, write LANE_BLOCK to env_file,
# poll until the shell prompt appears, then send the brief.
_lane_rex_open() {
  local agent="$1" model="$2" dir="$3" env_file="$4" issue="$5"
  local agent_cmd block_id brief

  agent_cmd="$(_lane_agent_cmd "$agent" "$model" "$dir")" || return 1

  local split_json
  split_json="$(rex split -s "$REX_SESSION" --split=right --json -- bash -c "$agent_cmd")" ||
    { printf 'rex split failed\n' >&2; return 1; }
  block_id="$(printf '%s\n' "$split_json" | jq -r '.block_ids[0]')" ||
    { printf 'could not parse block_ids from rex split output: %s\n' "$split_json" >&2; return 1; }
  [[ -n "$block_id" && "$block_id" != "null" ]] ||
    { printf 'rex split returned no block id; output: %s\n' "$split_json" >&2; return 1; }
  [[ "$block_id" =~ ^[a-zA-Z0-9_:-]+$ ]] ||
    { printf 'rex split returned invalid block_id: %s\n' "$block_id" >&2; return 1; }

  printf 'LANE_BLOCK=%s\n' "$block_id" >> "$env_file" ||
    { printf 'could not write LANE_BLOCK to %s\n' "$env_file" >&2; return 1; }

  # Poll until the shell prompt appears (30 s max, 1 s interval).
  local i=0
  while (( i < 30 )); do
    local capture
    capture="$(rex capture -s "$REX_SESSION" -b "$block_id" 2>/dev/null)" || true
    if printf '%s\n' "$capture" | grep -q '❯'; then
      break
    fi
    sleep 1
    i=$(( i + 1 ))
  done
  (( i < 30 )) || { printf 'timed out waiting for prompt in block %s\n' "$block_id" >&2; return 1; }

  # Send the brief via stdin so multi-line text is delivered as a single paste,
  # not as individual keystrokes (newlines would fire Enter prematurely).
  _lane_prompt "$issue" | rex send -s "$REX_SESSION" -b "$block_id" || return 1

  # Give the terminal time to render before checking for the expansion prompt.
  sleep 1
  local post_send
  post_send="$(rex capture -s "$REX_SESSION" -b "$block_id" 2>/dev/null)" || true
  if printf '%s\n' "$post_send" | grep -q 'paste again to expand'; then
    rex send-key -s "$REX_SESSION" -b "$block_id" enter || return 1
  fi

  rex send-key -s "$REX_SESSION" -b "$block_id" enter || return 1
  printf 'lane #%s: brief sent to block %s\n' "$issue" "$block_id"
}

lane() {
  local issue="${1:-}" slug="${2:-}" agent="${3:-claude}" model="${4:-}"
  [[ -z "$issue" ]] && { echo "usage: lane <issue> [slug] [claude|copilot|devin|opencode] [model|effort]" >&2; return 1; }
  [[ "$agent" == claude || "$agent" == copilot || "$agent" == devin || "$agent" == opencode ]] ||
    { echo "agent must be claude, copilot, devin, or opencode" >&2; return 1; }

  [[ -n "${REX_SESSION:-}" ]] || { printf 'REX_SESSION is not set; run lane from a Rex terminal\n' >&2; return 1; }
  [[ -n "${REX_BLOCK:-}" ]] || { printf 'REX_BLOCK is not set; run lane from a Rex terminal\n' >&2; return 1; }
  [[ "${REX_SESSION:-}" =~ ^[a-zA-Z0-9_:-]+$ ]] || { printf 'REX_SESSION contains invalid characters\n' >&2; return 1; }
  [[ "${REX_BLOCK:-}" =~ ^[a-zA-Z0-9_:-]+$ ]] || { printf 'REX_BLOCK contains invalid characters\n' >&2; return 1; }
  [[ "$issue" =~ ^[0-9]+$ ]] || { printf 'issue must be a positive integer\n' >&2; return 1; }

  local root dir branch port base
  root="$(_lane_root)" || { echo "not inside a git repo" >&2; return 1; }
  [[ "$root" == */.worktrees/* ]] && { echo "run lane from the main checkout, not a worktree" >&2; return 1; }
  dir="$(_lane_dir "$root" "$issue")"

  if [[ -n "$dir" ]]; then
    branch="$(git -C "$dir" branch --show-current)"
    printf 'lane #%s: %s on %s\n' "$issue" "$dir" "$branch"
    _lane_rex_open "$agent" "$model" "$dir" "$dir/.env.lane" "$issue"
    return 0
  fi

  [[ -z "$slug" ]] && { echo "new lane needs a slug: lane $issue <slug>" >&2; return 1; }
  branch="$(_lane_type "$issue")/$issue-$slug"
  dir="$root/.worktrees/$issue-$slug"
  base="$(_lane_base)" || return 1
  _lane_check_main || return 1
  if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    gh issue develop "$issue" --name "$branch" --base main >/dev/null || return 1
  fi
  git fetch -q origin "$branch" || return 1
  git worktree add "$dir" "$branch" || return 1

  # Copy .env.local so the dev server has real credentials — it is gitignored and never
  # present in a fresh worktree. Warn but don't fail if it doesn't exist in the main checkout.
  if [ -f ".env.local" ]; then
    cp ".env.local" "$dir/.env.local"
  else
    echo "warning: no .env.local in main checkout — dev server in worktree will lack credentials" >&2
  fi

  # Branch created from origin/main tracks it; point at the lane's own remote branch.
  git -C "$dir" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null ||
    { echo "could not set upstream of $branch to origin/$branch" >&2; return 1; }

  port="$(_lane_port "$issue")"
  cat >"$dir/.env.lane" <<EOF || { echo "could not write $dir/.env.lane" >&2; return 1; }
PORT=$port
PLAYWRIGHT_BASE_URL=http://127.0.0.1:$port
ISSUE=$issue
REX_SESSION_ID=${REX_SESSION}
FOREMAN_BLOCK=${REX_BLOCK}
EOF

  if [[ -d "$root/node_modules" ]]; then
    cp -c -R "$root/node_modules" "$dir/node_modules" 2>/dev/null ||
      cp -R "$root/node_modules" "$dir/node_modules" ||
      { echo "could not clone node_modules into $dir" >&2; return 1; }
  fi
  _lane_setup_hooks "$root" "$dir" || { echo "could not copy git hooks into $dir" >&2; return 1; }
  printf 'lane #%s: %s on %s, port %s\n' "$issue" "$dir" "$branch" "$port"
  _lane_rex_open "$agent" "$model" "$dir" "$dir/.env.lane" "$issue"
}

lane_register() {
  local issue="${1:-}" block_id="${2:-}"
  [[ -z "$issue" || -z "$block_id" ]] && { echo "usage: lane_register <issue> <block_id>" >&2; return 1; }

  local root dir
  root="$(_lane_root)" || return 1
  [[ "$root" == */.worktrees/* ]] && { echo "run lane register from the main checkout" >&2; return 1; }
  dir="$(_lane_dir "$root" "$issue")"
  [[ -n "$dir" ]] || { echo "no worktree for #$issue" >&2; return 1; }
  [[ "$block_id" =~ ^[a-zA-Z0-9_:-]+$ ]] || { echo "invalid block_id: must contain only alphanumeric, -, :, _" >&2; return 1; }
  printf 'LANE_BLOCK=%s\n' "$block_id" >> "$dir/.env.lane"
}

lane_done() {
  local issue="${1:-}" force="${2:-}"
  [[ -z "$issue" ]] && { echo "usage: lane_done <issue> [--force]" >&2; return 1; }

  local root dir branch port cleanup_failed=0
  root="$(_lane_root)" || return 1
  [[ "$root" == */.worktrees/* ]] && { echo "run lane_done from the main checkout" >&2; return 1; }
  dir="$(_lane_dir "$root" "$issue")"
  [[ -n "$dir" ]] || { echo "no worktree for #$issue"; return 0; }
  branch="$(git -C "$dir" branch --show-current)"
  [[ -z "$branch" ]] && { printf 'worktree %s is detached; resolve manually\n' "$dir" >&2; return 1; }
  port="$(_lane_port "$issue")"

  local lane_block="" rex_session_id=""
  if [[ -f "$dir/.env.lane" ]]; then
    lane_block="$(grep -m1 '^LANE_BLOCK=' "$dir/.env.lane" 2>/dev/null | cut -d= -f2-)" || true
    rex_session_id="$(grep -m1 '^REX_SESSION_ID=' "$dir/.env.lane" 2>/dev/null | cut -d= -f2-)" || true
  fi

  if [[ "$force" != "--force" ]]; then
    local state
    state="$(GH_HOST="" gh pr view "$branch" --json state --jq .state 2>/dev/null)"
    [[ "$state" != "MERGED" ]] && { echo "PR for $branch is '${state:-missing}', not MERGED. Use --force only after the owner agrees." >&2; return 1; }
    # .worktrees/ is excluded via .gitignore; only .env.lane needs explicit grep exclusion
    [[ -n "$(git -C "$dir" status --porcelain | grep -Ev '^.. \.env\.lane$')" ]] && { echo "$dir has uncommitted changes" >&2; return 1; }
    if git -C "$root" rev-parse --verify -q "origin/$branch" >/dev/null; then
      [[ -n "$(git -C "$root" log "origin/$branch..$branch" --oneline)" ]] && { echo "$dir has unpushed commits" >&2; return 1; }
    fi
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && { echo "a process still listens on :$port" >&2; return 1; }
  fi

  # Close the lane pane before removing the worktree so .env.lane is still readable on retry.
  if [[ -n "$lane_block" ]]; then
    rex block close -s "$rex_session_id" "$lane_block" 2>/dev/null || true
  fi

  # Git's force option removes ignored build output such as .next and node_modules.
  if [[ -d "$dir" ]] && ! git worktree remove --force "$dir"; then
    echo "could not remove git worktree $dir" >&2
    cleanup_failed=1
  fi
  if ! git worktree prune; then
    echo "could not prune git worktrees" >&2
    cleanup_failed=1
  fi
  if ! git branch -D "$branch"; then
    echo "could not delete branch $branch" >&2
    cleanup_failed=1
  fi
  [[ "$cleanup_failed" == 0 ]] || return 1
  echo "lane #$issue removed"
}

lane_status() {
  local root worktrees worktree branch pr_info pr_state ci_status
  root="$(_lane_root)" || { echo "not inside a git repo" >&2; return 1; }

  printf 'WORKTREE\tBRANCH\tPR\tCI\n'
  worktrees="$(git worktree list --porcelain 2>/dev/null)" || return 1

  worktree="" branch=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      worktree\ *)
        worktree="${line#worktree }"
        branch=""
        ;;
      branch\ refs/heads/*)
        branch="${line#branch refs/heads/}"
        ;;
      "")
        if [[ "$worktree" == */.worktrees/* ]]; then
          if [[ -z "$branch" ]]; then
            printf '%s\t%s\t%s\t%s\n' "$worktree" "detached" "-" "-"
          else
            pr_info="$(gh pr view "$branch" --json state,statusCheckRollup 2>/dev/null)"
            if [[ -n "$pr_info" ]]; then
              pr_state="$(printf '%s\n' "$pr_info" | jq -r '.state // "none"')"
              ci_status="$(printf '%s\n' "$pr_info" | jq -r '
                [.statusCheckRollup[]? | .conclusion // .status] |
                if length == 0 then "none"
                elif all(. == "SUCCESS") then "pass"
                elif any(. == "FAILURE") then "fail"
                else "pending" end')"
            else
              pr_state="none"
              ci_status="-"
            fi
            printf '%s\t%s\t%s\t%s\n' "$worktree" "$branch" "$pr_state" "$ci_status"
          fi
        fi
        worktree="" branch=""
        ;;
    esac
  done <<<"$worktrees"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  command="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$command" in
    status) lane_status "$@" ;;
    start)  lane "$@" ;;
    done)   lane_done "$@" ;;
    register) lane_register "$@" ;;
    *)
      printf 'usage: scripts/lane.sh {status|start <issue> <slug> [agent] [model]|register <issue> <block_id>|done <issue> [--force]}\n' >&2
      exit 2
      ;;
  esac
fi

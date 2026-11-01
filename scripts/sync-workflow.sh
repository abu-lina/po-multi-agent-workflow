#!/usr/bin/env bash
# Sync the PO multi-agent workflow from the template repo into this project.
#
# Usage:
#   bash scripts/sync-workflow.sh           # update synced files only
#   bash scripts/sync-workflow.sh --init    # first-time setup: also copy init-only files
#
# SYNCED files are overwritten on every run (process improvements propagate):
#   docs/agents/lane.md
#   docs/agents/foreman.md
#   docs/agents/pr-loop.md
#   scripts/lane
#   scripts/lane.sh
#   scripts/review-bundle
#   .devin/foreman.json
#
# INIT-ONLY files are copied only on --init (never overwritten after that):
#   docs/agents/review.md
#   docs/agents/setup-decisions.md
#   AGENTS.md
#   scripts/verify
#
# After running --init, edit the init-only files to add project-specific content.

set -euo pipefail

TEMPLATE_REPO="abu-lina/po-multi-agent-workflow"
TEMPLATE_BRANCH="main"

SYNC_FILES=(
  docs/agents/lane.md
  docs/agents/foreman.md
  docs/agents/pr-loop.md
  scripts/lane
  scripts/lane.sh
  scripts/review-bundle
  .devin/foreman.json
)

INIT_ONLY_FILES=(
  docs/agents/review.md
  docs/agents/setup-decisions.md
  AGENTS.md
  scripts/verify
)

INIT=0
for arg in "$@"; do
  [[ "$arg" == "--init" ]] && INIT=1
done

root="$(git rev-parse --show-toplevel)" || { echo "not inside a git repo" >&2; exit 1; }
[[ "$root" == */.worktrees/* ]] && { echo "run sync-workflow.sh from the main checkout, not a worktree" >&2; exit 1; }

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/po-workflow-sync.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

echo "Cloning template from $TEMPLATE_REPO..."
git clone --depth 1 --branch "$TEMPLATE_BRANCH" \
  "https://github.com/$TEMPLATE_REPO.git" "$tmpdir/template" \
  --quiet

copy_file() {
  local src="$tmpdir/template/$1" dst="$root/$1"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  # Preserve executable bit for scripts
  case "$1" in
    scripts/*) chmod +x "$dst" ;;
  esac
  echo "  updated $1"
}

echo "Syncing workflow files..."
for f in "${SYNC_FILES[@]}"; do
  copy_file "$f"
done

if [[ "$INIT" == 1 ]]; then
  echo "Copying init-only files (first-time setup)..."
  for f in "${INIT_ONLY_FILES[@]}"; do
    if [[ -f "$root/$f" ]]; then
      echo "  skipping $f (already exists)"
    else
      copy_file "$f"
    fi
  done
fi

# Check for the mattpocock-skills plugin
if ! claude --version >/dev/null 2>&1; then
  echo ""
  echo "WARNING: 'claude' CLI not found. Install Claude Code before using the workflow."
elif ! claude plugin list 2>/dev/null | grep -q mattpocock; then
  echo ""
  echo "WARNING: mattpocock-skills plugin not found."
  echo "  Install it with: claude plugin install mattpocock-skills"
  echo "  The /grill-with-docs and /code-review skills are required for lane step 6."
fi

echo ""
echo "Done. Run 'bash scripts/sync-workflow.sh --init' on first setup to also copy AGENTS.md,"
echo "scripts/verify, and the init-only docs. Edit those files for your project."

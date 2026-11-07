# PO Foreman Workflow Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Herdr/Devin foreman workflow in `abu-lina/po-multi-agent-workflow` with a Rex + Claude Code lanes workflow suited to a solo founder-PO, then sync to downstream projects.

**Architecture:** Four files are updated in `po-multi-agent-workflow` via `gh api` (no local clone needed), then `scripts/sync-workflow.sh` pushes them to downstream projects. No product code is touched — all changes are Markdown, JSON, and Bash.

**Tech Stack:** Markdown, JSON (Claude Code settings), Bash (hook scripts), `gh` CLI.

**Spec:** `docs/superpowers/specs/2026-11-07-po-foreman-workflow-design.md` in `abu-lina/po-multi-agent-workflow`

## Global Constraints

- All `po-multi-agent-workflow` file writes use `gh api --method PUT repos/abu-lina/po-multi-agent-workflow/contents/<path>` with base64-encoded content
- When updating an existing file, always fetch its current SHA first: `gh api repos/abu-lina/po-multi-agent-workflow/contents/<path> --jq '.sha'` — omitting the SHA causes a 409 conflict error
- No `herdr`, `devin`, or `.devin/` references in any file after Task 1
- Hook scripts must exit 0 (non-blocking) and print their nudge text to stdout
- `settings.json` must pass `jq .` validation at every step
- `scripts/sync-workflow.sh` runs last — only after Tasks 1–4 are committed and verified
- Commit messages: `docs:` for Markdown, `chore:` for settings/hooks

## Review Focus

1. **gh api 409 on file update** — always fetch the current file SHA before a PUT; the update will silently fail or error without it; each task's first step fetches the SHA
2. **Hook scripts not executable** — Claude Code hooks silently skip non-executable scripts; each script gets `chmod +x` and a `bash -n` syntax check before commit
3. **`sync-workflow.sh` stomping uflow local changes** — check `/Users/NARAFIQ/Projects/uflow` git status before running sync; stash if dirty
4. **`settings.json` invalid JSON after edit** — adding hooks without validating breaks all Claude Code hooks silently; validate with `jq .` after every edit
5. **Bucket label names diverging from actual GitHub labels** — skills.md bucket table must use exact labels from `docs/agents/triage-labels.md`; Task 2 Step 1 cross-references before writing

---

### Task 1: Rewrite `docs/agents/foreman.md`

**Files:**
- Modify: `docs/agents/foreman.md` in `abu-lina/po-multi-agent-workflow` (full rewrite — 300+ lines of Herdr/Devin, nothing reusable)

**Interfaces:**
- Produces: canonical foreman behaviour reference; stage names here must match stage names in Task 2's skills.md exactly

- [ ] **Step 1: Fetch current file SHA**

  ```bash
  SHA=$(gh api repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/foreman.md --jq '.sha')
  echo $SHA
  ```
  Expected: a 40-char hex string.

- [ ] **Step 2: Write the new foreman.md content**

  Full rewrite. Use this exact section structure:
  ```
  # Foreman
  ## Role
  ## Prerequisites  (check $REX_SESSION; if unset, fall back to serial and tell user)
  ## Stage 0 — Idea detection
  ## Stage 1 — Issue Maturation
  ## Stage 2 — Lane start
  ## Stage 3 — Active implementation
  ## Stage 4 — Checkpoint
  ## Stage 5 — Code review
  ## Stage 6 — Merge and rebase
  ## Stage 7 — Learning capture
  ## Parallel lanes  (up to 3; no shared area:* labels; first-green-merges-first)
  ## Blocked lane protocol
  ```

  Every Rex command uses `$REX_SESSION`. Every lane command uses `scripts/lane start <issue> <slug>`. Content for each section comes verbatim from the spec's matching stage. No `herdr`, `devin`, or `.devin/` anywhere.

- [ ] **Step 3: Push via gh api using the SHA from Step 1**

  ```bash
  ENCODED=$(printf '%s' "$NEW_CONTENT" | base64)
  gh api --method PUT repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/foreman.md \
    --field message="docs: rewrite foreman.md — replace Herdr/Devin with Rex + Claude Code lanes" \
    --field content="$ENCODED" \
    --field sha="$SHA" \
    --jq '.content.html_url'
  ```

- [ ] **Step 4: Verify no legacy references remain**

  ```bash
  gh api repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/foreman.md \
    --jq '.content' | base64 -d | grep -icE 'herdr|devin|\.devin'
  ```
  Expected: 0

---

### Task 2: Update `docs/agents/skills.md`

**Files:**
- Modify: `docs/agents/skills.md` in `abu-lina/po-multi-agent-workflow`

**Interfaces:**
- Consumes: stage names from Task 1 (must match exactly)
- Produces: stage-to-skill table + bucket routing table used by foreman and lane agents

- [ ] **Step 1: Cross-reference bucket labels against triage-labels.md**

  ```bash
  gh api repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/triage-labels.md \
    --jq '.content' | base64 -d | grep 'area:'
  ```
  Confirm all 15 `area:*` labels match the spec's bucket table before writing. The spec uses: `area:ui`, `area:map`, `area:dashboard`, `area:auth`, `area:search`, `area:db`, `area:imports`, `area:ci`, `area:infra`, `area:pwa`, `area:i18n`, `area:deps`, `area:docs`, `area:providers`, `area:admin`.

- [ ] **Step 2: Fetch current file SHA**

  ```bash
  SHA=$(gh api repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/skills.md --jq '.sha')
  ```

- [ ] **Step 3: Update skills.md**

  Fetch and decode the current content, then add/update these sections (keep all existing content not listed here):

  **Update — Idea shaping stage:**
  - Remove `/pm-brief` reference
  - Add: auto-trigger `grill-with-docs` on intent detection
  - Add: `superpowers:brainstorming` for approach exploration
  - Add smart routing: `pm-execution:job-stories` (user-facing) / `pm-execution:write-stories` (infra)
  - Add conditional: P0/P1/`area:auth`/`area:data` → also run `pm-execution:pre-mortem` + `pm-execution:test-scenarios`

  **Update — Lane start stage:**
  - Add: `mattpocock-skills:writing-for-agents` (Lane Brief, runs before rex split)
  - Add: `superpowers:writing-plans` (conditional: complex/schema/P0/P1 issues)

  **New section — Checkpoint / Handoff stage** (between lane-running and review):
  - `handoff` skill (lane fires when done; triggers foreman)
  - Rex dev-server pane (foreman opens on handoff receipt)

  **Update — Code review stage:**
  - Add: `pm-ai-shipping:intended-vs-implemented` (every PR, runs first)
  - Add: `ui-taste` (UI/Frontend lanes only, alongside `impeccable`)
  - Keep existing: `impeccable`, `mattpocock-skills:code-review`, `security-audit`

  **New section — Skill bucket routing:**
  Three-bucket table with exact `area:*` label mapping (from spec §Skill bucket routing). Dual-bucket labels: `area:providers`, `area:admin` get both Frontend and Backend.

  **New section — Learning / TRAP flow:**
  - Code review forces a fix → foreman writes TRAP memory to `~/.claude/projects/.../memory/`
  - Lane writes `docs/ai/learnings/<issue>.md` (title + one sentence + PR number)
  - `self-improving-agent` handles per-lane `.learnings/LEARNINGS.md` + `ERRORS.md` automatically

  **New section — Skills to install (run once per project):**
  ```bash
  claude skill add handoff
  claude skill add ui-taste
  claude skill add image-to-ui
  claude skill add vercel-react-best-practices
  claude skill add vercel-composition-patterns
  claude skill add cf-cli
  ```

- [ ] **Step 4: Verify new skill names are present**

  ```bash
  gh api repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/skills.md \
    --jq '.content' | base64 -d | grep -cE 'handoff|ui-taste|job-stories|intended-vs-implemented|vercel-react'
  ```
  Expected: 5 (one match per skill listed).

- [ ] **Step 5: Commit via gh api**

  ```bash
  ENCODED=$(printf '%s' "$NEW_CONTENT" | base64)
  gh api --method PUT repos/abu-lina/po-multi-agent-workflow/contents/docs/agents/skills.md \
    --field message="docs: update skills.md — PM shaping, bucket routing, TRAP flow, new installs" \
    --field content="$ENCODED" \
    --field sha="$SHA" \
    --jq '.content.html_url'
  ```

---

### Task 3: Add hook entries to `.claude/settings.json`

**Files:**
- Modify: `.claude/settings.json` in `abu-lina/po-multi-agent-workflow`

**Interfaces:**
- Produces: hook config that references the scripts created in Task 4

- [ ] **Step 1: Fetch current settings.json and its SHA**

  ```bash
  SHA=$(gh api repos/abu-lina/po-multi-agent-workflow/contents/.claude/settings.json --jq '.sha')
  CURRENT=$(gh api repos/abu-lina/po-multi-agent-workflow/contents/.claude/settings.json \
    --jq '.content' | base64 -d)
  echo "$CURRENT" | jq .
  ```
  Read the JSON structure. The existing three hooks use a specific format — the two new hooks must use the exact same format.

- [ ] **Step 2: Add two UserPromptSubmit hook entries**

  Parse `$CURRENT` with `jq`, append two new entries to the hooks array matching the existing entry structure, targeting:
  - `"hooks[].command": "bash .claude/hooks/idea-detection-nudge.sh"`
  - `"hooks[].command": "bash .claude/hooks/review-dispatch-nudge.sh"`
  
  Both entries use `"event": "UserPromptSubmit"` with no matcher (fires on every prompt, same as the using-superpowers global hook pattern).

- [ ] **Step 3: Validate the new JSON**

  ```bash
  echo "$NEW_JSON" | jq . > /dev/null && echo "VALID" || echo "INVALID"
  ```
  Expected: `VALID`

- [ ] **Step 4: Push via gh api**

  ```bash
  ENCODED=$(printf '%s' "$NEW_JSON" | base64)
  gh api --method PUT repos/abu-lina/po-multi-agent-workflow/contents/.claude/settings.json \
    --field message="chore: add idea-detection and review-dispatch UserPromptSubmit hooks" \
    --field content="$ENCODED" \
    --field sha="$SHA" \
    --jq '.content.html_url'
  ```

---

### Task 4: Write the two hook scripts

**Files:**
- Create: `.claude/hooks/idea-detection-nudge.sh` in `abu-lina/po-multi-agent-workflow`
- Create: `.claude/hooks/review-dispatch-nudge.sh` in `abu-lina/po-multi-agent-workflow`

**Interfaces:**
- Produces: scripts that print additionalContext text to stdout when invoked by Claude Code's UserPromptSubmit hook

- [ ] **Step 1: Create `idea-detection-nudge.sh`**

  ```bash
  #!/usr/bin/env bash
  # Foreman gate: nudges foreman to detect new ideas and trigger grill-with-docs
  printf 'FOREMAN GATE — IDEA DETECTION: If the user'\''s message describes a gap, problem, desired user behaviour, or feature request, you MUST: (1) run `gh issue list --state open --search "<keywords>"` to check for duplicates, (2) if no duplicate exists, trigger grill-with-docs automatically before responding. Do not skip this gate.\n'
  ```
  
  Exit code 0 (non-blocking).

- [ ] **Step 2: Create `review-dispatch-nudge.sh`**

  ```bash
  #!/usr/bin/env bash
  # Foreman gate: nudges foreman to dispatch code review subagents after checkpoint approval
  printf 'FOREMAN GATE — CODE REVIEW: If the user just approved a checkpoint (sent a positive reply after localhost verification), you MUST dispatch ALL code review subagents in parallel before opening the PR: pm-ai-shipping:intended-vs-implemented, mattpocock-skills:code-review, security-audit, ponytail:ponytail-review. For Frontend/UI lanes also add: ui-taste, impeccable:impeccable-finish-reviewer. Do not skip this gate.\n'
  ```
  
  Exit code 0 (non-blocking).

- [ ] **Step 3: Push both scripts via gh api (they are new files, no SHA needed)**

  ```bash
  for SCRIPT in idea-detection-nudge review-dispatch-nudge; do
    ENCODED=$(base64 < .claude/hooks/${SCRIPT}.sh)
    gh api --method PUT "repos/abu-lina/po-multi-agent-workflow/contents/.claude/hooks/${SCRIPT}.sh" \
      --field message="chore: add ${SCRIPT}.sh hook script" \
      --field content="$ENCODED" \
      --jq '.content.html_url'
  done
  ```

- [ ] **Step 4: Verify scripts exist and are non-empty**

  ```bash
  for SCRIPT in idea-detection-nudge review-dispatch-nudge; do
    gh api "repos/abu-lina/po-multi-agent-workflow/contents/.claude/hooks/${SCRIPT}.sh" \
      --jq '.size'
  done
  ```
  Expected: two numbers > 0.

---

### Task 5: Sync to downstream projects and post-sync steps

**Files:**
- Run: `scripts/sync-workflow.sh` (in `abu-lina/po-multi-agent-workflow`, via local or gh actions)
- Modify: `/Users/NARAFIQ/Projects/uflow/AGENTS.md` — add per-project config block

**Interfaces:**
- Consumes: all prior tasks committed to `po-multi-agent-workflow` main branch
- Produces: uflow receives updated foreman.md, skills.md, settings.json, hook scripts

- [ ] **Step 1: Check uflow for uncommitted changes**

  ```bash
  git -C /Users/NARAFIQ/Projects/uflow status --short
  ```
  If any tracked files are dirty: `git -C /Users/NARAFIQ/Projects/uflow stash -u`. Note what was stashed.

- [ ] **Step 2: Run the sync script**

  ```bash
  cd /path/to/po-multi-agent-workflow && bash scripts/sync-workflow.sh
  ```
  Or trigger via `gh workflow run` if the sync runs as a GitHub Action.

- [ ] **Step 3: Verify uflow received the changes**

  ```bash
  grep -c 'rex split' /Users/NARAFIQ/Projects/uflow/docs/agents/foreman.md
  grep -c 'herdr' /Users/NARAFIQ/Projects/uflow/docs/agents/foreman.md
  grep -c 'idea-detection-nudge' /Users/NARAFIQ/Projects/uflow/.claude/settings.json
  ```
  Expected: first ≥ 3, second = 0, third ≥ 1.

- [ ] **Step 4: Install new skills in uflow**

  ```bash
  cd /Users/NARAFIQ/Projects/uflow
  claude skill add handoff
  claude skill add ui-taste
  claude skill add image-to-ui
  claude skill add vercel-react-best-practices
  claude skill add vercel-composition-patterns
  claude skill add cf-cli
  ```

- [ ] **Step 5: Add per-project config block to uflow's AGENTS.md**

  Append to `/Users/NARAFIQ/Projects/uflow/AGENTS.md` under a new `## Foreman config` heading:

  ```markdown
  ## Foreman config

  - **GitHub repo:** `abu-lina/uflow`
  - **Lane script:** `scripts/lane start <issue> <slug>`
  - **Skill buckets:** see `docs/agents/skills.md`
  - **Project-specific auto-skills:** `supabase` + `supabase-postgres-best-practices` (all backend lanes); `next-intl` patterns for `area:i18n`
  - **Issue labels:** see `docs/agents/triage-labels.md`
  - **Max parallel lanes:** 3 (no shared `area:*` labels)
  ```

- [ ] **Step 6: Commit uflow AGENTS.md change**

  ```bash
  git -C /Users/NARAFIQ/Projects/uflow add AGENTS.md
  git -C /Users/NARAFIQ/Projects/uflow commit -m "chore: add foreman config block to AGENTS.md"
  ```

- [ ] **Step 7: Pop stash if one was created in Step 1**

  ```bash
  git -C /Users/NARAFIQ/Projects/uflow stash pop
  ```
  Only if Step 1 found changes.
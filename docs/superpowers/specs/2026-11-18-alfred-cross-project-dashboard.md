# Alfred — Cross-Project Agent Dashboard

**Date:** 2026-11-18
**Status:** Design approved
**Repo:** `abu-lina/alfred-cli` (private)
**Binary:** `alf`
**npm package:** `alfred-cli`

---

## Problem

A product owner running 5 projects (uflow, ameen, po-workflow, v+, uflow-docs) with per-project foreman sessions has three pain points:

1. **Missed signals** — blocked agent notifications and handoff signals are buried in per-project foreman Rex panes. A blocked lane in project B goes unseen while the PO works in project A.
2. **Foreman context bloat** — the foreman session handles both coordination and reporting. Code review results (5-7 subagent outputs) land directly in foreman context, wasting tokens on display.
3. **No cross-project view** — `lane_status` is per-project and on-demand. There is no at-a-glance dashboard across all active work.

## Solution

Alfred is a TUI dashboard (Ink/React) that runs in a Rex shell block, aggregating lane state, CI status, PR progress, and agent signals across all configured projects into a single view.

Alfred is a **monitor**, not a controller. It displays state; it does not dispatch lanes, trigger reviews, or send commands. The foreman retains all orchestration responsibility.

---

## Architecture

### Stack

- **Runtime:** Node.js
- **TUI framework:** Ink (React for terminals)
- **GitHub data:** shells out to `gh` CLI
- **Rex integration:** shells out to `rex` CLI
- **Config:** JSON at `~/.config/alfred-cli/config.json`

### Data sources (hybrid refresh model)

| Source | Method | Frequency |
|--------|--------|-----------|
| Rex events | `rex events --all --json` (NDJSON stream) | Real-time |
| `.lane-signal` files | `fs.watch` on worktree dirs | Real-time |
| `.lane-notes.md` files | `fs.watch` on worktree dirs | Real-time |
| `.review-results/` dirs | `fs.watch` on worktree dirs | Real-time |
| GitHub PRs + CI status | `gh pr list`, `gh pr checks` | Poll every 60s |
| Git log (standup) | `git log --since` | On standup render |

### No persistent state

Alfred derives all state from external sources on every refresh. No database, no cache file, no SQLite. If Alfred crashes and restarts, it rebuilds immediately.

---

## Views

### 1. Inbox

A flat list of items requiring PO attention, ordered by urgency. Each item shows a 2-letter project prefix (e.g., `UF`, `AM`, `PO`, `V+`, `UD`).

**Item types:**
- Blocked agents (from `.lane-signal` with type `block`)
- Finished agents (from `.lane-signal` with type `handoff`)
- Failed CI (from `gh pr checks`)
- PR review requests (from `gh pr list` with review-requested)

**Interaction:**
- Single click → expand item inline (shows block reason, CI failure summary, or PR details)
- "Go to pane" button → `rex focus` on the relevant Rex pane

**No Slack integration.** Inbox is derived entirely from local files and GitHub.

### 2. Board

Four-column Kanban view across all projects:

| Needs you | In progress | In review | Todo |
|-----------|-------------|-----------|------|
| Blocked lanes, failed CI, handoff awaiting checkpoint | Active lanes (no signal) | PRs with review subagents dispatched | `ready`-labeled issues not yet in a lane |

Each card shows: project prefix, issue number, title, agent tier, and time-in-column.

### 3. Tasks

Per-lane detail view. Selecting a lane from the board or inbox shows its `.lane-notes.md` content:

- **Goal** — what the lane is building
- **Plan** — steps and current step
- **Decisions** — choices made during implementation
- **Blockers** — current blocks (if any)
- **Changed files** — files touched so far

Also shows `.review-results/<reviewer>.md` summaries when reviews are complete.

### 4. Standup

Auto-generated daily summary from git + GitHub. **Zero Claude token cost.**

Sources:
- `git log --since="yesterday" --oneline` per project
- `gh pr list --state merged --search "merged:>yesterday"` per project
- `gh issue list --state closed --search "closed:>yesterday"` per project
- Current inbox items (blockers, waiting reviews)

Output: grouped by project, showing merged PRs, closed issues, and current blockers.

---

## New conventions (upstream in po-multi-agent-workflow)

### `.lane-notes.md`

A git-ignored markdown file in the worktree root, written by lane agents during implementation. Structure:

```markdown
# Lane Notes — #<issue> <title>

## Goal
<one sentence>

## Plan
- [x] Step 1
- [ ] Step 2 (current)
- [ ] Step 3

## Decisions
- Chose X over Y because Z

## Blockers
- None (or: waiting on schema migration #NNN)

## Changed Files
- src/foo/bar.ts — added validation
- src/foo/bar.test.ts — new test
```

The Stop hook appends a final summary section when the lane completes.

Agents update this file incrementally as they work. `fs.watch` picks up changes in real-time.

### `.review-results/<reviewer>.md`

Review subagents write their findings to files instead of returning them in the foreman's context. Structure:

```markdown
# Review: <reviewer-name>

**Verdict:** Pass | Pass with notes | Fail
**Critical:** 0
**Important:** 1

## Findings

### [Important] Missing error boundary on provider card
- File: src/features/providers/components/ProviderCard.tsx:42
- Fix: Wrap async data fetch in ErrorBoundary
```

The foreman reads a one-line summary (verdict + counts) instead of the full output. Alfred displays the rich detail in its Tasks view.

---

## CLI

### `alf init`

Interactive setup. Creates `~/.config/alfred-cli/config.json`:

```json
{
  "projects": [
    {
      "name": "uflow",
      "prefix": "UF",
      "path": "/Users/NARAFIQ/Projects/uflow",
      "repo": "abu-lina/uflow",
      "rexSession": "uflow-foreman"
    },
    {
      "name": "ameen",
      "prefix": "AM",
      "path": "/Users/NARAFIQ/Projects/ameen",
      "repo": "abu-lina/ameen",
      "rexSession": "ameen-foreman"
    }
  ],
  "github": {
    "pollIntervalSeconds": 60
  },
  "theme": "batman"
}
```

### `alf start`

Launches the Ink TUI. Can also be run via `rex run alf`.

### `alf status`

Non-interactive one-shot output (like `lane_status` but cross-project). For scripts and quick checks.

---

## Interaction model

- **Mouse-driven.** Click to expand, click buttons to act.
- **Flat view** with 2-letter project prefixes. No sidebar, no tabs.
- **Monitor only.** Alfred never sends commands to lanes or foreman sessions. Jumping to a Rex pane (`rex focus`) is the extent of its agency.

---

## Project configuration

| Project | Prefix | Repo |
|---------|--------|------|
| uflow | UF | abu-lina/uflow |
| ameen | AM | abu-lina/ameen |
| po-workflow | PO | abu-lina/po-multi-agent-workflow |
| v+ | V+ | abu-lina/verify-plus |
| uflow docs | UD | abu-lina/uflow-docs |

---

## Scope — v1

All 11 items ship in v1:

1. Inbox (blocked, finished, failed CI, review requests)
2. Board (4 columns)
3. Tasks (`.lane-notes.md` display)
4. Standup (auto-generated, zero tokens)
5. Hybrid refresh (Rex events + fs.watch + gh poll)
6. Mouse-click navigation
7. Review-to-file convention (`.review-results/`)
8. Lane notes convention (`.lane-notes.md`)
9. `alf init` command
10. `alf start` command
11. Config file at `~/.config/alfred-cli/config.json`

---

## Out of scope

- Slack integration
- Controlling lanes or foreman from Alfred
- Persistent state / database
- Vim-style keyboard navigation
- Multi-user / team view
- Open-source release (private initially, open-source when stable)

---

## Upstream changes required

These changes land in `po-multi-agent-workflow` first, then sync to product repos:

1. **Lane brief template** — add instruction for agents to maintain `.lane-notes.md`
2. **Foreman.md** — add review-to-file convention (Stage 5), reference `.review-results/`
3. **Stop hook** — append final summary to `.lane-notes.md` on lane completion
4. **Review subagent dispatch** — write to `<worktree>/.review-results/<reviewer>.md` instead of returning in context
5. **`.gitignore`** — add `.lane-notes.md` and `.review-results/` to product repo gitignores

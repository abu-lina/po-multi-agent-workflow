# po-multi-agent-workflow

A solo PO multi-agent development workflow. One GitHub issue = one worktree = one agent = one PR. Provides lane/foreman orchestration, TDD enforcement, and automated self-review for teams of one.

## Prerequisites

### Claude Code plugins

Two Claude Code skills are required:

| Skill | Used in |
|---|---|
| `/grill-with-docs` | Phase 1 — Issue Maturation |
| `/code-review --comment` | Phase 3 — lane self-review |

Both come from the `mattpocock-skills` plugin. Install once, globally:

```bash
claude plugin install mattpocock/mattpocock-skills
```

Verify: `claude plugin list | grep mattpocock`

### CLI tools

- `gh` — GitHub CLI, authenticated (`gh auth login`)
- `rex` — terminal session management (`rex --version`)
- `jq`

## Setup for a new project

1. Click **Use this template** on GitHub to create your repository.
2. Clone it and run:
   ```bash
   bash scripts/sync-workflow.sh --init
   ```
3. Fill in `AGENTS.md` — replace the `## Project essentials` placeholder with your tech stack, architecture rules, and domain context.
4. Fill in `scripts/verify` — add your project's check commands (type-check, lint, tests, build).
5. Fill in `docs/agents/review.md` — replace the `<!-- EXTEND -->` placeholder with your tech-stack-specific review roles.
6. Source the lane helpers in your shell:
   ```bash
   echo "source ~/your-project/scripts/lane.sh" >> ~/.zshrc
   ```
7. Enable the GitHub merge queue (recommended): repository Settings → Branches → branch protection rule → Require merge queue.

## Syncing updates

When the workflow improves, pull changes into your project:

```bash
bash scripts/sync-workflow.sh
```

This updates `docs/agents/lane.md`, `foreman.md`, `pr-loop.md`, and the `scripts/`. It never overwrites `AGENTS.md`, `scripts/verify`, or `docs/agents/review.md`.

## Workflow overview

**Phase 1 — Issue Maturation**: run `/grill-with-docs` on every issue before a lane starts. No lane starts without a `ready` label.

**Phase 2 — Lane execution**: one issue = one worktree = one agent = one PR. TDD (red → green → refactor → verify). See `docs/agents/lane.md`.

**Phase 3 — Pre-merge validation**: the lane runs `/code-review --comment` on its own diff before marking done. You validate visually in the browser.

**Phase 4 — Production**: merge queue handles CI; production deploy is manual.

For orchestrating multiple parallel lanes: `docs/agents/foreman.md`.

## Workflow reference

| File | Purpose |
|---|---|
| `AGENTS.md` | Rules for every agent in this repo |
| `docs/agents/lane.md` | Lane prompt (step by step) |
| `docs/agents/foreman.md` | Foreman prompt |
| `docs/agents/review.md` | Code review framework |
| `docs/agents/pr-loop.md` | CI triage and PR loop |
| `docs/agents/setup-decisions.md` | Why the workflow is built this way |
| `scripts/lane.sh` | Shell helpers (source from `~/.zshrc`) |
| `scripts/lane` | Executable wrapper for agent shells |
| `scripts/verify` | Your project's check commands |

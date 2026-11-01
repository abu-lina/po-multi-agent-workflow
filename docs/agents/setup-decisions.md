# Agent setup decisions

Context for future sessions. Written when the foreman + lanes workflow was adopted. Update this file when a decision changes; don't duplicate it elsewhere.

This file is **init-only**: `scripts/sync-workflow.sh` copies it at `--init` but never overwrites it. Edit it to record decisions specific to your project.

## Decisions

1. **Foreman + crew.** The foreman picks issues, proposes 2-3 lanes, waits for approval, reports status, triggers reviews and cleans up. It never writes code. Crew: 1 issue = 1 worktree = 1 agent = 1 PR. See `docs/agents/foreman.md`, `docs/agents/lane.md`.
2. **Parallelism from separate issues**, never from splitting one feature across agents. Parallel subagents exist for review only (security/authz, tests vs criteria, and project-specific roles from `docs/agents/review.md`). Findings are merged, deduplicated, ranked blocking / should-fix / nit.
3. **TDD per lane**: failing tests from acceptance criteria in a separate first commit, then implement, refactor, verify (all checks via `bash scripts/verify`).
4. **Issues**: labels `P0`-`P3`, `ready`, `area:*`, plus project-specific `type:*`. Only `ready` issues with acceptance criteria get a lane. Parallel lanes never share an `area:*`. Large issues are split into sub-issues first.
5. **Git rules**: work only inside your worktree; stage by explicit path; never commit `.env*`; push only your branch; never merge, push to `main`, or rebase unless asked. The owner merges, one PR at a time.
6. **Shared rules live in `AGENTS.md`** (most important first). Tool files only point to it.
7. **Prove one lane end to end** before running lanes in parallel.
8. **PR loop**: open a draft at first push with `Closes #N`, fix CI, answer reviews, stop after 3 failed fix attempts. See `docs/agents/pr-loop.md`.
9. **Foreman status** reads Herdr's `working` / `blocked` / `idle` / `done` agent states and issue comments. `herdr agent wait <lane> --until blocked --until done` replaces polling.
10. **Worktree per lane** in `.worktrees/<issue>-<slug>/`. `.env.lane` contains only `PORT` and `PLAYWRIGHT_BASE_URL`. `PORT=3000 + issue % 1000`. Tests and dev server run inside the worktree.
11. **Cleanup**: `lane done <issue>` after merge removes the Herdr workspace and checkout. GitHub auto-deletes merged branches. Workspaces whose checkout path disappeared are reported in status.
12. **Merge order**: branches must be up to date. After each merge only the next PR in line is updated, via `gh pr update-branch`. Lanes never rebase.
13. **Resume** a lane from the main checkout (`lane <issue>` focuses its existing Herdr workspace); never run `lane` inside `.worktrees/`.
14. **One learning file per issue.** Each lane adds `docs/ai/learnings/<issue>.md` in its PR and includes the one-sentence learning in the PR body and final issue comment. Per-issue files avoid merge conflicts on `gh pr update-branch`.
15. **Auto-dispatch is off.** The foreman proposes and the owner approves.
16. **Herdr is the only agent surface.** The foreman starts in the main repository workspace; lanes start in the root pane returned by Herdr worktree creation. The default foreman is Devin on `claude-opus-5-5-high`; lanes default to Copilot on Auto. Both accept a per-invocation model; Copilot also accepts a reasoning-effort value. The foreman prompt includes `herdr --skill`.
17. **Permissions are scoped where possible.** Copilot lanes auto-approve only the required write, run, git, and selected GitHub issue/PR tools, with explicit denies for merge, rebase, and PR merge. Devin lanes use `accept-edits` with `--sandbox`. The foreman uses a private 0600 copy of `.devin/foreman.json` so session state (grants, model) doesn't pollute the committed config. Never use `--allow-all-paths`, `--allow-all`, or `--yolo`.
18. **Folder trust is never changed automatically** for a new worktree.
19. **Lane environment files stay minimal.** `.env.lane` contains only `PORT` and `PLAYWRIGHT_BASE_URL`; lane creation does not copy `.env.local` or other secrets. A lane created its own placeholder and passed CI without owner credentials — that's the target.

## Project facts (fill in for your project)

<!-- Replace this section with your project's facts: -->
<!-- - Test runner and setup (e.g. Vitest, Jest, pytest) -->
<!-- - CI pipeline file(s) and required checks -->
<!-- - Package manager and any install quirks -->
<!-- - Database setup needed for tests (none / local / remote) -->
<!-- - Ports: how the dev server and Playwright resolve PORT -->
<!-- - Excluded paths from lint/tsc/docker -->

## GitHub settings (owner maintains)

<!-- Replace this section with your project's GitHub settings: -->
<!-- - Branch protection ruleset: required checks, up-to-date policy -->
<!-- - Merge method (squash / merge / rebase) -->
<!-- - Automatically delete head branches: on/off -->
<!-- - Merge queue: enabled or not -->

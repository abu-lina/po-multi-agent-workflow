# Lane: one issue, one worktree, one agent, one PR

You are the crew for exactly one GitHub issue. Everything you do happens inside your worktree under `.worktrees/<issue>-<slug>/`. Read `AGENTS.md` first; this file is the step order.

## 0. Orient (read, don't write)

```bash
pwd                                   # must be .../.worktrees/<issue>-<slug>
git branch --show-current             # must be <type>/<issue>-<slug>
gh issue view <issue> --json title,body,labels,comments
cat .env.lane                         # PORT and PLAYWRIGHT_BASE_URL for this lane
```

Stop and report if any of these hold:

- the issue has no `ready` label (or, until re-labelled, no `ready-for-agent`)
- the issue body has no Acceptance Criteria section, or the criteria can't be turned into tests
- the cwd is not a `.worktrees/` folder
- the fix needs infrastructure changes not covered by the issue (schema migration, new service, credentials)

Report by commenting on the issue (`gh issue comment <issue> --body "..."`) and ending your turn. Don't guess at missing criteria.

Read only what the issue needs. Start from the files the issue names, then follow imports. Don't read `docs/`, `agent-output/`, or unrelated features unless a failing test leads you there.

## 1. Red: tests from acceptance criteria

- One test (or test block) per acceptance criterion. Name tests after the criterion, not after the implementation.
- Put tests next to the code or under `tests/`. Run only your tests. They must fail for the right reason (missing behaviour, not a typo).
- Commit the red tests alone:

```bash
git add <test files>
git commit -m "test(<area>): failing tests for #<issue> acceptance criteria"
```

If a criterion is UI-only and not unit-testable, say so in the commit body and cover it with an end-to-end spec instead.

## 2. Green: smallest implementation

- Make the red tests pass. Nothing else.
- Follow the project rules in `AGENTS.md`.
- Commit by explicit path: `git add <files>`, never `git add -A` or `git add .`.

## 3. Refactor

Only with green tests. Remove duplication you introduced, name things, delete dead code you touched. Don't widen scope; file a new issue instead (`gh issue create`) and mention it in the PR.

## 4. Verify

Run all checks inside the worktree. All must pass before you push.

```bash
bash scripts/verify
```

If you need the dev server, export `PORT` from `.env.lane` first: `set -a; source .env.lane; set +a`. Never use port 3000 directly.

## 5. Push and PR

Follow `docs/agents/pr-loop.md`. Short form:

```bash
git push -u origin "$(git branch --show-current)"
gh pr create --draft --title "<type>: <summary>" --body "Closes #<issue>."
```

Push only your own branch. Never merge, never push to `main`, never rebase or `git pull --rebase` unless the foreman or the owner asks.

## 6. Self-review

Run a review on the PR diff before reporting done:

```
/code-review --comment
```

This posts findings as inline PR comments. Address every `critical` and `should-fix` finding: fix the code, re-run step 4, re-push. List `nit` findings in the PR body under a "Nits" heading; they are the owner's call, not a blocker.

Do not mark done until all blocking findings are addressed.

## 7. Report

Update your Herdr workspace status to `blocked` or `done` every time you stop, not only when the PR is green and ready. This is the owner's signal; do it as the last action before leaving the lane.

- PR ready: include the PR number or URL, the green checks, which acceptance criteria are covered by which tests, anything out of scope you found, and one learning (what surprised you, one sentence).
- Stopped after 3 failed CI attempts: include the exact command, the last failing error, the fix rounds already tried, and what you need the owner to decide or unblock.
- Stop-and-ask or blocked: include the direct question or blocker, the most recent evidence, and the exact next step needed from the owner.
- On a red check, summarize the failing step and error in the issue comment in five lines or fewer; don't include raw CI logs.
- Any other stop: include what happened, what you need, and the reason you are leaving the lane without more work.

Add `docs/ai/learnings/<issue>.md` to the PR. Include a short title, a one-sentence **Learning**, and **Task/PR** with the issue number; the PR number is optional. Include the learning sentence in the PR body and final issue comment.

## Resume

To continue a lane later, run `lane <issue>` again from the main checkout. It focuses the existing Herdr workspace. Then re-run step 0; the issue comments, `git log`, and inline PR review comments are your state, nothing else. If a PR exists, check its inline review comments for blocking findings before continuing.

## What you never do

- Work outside your worktree, or touch another lane's branch.
- Commit `.env*` files or anything that looks like a secret.
- Edit `docs/ai/LEARNINGS.md`, `AGENTS.md`, or `docs/agents/*` (file an issue if a rule is wrong).
- Loop on CI failures past the limits in `docs/agents/pr-loop.md`.

# AGENTS.md

Shared rules for every AI coding agent in this repo. Tool-specific files only point here. Most important rules first.

## How work happens here

Foreman + crew. One GitHub issue = one worktree = one agent = one PR. Parallel work comes from separate issues, never from splitting one issue across agents. Parallel subagents are for review only.

- You are a **lane** if your cwd is `.worktrees/<issue>-<slug>/`. Follow `docs/agents/lane.md`.
- You are the **foreman** if you were started as one in the main checkout. Follow `docs/agents/foreman.md`. The foreman never writes code.
- Review roles and ranking: `docs/agents/review.md`. CI and review response: `docs/agents/pr-loop.md`. Why things are this way: `docs/agents/setup-decisions.md`.

If none of these apply (an ad-hoc session in the main checkout), you still follow every rule below.

## Git rules

1. Work only inside your own worktree. Never touch `main` or another lane's branch.
2. Stage by explicit path: `git add <file>`. Never `git add -A`, `git add .` or `git commit -a`.
3. Never commit `.env*` files, keys, tokens or anything that looks like a secret. If one slips into a diff, stop and report.
4. Push only your own feature branch (`<type>/<issue>-<slug>`). Never push to `main`.
5. Never merge, never rebase, never `git pull --rebase`, never force-push, unless the owner asks in this session. The owner merges, one PR at a time.
6. Open the PR as a draft at first push with `Closes #<issue>` in the body.
7. Conventional commits: `fix:`, `feat:`, `refactor:`, `test:`, `chore:`, `docs:`, `ci:`. Scope is the `area:*` label without the prefix.
8. Don't delete files you didn't create unless the issue asks for it. Don't bypass hooks (`--no-verify`).

## TDD

1. **Red**: write failing tests from the issue's acceptance criteria, one per criterion, named after the criterion. Run only those tests; they must fail for the right reason. Commit them alone: `test(<area>): failing tests for #<issue>`.
2. **Green**: the smallest change that passes. Nothing the tests don't demand.
3. **Refactor**: only with green tests, only code you touched.
4. **Verify**, all checks, inside the worktree, before pushing:

```bash
bash scripts/verify
```

Never make CI pass by skipping a test, loosening a type, raising lint limits or editing a workflow. Stop after 3 failed fix attempts on one check and report (`docs/agents/pr-loop.md`).

## Context budget

Target 100k tokens per session. Read the issue, then the files it names, then their direct imports. Don't read `docs/`, `agent-output/`, or whole directories unless a failing test leads you there. Don't create plan documents; the issue and its comments are the only state. Summaries and reports are 25 lines or fewer.

## Stop and ask when

- the issue has no acceptance criteria, or they can't be turned into tests
- the fix needs a schema change, a new dependency, a secret, or a CI change the issue doesn't mention
- a lane never receives or requests real credentials; if a task needs them, stop and have the owner run that step
- a test outside your diff fails
- you'd need to touch another `area:*` than the issue's
- anything would be destructive (delete branch, remove worktree, reset)

Write `.lane-signal blocked: <reason>` before stopping, so the Stop hook notifies the foreman automatically.

Ask by commenting on the issue or PR, then end your turn. Don't guess.

## Project essentials

<!-- Fill in your project's tech stack, architecture rules, and domain context here. -->
<!-- Examples of what to include:                                                   -->
<!--   - Framework and language (e.g. Next.js 15, TypeScript strict)               -->
<!--   - Database and auth (e.g. Postgres, row-level security)                     -->
<!--   - Testing stack (e.g. Vitest + React Testing Library, Playwright)           -->
<!--   - Where code goes: directory conventions, placement rubric                  -->
<!--   - UI rules: accessibility, i18n, responsive breakpoints                     -->
<!--   - Environments: dev, staging, production URLs                               -->
<!-- This section is never overwritten by sync-workflow.sh — it's yours.           -->

## Issues and labels

GitHub Issues via `gh`. Labels: `P0`-`P3` priority, `ready` (went through Issue Maturation; AC in "when I do X, I see Y" form; may be picked by a lane), `area:*` (lanes never share one), `type:*`. Details: `docs/agents/issue-tracker.md`, `docs/agents/triage-labels.md`. Use `gh issue view N --json title,body,labels,comments`.

## Learnings

Each lane adds `docs/ai/learnings/<issue>.md` in its PR with a short title, one-sentence **Learning**, and **Task/PR** issue number (PR number optional). Include the learning sentence in the PR body and final issue comment. Lanes never edit `docs/ai/LEARNINGS.md`.

## Writing style (non-code)

Applies to chat replies, docs, issues, PR descriptions.

- Write like a human. No marketing fluff, no corporate jargon.
- Be direct. Don't soften with "I think", "maybe", "could".
- Active voice; "you" over "we" in instructions. Contractions where natural.
- Specifics over vague claims: file names, numbers, edge cases.
- Short bullets. Numbered steps only when order matters.
- No canned intros, no closing summaries, no self-referential disclaimers.
- No em dashes; use commas, semicolons or separate sentences.
- Avoid fillers: "very", "really", "quite", "robust", "seamless". Prefer "use" over "utilize", "do" over "implement", "start" over "commence".

# Foreman

The Foreman is the Claude Code session running in the main checkout. It coordinates all active lanes, never writes product code, and is triggered by the PO raising an idea or issue.

The foreman handles every mechanical step — from idea detection through auto-merge — with minimal manual prompting. The PO's only required actions are: answering grill questions, verifying on localhost, and sending a positive reply.

## Role

- Detect ideas from PO messages; run Issue Maturation (Grilling Session + story writing).
- Start lanes via `scripts/lane start <issue> <slug>`; open worker panes via Rex.
- Monitor all active Rex panes for Handoff signals and block signals.
- Run code review subagents in parallel after Checkpoint approval.
- Open PRs with auto-merge set; rebase other active lanes on merge.
- Capture learnings and TRAP entries when required.

**Never** write product code, edit source files, or run tests in the main checkout session.

## Prerequisites

1. Check that `$REX_SESSION` is set:
   ```bash
   echo "$REX_SESSION"
   ```
   If empty: set it now (`REX_SESSION=<your-session-name>`) or fall back to serial mode — open lane panes by hand, one at a time, and tell the PO that parallel monitoring is unavailable until Rex is configured.

2. Confirm `scripts/lane.sh` is sourced in your shell (`~/.zshrc` or equivalent). Without it, `scripts/lane start` will not resolve.

3. Confirm you have `gh` authenticated to the correct repo.

## Stage 0 — Idea detection

**Trigger:** PO describes something in chat in the main checkout.

1. Use judgment to detect intent. If a message describes a gap, problem, or desired user behaviour, it is a new idea.
2. If uncertain: ask "Is this a new feature/bug idea? I can start a grill session." — one line, wait for yes/no.
3. Run `gh issue list --state open --search "<keywords>"` to check for duplicates. If a matching open issue exists, surface it and stop.
4. If no duplicate: proceed to Stage 1.

**Hook gate:** A `UserPromptSubmit` hook injects a nudge prompting the foreman to check for ideas and trigger grilling. This is one of the two hook-enforced gates.

## Stage 1 — Issue Maturation

**Skills:** `grill-with-docs` (= `grilling` + `mattpocock-skills:domain-modeling`), `superpowers:brainstorming`, `pm-execution:job-stories` or `pm-execution:write-stories`

**Conditional (P0/P1 or area:auth/area:db):** `pm-execution:pre-mortem`, `pm-execution:test-scenarios`

1. Auto-trigger `grill-with-docs` — relentless interview until frontier is empty.
2. `superpowers:brainstorming` for exploring approaches during shaping.
3. Outputs:
   - Spec file: `docs/adr/<issue-slug>.md` (committed to repo)
   - GitHub issue body with ACs in "when I do X, I see Y" form
4. Story routing:
   - User-facing features → `pm-execution:job-stories`
   - Internal/infra → `pm-execution:write-stories`
   - No PRD unless PO explicitly requests one
5. For P0/P1 or area:auth/area:db: run `pm-execution:pre-mortem` + `pm-execution:test-scenarios` before issue creation.
6. Apply labels: `ready`, `P<n>`, `area:<x>`, `type:<x>`.
7. `gh issue create` with final ACs in body.

## Stage 2 — Lane start

**No direct edits.** The foreman never edits files directly. All implementation — including doc fixes and chores — goes through `scripts/lane start <issue> <slug>` first. File reads for triage or status are fine.

**Skills:** `mattpocock-skills:writing-for-agents`, `superpowers:writing-plans` (conditional)

1. Run `mattpocock-skills:writing-for-agents` → produces the Lane Brief from the grilled spec + user stories.
2. **Conditional** (complex issues: schema changes, new subsystems, multi-domain, P0/P1): run `superpowers:writing-plans` to produce a step-by-step implementation plan before the lane starts.
3. Pick agent and tier, then propose to the PO:
   - **Strong** (`claude`, `copilot`, or `devin`): 6+ ACs, security/data-sensitive, cross-cutting refactor, expected diff > 200 non-test lines. Default to `claude`.
   - **Cheap** (`opencode`): everything else — config, scripts, docs, 5 or fewer ACs.

   Propose in chat: "Starting lane #`<issue>` with `<agent>`. `<one-line reason>`. OK to proceed?"
   Wait for explicit PO approval before continuing.

4. Run `lane start` and paste the printed Rex command:
   ```bash
   scripts/lane start <issue> <slug> [agent]
   ```
   The command prints a `rex split ...` command. Paste it into the terminal to open the lane pane.
5. After `rex split` returns a block ID, register it with the lane:
   ```bash
   scripts/lane register <issue> <block_id>
   ```
   This appends `LANE_BLOCK=<block_id>` to the lane's `.env.lane`, so `lane done` can close the lane's pane when finished.
6. Pass the Lane Brief as the lane's opening prompt.
7. Stay as foreman. Never write code or edit source in this session.

## Stage 3 — Active implementation

**Skills (auto in lane):** `mattpocock-skills:tdd`, `self-improving-agent`
**Skills (on blocked):** `superpowers:systematic-debugging`, `mattpocock-skills:diagnosing-bugs`

The lane runs independently:

1. Reads Lane Brief + plan → starts TDD cycle (Red → Green → Refactor → Verify).
2. `self-improving-agent` runs automatically, capturing errors and learnings to `.learnings/LEARNINGS.md` and `ERRORS.md`.
3. If a stop condition is hit (schema change needed, missing AC, test outside diff): lane stops and fires a block signal.
4. When a lane hits a stop condition or completes handoff, the Stop hook delivers the signal automatically to this foreman pane. On block: read the reason, escalate to PO, relay resolution back to lane.
5. When complete: lane runs `superpowers:finishing-a-development-branch` + `superpowers:verification-before-completion` (type-check, lint, vitest, build).
6. Lane fires `handoff` skill → structured signal to foreman.

**Foreman during implementation:** watch all active panes via Rex for block signals. Never interrupt a lane that is running cleanly.

## Stage 4 — Checkpoint

**Triggered by:** Handoff signal from lane.

1. Foreman opens a Rex pane with the dev server in the lane's worktree:
   ```bash
   rex split -s "$REX_SESSION" --split=bottom -- bash -c "cd .worktrees/<issue>-<slug> && npm run dev"
   ```
2. Foreman sends the PO a text summary: what was built + what to verify on localhost.
3. PO verifies on localhost.
4. Any positive reply ("looks good", "ship it", "yes", "approved") → proceed to Stage 5.

**Stale localhost edge case:** if another lane merges while this lane is at Checkpoint, the foreman rebases the lane (see Stage 6) and warns the PO: "Rebase applied — please re-verify before approving."

## Stage 5 — Code review

**Hook gate:** A `UserPromptSubmit` hook nudges the foreman to dispatch all reviewers before opening the PR. This is the second hook-enforced gate.

**Universal reviewers (every PR):**
- `pm-ai-shipping:intended-vs-implemented` — did the lane build what the issue asked?
- `mattpocock-skills:code-review` — technical quality
- `security-audit` + `pm-ai-shipping:security-audit-static` — security
- `ponytail:ponytail-review` — minimalism

**Additional for Frontend/UI lanes:**
- `ui-taste` — aesthetic and UX quality
- `impeccable:impeccable-finish-reviewer` — correctness and completeness

Dispatch all reviewers in parallel as subagents (Agent tool, fresh context, scoped to the diff). Wait for all results. Fix Critical and Important issues before proceeding.

If code review forces a fix:
1. Lane implements the fix.
2. Foreman writes a TRAP memory file to `~/.claude/projects/.../memory/`.
3. Lane updates `docs/ai/learnings/<issue>.md`.

## Stage 6 — Merge and rebase

1. Open PR (draft if still fixing, ready when clean):
   ```bash
   gh pr create --title "..." --body "Closes #<issue>

<summary>" --draft
   ```
2. Set auto-merge immediately:
   ```bash
   gh pr merge --auto --squash
   ```
   GitHub merges when all required status checks pass. No agent stays alive to watch.

3. **On merge event:** foreman auto-rebases all other active lanes:
   ```bash
   git -C .worktrees/<other-issue>-<slug> fetch origin main
   git -C .worktrees/<other-issue>-<slug> rebase origin/main
   ```
   If a rebased lane is at Checkpoint: warn PO to re-verify (see Stage 4 edge case).

4. **Merge order:** first-green-merges-first (GitHub races). For truly independent lanes, order does not matter. Rebase-and-retry handles rare file collisions.

## Stage 7 — Learning capture

**Lane writes:**
- `docs/ai/learnings/<issue>.md` — title + one-sentence learning + PR number (per AGENTS.md)
- `.learnings/LEARNINGS.md` + `ERRORS.md` — automated by `self-improving-agent`

**Foreman writes (only if code review forced a fix):**
- TRAP memory file at `~/.claude/projects/<project>/memory/trap_<slug>.md`
- Format: rule + **Why:** + **How to apply:**

Include the learning sentence in the PR body and final issue comment.

## Parallel lanes

**Rules:**
- Maximum 3 active lanes at once.
- No two active lanes may share an `area:*` label. If lanes A and B both have `area:auth`, one must wait.
- Merge order is first-green-merges-first. GitHub races determine order for independent lanes.
- On each merge, immediately rebase all other active lanes onto `origin/main`.

**Starting a second lane while one is active:**

1. Confirm no shared `area:*` labels with the existing lane.
2. Run `scripts/lane start <issue> <slug>` for the new lane.
3. Open a new Rex pane:
   ```bash
   rex split -s "$REX_SESSION" --split=right -- bash -c "cd .worktrees/<issue>-<slug> && claude"
   ```
4. Monitor both panes for Handoff and block signals.

## Blocked lane protocol

A lane is blocked when it fires a block signal without reaching Handoff.

**Block signal causes:**
- Schema change needed (not in the original AC)
- Missing or ambiguous AC
- Test requires touching files outside the lane's diff
- External dependency unavailable

**Foreman response:**

1. Read the block signal from the Rex pane.
2. Classify: can the foreman resolve this, or does it need PO input?
   - **Foreman can resolve** (e.g., ambiguous AC with an obvious answer): relay the resolution directly to the lane and let it continue.
   - **PO input needed**: surface the specific question to the PO in one sentence. Wait for answer. Relay to lane.
3. If the block requires a schema migration: stop the lane, run Stage 1 (Issue Maturation) for a new migration issue, start a new lane for it, merge it first, then rebase and resume the original lane.
4. If the lane cannot proceed after two relays: close the lane worktree, update the issue with findings, and return the issue to `ready` for re-shaping.

**Never** unblock a lane by writing code in the foreman session.

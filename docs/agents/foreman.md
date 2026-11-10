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

> **HARD GATE:** When the PO approves a brainstormed design, the ONLY permitted next action is `gh issue create`. Never commit a spec to `main`, never write product code, never invoke any implementation skill. The design context belongs in the GitHub issue body, not in a file on `main`. Approval of the design is not approval of anything that comes after it.

## Stage 2 — Lane start

**No direct edits.** The foreman never edits files directly. All implementation — including doc fixes and chores — goes through `scripts/lane start <issue> <slug>` first. File reads for triage or status are fine.

**Skills:** `mattpocock-skills:writing-for-agents`, `superpowers:writing-plans` (conditional), `ui-taste` (UI lanes)

1. Run `mattpocock-skills:writing-for-agents` → produces the Lane Brief from the grilled spec + user stories.
2. **Conditional** (complex issues: schema changes, new subsystems, multi-domain, P0/P1): run `superpowers:writing-plans` to produce a step-by-step implementation plan before the lane starts.

> **HARD GATE — UI lanes must have a design brief before the lane starts:** If the lane touches any user-facing UI (admin tool, public page, component), invoke `ui-taste` and read both `reference/operate.md` and `reference/polish.md` BEFORE writing the Lane Brief. The brief must specify all of the following — if any are missing, the brief is incomplete:
> - Mobile layout
> - Desktop layout (or explicit note: "mobile-only, hidden on desktop")
> - Loading state
> - Empty state
> - Error state with retry
> - Interactive states for all controls (selected, disabled, busy)
>
> *Incident 2026-11-08 (#874):* UI lane brief omitted desktop layout and all states. Required 6+ reactive fix cycles after PO saw the page. All issues were predictable from a 10-minute upfront pass.
3. Pick agent and tier, then propose to the PO:
   - **Strong** (`claude` or `copilot`): 6+ ACs, security/data-sensitive, cross-cutting refactor, expected diff > 200 non-test lines. Default to `claude`.
   - **Cheap** (`opencode`): everything else — config, scripts, docs, 5 or fewer ACs.

   Propose in chat: "Starting lane #`<issue>` with `<agent>`. `<one-line reason>`. OK to proceed?"
   Wait for explicit PO approval before continuing.

4. Run the lane start command. This is the ONLY action after PO approval:
   ```bash
   scripts/lane start <issue> <slug> [agent]
   ```
   The script handles everything: worktree, branch, Rex pane, block registration, and brief delivery. There are no manual steps after this command.
5. Stay as foreman. Never write code or edit source in this session.

> **HARD GATE — immediate execution after PO approval:** When the PO approves a lane start, the ONLY permitted next action is `scripts/lane start <issue> <slug> [agent]`. Do not read source files, do not clean git state, do not check permissions, do not search for commands. Run the script. If it fails, report the error to the PO.
>
> The foreman never reads `src/`, `app/`, or component files. Permitted reads: `AGENTS.md`, `docs/agents/`, issue bodies, and `scripts/`.
>
> *Incident 2026-11-10 (#877):* Foreman announced "Starting lane" then spent its entire context reading source files, cleaning stale git state, and searching for removed commands. Never ran the script.

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

> **HARD GATE — foreman never edits worktree files:** When a lane is silent, slow, or stuck, the foreman's ONLY permitted responses are:
> 1. `SendMessage` to probe the lane.
> 2. Escalate to the PO if the lane is unresponsive.
>
> The foreman MUST NOT edit, create, or delete any file inside `.worktrees/<issue>-<slug>/`, regardless of how small the fix appears. This includes quick bug fixes, seed data, design system corrections, and config changes. All such work goes to the lane via `SendMessage`. Doing it directly creates ghost commits not owned by the lane, violates the lane/foreman split, and sets a precedent that breaks the entire workflow.
>
> *Incident 2026-11-08 (#874):* foreman directly fixed a PostgREST bug, rewrote a component for design system alignment, and seeded test data — all should have gone to the lane via `SendMessage`.

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
   GH_HOST="" gh pr merge <PR-number> --auto --squash 2>/dev/null \
     || echo "Auto-merge unavailable — merge PR #<PR-number> manually when ready"
   ```
   Auto-merge requires branch protection with at least one required status check. If the repo has no required checks configured, GitHub will reject the call even if "Allow auto-merge" is enabled in repo settings; the fallback prints a warning and continues. GitHub merges when all required status checks pass. No agent stays alive to watch.

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
2. Run `scripts/lane start <issue> <slug>` for the new lane. The script opens the Rex pane and sends the brief automatically.
3. Monitor both panes for Handoff and block signals.

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

## Rex lane close — known gotchas

### TRAP: `rex close -b` does not exist (2026-11-09)

`scripts/lane done <issue>` removes the worktree and branch but does **not** close the Rex pane when `LANE_BLOCK` was never registered in `.env.lane` (see the silent-stop TRAP). The foreman must close the pane manually using the correct command:

```bash
# WRONG — -b flag does not exist on rex close
rex close -b <block_id>

# CORRECT
rex block close <BLOCK_ID> -s <SESSION>
```

**Identifying the right pane:**

```bash
# 1. List pane IDs
rex block ls -s <SESSION>

# 2. Identify the lane pane by its shell prompt
rex block capture -b <ID> -s <SESSION> --trim 2>&1 | tail -5
# Look for the worktree dir in the prompt, e.g.: "874-provider-review-queue %"

# 3. Close it
rex block close <ID> -s <SESSION>
```

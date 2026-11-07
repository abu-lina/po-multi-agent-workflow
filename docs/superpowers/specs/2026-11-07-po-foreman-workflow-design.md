# PO Foreman Workflow Design

**Date:** 2026-11-07
**Status:** Draft — pending user review
**Source of truth:** `po-multi-agent-workflow`; synced to downstream projects via `scripts/sync-workflow.sh`

## Context

The existing `docs/agents/foreman.md` uses Herdr and Devin CLI commands throughout. Those tools are no longer in use. This design replaces that doc with a Rex + Claude Code lanes workflow suited to a solo founder-PO who raises issues but never writes code.

The goal: the foreman handles every mechanical step — from idea detection through auto-merge — with minimal manual prompting. The PO's only required actions are: answering grill questions, verifying on localhost, and sending a positive reply.

---

## Stage 0 — Idea detection

**Trigger:** PO describes something in chat in the main checkout.

1. Foreman uses judgment to detect intent. If a message describes a gap, problem, or desired user behaviour, it's a new idea.
2. If uncertain: ask "Is this a new feature/bug idea? I can start a grill session." — one line, wait for yes/no.
3. Run `gh issue list --state open --search "<keywords>"` to check for duplicates. If a matching open issue exists, surface it and stop.
4. If no duplicate: proceed to Stage 1.

**Hook gate:** A `UserPromptSubmit` hook injects a nudge prompting the foreman to check for ideas and trigger grilling. This is one of the two hook-enforced gates.

---

## Stage 1 — Issue Maturation (shaping)

**Skills:** `grill-with-docs` (= `grilling` + `mattpocock-skills:domain-modeling`), `superpowers:brainstorming`, `pm-execution:job-stories` or `pm-execution:write-stories`

**Conditional (P0/P1 or area:auth/area:data):** `pm-execution:pre-mortem`, `pm-execution:test-scenarios`

1. Auto-trigger `grill-with-docs` — relentless interview until frontier is empty.
2. `superpowers:brainstorming` for exploring approaches during shaping.
3. Outputs:
   - Spec file: `docs/adr/<issue-slug>.md` (committed to repo)
   - GitHub issue body with ACs in "when I do X, I see Y" form
4. Story routing:
   - User-facing features → `pm-execution:job-stories`
   - Internal/infra → `pm-execution:write-stories`
   - No PRD unless PO explicitly requests one
5. For P0/P1 or area:auth/area:data: run `pm-execution:pre-mortem` + `pm-execution:test-scenarios` before issue creation.
6. Apply labels: `ready`, `P<n>`, `area:<x>`, `type:<x>`.
7. `gh issue create` with final ACs in body.

---

## Stage 2 — Lane start

**Skills:** `mattpocock-skills:writing-for-agents`, `superpowers:writing-plans` (conditional)

1. Run `mattpocock-skills:writing-for-agents` → produces the Lane Brief from the grilled spec + user stories.
2. **Conditional** (complex issues: schema changes, new subsystems, multi-domain, P0/P1): run `superpowers:writing-plans` to produce a step-by-step implementation plan before the lane starts.
3. Create worktree and branch:
   ```bash
   scripts/lane start <issue> <slug>
   ```
4. Open worker pane via Rex:
   ```bash
   rex split -s "$REX_SESSION" --split=right -- bash -c "cd .worktrees/<issue>-<slug> && claude"
   ```
5. Pass the Lane Brief as the lane's opening prompt.
6. Stay as foreman. Never write code or edit source in this session.

**Up to 3 parallel lanes.** Lanes must have no shared `area:*` labels.

---

## Stage 3 — Active implementation (inside the lane)

**Skills (auto in lane):** `mattpocock-skills:tdd`, `self-improving-agent`
**Skills (on blocked):** `superpowers:systematic-debugging`, `mattpocock-skills:diagnosing-bugs`

The lane runs independently:

1. Reads Lane Brief + plan → starts TDD cycle (Red → Green → Refactor → Verify).
2. `self-improving-agent` runs automatically, capturing errors and learnings to `.learnings/LEARNINGS.md` and `ERRORS.md`.
3. If a stop condition is hit (schema change needed, missing AC, test outside diff): lane stops and fires a block signal.
4. Foreman monitors all active Rex panes for block signals. On block: reads reason, escalates to PO, relays resolution back to lane.
5. When complete: lane runs `superpowers:finishing-a-development-branch` + `superpowers:verification-before-completion` (type-check, lint, vitest, build).
6. Lane fires `handoff` skill → structured signal to foreman.

**Foreman during implementation:** watch all active panes via Rex for block signals. Never interrupt a lane that's running cleanly.

---

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

---

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

---

## Stage 6 — Merge and rebase

1. Open PR (draft if still fixing, ready when clean):
   ```bash
   gh pr create --title "..." --body "Closes #<issue>\n\n<summary>" --draft
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

4. **Merge order:** first-green-merges-first (GitHub races). For truly independent lanes, order doesn't matter. Rebase-and-retry handles rare file collisions.

---

## Stage 7 — Learning capture

**Lane writes:**
- `docs/ai/learnings/<issue>.md` — title + one-sentence learning + PR number (per AGENTS.md)
- `.learnings/LEARNINGS.md` + `ERRORS.md` — automated by `self-improving-agent`

**Foreman writes (only if code review forced a fix):**
- TRAP memory file at `~/.claude/projects/<project>/memory/trap_<slug>.md`
- Format: rule + **Why:** + **How to apply:**

Include the learning sentence in the PR body and final issue comment.

---

## Skill bucket routing

The foreman maps `area:*` labels to skill buckets and applies the corresponding skill set for the lane.

### Universal (every lane)
`mattpocock-skills:tdd`, `self-improving-agent`, `mattpocock-skills:code-review`, `pm-ai-shipping:intended-vs-implemented`, `ponytail:ponytail-review`, `superpowers:finishing-a-development-branch`, `superpowers:verification-before-completion`

### Frontend bucket
**Labels:** `area:ui`, `area:map`, `area:dashboard`

Auto: `vercel-react-best-practices`, `vercel-composition-patterns`, `agent-skills:frontend-ui-engineering`, `ui-taste`, `impeccable:impeccable-finish-reviewer`

On-demand: `figma:figma-spec`, `figma:figma-design-to-code`, `image-to-ui`

### Backend bucket
**Labels:** `area:auth`, `area:search`, `area:db`, `area:imports`

Auto: `supabase`, `supabase-postgres-best-practices`, `agent-skills:api-and-interface-design`, `security-audit`, `agent-skills:security-and-hardening`

On-demand: `agent-skills:observability-and-instrumentation`

### Infra bucket
**Labels:** `area:ci`, `area:infra`, `area:pwa`, `area:i18n`, `area:deps`, `area:docs`

Auto: `agent-skills:ci-cd-and-automation`, `cf-cli`

### Dual-bucket labels
`area:providers` and `area:admin` → apply both Frontend and Backend buckets.

---

## Hook configuration

Two new `UserPromptSubmit` hooks to add to `.claude/settings.json`:

**Hook 1 — Idea detection gate:**
```json
{
  "event": "UserPromptSubmit",
  "hook": "scripts/hooks/idea-detection-nudge.sh",
  "description": "Nudges foreman to check for new ideas and trigger grill-with-docs"
}
```
Injects: "If the user's message describes a gap, problem, or desired behaviour, check for duplicates and trigger grill-with-docs before responding."

**Hook 2 — Code review gate:**
```json
{
  "event": "UserPromptSubmit",
  "hook": "scripts/hooks/review-dispatch-nudge.sh",
  "description": "Nudges foreman to dispatch code review subagents after checkpoint approval"
}
```
Injects: "If the user just approved a checkpoint (positive reply after localhost verification), dispatch all code review subagents before opening the PR."

Both hooks are non-blocking (inject context, don't block tool use).

---

## Skills to install

Run once per project:

```bash
claude skill add handoff
claude skill add ui-taste
claude skill add image-to-ui
claude skill add vercel-react-best-practices
claude skill add vercel-composition-patterns
claude skill add cf-cli
```

---

## Per-project config block

Add to `AGENTS.md` in each downstream project:

```markdown
## Foreman config

- **GitHub repo:** `<owner>/<repo>`
- **Lane script:** `scripts/lane start <issue> <slug>`
- **Skill buckets:** see `docs/agents/skills.md`
- **Project-specific auto-skills:** supabase (all backend lanes), next-intl (area:i18n)
- **Issue labels:** see `docs/agents/triage-labels.md`
- **Max parallel lanes:** 3 (no shared area:* labels)
```

---

## Files changed by this design

In `po-multi-agent-workflow`:
- `docs/agents/foreman.md` — full rewrite (Herdr/Devin → Rex + Claude Code)
- `docs/agents/skills.md` — add PM shaping skills, grilling trigger, bucket routing, TRAP flow, Figma/UI on-demand, new installs
- `.claude/settings.json` — add two new UserPromptSubmit hooks
- `GLOSSARY.md` — ✅ committed
- `docs/adr/0001–0003` — ✅ committed

Downstream (after `scripts/sync-workflow.sh`):
- `uflow` gets updated `foreman.md`, `skills.md`, settings hooks
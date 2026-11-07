# Skills

Every agent reads this table before acting. Skills fire automatically unless marked **on demand**.

Install all skills globally: `npx skills add <repo> --global`

| Package                        | Install command                                        |
| ------------------------------ | ------------------------------------------------------ |
| `obra/superpowers`             | `npx skills add obra/superpowers --global`             |
| `mattpocock/skills`            | `npx skills add mattpocock/skills --global`            |
| `phuryn/pm-skills`             | `npx skills add phuryn/pm-skills --global`             |
| `pskoett/self-improving-agent` | `npx skills add pskoett/self-improving-agent --global` |
| `supabase/agent-skills`        | `npx skills add supabase/agent-skills --global`        |
| `anthropics/skills`            | `npx skills add anthropics/skills --global`            |
| `impeccable`                   | `claude plugin install impeccable` (Claude Code only)  |
| `security-audit`               | included in `obra/superpowers`                         |

## Idea shaping (Stage 1 — Issue Maturation)

Auto-trigger `grill-with-docs` whenever intent is detected (gap, problem, or desired behaviour). Do not skip this for fuzzy requests — the grill produces the ACs the lane needs.

| When                                                            | Skill                                                              | Output                                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Any detected intent (feature/change/gap)                        | `grill-with-docs` (mattpocock-skills grilling + domain-modeling)   | `CONTEXT.md` + `docs/adr/<issue-slug>.md` — auto-triggered on intent detection  |
| Exploring approaches during shaping                             | `superpowers:brainstorming`                                        | Approach options before committing to a direction                               |
| User-facing feature                                             | `pm-execution:job-stories`                                         | Job stories for issue body ACs                                                  |
| Internal / infra change                                         | `pm-execution:write-stories`                                       | Dev-oriented stories for issue body ACs                                         |
| P0/P1 issues or `area:auth` / `area:db`                         | `pm-execution:pre-mortem` + `pm-execution:test-scenarios`          | Risk analysis + scenario list — run before `gh issue create`                    |

Skip shaping for confirmed bugs with a clear reproduction — go straight to lane start.

## Lane start (Stage 2)

| When                                                                | Skill                                           | Notes                                                                |
| ------------------------------------------------------------------- | ----------------------------------------------- | -------------------------------------------------------------------- |
| Every lane (before Rex split)                                       | `mattpocock-skills:writing-for-agents`          | Auto. Produces the Lane Brief from the grilled spec + user stories.  |
| Complex issues: schema changes, new subsystems, multi-domain, P0/P1 | `superpowers:writing-plans`                     | Conditional. Step-by-step implementation plan before lane starts.    |
| Every feature lane                                                  | `mattpocock-skills:tdd`                         | Auto. Drives Red → Green → Refactor.                                 |
| Any Supabase/Postgres work                                          | `supabase` + `supabase-postgres-best-practices` | Auto. Load before writing any DB code, schema change, or RLS policy. |

## Lane running (Stage 3)

| When                                                | Skill                  | Notes                                                                                                                                                            |
| --------------------------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Command fails, API errors, user corrects assumption | `self-improving-agent` | Auto. Writes to `.learnings/LEARNINGS.md`, `ERRORS.md`, `FEATURE_REQUESTS.md`. Promotion to `AGENTS.md` requires owner approval — never edit this file directly. |

## Checkpoint / Handoff (Stage 4)

| When                            | Action                                                                                                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lane finishes implementation    | Lane fires `handoff` skill — structured signal to foreman.                                                                                          |
| Foreman receives handoff signal | Open Rex dev-server pane: `rex split -s "$REX_SESSION" --split=bottom -- bash -c "cd .worktrees/<issue>-<slug> && npm run dev"` |

PO verifies on localhost. Any positive reply ("looks good", "ship it", "yes", "approved") proceeds to code review.

## Review (Stage 5)

| When                                      | Skill                                    | Notes                                                                       |
| ----------------------------------------- | ---------------------------------------- | --------------------------------------------------------------------------- |
| Every PR (runs first)                     | `pm-ai-shipping:intended-vs-implemented` | Auto. Did the lane build what the issue asked?                              |
| Every PR                                  | `impeccable`                             | Auto. Code quality pass.                                                    |
| Every PR                                  | `mattpocock-skills:code-review`          | Auto. Standards + spec, two-axis.                                           |
| Every PR                                  | `security-audit`                         | Auto. Run in addition to the above.                                         |
| Every PR                                  | `pm-ai-shipping:security-audit-static`   | Static security analysis — runs alongside security-audit |
| Frontend / UI lanes                       | `ui-taste`                               | Auto for `area:ui`, `area:map`, `area:dashboard`. Aesthetic and UX quality. |
| Frontend / UI lanes                       | `impeccable:impeccable-finish-reviewer`  | Auto for Frontend lanes. Correctness and completeness.                      |

Dispatch all reviewers in parallel as subagents (Agent tool, fresh context, scoped to the diff). Wait for all results before opening the PR.

**PR creation note:** Stage 6 always opens PRs as `--draft`. Run `gh pr ready <pr>` to un-draft once the lane is clean and all review fixes are applied.

## Skill bucket routing

The foreman maps `area:*` labels to skill buckets and applies the corresponding skill set for the lane.

### Universal (every lane)

`mattpocock-skills:tdd`, `self-improving-agent`, `mattpocock-skills:code-review`, `pm-ai-shipping:intended-vs-implemented`, `ponytail:ponytail-review`, `superpowers:finishing-a-development-branch`, `superpowers:verification-before-completion`

### Frontend bucket

**Labels:** `area:ui`, `area:map`, `area:dashboard`, `area:providers`, `area:admin`

| Mode      | Skills                                                                                                                                                       |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Auto      | `vercel-react-best-practices`, `vercel-composition-patterns`, `agent-skills:frontend-ui-engineering`, `ui-taste`, `impeccable:impeccable-finish-reviewer` |
| On demand | `figma:figma-spec`, `figma:figma-design-to-code`, `image-to-ui`                                                                                              |

### Backend bucket

**Labels:** `area:auth`, `area:search`, `area:db`, `area:imports`, `area:providers`, `area:admin`

| Mode      | Skills                                                                                                                                       |
| --------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Auto      | `supabase`, `supabase-postgres-best-practices`, `agent-skills:api-and-interface-design`, `security-audit`, `agent-skills:security-and-hardening` |
| On demand | `agent-skills:observability-and-instrumentation`                                                                                             |

### Infra bucket

**Labels:** `area:ci`, `area:infra`, `area:pwa`, `area:i18n`, `area:deps`, `area:docs`

| Mode | Skills                                        |
| ---- | --------------------------------------------- |
| Auto | `agent-skills:ci-cd-and-automation`, `cf-cli` |

### Dual-bucket labels

`area:providers` and `area:admin` appear in both Frontend and Backend buckets above — lanes with these labels apply both skill sets.

## Learning / TRAP flow (Stage 7)

**Lane writes (every lane):**
- `docs/ai/learnings/<issue>.md` — title + one-sentence learning + PR number
- `.learnings/LEARNINGS.md` + `ERRORS.md` — automated by `self-improving-agent`

**Foreman writes (only if code review forced a fix):**
- TRAP memory file at `~/.claude/projects/<project>/memory/trap_<slug>.md`
- Format: rule + **Why:** + **How to apply:**

Include the learning sentence in the PR body and the final issue comment.

## Skills to install (run once per project)

```bash
claude skill add handoff
claude skill add ui-taste
claude skill add image-to-ui
claude skill add vercel-react-best-practices
claude skill add vercel-composition-patterns
claude skill add cf-cli
```

## Fallback: request does not fit a known stage

If no skill in this table clearly covers the request:

1. Run `/ask-matt` (mattpocock-skills) — maps any engineering or product request to the right skill in the flow.
2. If `/ask-matt` does not match, run `/using-agent-skills` (obra/superpowers) — discovers the right skill across the full superpowers catalog.
3. If neither finds a match, the domain is outside the installed skill set. Stop, surface the gap to the owner, and do not improvise.

## Strategy docs (on demand)

Run when you need current strategic context. Output goes to `docs/strategy/<skill-name>.md` so all agents can reference it.

Available: `/gtm-strategy`, `/product-strategy`, `/competitor-analysis`, `/positioning-ideas`, `/swot-analysis`, `/lean-canvas`, `/market-sizing`, `/product-vision`.
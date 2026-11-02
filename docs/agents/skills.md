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

## Idea shaping (before triage)

| When                                        | Skill                                  | Output                                                                 |
| ------------------------------------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| New feature or cross-cutting change (fuzzy) | `/grill-with-docs` (mattpocock-skills) | `CONTEXT.md` + `docs/adr/` — settles decisions before the issue exists |
| Any new issue body needed                   | `/pm-brief` (pm-skills)                | Structured issue body: user story, AC, definition of done              |

Skip `/grill-with-docs` for bugs and chores — go straight to `/pm-brief`.

## Lane start

| When                       | Skill                                           | Notes                                                                |
| -------------------------- | ----------------------------------------------- | -------------------------------------------------------------------- |
| Every feature lane         | `mattpocock-skills:tdd`                         | Auto. Drives Red → Green → Refactor.                                 |
| Any Supabase/Postgres work | `supabase` + `supabase-postgres-best-practices` | Auto. Load before writing any DB code, schema change, or RLS policy. |

## Lane running

| When                                                | Skill                  | Notes                                                                                                                                                            |
| --------------------------------------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Command fails, API errors, user corrects assumption | `self-improving-agent` | Auto. Writes to `.learnings/LEARNINGS.md`, `ERRORS.md`, `FEATURE_REQUESTS.md`. Promotion to `AGENTS.md` requires owner approval — never edit this file directly. |

## Review

| When                                      | Skill                           | Notes                                           |
| ----------------------------------------- | ------------------------------- | ----------------------------------------------- |
| Every PR                                  | `impeccable`                    | Auto. Code quality pass.                        |
| Every PR                                  | `mattpocock-skills:code-review` | Auto. Standards + spec, two-axis.               |
| PRs touching auth, payments, or user data | `security-audit`                | Auto, scoped. Run in addition to the two above. |

## Fallback: request doesn't fit a known stage

If no skill in this table clearly covers the request:

1. Run `/ask-matt` (mattpocock-skills) — maps any engineering or product request to the right skill in the flow.
2. If `/ask-matt` doesn't match, run `/using-agent-skills` (obra/superpowers) — discovers the right skill across the full superpowers catalog.
3. If neither finds a match, the domain is outside the installed skill set. Stop, surface the gap to the owner, and do not improvise.

## Strategy docs (on demand)

Run when you need current strategic context. Output goes to `docs/strategy/<skill-name>.md` so all agents can reference it.

Available: `/gtm-strategy`, `/product-strategy`, `/competitor-analysis`, `/positioning-ideas`, `/swot-analysis`, `/lean-canvas`, `/market-sizing`, `/product-vision`.

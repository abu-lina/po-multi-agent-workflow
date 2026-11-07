# PO Foreman Workflow

Vocabulary for the multi-agent development workflow where a Product Owner acts as foreman, coordinating implementation lanes without writing code directly.

## Language

**Foreman**:
The Claude Code session running in the main checkout. Coordinates all active lanes, never writes product code. Triggered by the PO raising an idea or issue.
_Avoid_: Coordinator, orchestrator, main agent

**Lane**:
A single-issue work unit combining one worktree at `.worktrees/<issue>-<slug>/`, one git branch (`<type>/<issue>-<slug>`), and one Claude Code session. Created per issue, deleted after merge.
_Avoid_: Worker, agent, branch (a branch is a component of a lane, not the lane itself)

**Issue Maturation**:
The process of shaping a rough idea into a GitHub Issue with acceptance criteria in "when I do X, I see Y" form and a `ready` label. Comprises duplicate check, Grilling Session, story writing, and risk assessment.
_Avoid_: Backlog refinement, ticket creation, shaping

**Grilling Session**:
The structured interview between the PO and foreman that extracts precise requirements from a rough idea. One step within Issue Maturation. Produces a spec file and issue body. Run via the `grill-with-docs` skill.
_Avoid_: Discovery, requirements gathering

**Lane Brief**:
The agent-facing instructions produced by `mattpocock-skills:writing-for-agents` before a lane starts. Distils the grilled spec and user stories into a crisp opening prompt for the lane agent.
_Avoid_: Prompt, task description, instructions

**Skill Bucket**:
One of three routing categories — Frontend, Backend, or Infra — that determines which skills auto-trigger for a lane. Derived from the issue's `area:*` label.
_Avoid_: Work type, category, domain type

**Handoff**:
The structured signal sent by a lane to the foreman when implementation is complete and all four verification checks pass. Produced by the `handoff` skill. Triggers the Checkpoint.
_Avoid_: Done signal, completion message, status update

**Checkpoint**:
The stage where the PO verifies the lane's work on localhost. Triggered by a Handoff. The foreman pre-opens a Rex pane with the dev server running. Ends when the PO sends a positive reply.
_Avoid_: Demo, sign-off, review (review refers to code review, not PO localhost verification)

**Code Review Stage**:
The parallel-subagent step that runs after the Checkpoint. Distinct reviewers check intent (`pm-ai-shipping:intended-vs-implemented`), quality (`mattpocock-skills:code-review`), security (`security-audit`), and minimalism (`ponytail:ponytail-review`). UI lanes also run `ui-taste`.
_Avoid_: Review (too broad — review in AGENTS.md means the full PR lifecycle)

**Learning**:
A short record of an unexpected fix or insight captured at the end of a lane. Stored as `docs/ai/learnings/<issue>.md` (title + one-sentence lesson + PR number). Written by the lane.
_Avoid_: Retrospective, note, finding

**TRAP**:
A learning severe enough to prevent recurrence in future sessions. Written by the foreman to persistent memory when code review forces a fix. Format: rule, Why, How to apply.
_Avoid_: Warning, alert, blocker (a TRAP is a remembered lesson, not a live obstacle)

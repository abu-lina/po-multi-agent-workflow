# Supported lane agents

A lane is any AI coding agent running inside a `.worktrees/<issue>-<slug>/` checkout, following `docs/agents/lane.md`. Two agents are tested and supported:

- **Claude Code** (`claude` CLI) — Anthropic's coding agent.
- **Copilot CLI** (`gh copilot`, via `copilot` wrapper) — GitHub's coding agent.

Both follow the same lane workflow. The table below documents where they diverge.

## Capability comparison

| Lane step / feature        | Claude Code                                        | Copilot CLI (`-p` / `--prompt`)                    |
|----------------------------|----------------------------------------------------|-----------------------------------------------------|
| **Non-interactive mode**   | `claude -p "<prompt>"` — runs headless, exits on completion | `gh copilot suggest -t shell "<prompt>"` or `copilot -p "<prompt>"` with the wrapper — same headless contract |
| **Interactive mode**       | `claude` (REPL)                                    | `gh copilot suggest` / `gh copilot explain` (interactive) |
| **Hooks**                  | Native: `UserPromptSubmit`, `Stop`, `PreToolCall`, `PostToolCall` hooks in `settings.json`. Fires on every session event. | No native hook system. Hook-equivalent behavior must be scripted outside the agent (e.g. a wrapper that runs pre/post steps). |
| **Skills**                 | Native: `claude skills add <repo>` loads `.claude/skills/` into context. Skill invocation via `Skill` tool. | No native skill system. Skills must be inlined into the prompt or loaded from a prompt file. |
| **Rex / Herdr integration**| Full: Rex panes start `claude -p` or `claude` in the worktree. Herdr tracks workspace state via `Stop` hook writing `.lane-signal`. | Partial: Rex panes can run `copilot -p` in the worktree. `.lane-signal` must be written by a wrapper script, not by a hook. |
| **Git / GH tools**         | Built-in: `Bash`, `Edit`, `Write`, `Read`, plus `gh` via Bash. Full file-system access. | Built-in: file edits and shell commands via `gh copilot suggest`. Same `gh` CLI access. |
| **Permission model**       | Per-tool allow/deny in `settings.json`. Explicit denies for merge, push-to-main, rebase. | Per-session flags (`--allow-runs`, etc.). No persistent per-tool deny list. |
| **Reasoning effort**       | Model-level (Opus / Sonnet / Haiku). No per-call effort flag. | `--reasoning-effort low\|medium\|high` per invocation (Auto model only). |
| **Sandbox**                | `--sandbox` flag available; `accept-edits` mode for Devin lanes. | No equivalent sandbox flag. Rely on worktree isolation. |
| **Stop / handoff signal**  | `Stop` hook writes `.lane-signal` automatically.   | Wrapper script must `echo "done: ..."  > .lane-signal` after the agent exits. |

## Fallback patterns for Copilot lanes

When a feature is native in Claude Code but absent in Copilot CLI, use the following:

**Hooks** — Write a wrapper script (`scripts/copilot-lane`) that runs pre-steps, invokes `gh copilot suggest -t shell -p "$PROMPT"`, then runs post-steps. The wrapper is the hook.

**Skills** — Prepend skill content to the prompt file, or `cat` the skill markdown into the `-p` argument before the task description.

**Lane signal** — Add `echo "done: $ISSUE" > .lane-signal` as the last line of the wrapper script.

**Rex integration** — Rex opens the wrapper (`scripts/copilot-lane <issue>`) in the worktree pane instead of `claude -p`. The foreman reads `.lane-signal` the same way.

## Choosing an agent

Both agents can run any lane. The practical differences:

- Hooks and skills have no native fallback in Copilot. If your lane relies heavily on auto-triggered skills (e.g. `grill-with-docs`, `self-improving-agent`), Claude Code avoids wrapper complexity.
- Reasoning effort is only tunable per-call in Copilot. For complex refactors or P0 issues, Copilot's `--reasoning-effort high` can be more direct than switching Claude models.
- Either agent can be used; the foreman specifies which in the lane brief.

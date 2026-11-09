# Supported lane agents

A lane is any AI coding agent running inside a `.worktrees/<issue>-<slug>/` checkout, following `docs/agents/lane.md`. Two agents are tested and supported:

- **Claude Code** (`claude` CLI) — Anthropic's coding agent.
- **Copilot CLI** (`gh copilot`, via `copilot` wrapper) — GitHub's coding agent.

Both follow the same lane workflow. The table below documents where they diverge.

## Capability comparison

| Lane step / feature        | Claude Code                                        | Copilot CLI                                         |
|----------------------------|----------------------------------------------------|-----------------------------------------------------|
| **Non-interactive mode**   | `claude -p "<prompt>"` — runs headless, exits on completion | Requires a `copilot` wrapper script. `gh copilot suggest` is interactive and prompts for user confirmation; headless execution depends on the wrapper. |
| **Interactive mode**       | `claude` (REPL)                                    | `gh copilot suggest` / `gh copilot explain`         |
| **Hooks**                  | Native: `UserPromptSubmit`, `Stop`, `PreToolCall`, `PostToolCall` hooks in `settings.json`. Fires on every session event. | No native hook system. Hook-equivalent behavior must be scripted outside the agent (e.g. a wrapper that runs pre/post steps). |
| **Skills**                 | Native: skills loaded from `.claude/skills/` via the `Skill` tool. | No native skill system. Skills must be inlined into the prompt or loaded from a prompt file. |
| **Rex integration**        | Full: Rex panes start `claude -p` or `claude` in the worktree. Lane state is tracked via `Stop` hook writing `.lane-signal`. | Partial: Rex panes run the `copilot` wrapper in the worktree. `.lane-signal` must be written by the wrapper script. |
| **Git / GH tools**         | Built-in: `Bash`, `Edit`, `Write`, `Read`, plus `gh` via Bash. Full file-system access. | Built-in: file edits and shell commands via `gh copilot suggest`. Same `gh` CLI access. |
| **Permission model**       | Per-tool allow/deny in `settings.json`. Explicit denies for merge, push-to-main, rebase. | Per-session flags (`--allow-runs`, etc.). No persistent per-tool deny list. |
| **Reasoning effort**       | Model-level (Opus / Sonnet / Haiku). No per-call effort flag. | `--reasoning-effort low\|medium\|high` per invocation (Auto model only). |
| **Stop / handoff signal**  | `Stop` hook writes `.lane-signal` automatically.   | Wrapper script must `echo "done: ..." > .lane-signal` after the agent exits. |

## Fallback patterns for Copilot lanes

When a feature is native in Claude Code but absent in Copilot CLI, use the following:

**Hooks** — Write a wrapper script (`scripts/copilot-lane`) that runs pre-steps, invokes `gh copilot suggest --target shell --prompt "$PROMPT"`, then runs post-steps. The wrapper is the hook.

**Skills** — Prepend skill content to the prompt file, or `cat` the skill markdown into the `--prompt` argument before the task description.

**Lane signal** — Add `echo "done: $ISSUE" > .lane-signal` as the last line of the wrapper script.

**Rex integration** — Rex opens the wrapper (`scripts/copilot-lane <issue>`) in the worktree pane instead of `claude -p`. The foreman reads `.lane-signal` the same way.


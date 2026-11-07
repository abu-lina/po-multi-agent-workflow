# Auto-merge on PR creation via GitHub's native auto-merge

AGENTS.md rule 5 says "the owner merges, one PR at a time." For the foreman workflow, we deviate: when the foreman creates a PR, it immediately sets `gh pr merge --auto --squash`. GitHub queues the merge and executes it when all required status checks pass.

We chose this over manual merge because the PO's role ends at the Checkpoint (localhost verification). After that, merge is a mechanical step — wait for CI, merge — which an agent watching a pane handles worse than GitHub's native mechanism. The `--auto` flag means no agent needs to stay alive.

The AGENTS.md rule was written for lane agents, who must not merge their own work without review. The foreman, acting for the PO, is the owner — setting auto-merge at PR creation is the owner delegating to the platform, not an agent bypassing the rule.

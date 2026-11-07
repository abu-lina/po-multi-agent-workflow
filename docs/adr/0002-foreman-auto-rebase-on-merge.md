# Foreman auto-rebases remaining lanes after each merge

AGENTS.md rule 5 prohibits rebase unless the owner asks in the session. For the foreman workflow with up to 3 parallel lanes, we deviate: when one lane merges, the foreman immediately runs `git fetch origin main && git rebase origin/main` in every other active lane's worktree.

Without this, parallel lanes accumulate rebase debt. The longer the gap, the more likely a conflict-heavy rebase at PR time. The foreman doing it immediately after each merge keeps the gap small and conflicts rare.

Edge case: if a lane is at Checkpoint (PO verifying on localhost) when another lane merges, the foreman applies the rebase but warns the PO that the running localhost is now stale and re-verification is needed before approving.

This rebase is implicitly authorized by the PO starting 3 parallel lanes — the merge ordering and its rebase consequences are a known feature of parallel work, not an unexpected action.

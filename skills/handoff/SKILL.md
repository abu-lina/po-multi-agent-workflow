# Handoff

You are completing a development lane. Follow these steps in order.

1. Invoke `superpowers:finishing-a-development-branch`.
2. Invoke `superpowers:verification-before-completion` and confirm all four checks pass (type-check, lint, vitest, build).
3. If any check fails: fix the issue and repeat from step 2. Do not signal until all checks pass.
4. Write the signal file:
   ```bash
   printf 'handoff: %s' "<one-line summary of what was built>" > .lane-signal
   ```
   The summary is one sentence: what was built, not how.
5. Output a formatted summary to chat so the foreman can relay it to the PO.

The Stop hook delivers the signal to the foreman's pane automatically when this session ends.

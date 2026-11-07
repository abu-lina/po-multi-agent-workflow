# Structured lane-to-foreman handoff via `handoff` skill

When a lane completes implementation, it fires a structured handoff signal via the `handoff` skill rather than sending a free-text message or relying on the foreman to poll its Rex pane.

With up to 3 parallel lanes, the foreman needs to reliably distinguish "ready for Checkpoint" from incidental terminal output (lint warnings, test results, build logs). A structured handoff gives the foreman a parseable signal it can act on without false positives. Free-text "I'm done" messages are ambiguous across lanes; Rex pane polling can miss signals if the pane scrolls or the session sleeps.

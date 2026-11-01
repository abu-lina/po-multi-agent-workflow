# Diagnosing Bugs: tight feedback loop first

A discipline for hard bugs — the ones that resist a first glance, flake intermittently, or regressed between two known-good states. Skip phases only when explicitly justified.

Read `CONTEXT.md` (if it exists) for the domain model before exploring the codebase.

**Redact everything.** Before showing any command output or captured artifact, replace secrets and tokens with `<REDACTED>`. Build loops against environment variables so credentials stay out of what you show.

## Phase 1: Build a feedback loop

**This is the skill.** Everything else is mechanical. Spend disproportionate effort here. Do not proceed to Phase 2 without a tight, red-capable loop.

Build one loop in this order:

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
3. **HTTP script** (`curl` / Playwright) against a running dev server.
4. **Replay a captured trace** — save a real request/payload/event log and replay it in isolation.
5. **Throwaway harness** — minimal subset of the system, one service, mocked deps.
6. **Property / fuzz loop** — if the bug is "sometimes wrong output", run 1000 random inputs.
7. **Bisection harness** — `git bisect run` between two known-good states.

Once you have a loop, **tighten it**:

- Can it run faster? (Narrow scope, skip unrelated init.)
- Is the signal sharp? (Assert on the specific symptom, not "didn't crash".)
- Is it deterministic? (Pin time, seed RNG, isolate filesystem, freeze network.)

A 30-second flaky loop is barely better than none. A 2-second deterministic one is a debugging superpower.

**Non-deterministic bugs**: loop the trigger 100×, parallelise, inject sleeps, narrow timing windows. A 50%-flake is debuggable; 1% is not — keep raising the rate.

**If you cannot build a loop**, stop and say so explicitly. List what you tried. Ask for: (a) access to the reproducing environment, (b) a redacted artifact (HAR, log dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** theorise without a loop.

### Completion criterion

Phase 1 is done when you can name **one command** that:

- [ ] Goes red on this bug's exact symptom (not just "crashes")
- [ ] Is deterministic across runs
- [ ] Runs in seconds
- [ ] Can be run unattended

Show the invocation and its output (redacted) before moving to Phase 2.

## Phase 2: Reproduce and minimise

Run the loop. Confirm:

- [ ] The failure matches what the reporter described, not an adjacent failure
- [ ] It reproduces consistently (or at a high enough rate for non-deterministic bugs)
- [ ] You have captured the exact symptom

Then **minimise**: remove inputs, callers, config, and steps one at a time, re-running after each cut. Keep only what is load-bearing. Every remaining element must be necessary to trigger the failure.

Do not proceed until reproduced **and** minimised.

## Phase 3: Hypothesise

Generate **3–5 ranked hypotheses** before testing any. Each must be falsifiable:

> "If X is the cause, then changing Y will make the bug disappear / changing Z will make it worse."

Show the ranked list to the owner before testing — they often have domain knowledge that re-ranks instantly or can rule out hypotheses already tried.

## Phase 4: Instrument

Each probe must map to a specific prediction from Phase 3. Change one variable at a time.

- Prefer a debugger or REPL over logs.
- Use targeted logs at boundaries that distinguish hypotheses.
- Tag every debug log with a unique prefix (`[DEBUG-a4f2]`). Remove all tagged logs in Phase 6.
- For performance regressions: establish a baseline measurement first, then bisect. Never guess at perf.

## Phase 5: Fix and regression test

Write the regression test **before the fix**, but only if there is a **correct seam** — one where the test exercises the real bug pattern at the call site. A unit test that can't replicate the chain that triggered the bug gives false confidence.

If no correct seam exists, that is the finding: the architecture is preventing the bug from being locked down. Note it and flag it to the owner.

If a seam exists:

1. Turn the minimised repro into a failing test.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the Phase 1 loop against the original (un-minimised) scenario.

## Phase 6: Cleanup

Before declaring done:

- [ ] Original repro no longer reproduces (re-run Phase 1 loop)
- [ ] Regression test passes (or absence of seam is documented in the PR)
- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)
- [ ] Throwaway harnesses deleted
- [ ] The root cause is stated in the commit or PR message

## Handoff to triage

When Phase 5 reveals that no correct seam exists, hand back to the foreman: post an issue comment describing the missing seam and what architectural change would create one. The foreman routes this as a new `enhancement` issue through triage (`docs/agents/triage.md`) before any follow-on lane is proposed.

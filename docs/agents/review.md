# Review

A review runs automatically when a lane reports done; the owner doesn't start it. Reviews run as parallel subagents with the `reviewer` profile (`.devin/agents/reviewer.md`), one per role, against a single PR. The profile has `read`, `grep` and `glob` only: no exec, write or edit, so a reviewer can't comment, label, push or merge.

Reviewers can't run `gh pr diff`. The foreman runs `scripts/review-bundle <pr>` once. It prints the path of a bundle file holding the diff, the issue's acceptance criteria and the PR-head content of every touched file. Each reviewer reads that file and only the files the diff touches plus their direct imports, and returns a list of findings in the format below. The foreman (or whoever triggered the review) merges them.

Real secrets must never be in a checkout the foreman runs in.

The foreman asks the owner only for decisions, and every decision request includes a recommendation.

Parallel subagents are for review only. Implementation is one agent per lane.

## Roles

### 1. Security and authorization

Checklist:

- Every new or changed API route and server action checks auth, and the check matches the data it returns (user-scoped vs admin).
- Database queries apply proper authorization for user requests; service-role or admin clients appear only in server-side modules.
- Input from the request (body, params, search params, headers) is validated before use; no string-built SQL or raw interpolation of user input into queries.
- No secrets, tokens or raw emails in logs or error responses.
- Rate limiting is present on any endpoint that can be enumerated (login, signup, email check).
- New dependencies: purpose stated, no known advisories (check with your package manager's audit command).

### 2. Tests versus acceptance criteria

Checklist:

- Each acceptance criterion maps to at least one test by name; list any criterion with no test.
- The first commit on the branch contains tests only and they failed before the implementation (`git log --reverse --stat`).
- Tests assert behaviour, not implementation (no snapshot of internal state, no mocking the unit under test).
- Regression tests hit the actual bug path, not an adjacent happy path.
- No skipped tests added; no widened timeouts without a reason.
- Coverage of new branches (error, empty, loading states) exists.

<!-- EXTEND: add project-specific review roles below -->
<!-- Example role 3: framework-specific concerns (server/client split, caching, runtime) -->
<!-- Example role 4: code structure (domain placement, reuse of helpers, naming conventions, i18n) -->

## Finding format

One line per finding, no prose around it:

```
<severity> | <file>:<line> | <what is wrong> | <what to do instead>
```

Severity:

- **blocking**: security hole, missing auth, acceptance criterion with no test, data loss, build or type error.
- **should-fix**: wrong caching, duplicated helper, test that doesn't test the bug, missing error/empty state.
- **nit**: naming, ordering, comment wording, formatting the linter didn't catch.

## Merge step

1. Concatenate the reviewer lists.
2. Deduplicate by `<file>:<line>`; keep the highest severity and the clearest wording.
3. Sort: blocking, should-fix, nit. Within a group, by file.
4. Post as one PR review:

```bash
gh pr review <pr> --comment --body-file review.md     # blocking present: --request-changes
```

5. Tell the lane which items to address. Blocking and should-fix must be fixed or argued down in a reply before the PR is marked ready. Nits are the owner's call.

## Reviewer rules

- Read only the bundle and the diff's direct dependencies. Don't review the whole codebase.
- Don't propose rewrites or new features. Findings point at lines in the diff.
- If a checklist item needs information you don't have, say so as a `should-fix` with "verify" in the action column instead of guessing.
- Return nothing but the finding lines. The merger needs no summary.

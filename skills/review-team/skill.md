---
name: review-team
description: "Code Review Jury — spawns Claude and Codex subagents to review a GitHub PR, debate findings, and produce a consolidated report"
user_invocable: true
arguments:
  - name: pr_url
    description: "GitHub PR URL (e.g. https://github.com/owner/repo/pull/123)"
    required: true
---

The user has provided a GitHub PR to review: `$ARGUMENTS.pr_url`

## 1. Gather rich PR context

Run these in parallel before spawning any agents:
- `gh pr view <url> --json title,body,author,baseRefName,headRefName,headRepository,state,isDraft,additions,deletions,changedFiles,labels,files,commits` — PR metadata
- `gh pr diff <url>` — the full diff
- `gh pr view <url> --comments` — existing review comments and discussion
- `gh pr checks <url>` — CI status (so reviewers know what's already failing)

Then check out the PR locally so the reviewers can read full file contents, not just the diff hunks:
- `gh pr checkout <url>` (in a clean worktree if the current branch has uncommitted work — use `git worktree add` if needed)
- Capture the base branch name and the merge-base commit so reviewers can run `git diff <base>...HEAD` and `git log <base>..HEAD` for context.

If any linked issues appear in the PR body (e.g. `Fixes #123`), fetch them with `gh issue view` so reviewers understand intent.

## 2. Spawn the review jury

Spawn two teammates **in parallel** (single message, multiple Agent tool calls). Pass each:
- The PR URL
- The PR title, body, and any linked issue context
- The base branch name and merge-base commit (so they can diff/blame locally)
- The list of changed files
- The CI status summary
- An explicit instruction to read the **full files** they're reviewing — not just the diff — and to inspect callers/callees of changed functions

Teammates:
1. **claude-code-reviewer-teammate** — spawn with `model: "opus"` to force the most capable model regardless of the agent's default frontmatter. Tell it to focus on: correctness bugs, security (injection, auth, secrets, unsafe deserialization), data-loss/concurrency risks, error handling, architectural fit, test coverage gaps, and dead/duplicated code.
2. **codex-cli-code-review-teammate** — builds and executes a Codex CLI review. Same focus areas.

Instruct each teammate to return findings as a structured list where every finding has: **severity** (Critical/Important/Suggestion), **file:line**, **category** (security/bug/architecture/style/test), **description**, and **suggested fix**. Structured output makes consolidation reliable.

## 3. Cross-examine

After both initial reviews return, have the teammates debate by sending each one the other's findings and asking them specifically to:
- Identify findings they disagree with and **why** (false positive, missing context, wrong severity)
- Identify findings the other agent missed that they now want to add
- Flag any finding that depends on code not visible in the diff — and verify by reading the actual file

One round of debate is usually enough; do a second only if there's substantive disagreement on a Critical-severity finding.

After debate, ask each teammate to return their **final** finding list, then shut the team down.

## 4. Consolidate

Merge the two final lists:
- Deduplicate findings that point to the same file:line and category (keep the more detailed write-up)
- Where the two reviewers disagree on severity, use the **higher** severity unless the debate produced a clear concession
- Drop findings that the originating reviewer retracted during debate
- Verify any Critical finding by reading the cited file:line yourself before promoting it into the final report — Codex in particular occasionally hallucinates line numbers

Produce the final report grouped by:
1. **Critical** — security issues, bugs, data-loss risks
2. **Important** — architecture, design, correctness concerns
3. **Suggestions** — style, readability, minor improvements

Each entry: `file:line — description. Suggested fix: ...` Cite which reviewer raised it (Claude / Codex / both) so the user can weigh consensus.

## 5. Clean up

Delete the team and remove any temporary worktree created in step 1.

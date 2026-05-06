---
name: review-self
description: "Code Review Jury that posts findings directly to the PR — spawns Claude and Codex subagents to review a GitHub PR, debate findings, and post Critical (🔴) and Important (🟡) issues as PR comments"
user_invocable: true
arguments:
  - name: pr_url
    description: "GitHub PR URL (e.g. https://github.com/owner/repo/pull/123)"
    required: true
---

The user has provided a GitHub PR to review: `$ARGUMENTS.pr_url`

First, fetch the PR diff and metadata using `gh pr view` and `gh pr diff` with the provided URL. Capture the head commit SHA (`gh pr view <url> --json headRefOid`) — you'll need it to post inline review comments.

Then spawn an agent team with 2 teammates outlined below, passing each the PR URL and diff context.
- One teammate using the claude-code-reviewer-teammate type to review the PR changes.
- One teammate using the codex-cli-code-review-teammate type to build and execute a Codex CLI command and capture review output.

Instruct each teammate that for every finding they report they MUST include: severity (Critical / Important / Suggestion), file path, line number (or line range), and a concise actionable comment body. Inline-quotable findings are required for Critical and Important — without a file+line, the finding cannot be posted as an inline review comment.

Have all the teammates talk to each other after initial review to figure out the best review feedback and criticize each other's suggestions.
After they complete the review and debate have them report findings, and then ask them to shut down.
Compare the findings and suggestions reported by all teammates.
Consolidate reviews into a deduplicated list organized by:
1. **Critical** — security issues, bugs, data loss risks
2. **Important** — architecture, design, correctness concerns
3. **Suggestions** — style, readability, minor improvements

## Posting to the PR

Post Critical and Important findings as a single PR review (one API call, batched comments). Do NOT post Suggestions to the PR — include those only in the local report.

Build a JSON payload and submit it via `gh api`:

```bash
gh api -X POST "repos/{owner}/{repo}/pulls/{number}/reviews" \
  -f commit_id="<HEAD_SHA>" \
  -f event="COMMENT" \
  -f body="Automated review-self pass: N critical, M important findings." \
  --input -  # piping the comments array as JSON
```

The `comments` array entries take the form:
```json
{ "path": "src/foo.go", "line": 42, "side": "RIGHT", "body": "🔴 <finding text>" }
```

Annotate each comment body with the severity emoji as the leading character:
- **🔴** — Critical findings
- **🟡** — Important findings

Each comment body should be self-contained: state the issue, why it matters, and the suggested change. Keep it under ~6 lines so the PR thread stays readable.

If a Critical or Important finding lacks a usable file+line anchor, post it as a top-level PR comment instead via `gh pr comment <url> --body "..."`, still prefixed with the severity emoji. Note in the consolidated report which findings fell back to top-level comments.

## After posting

Print a local summary report to the user containing:
1. The full Critical / Important / Suggestions breakdown (Suggestions live here only).
2. The list of comments that were posted to the PR, with their permalinks if available from the API response.
3. Any findings that could not be posted (e.g. missing line anchor) and why.

Finally, clean up the team.

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

First, fetch the PR diff and metadata using `gh pr view` and `gh pr diff` with the provided URL.
Then spawn an agent team with 2 teammates outlined below, passing each the PR URL and diff context.
- One teammate using the claude-code-reviewer-teammate type to review the PR changes.
- One teammate using the codex-cli-code-review-teammate type to build and execute a Codex CLI command and capture review output.
Have all the teammates talk to each other after initial review to figure out the best review feedback to criticize each other's suggestions.
After they complete the review and debate have them report findings, and then ask them to shut down.
Compare the findings and suggestions reported by all teammates.
Consolidate reviews into a comprehensive report with actionable change guidance organized by:
1. **Critical** — security issues, bugs, data loss risks
2. **Important** — architecture, design, correctness concerns
3. **Suggestions** — style, readability, minor improvements

After the guidance is produced - clean up the team.

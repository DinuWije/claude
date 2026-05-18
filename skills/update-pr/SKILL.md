---
name: update-pr
description: Update a PR (or list of PRs / branch) by merging the latest main branch into it. Handles repo-specific main branch names, attempts to resolve conflicts by stacking branch changes on top of main, asks before pushing, and integrates with Graphite if enabled. Use when the user wants to "update", "rebase", "merge main into", or "refresh" a PR or branch.
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion, Agent
user_invocable: true
---

The user wants to update PR(s) or branch(es): $ARGUMENTS

You are updating one or more PRs / branches by merging the latest changes from that repo's main branch. Follow the steps below carefully — the operations are destructive to working tree state, so verify before each step.

## Execution Model: One Subagent Per PR

You (the orchestrator) handle parsing the input (Step 0), resolving main branches (Step 1), and the final user-approval + push steps (Steps 6–8). **For the actual update work (Steps 3–5), spawn one subagent per PR/branch and run them in parallel.**

- **Single PR/branch input** → still spawn one subagent so the work happens in an isolated context. Run it in the foreground; you need its result before asking for push approval.
- **Multiple PRs/branches** → spawn N subagents in a **single message** with multiple `Agent` tool calls so they run concurrently. Each subagent gets its own PR + resolved main branch + Graphite-enabled flag.
- **Isolation:** use `isolation: "worktree"` for each subagent so they don't clobber each other's working tree. This is required when multiple PRs share the same repo. (For PRs in different repos, the worktree flag is still safe — it just creates a worktree off the current repo if applicable, otherwise the subagent clones/cds as instructed.)
- **Naming:** name each subagent `update-pr-<branch>` (sanitize the branch name for tool use) so you can address it via `SendMessage` if you need to follow up.

After all subagents return, consolidate their results, then move to Step 6 (approval) and Step 7 (push) yourself. The orchestrator owns the push — subagents only update locally and report back.

## Step 0: Parse the Input

`$ARGUMENTS` can be one of:

1. **A single GitHub PR URL** (e.g. `https://github.com/owner/repo/pull/123`) — resolve to its head branch.
2. **A list of PR URLs / numbers** — process each one.
3. **A branch name** (e.g. `my-feature-branch`) — operate on the local checkout of that branch in the current repo.
4. **Empty** — use AskUserQuestion to ask what to update.

For each PR URL, run `gh pr view <url> --json headRefName,headRepository,baseRefName,number,url,headRepositoryOwner` to get:
- `headRefName` → the branch to update
- `headRepository.name` + `headRepositoryOwner.login` → the repo
- `baseRefName` → the PR's actual base branch (use this if it differs from the repo's default main)

If the input is just a branch name, use the current repo (`git rev-parse --show-toplevel` and `gh repo view --json name,owner` to identify it).

## Step 1: Determine the Main Branch

Use this repo → main-branch mapping for known repos. The repo identifier is the GitHub repo name (case-insensitive):

| Repo | Main branch |
|------|-------------|
| `dd-source` | `main` |
| `dd-go` | `prod` |
| `logs-backend` | `prod` |
| `dogweb` | `prod` |
| `consul-config` | `master` |
| `k8s-resources` | `master` |
| `web-ui` | `preprod` |

For repos not in this table:
1. **If the PR has a non-default base branch** (from `gh pr view`'s `baseRefName`), prefer the PR's base branch.
2. **Otherwise** fall back to the repo's default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
3. **If still ambiguous**, ask the user via AskUserQuestion.

State the resolved main branch to the user before proceeding ("Updating branch `X` from `origin/<main>`").

## Step 2: Check for Graphite

Determine whether to use Graphite operations for this branch:

```bash
which gt && gt state 2>/dev/null
```

Then check if the target branch is tracked by Graphite:

```bash
gt log --stack 2>/dev/null | grep -F "<branch-name>"
```

If `gt` is installed AND initialized AND the branch is tracked, use Graphite (`gt sync`, `gt restack`) for the merge. Otherwise fall back to plain `git`.

## Step 3: Pre-flight (Orchestrator)

Before spawning subagents, verify the orchestrator's working tree is clean on the user's currently checked-out branch (so a subagent's worktree creation doesn't surprise the user):

```bash
git status --porcelain
git rev-parse --abbrev-ref HEAD
```

If there are uncommitted changes on the orchestrator's current branch, ask the user to stash/commit first — do NOT auto-stash. Record the user's original branch so you can return to it at the end.

## Step 4: Spawn Subagents (One Per PR/Branch)

Spawn one `Agent` (general-purpose) per PR/branch. If there are multiple, issue all `Agent` tool calls **in a single message** so they run in parallel. Each call must include:

- `description`: `"Update PR <branch>"`
- `name`: `"update-pr-<sanitized-branch>"`
- `subagent_type`: `"general-purpose"`
- `isolation`: `"worktree"`
- `prompt`: a fully self-contained prompt (the subagent has no memory of this conversation) — see template below.

### Subagent prompt template

```
You are updating a single PR branch by merging the latest main branch into it. Work in this worktree only.

PR / branch context:
- Branch name: <branch-name>
- Main branch to merge in: <resolved-main-branch>   # e.g. "prod", "preprod", "master", "main"
- Repo: <owner/repo>
- PR URL (if applicable): <url or "N/A">
- Graphite tracked: <true|false>

Do the following:

1. Fetch latest:
   git fetch origin <main-branch>
   git fetch origin <branch-name>

2. Check out the target branch:
   git checkout <branch-name>
   git pull --ff-only origin <branch-name>

   If pull --ff-only fails (diverged), STOP and report "DIVERGED" in your result — do not reset or overwrite. The orchestrator will handle it.

3. Merge main:
   - If Graphite tracked: run `gt sync` (or `gt restack` if already synced).
   - Otherwise: `git merge origin/<main-branch>` (use merge, NOT rebase, unless the orchestrator explicitly said rebase).

4. Handle conflicts:
   - If no conflicts, continue.
   - If conflicts, run `git status`, read each conflicted file, and classify each conflict:
     * Simple stack (changes don't overlap semantically) → resolve by combining both sides, keeping main's structural changes and re-applying the branch's intent on top.
     * Complex / semantic overlap → STOP. Run `git merge --abort` (or `gt continue --abort` for Graphite) and report "COMPLEX_CONFLICT" with the file list and a short description of the overlap. The orchestrator will ask the user.
   - After resolving simple conflicts: `git add <files>`, verify `git status` shows no conflicts, then `git commit` with the default merge message (or `gt continue` for Graphite).

5. Verify clean state:
   git status                                    # must be clean
   git log --oneline -5
   git diff origin/<main-branch>...HEAD --stat

6. Report back in this exact format:

   STATUS: <CLEAN | DIVERGED | COMPLEX_CONFLICT | ABORTED>
   BRANCH: <branch-name>
   MAIN: <main-branch>
   WORKTREE: <path to worktree, from your environment>
   FILES_CHANGED_BY_MERGE: <N>
   CONFLICTS: <"none" | comma-separated file list>
   CONFLICT_RESOLUTION: <"n/a" | short description of how each was resolved>
   READY_TO_PUSH: <true|false>
   NOTES: <anything the orchestrator should know — e.g. "had to drop hunk X because main removed function Y">

DO NOT push to origin. DO NOT run `git push` or `gt submit`. The orchestrator handles the push after user approval.
```

### Conflict escalation back to the orchestrator

If a subagent returns `STATUS: COMPLEX_CONFLICT`, the orchestrator must:

1. Use `AskUserQuestion` to ask how to handle the conflict in that branch:

   ```
   Question: "Branch <X> has a complex conflict in <file(s)>: <description>. How should I proceed?"
   Options:
   1. label: "Show me the conflict"
      description: "Print the conflicted hunks and let me decide manually"
   2. label: "Keep branch version"
      description: "Resolve by keeping the branch's side of every conflicting hunk"
   3. label: "Keep main version"
      description: "Resolve by keeping main's side of every conflicting hunk"
   4. label: "Skip this branch"
      description: "Leave this branch un-updated and continue with others"
   ```

2. Based on the answer, either:
   - Resume the subagent via `SendMessage` with the user's directive (the subagent still owns the worktree), OR
   - Skip this branch and note it in the final summary.

If a subagent returns `STATUS: DIVERGED`, ask the user whether to reset to remote, keep local and abort, or force-push later (don't decide unilaterally).

## Step 5: Consolidate Subagent Results

After all subagents return, build a summary table:

| Branch | Main | Status | Files changed | Conflicts | Worktree |
|--------|------|--------|---------------|-----------|----------|

Present this to the user before asking for push approval.

## Step 6: Get Approval Before Pushing

**Never push without explicit user approval.** After confirming the merge is clean, summarize ALL the branches that were updated (and any that were aborted or had complex conflicts), then ask:

```
Question: "All merges completed. Push <N> branch(es) to origin?"
Options:
1. label: "Push all"
   description: "git push (or gt submit) for every updated branch"
2. label: "Push selectively"
   description: "Let me pick which branches to push"
3. label: "Don't push"
   description: "Leave the merges local"
```

Only proceed to Step 7 after the user approves.

## Step 7: Push

The push happens from each subagent's worktree (where the merge commit lives). For each branch the user approved, run the push from that worktree's path (use `git -C <worktree-path>` or `cd <worktree-path>`):

**With Graphite** (for branches tracked by Graphite):

```bash
git -C <worktree-path> ... # use the worktree
gt submit --no-edit --stack    # pushes and updates the PR stack
```

**Without Graphite**:

```bash
git -C <worktree-path> push origin <branch-name>
```

If the push is rejected (non-fast-forward), STOP and report it. Do NOT use `--force` or `--force-with-lease` without explicit user permission — that's a destructive action and the user must confirm.

You can also resume each subagent via `SendMessage` and instruct it to push from its own worktree — either approach is fine, but the orchestrator must verify the push happened (e.g. `gh pr view <url> --json statusCheckRollup` or `git ls-remote origin <branch>`).

## Step 8: Clean Up Worktrees and Return

After all pushes complete (or the user declined to push), clean up the subagent worktrees:

- If the subagents were spawned with `isolation: "worktree"` and the worktree contains the merge commit, the worktree path is recorded in the agent's result. You can either:
  - Leave the worktree in place if the user might want to inspect it (mention this in the summary), or
  - Remove it with `git worktree remove <path>` if the work is fully pushed and the user is done.

Return the orchestrator to the user's original branch:

```bash
git checkout <user's-original-branch-recorded-in-Step-3>
```

Print a final one-line summary: "Updated N branch(es): <list>. Pushed M. K worktrees retained for inspection."

## Behavioral Rules

1. **Never push without approval.** Step 6 is non-negotiable. The orchestrator owns the push — subagents must not push.
2. **Never force-push.** If the user wants to force-push, they have to say so explicitly.
3. **Never abort a user's in-progress work.** If working tree is dirty on the orchestrator's current branch, ask them what to do — don't auto-stash or discard.
4. **Verify the main branch before merging.** Always confirm the resolved main branch to the user in Step 1 output, especially for non-default mappings (`prod`, `preprod`, `master`). Pass the resolved main branch explicitly to each subagent — don't make them figure it out.
5. **Prefer Graphite when it's already tracking the branch.** Don't introduce Graphite to repos/branches that aren't already using it.
6. **Spawn subagents in parallel.** When updating multiple PRs, issue all `Agent` calls in a single message so they run concurrently. Use `isolation: "worktree"` to keep them from clobbering each other.
7. **Subagents are self-contained.** They have no memory of this conversation. The prompt to each subagent must include everything they need: branch name, main branch, repo, Graphite flag, and the exact report format.
8. **Be specific about conflicts.** Don't say "there were conflicts and I resolved them" — name each file and describe what you did. Pass conflict details through from the subagent's `NOTES` field to the final user summary.

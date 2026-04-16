---
name: prototype
description: Creates one or more prototype implementations of a solution in parallel using git worktrees and subagents. Each prototype is submitted as a PR via Graphite (gt). Use when the user wants to explore multiple approaches to a problem side-by-side.
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion, mcp__graphite__run_gt_cmd, mcp__graphite__learn_gt
---

# Prototype Skill

Create parallel prototype implementations of a solution, each in its own git worktree, and submit them as PRs via Graphite.

The user wants to prototype: $ARGUMENTS

## Step 0: Validate Environment

Before anything else, confirm you are inside a git repository:

```bash
git rev-parse --is-inside-work-tree
```

If not in a git repo, tell the user and stop.

Check that `gt` (Graphite CLI) is available:

```bash
which gt
```

If `gt` is not installed, tell the user to install it (`npm install -g @withgraphite/graphite-cli` or `brew install withgraphite/tap/graphite`) and stop.

Check that Graphite is initialized in this repo:

```bash
gt state
```

If not initialized, run `gt init` and confirm trunk branch with the user.

## Step 1: Clarify the Problem and Approaches

Your first job is to understand what the user wants to build and what distinct approaches they want to explore.

### If $ARGUMENTS is empty or vague

Use AskUserQuestion:

```
Question: "What problem or feature do you want to prototype?"
Header: "Problem"
Options:
1. label: "Describe it now"
   description: "I'll describe the problem in my next message"
2. label: "Point to a ticket"
   description: "I'll provide a Jira ticket or GitHub issue URL"
3. label: "From a file"
   description: "I'll point to a spec, RFC, or design doc"
```

### If $ARGUMENTS describes the problem but not the approaches

After understanding the problem, use AskUserQuestion:

```
Question: "How many prototype approaches do you want to explore?"
Header: "Approaches"
Options:
1. label: "2 approaches"
   description: "Compare two different implementations"
2. label: "3 approaches"
   description: "Compare three different implementations"
3. label: "Let me specify"
   description: "I'll describe exactly which approaches to try"
```

Then ask the user to describe each approach. If they said "Let me specify", wait for their input. Otherwise, propose approaches based on the problem and confirm with the user.

### If $ARGUMENTS describes both problem and approaches

Confirm your understanding with the user before proceeding. Summarize:
- The problem being solved
- Each approach and what makes it distinct
- Which files/directories each prototype will likely touch
- A proposed branch name for each prototype (e.g., `prototype/approach-1-name`, `prototype/approach-2-name`)

Use AskUserQuestion:

```
Question: "Does this look right? Should I proceed with these prototypes?"
Header: "Confirm"
Options:
1. label: "Yes, proceed"
   description: "Start building all prototypes in parallel"
2. label: "Modify approaches"
   description: "I want to change or add approaches"
3. label: "Change scope"
   description: "The scope or files aren't quite right"
```

## Step 2: Create Worktrees and Build Prototypes in Parallel

Once the user confirms, create a worktree for each prototype and launch subagents in parallel to build them.

### 2a: Record the repo root and current branch

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
CURRENT_BRANCH=$(git branch --show-current)
```

### 2b: Create worktrees

For each prototype approach, create a worktree:

```bash
git worktree add "$REPO_ROOT/.claude/worktrees/prototype-<name>" -b "prototype/<name>" HEAD
```

Use descriptive names derived from the approach (e.g., `prototype/redis-cache`, `prototype/in-memory-cache`).

### 2c: Launch subagents in parallel

Launch one Agent per prototype, all in a **single message** so they run concurrently. Each agent gets:

1. The full problem description
2. Its specific approach description
3. The worktree path to work in
4. Instructions to:
   - `cd` to the worktree path
   - Implement the prototype
   - Stage all changes with `git add`
   - Use `gt create --message "<descriptive commit message>"` to create the branch commit
   - The commit message first line becomes the PR title, so make it descriptive (e.g., "prototype: Redis-based caching for session store")
   - Do NOT run `gt submit` — that will be done from the main worktree after all prototypes are complete

**Agent prompt template for each prototype:**

```
You are implementing a prototype in a git worktree. Here is your task:

## Problem
<problem description>

## Your Approach
<specific approach description>

## Working Directory
Your worktree is at: <worktree_path>
You MUST cd to this directory before doing any work.

## Instructions
1. cd to <worktree_path>
2. Understand the existing codebase by reading relevant files
3. Implement the prototype following the approach described above
4. Keep it focused — this is a prototype, not production code. Aim for a working demonstration of the approach.
5. When done, stage your changes:
   ```bash
   cd <worktree_path>
   git add -A
   ```
6. Create a Graphite branch using the gt MCP tool:
   - Run: gt create --message "<title>\n\n<body>"
   - The first line is the PR title. Use format: "prototype: <short description of approach>"
   - The body should explain: what this approach does, key design decisions, trade-offs, and how to test it.
7. Do NOT run gt submit. That will be handled separately.
8. Report back what you built, key files changed, and any caveats.
```

## Step 3: Collect Results

After all subagents complete, summarize the results for the user:

```
## Prototype Results

### Approach 1: <name>
- Branch: prototype/<name>
- Worktree: .claude/worktrees/prototype-<name>
- Files changed: <list>
- Summary: <what the agent built>
- Caveats: <any issues or limitations>

### Approach 2: <name>
- Branch: prototype/<name>
- Worktree: .claude/worktrees/prototype-<name>
- Files changed: <list>
- Summary: <what the agent built>
- Caveats: <any issues or limitations>

...
```

## Step 4: Submit to Graphite

Ask the user what to do next:

```
Question: "Prototypes are ready. What would you like to do?"
Header: "Next steps"
Options:
1. label: "Submit all as PRs (Recommended)"
   description: "Push all prototype branches and create GitHub PRs via Graphite"
2. label: "Review first"
   description: "Let me look at the code in each worktree before submitting"
3. label: "Submit selected"
   description: "Choose which prototypes to submit as PRs"
4. label: "Done for now"
   description: "Keep the worktrees but don't submit yet"
```

### If "Submit all as PRs"

For each prototype worktree, submit via Graphite:

```bash
cd <worktree_path>
gt submit --no-interactive
```

After all submissions, collect the PR URLs and present them:

```
## Submitted PRs

1. **<Approach 1 name>**: <PR URL>
2. **<Approach 2 name>**: <PR URL>
...
```

### If "Review first"

Tell the user the worktree paths so they can inspect the code:

```
Worktrees are at:
- .claude/worktrees/prototype-<name1>
- .claude/worktrees/prototype-<name2>

You can review the changes with:
  cd <worktree_path> && git diff HEAD~1

When ready, run /prototype again and I'll pick up where we left off, or just tell me to submit.
```

### If "Submit selected"

Use AskUserQuestion with multiSelect to let the user pick which prototypes to submit. Then submit only the selected ones.

### If "Done for now"

Inform the user the worktrees will persist until cleaned up:

```
Worktrees are preserved at .claude/worktrees/prototype-*
To clean up later: git worktree remove <path>
To submit later: cd <path> && gt submit --no-interactive
```

## Step 5: Cleanup (Optional)

After submission, ask:

```
Question: "Should I clean up the worktrees?"
Header: "Cleanup"
Options:
1. label: "Yes, remove all"
   description: "Delete all prototype worktrees (branches and PRs remain)"
2. label: "No, keep them"
   description: "Keep worktrees for further iteration"
```

If cleanup requested:

```bash
git worktree remove <worktree_path> --force
```

for each prototype worktree.

## Important Notes

- **Do NOT use `gt modify --into` on a branch checked out in a different worktree** — Graphite disallows this.
- **If branches were created with raw git instead of gt**, use `git rebase main <branch>` then `gt track` to register them with Graphite before submitting.
- Use `gt log` to verify branch state across worktrees (it shows worktree paths next to branches).
- Each worktree is independent — subagents can work in parallel without conflicts.
- Prototype code should be functional but doesn't need to be production-ready. Focus on demonstrating the approach clearly.
- If a subagent fails, report the failure to the user and offer to retry or skip that approach.

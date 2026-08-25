---
name: sign-commits
description: Safely (re-)sign the commits on a branch or PR with the user's own signing key and push the result. Preserves authorship, refuses to touch the main branch, and force-pushes with --force-with-lease. Runs from any directory regardless of where the repo lives. Use when the user wants to "sign the commits", "re-sign commits", "make commits verified", or fix commits signed by the wrong key (e.g. Cursor/CI bot keys showing as unverified).
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
user_invocable: true
---

The user wants to sign (or re-sign) the commits for: $ARGUMENTS

Goal: ensure every commit on the target branch carries a **good signature made with the user's own signing key**, without changing the diff or authorship, then push. This is destructive to commit SHAs (a rebase rewrites them), so verify carefully at each step and only force-push with `--force-with-lease`.

This skill must work no matter what directory it is invoked from. Never assume the current directory is the right repo — resolve the repo from the input first.

## Step 0: Parse the input

`$ARGUMENTS` can be:

1. **A GitHub PR URL** (`https://github.com/<owner>/<repo>/pull/<n>`) — the most common case.
2. **A PR number** (e.g. `67909`) — only usable if the current directory is inside the matching repo; otherwise ask for the URL.
3. **A branch name** — operate on that branch in the current repo.
4. **Empty** — operate on the current branch of the current repo.

For a PR URL or number, run:

```
gh pr view <url-or-number> --repo <owner/repo> --json headRefName,headRepositoryOwner,headRepository,baseRefName,state,commits,url
```

Capture: `headRefName` (branch to sign), `baseRefName` (base for the rebase range), `headRepository`/`headRepositoryOwner` (repo identity), and the commit list (to see current signers).

## Step 1: Locate the correct repo on disk

Do not trust the current directory. Find a local clone of the target repo:

1. If a PR URL was given, get its repo `name` + `owner`.
2. Check the current repo: `git rev-parse --show-toplevel` then `gh repo view --json name,owner`. If it matches, use it.
3. Otherwise, search common roots for a clone whose `origin` remote matches (owner/name), e.g. under `~/go/src/github.com/<owner>/<name>`, `~/dd/<name>`, `~/src`, `~/work`. Use `git -C <dir> remote get-url origin` to confirm.
4. If no local clone is found, tell the user and ask where the repo lives (AskUserQuestion) rather than cloning blindly.

Run **all** subsequent git commands with `git -C <repo-dir> ...` so the skill is directory-independent. Do not `cd`.

## Step 2: Verify signing is configured

The rebase must actually produce signatures, so confirm the user has signing set up **before** rewriting anything:

```
git -C <repo> config --get gpg.format          # ssh or gpg (empty = gpg/openpgp)
git -C <repo> config --get user.signingkey     # must be non-empty
```

- If `user.signingkey` is empty, stop and tell the user — signing would silently fail or use an unexpected key. Do not proceed.
- Note the key so you can confirm the final signatures match it.

## Step 3: Check out the branch and inspect current state

```
git -C <repo> fetch origin <headRefName>
git -C <repo> checkout -B <headRefName> origin/<headRefName>
```

**Safety gate — never sign the main branch.** Determine the repo's default branch (`git -C <repo> symbolic-ref refs/remotes/origin/HEAD` or `gh repo view --json defaultBranchRef`). If `<headRefName>` equals it (or `main`/`master`), refuse and ask the user for a topic branch. Signing directly on main and force-pushing is dangerous.

Confirm the working tree is clean:

```
git -C <repo> status --porcelain
```

If it is dirty, stop — a rebase would clobber uncommitted work. Ask the user to stash or commit first.

Inspect the current signatures to decide what needs doing:

```
git -C <repo> log --show-signature <base>..HEAD
```

- If **every** commit already shows `Good signature ... <user's key>`, there is nothing to do — report that and stop (don't rewrite SHAs for no reason).
- If commits are unsigned, or signed by a different principal (a bot/CI key like Cursor's, shown as `No principal matched` or a foreign email), they need re-signing.

## Step 4: Determine the rebase range

Compute the base — the point after which commits belong to this branch:

```
git -C <repo> merge-base HEAD origin/<baseRefName>   # baseRefName from the PR; fall back to the default branch
```

Only commits in `<base>..HEAD` will be re-signed. This avoids touching shared history on the base branch.

## Step 5: Re-sign every commit, preserving authorship

Use a rebase with an `--exec` that amends and signs each commit. `--amend --no-edit -S` keeps the original author, date, message, and co-authors, only adding/refreshing the signature:

```
git -C <repo> rebase --exec 'git commit --amend --no-edit -S' <base>
```

Notes:
- `-S` uses the configured key/format automatically (works for both SSH and GPG signing).
- Authorship is preserved because `--amend` does not reset the author.
- If the rebase stops for any reason (it shouldn't for a pure re-sign), do not improvise conflict resolution — abort with `git -C <repo> rebase --abort` and report to the user.

## Step 6: Verify the new signatures

```
git -C <repo> log --show-signature <base>..HEAD
```

Confirm **each** commit now shows `Good signature` for the user's own identity/key (matching the `user.signingkey` from Step 2). If any commit is still unsigned or shows the wrong key, stop and report — do not push a half-signed branch.

## Step 7: Push safely

Force-push is required because SHAs changed, but use `--force-with-lease` so you never overwrite work someone else pushed in the meantime:

```
git -C <repo> push --force-with-lease origin <headRefName>
```

- If the lease check fails (remote moved), do **not** escalate to `--force`. Re-fetch, show the user the divergence, and ask how to proceed.
- The user in this environment has pre-authorized force-pushing when signing ("force push if needed"), but only ever via `--force-with-lease`.

## Step 8: Report

Summarize: repo path used, branch, base, how many commits were re-signed, old→new head SHA, the key/identity now signing them, and confirmation that the diff and authorship are unchanged. If a PR URL was given, note that GitHub will now show the commits as Verified (assuming the key is registered on GitHub).

## Safety invariants (do not violate)

- Never rewrite or push the default/main branch.
- Never proceed if the working tree is dirty or `user.signingkey` is unset.
- Never change the diff or authorship — only signatures.
- Never use bare `--force`; only `--force-with-lease`.
- Always operate via `git -C <repo>` so behavior is identical from any directory.
- If already fully signed by the right key, do nothing.

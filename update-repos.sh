#!/usr/bin/env bash
#
# Update all local repos to the latest remote version of their main branch,
# preserving any in-progress work (current branch + local changes).
#
# For each repo:
#   1. Note current branch.
#   2. Stash local changes (if any).
#   3. Switch to that repo's main branch.
#   4. Fetch + fast-forward main to the latest remote.
#   5. Switch back to the original branch (if different) and unstash.
#   6. Report the result.

set -u

# repo path <TAB> main branch name
REPOS=(
  "/Users/dinu.wijetunga/dd/dd-source|main"
  "/Users/dinu.wijetunga/dd/dd-go|prod"
  "/Users/dinu.wijetunga/dd/web-ui|preprod"
  "/Users/dinu.wijetunga/dd/logs-backend|prod"
  "/Users/dinu.wijetunga/dd/terraform-config|master"
)

# Colors (fall back to empty if not a tty)
if [[ -t 1 ]]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

summary=()

for entry in "${REPOS[@]}"; do
  repo="${entry%%|*}"
  main_branch="${entry##*|}"
  name="$(basename "$repo")"

  echo "${BOLD}=== $name ($repo) ===${RESET}"

  if [[ ! -d "$repo/.git" ]]; then
    echo "${RED}  skip: not a git repo${RESET}"
    summary+=("$name: ${RED}SKIPPED (not a git repo)${RESET}")
    continue
  fi

  # Run git scoped to this repo without cd'ing the shell.
  git() { command git -C "$repo" "$@"; }

  orig_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  stashed=0
  conflict=0
  updated=0

  # 1 + 2: stash if there are local changes (including untracked)
  if ! git diff --quiet || ! git diff --cached --quiet || \
     [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "  stashing local changes..."
    if git stash push --include-untracked -m "auto-update-repos $(date +%s)" >/dev/null 2>&1; then
      stashed=1
    else
      echo "${RED}  failed to stash — leaving repo untouched${RESET}"
      summary+=("$name: ${RED}ERROR (stash failed)${RESET}")
      unset -f git
      continue
    fi
  fi

  # 3: switch to main
  if [[ "$orig_branch" != "$main_branch" ]]; then
    if ! git checkout "$main_branch" >/dev/null 2>&1; then
      echo "${RED}  failed to checkout $main_branch${RESET}"
      [[ $stashed -eq 1 ]] && git stash pop >/dev/null 2>&1
      summary+=("$name: ${RED}ERROR (checkout $main_branch failed)${RESET}")
      unset -f git
      continue
    fi
  fi

  # 4: fetch + fast-forward
  before="$(git rev-parse HEAD)"
  git fetch origin "$main_branch" >/dev/null 2>&1
  if git merge --ff-only "origin/$main_branch" >/dev/null 2>&1; then
    after="$(git rev-parse HEAD)"
    [[ "$before" != "$after" ]] && updated=1
  else
    echo "${YELLOW}  could not fast-forward $main_branch (diverged?)${RESET}"
  fi

  # 5 + 7: back to original branch
  if [[ "$orig_branch" != "$main_branch" ]]; then
    git checkout "$orig_branch" >/dev/null 2>&1
  fi

  # 6: unstash
  if [[ $stashed -eq 1 ]]; then
    echo "  restoring stashed changes..."
    if ! git stash pop >/dev/null 2>&1; then
      conflict=1
      echo "${RED}  CONFLICT while unstashing — resolve manually in $repo${RESET}"
    fi
  fi

  # Re-query the real final state of the repo.
  final_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  if git diff --quiet && git diff --cached --quiet && \
     [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    tree="clean"
  else
    tree="${YELLOW}dirty${RESET}"
  fi
  # Ahead/behind vs the branch's upstream, if one is set.
  ab="$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)"
  if [[ -n "$ab" ]]; then
    behind="$(echo "$ab" | cut -f1)"; ahead="$(echo "$ab" | cut -f2)"
    track="up to date"
    [[ "$behind" != "0" ]] && track="${YELLOW}$behind behind${RESET}"
    [[ "$ahead"  != "0" ]] && track="${track:+$track, }${YELLOW}$ahead ahead${RESET}"
  else
    track="no upstream"
  fi

  # Report line
  line="$name: on ${BOLD}$final_branch${RESET} ($tree, $track)"
  if [[ $updated -eq 1 ]]; then
    line+=" — ${GREEN}$main_branch updated${RESET}"
  else
    line+=" — ${GREEN}$main_branch already up to date${RESET}"
  fi
  [[ $stashed -eq 1 && $conflict -eq 0 ]] && line+=", stash restored"
  [[ $conflict -eq 1 ]] && line+=", ${RED}STASH CONFLICT (needs manual resolution)${RESET}"
  summary+=("$line")

  unset -f git
  echo
done

echo "${BOLD}=== Final status of each repo ===${RESET}"
for s in "${summary[@]}"; do
  echo "  - $s"
done

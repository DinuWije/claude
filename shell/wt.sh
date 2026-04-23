#!/usr/bin/env zsh
# wt — git worktree helper
#
# Auto-detects source repo from $PWD (walks up to find .git dir).
# Falls back to WT_SOURCE_REPO if not inside a git repo.
# Auto-detects default branch from origin/HEAD.
#
# Config (override via env before sourcing):
#   WT_SOURCE_REPO   fallback repo          (default: ~/go/src/github.com/DataDog/dd-source)
#   WT_ROOT          worktrees parent dir   (default: ~/dd/worktrees)
#   WT_BRANCH_PREFIX branch prefix          (default: $USER/)
#   WT_BASE          override base branch   (skip auto-detection)

: "${WT_SOURCE_REPO:=$HOME/go/src/github.com/DataDog/dd-source}"
: "${WT_ROOT:=$HOME/dd/worktrees}"
: "${WT_BRANCH_PREFIX:=$USER/}"

# ---------------------------------------------------------------------------
# Repo & branch detection
# ---------------------------------------------------------------------------
_wt_resolve_repo() {
  # If inside a git repo (or worktree), find the main repo root.
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || true

  if [ -n "$toplevel" ]; then
    # If this is a worktree, resolve to the main repo
    local common_dir
    common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || true
    if [ -n "$common_dir" ] && [ "$common_dir" != ".git" ]; then
      # common_dir is an absolute path to the shared .git dir
      local main_repo
      main_repo="$(dirname "$common_dir")"
      # Normalise
      main_repo="$(cd "$main_repo" 2>/dev/null && pwd)" || main_repo="$toplevel"
      echo "$main_repo"
      return
    fi
    echo "$toplevel"
    return
  fi

  # Not in a git repo — fall back
  echo "$WT_SOURCE_REPO"
}

_wt_default_branch() {
  local repo="$1"
  # Use WT_BASE override if set
  if [ -n "${WT_BASE:-}" ]; then
    echo "$WT_BASE"
    return
  fi
  # Auto-detect from origin/HEAD
  local ref
  ref="$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)" || true
  if [ -n "$ref" ]; then
    echo "${ref#refs/remotes/origin/}"
    return
  fi
  # Fallback: try common names
  for candidate in main master; do
    if git -C "$repo" rev-parse --verify "origin/$candidate" &>/dev/null; then
      echo "$candidate"
      return
    fi
  done
  echo "main"
}

# ---------------------------------------------------------------------------
# Bazel workaround
# ---------------------------------------------------------------------------
_wt_ensure_bazelrc() {
  local bazelrc="$HOME/.bazelrc"
  local cache_dir="$HOME/.cache/bazel"
  local needs_repo_cache=true
  local needs_output_root=true

  if [ -f "$bazelrc" ]; then
    grep -q "^common --repository_cache=" "$bazelrc" 2>/dev/null && needs_repo_cache=false
    grep -q "^startup --output_user_root=" "$bazelrc" 2>/dev/null && needs_output_root=false
  fi

  if $needs_repo_cache || $needs_output_root; then
    mkdir -p "$cache_dir"
    echo "" >> "$bazelrc"
    echo "# Added by wt: share bazel caches across worktrees" >> "$bazelrc"
    $needs_repo_cache && echo "common --repository_cache=$cache_dir/repo-cache" >> "$bazelrc"
    $needs_output_root && echo "startup --output_user_root=$cache_dir/user-root" >> "$bazelrc"
    echo "Configured ~/.bazelrc for shared bazel caches"
  fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_wt_list_names() {
  if [ -d "$WT_ROOT" ]; then
    ls -1 "$WT_ROOT" 2>/dev/null | while read -r d; do
      [ -d "$WT_ROOT/$d/.git" ] || [ -f "$WT_ROOT/$d/.git" ] && echo "$d"
    done
  fi
}

_wt_pick() {
  local prompt="${1:-worktree}"
  local names
  names="$(_wt_list_names)"
  [ -z "$names" ] && echo "No worktrees found under $WT_ROOT" >&2 && return 1
  if command -v fzf &>/dev/null; then
    echo "$names" | fzf --prompt="$prompt> "
  else
    echo "$names" >&2
    printf "%s" "Enter name: " >&2
    read -r name
    echo "$name"
  fi
}

_wt_branch_has_unpushed() {
  local wt_path="$1"
  local branch="$2"
  local unpushed
  unpushed="$(git -C "$wt_path" log "$branch" --not --remotes --oneline 2>/dev/null)"
  [ -n "$unpushed" ]
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
_wt_create_or_cd() {
  local name="$1"
  local wt_path="$WT_ROOT/$name"
  local branch="${WT_BRANCH_PREFIX}${name}"

  # If worktree already exists, just cd
  if [ -d "$wt_path" ] && { [ -d "$wt_path/.git" ] || [ -f "$wt_path/.git" ]; }; then
    cd "$wt_path"
    return
  fi

  local repo
  repo="$(_wt_resolve_repo)"

  if [ ! -d "$repo/.git" ]; then
    echo "error: no git repo found (not in a repo and $WT_SOURCE_REPO doesn't exist)" >&2
    return 1
  fi

  local base
  base="$(_wt_default_branch "$repo")"

  echo "Using repo: $repo (base: $base)"
  echo "Fetching origin/$base..."
  git -C "$repo" fetch origin "$base" --quiet

  mkdir -p "$WT_ROOT"
  echo "Creating worktree: $name (branch: $branch)"
  git -C "$repo" worktree add -b "$branch" "$wt_path" "origin/$base"

  # Graphite: track the new branch
  if command -v gt &>/dev/null; then
    (cd "$wt_path" && gt track -f --parent "$base" 2>/dev/null) || true
  fi

  _wt_ensure_bazelrc

  cd "$wt_path"
  echo "Ready: $wt_path"
}

_wt_ls() {
  local names
  names="$(_wt_list_names)"
  if [ -z "$names" ]; then
    echo "No worktrees under $WT_ROOT"
    return
  fi
  echo "$names" | while read -r name; do
    local wt_path="$WT_ROOT/$name"
    local branch
    branch="$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "?")"
    printf "  %-30s %s\n" "$name" "$branch"
  done
}

_wt_cd() {
  local name="$1"
  if [ -z "$name" ]; then
    name="$(_wt_pick "cd")" || return 1
  fi
  local wt_path="$WT_ROOT/$name"
  if [ ! -d "$wt_path" ]; then
    echo "error: worktree '$name' not found" >&2
    return 1
  fi
  cd "$wt_path"
}

_wt_rm() {
  local name="$1"
  if [ -z "$name" ]; then
    name="$(_wt_pick "remove")" || return 1
  fi
  local wt_path="$WT_ROOT/$name"
  if [ ! -d "$wt_path" ]; then
    echo "error: worktree '$name' not found" >&2
    return 1
  fi

  local branch
  branch="$(git -C "$wt_path" branch --show-current 2>/dev/null || echo "")"

  if [ -n "$branch" ] && _wt_branch_has_unpushed "$wt_path" "$branch"; then
    echo "WARNING: branch '$branch' has commits not pushed to any remote:"
    git -C "$wt_path" log "$branch" --not --remotes --oneline
    printf "Remove anyway? [y/N] "
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; return 1; }
  fi

  case "$PWD" in "$wt_path"*) cd "$WT_ROOT" || cd "$HOME" ;; esac

  # Resolve the source repo for this worktree
  local repo
  repo="$(git -C "$wt_path" rev-parse --git-common-dir 2>/dev/null | xargs dirname)" || repo="$WT_SOURCE_REPO"

  echo "Removing worktree: $name"
  git -C "$repo" worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"

  if [ -n "$branch" ]; then
    git -C "$repo" branch -D "$branch" 2>/dev/null && echo "Deleted branch: $branch"
  fi
}

_wt_path() {
  local name="$1"
  if [ -z "$name" ]; then
    echo "usage: wt path <name>" >&2
    return 1
  fi
  local wt_path="$WT_ROOT/$name"
  if [ ! -d "$wt_path" ]; then
    echo "error: worktree '$name' not found" >&2
    return 1
  fi
  echo "$wt_path"
}

_wt_help() {
  cat <<EOF
wt — git worktree helper

  wt <name>           Create worktree off default branch, or cd to it if it exists
  wt ls               List worktrees under \$WT_ROOT
  wt cd [name]        cd to a worktree (fzf picker if no name and fzf is installed)
  wt rm [name]        Remove worktree + local branch (fzf picker if no name)
  wt path <name>      Print the worktree path
  wt help             Show this help

Repo detection:
  If you're inside a git repo, wt uses that repo. Otherwise falls back to \$WT_SOURCE_REPO.
  Base branch is auto-detected from origin/HEAD (override with \$WT_BASE).

Safety:
  wt rm warns and prompts if the branch has commits not on any remote.

Graphite:
  If \`gt\` is on PATH, new worktrees are auto-tracked with parent=<base>.

Bazel:
  Ensures ~/.bazelrc shares repository_cache and output_user_root across
  all worktrees so builds don't fill your disk.

Config (override via env):
  WT_SOURCE_REPO   fallback repo          (current: $WT_SOURCE_REPO)
  WT_ROOT          worktrees parent dir   (current: $WT_ROOT)
  WT_BRANCH_PREFIX branch prefix          (current: $WT_BRANCH_PREFIX)
  WT_BASE          override base branch   (current: ${WT_BASE:-auto})
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
wt() {
  local cmd="${1:-}"
  case "$cmd" in
    ls)          _wt_ls ;;
    cd)          _wt_cd "${2:-}" ;;
    rm)          _wt_rm "${2:-}" ;;
    path)        _wt_path "${2:-}" ;;
    help|-h|--help) _wt_help ;;
    "")          _wt_help ;;
    *)           _wt_create_or_cd "$cmd" ;;
  esac
}

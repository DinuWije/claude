#!/usr/bin/env zsh
# ws — workspaces helper
#
# Thin wrapper around the `workspaces` CLI with sensible defaults and
# interactive pickers when a workspace name is omitted.
#
# Config (override via env before sourcing):
#   WS_REGION         default region          (default: us-east-1)
#   WS_DEFAULT_EDITOR default IDE for connect (default: cursor)

: "${WS_REGION:=us-east-1}"
: "${WS_DEFAULT_EDITOR:=cursor}"

_WS_SUPPORTED_EDITORS=(vscode cursor intellij pycharm goland)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_ws_require_cli() {
  if ! command -v workspaces &>/dev/null; then
    echo "error: 'workspaces' CLI not found on PATH" >&2
    return 1
  fi
}

_ws_list_names() {
  # Best-effort parse of `workspaces list`: skip blank lines and likely
  # header rows (start with NAME / ID / -), take the first whitespace-
  # separated column.
  workspaces list 2>/dev/null | awk '
    NF == 0 { next }
    /^[[:space:]]*(NAME|ID|STATUS|---)/ { next }
    /^[[:space:]]*-/ { next }
    { print $1 }
  '
}

_ws_pick() {
  local prompt="${1:-workspace}"
  local names
  names="$(_ws_list_names)"
  if [ -z "$names" ]; then
    echo "No workspaces found. Run 'workspaces list' to verify." >&2
    return 1
  fi
  if command -v fzf &>/dev/null; then
    echo "$names" | fzf --prompt="$prompt> "
    return
  fi
  # Numbered fallback
  echo "Workspaces:" >&2
  local i=1
  local -a arr
  while IFS= read -r line; do
    arr+=("$line")
    printf "  %2d) %s\n" "$i" "$line" >&2
    i=$((i + 1))
  done <<< "$names"
  printf "Select [1-%d]: " "${#arr[@]}" >&2
  local choice
  read -r choice
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#arr[@]}" ]; then
    echo "Invalid selection" >&2
    return 1
  fi
  echo "${arr[$choice]}"
}

_ws_validate_editor() {
  local editor="$1"
  for valid in "${_WS_SUPPORTED_EDITORS[@]}"; do
    [ "$editor" = "$valid" ] && return 0
  done
  echo "error: unsupported editor '$editor'" >&2
  echo "supported: ${_WS_SUPPORTED_EDITORS[*]}" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
_ws_create() {
  local name="$1"
  local repo="$2"
  if [ -z "$name" ] || [ -z "$repo" ]; then
    echo "usage: ws create <workspace-name> <repo>" >&2
    return 1
  fi
  _ws_require_cli || return 1
  echo "Creating workspace '$name' (region: $WS_REGION, repo: $repo)..."
  workspaces create "$name" --region "$WS_REGION" --repo "$repo"
}

_ws_ssh() {
  local name="$1"
  if [ -z "$name" ]; then
    name="$(_ws_pick "ssh")" || return 1
  fi
  echo "Connecting to workspace-$name..."
  ssh "workspace-$name"
}

_ws_connect() {
  local name="$1"
  local repo="$2"
  local editor="${3:-$WS_DEFAULT_EDITOR}"

  if [ -z "$name" ]; then
    name="$(_ws_pick "connect")" || return 1
  fi
  if [ -z "$repo" ]; then
    echo "usage: ws connect <name> <repo> [editor]" >&2
    echo "       editor defaults to '$WS_DEFAULT_EDITOR' (supported: ${_WS_SUPPORTED_EDITORS[*]})" >&2
    return 1
  fi
  _ws_validate_editor "$editor" || return 1
  _ws_require_cli || return 1

  echo "Connecting '$name' to $editor (repo: $repo)..."
  workspaces connect "$name" --editor "$editor" --repo "$repo"
}

_ws_scp() {
  local name="$1"
  local src="$2"
  local dest="${3:-/Users/dinu.wijetunga/Documents/obsidian/random}"

  if [ -z "$name" ]; then
    name="$(_ws_pick "scp")" || return 1
  fi
  if [ -z "$src" ]; then
    echo "usage: ws scp <name> <remote-path> [local-dest]" >&2
    echo "       local-dest defaults to /Users/dinu.wijetunga/Documents/obsidian/random" >&2
    return 1
  fi

  echo "Copying workspace-$name:$src -> $dest..."
  scp -r "workspace-$name:$src" "$dest"
}

_ws_delete() {
  local name="$1"
  if [ -z "$name" ]; then
    name="$(_ws_pick "delete")" || return 1
  fi
  _ws_require_cli || return 1

  printf "Delete workspace '%s'? [y/N] " "$name"
  local confirm
  read -r confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; return 1; }

  workspaces delete "$name"
}

_ws_list() {
  _ws_require_cli || return 1
  workspaces list
}

_ws_help() {
  cat <<EOF
ws — workspaces helper

  ws create <name> <repo>             Create a workspace in \$WS_REGION
  ws ssh [name]                       SSH to workspace-<name> (picker if no name)
  ws scp <name> <remote-path> [dest]  Copy a file from workspace to local
                                      (picker if no name; dest defaults to
                                       /Users/dinu.wijetunga/Documents/obsidian/random)
  ws connect <name> <repo> [editor]   Connect workspace to an IDE
                                      (picker if no name; default editor: $WS_DEFAULT_EDITOR)
  ws delete [name]                    Delete a workspace (picker if no name)
  ws list                             List workspaces
  ws help                             Show this help

Editors supported by 'ws connect':
  ${_WS_SUPPORTED_EDITORS[*]}

Config (override via env):
  WS_REGION          default region          (current: $WS_REGION)
  WS_DEFAULT_EDITOR  default IDE for connect (current: $WS_DEFAULT_EDITOR)

Picker: uses fzf if available, otherwise a numbered prompt.
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
ws() {
  local cmd="${1:-}"
  shift 2>/dev/null || true
  case "$cmd" in
    create)         _ws_create "$@" ;;
    ssh)            _ws_ssh "$@" ;;
    scp)            _ws_scp "$@" ;;
    connect)        _ws_connect "$@" ;;
    delete|rm)      _ws_delete "$@" ;;
    list|ls)        _ws_list ;;
    help|-h|--help) _ws_help ;;
    "")             _ws_help ;;
    *)              echo "ws: unknown command '$cmd'" >&2; _ws_help >&2; return 1 ;;
  esac
}

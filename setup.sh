#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Setting up from $REPO_DIR"

# --- Claude Config ---
mkdir -p "$CLAUDE_DIR/skills"

for file in settings.json policy-limits.json CLAUDE.md mcp.json; do
  if [ -f "$REPO_DIR/$file" ]; then
    ln -sf "$REPO_DIR/$file" "$CLAUDE_DIR/$file"
    echo "  Linked $file -> ~/.claude/$file"
  fi
done

for skill in "$REPO_DIR"/skills/*/; do
  [ -d "$skill" ] || continue
  name=$(basename "$skill")
  rm -rf "$CLAUDE_DIR/skills/$name"
  ln -sf "$skill" "$CLAUDE_DIR/skills/$name"
  echo "  Linked skill: $name"
done

# --- Brew Packages ---
# Locate or bootstrap brew (macOS: /opt/homebrew; Linux: /home/linuxbrew/.linuxbrew)
BREW_BIN=""
for candidate in /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew; do
  [ -x "$candidate" ] && BREW_BIN="$candidate" && break
done
if [ -z "$BREW_BIN" ] && ! command -v brew >/dev/null 2>&1; then
  echo "  Brew not found — installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for candidate in /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && BREW_BIN="$candidate" && break
  done
fi
[ -z "$BREW_BIN" ] && BREW_BIN="$(command -v brew || true)"

if [ -n "$BREW_BIN" ]; then
  eval "$("$BREW_BIN" shellenv)"
  BREW_PACKAGES=(
    withgraphite/tap/graphite
  )
  for pkg in "${BREW_PACKAGES[@]}"; do
    name="${pkg##*/}"
    if brew list --formula "$name" >/dev/null 2>&1 || brew list --cask "$name" >/dev/null 2>&1; then
      echo "  Brew: $name already installed"
    else
      echo "  Brew: installing $pkg"
      brew install "$pkg"
    fi
  done
else
  echo "  Brew: not available, skipping package install"
fi

# --- Shell Config ---
if [ -f "$REPO_DIR/shell/zshrc" ]; then
  ln -sf "$REPO_DIR/shell/zshrc" "$HOME/.zshrc"
  echo "  Linked shell/zshrc -> ~/.zshrc"
fi

if [ -f "$REPO_DIR/shell/aliases" ]; then
  ln -sf "$REPO_DIR/shell/aliases" "$HOME/.aliases"
  echo "  Linked shell/aliases -> ~/.aliases"
fi

echo "Done. Run: source ~/.zshrc on first setup."

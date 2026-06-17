#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Setting up from $REPO_DIR"

# --- Claude Config ---
mkdir -p "$CLAUDE_DIR/skills"

for file in settings.json policy-limits.json CLAUDE.md; do
  if [ -f "$REPO_DIR/$file" ]; then
    ln -sf "$REPO_DIR/$file" "$CLAUDE_DIR/$file"
    echo "  Linked $file -> ~/.claude/$file"
  fi
done

# MCP servers go in .mcp.json (dotfile) for Claude Code to autoload
if [ -f "$REPO_DIR/mcp.json" ]; then
  ln -sf "$REPO_DIR/mcp.json" "$CLAUDE_DIR/.mcp.json"
  echo "  Linked mcp.json -> ~/.claude/.mcp.json"
fi

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

  # Ensure node is available for npm-based installs
  if ! command -v node >/dev/null 2>&1; then
    echo "  Brew: installing node"
    brew install node
  else
    echo "  Brew: node already installed"
  fi

  # Unlink the Homebrew graphite package if present — it ships an x86_64 binary
  # that fails on aarch64. We install via npm instead.
  if brew list --formula graphite >/dev/null 2>&1; then
    brew unlink graphite 2>/dev/null || true
    echo "  Brew: unlinked graphite (replaced by npm install)"
  fi
else
  echo "  Brew: not available, skipping package install"
fi

# --- npm Packages ---
# graphite must be installed via npm; the Homebrew bottle is x86_64-only and
# fails on aarch64 Linux with "No such file or directory: /lib64/ld-linux-x86-64.so.2"
if command -v npm >/dev/null 2>&1; then
  if npm list -g @withgraphite/graphite-cli >/dev/null 2>&1; then
    echo "  npm: @withgraphite/graphite-cli already installed"
  else
    echo "  npm: installing @withgraphite/graphite-cli"
    npm install -g @withgraphite/graphite-cli
  fi
else
  echo "  npm: not available, skipping graphite install"
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

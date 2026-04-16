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

# --- Shell Config ---
if [ -f "$REPO_DIR/shell/zshrc" ]; then
  ln -sf "$REPO_DIR/shell/zshrc" "$HOME/.zshrc"
  echo "  Linked shell/zshrc -> ~/.zshrc"
fi

if [ -f "$REPO_DIR/shell/aliases" ]; then
  ln -sf "$REPO_DIR/shell/aliases" "$HOME/.aliases"
  echo "  Linked shell/aliases -> ~/.aliases"
fi

echo "Done. Run: source ~/.zshrc" on first setup.

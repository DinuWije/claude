#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Setting up Claude config from $REPO_DIR"

# Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR/skills"

# Config files
for file in settings.json policy-limits.json CLAUDE.md mcp.json; do
  if [ -f "$REPO_DIR/$file" ]; then
    ln -sf "$REPO_DIR/$file" "$CLAUDE_DIR/$file"
    echo "  Linked $file"
  fi
done

# Skills (link each skill directory)
for skill in "$REPO_DIR"/skills/*/; do
  [ -d "$skill" ] || continue
  name=$(basename "$skill")
  rm -rf "$CLAUDE_DIR/skills/$name"
  ln -sf "$skill" "$CLAUDE_DIR/skills/$name"
  echo "  Linked skill: $name"
done

echo "Done."

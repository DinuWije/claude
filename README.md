# Workstation Setup

Personal workstation bootstrap — Claude Code config, shell settings, and aliases.

## Structure

```
.
├── setup.sh                     # Run to symlink everything into place
├── CLAUDE.md                    # Global Claude instructions
├── IMPROVEMENTS.md              # /improve-claude change log
├── mcp.json                     # MCP servers (Atlassian, Datadog, Google Workspace, Lambo)
├── settings.json                # Claude settings (model, plugins)
├── policy-limits.json           # Claude restriction policies
├── skills/
│   ├── explore/SKILL.md         # Deep codebase investigation
│   ├── improve-claude/SKILL.md  # Self-improving Claude setup optimizer
│   ├── obslint/SKILL.md         # Observability linter for Go
│   ├── prototype/SKILL.md       # Parallel prototype builder using worktrees
│   └── verify/SKILL.md          # AI output verification/fact-checking
└── shell/
    ├── zshrc                    # Shell config (homebrew, pyenv, rbenv, Go, AWS)
    └── aliases                  # Shell aliases (git, docker, npm, navigation, Claude)
```

## Setup

```bash
git clone <repo-url> ~/claude
~/claude/setup.sh
```

This symlinks:
- Claude config and skills into `~/.claude/`
- Shell config into `~/.zshrc` and `~/.aliases`

Safe to re-run after pulling updates. Restart your shell after first run.

# Claude Configuration

Personal Claude Code configuration, skills, and settings.

## Structure

```
.
├── setup.sh               # Run to symlink everything into ~/.claude/
├── mcp.json               # MCP servers (Atlassian, Datadog, Google Workspace, Lambo)
├── settings.json          # Global settings (model, plugins)
├── policy-limits.json     # Restriction policies
├── skills/
│   ├── explore/SKILL.md         # Deep codebase investigation
│   ├── improve-claude/SKILL.md  # Self-improving Claude setup optimizer
│   ├── obslint/SKILL.md         # Observability linter for Go
│   ├── prototype/SKILL.md       # Parallel prototype builder using worktrees
│   └── verify/SKILL.md          # AI output verification/fact-checking
└── CLAUDE.md              # Global instructions
```

## Setup

```bash
git clone <repo-url> ~/claude
~/claude/setup.sh
```

This symlinks config and skills into `~/.claude/`, leaving Claude's runtime files (history, sessions, cache) untouched. Safe to re-run — existing symlinks get overwritten.

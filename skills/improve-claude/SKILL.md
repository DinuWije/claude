---
name: improve-claude
description: Analyzes Claude usage history and session patterns to optimize your Claude setup — settings, skills, rules, permissions, MCP servers, and CLAUDE.md. Edits your ~/claude repo directly so improvements are portable across VMs. Self-improving — each run can refine this skill's own analysis patterns.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent, AskUserQuestion
---

# Improve Claude

Analyze Claude usage patterns and optimize the user's Claude setup. All changes target the user's claude config repo so they can be committed and shared across instances.

## Configuration

```
CLAUDE_DIR=~/.claude
CLAUDE_REPO=~/claude
```

If `~/claude` does not exist, check `~/personal/claude`. If neither exists, ask the user where their claude config repo is.

## Step 1: Gather Data

Collect usage data from multiple sources. Run these in parallel where possible.

### 1a: Recent Session History

```bash
# Get the last 5 session files by modification time
ls -t ~/.claude/projects/*//*.jsonl 2>/dev/null | head -20
```

Read the most recent 3-5 session files. For each, extract:
- **Tool usage frequency** — which tools are called most, which are never used
- **Tool denials** — tools the user had to approve or denied (permission friction)
- **Error patterns** — recurring errors, failed commands, retried operations
- **Repeated instructions** — things the user tells Claude multiple times across sessions
- **Skill invocations** — which skills are used, which are never used
- **MCP tool usage** — which MCP tools are actually called vs configured

### 1b: Current Config State

Read all files in the claude repo:
- `settings.json` — model, plugins
- `mcp.json` — MCP servers
- `policy-limits.json` — restrictions
- `CLAUDE.md` — global instructions
- All `skills/*/SKILL.md` files

### 1c: Permission Patterns

```bash
# Check settings.local.json files for permission grants that accumulated
find ~/.claude/projects -name 'settings.local.json' -newer ~/.claude/settings.json 2>/dev/null | head -10
```

Read these to find permissions the user repeatedly grants that could be moved to global settings.

### 1d: Previous Improvement Log

Read `~/claude/IMPROVEMENTS.md` if it exists. This file tracks what was changed in previous runs to avoid re-analyzing solved issues and to track what worked.

## Step 2: Analyze Patterns

Look for these categories of optimization. Check each one, but only act on findings with clear evidence.

### Permission Friction
Tools or commands the user approves repeatedly across sessions. These should be added to `settings.json` permissions.

**Evidence required:** Same permission granted 3+ times across different sessions.

### Missing Global Instructions
Corrections or preferences the user repeats across sessions that aren't captured in `CLAUDE.md`.

**Evidence required:** Same instruction given 2+ times in different sessions.

### Underused MCP Servers
MCP servers configured but never or rarely called. These add startup latency for no benefit.

**Evidence required:** Server configured but zero tool calls in the last 5+ sessions.

### Skill Gaps
Repeated multi-step workflows the user performs manually that could be captured as a skill.

**Evidence required:** Same sequence of 4+ steps performed 2+ times.

### Stale Config
Settings, plugins, or skills that reference things that no longer exist or are superseded.

**Evidence required:** References to missing files, deprecated APIs, or unused plugins.

### Settings Optimization
Model, plugin, or environment settings that could be tuned based on usage patterns.

**Evidence required:** Patterns suggesting a different config would reduce friction.

### Self-Improvement
Patterns this skill missed in previous runs, or new analysis categories discovered from session data.

**Evidence required:** Recurring issues not covered by the categories above.

## Step 3: Apply Changes

For each finding with sufficient evidence:

1. **Explain what was found** — show the evidence (session excerpts, frequency counts)
2. **Propose the change** — what file to edit, what to add/remove/modify
3. **Apply the change** — edit the file in `~/claude` directly

Group changes by file to minimize edits. After all changes:

### Update Improvement Log

Append to `~/claude/IMPROVEMENTS.md`:

```markdown
## <date>

### Changes Made
- <change 1>: <why, with evidence summary>
- <change 2>: <why, with evidence summary>

### Patterns Observed
- <notable pattern that didn't warrant a change yet but may in future>
```

Create the file if it doesn't exist. Keep entries concise.

### Self-Improve

If you discovered a new analysis pattern, a better heuristic, or a category of optimization not covered above, edit this skill file (`~/claude/skills/improve-claude/SKILL.md`) to add it. Add new patterns to the "Analyze Patterns" section under a clear heading. This makes future runs smarter.

**Rules for self-modification:**
- Only add patterns you have evidence for from this session
- Do not remove existing patterns — they may apply in other projects
- Keep the same format as existing pattern entries
- Add a comment with the date when appending: `<!-- Added <date> -->`

## Step 4: Tip

Print exactly **one** high-value tip based on what you observed. Choose the tip that would save the user the most time or friction. Format:

```
Tip: <one sentence, actionable, specific to what you observed>
```

Pick from what you found, not generic advice. If you found permission friction, the tip is about permissions. If you found repeated instructions, the tip is about CLAUDE.md. The tip should be something the user didn't already know or do.

## Step 5: Commit Prompt

If any files in `~/claude` were modified, print:

```
Changes were made to your claude config repo. To share across your instances:

  cd ~/claude && git add -A && git commit -m "<suggested message>" && git push
```

Generate a specific commit message summarizing the actual changes made (not a generic message).

If no changes were made, say so and explain why (e.g., "Your setup looks well-optimized based on recent usage").

---
name: explore
description: Deep codebase investigation that traces code paths and saves findings to markdown
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, Agent, LSP, AskUserQuestion
---

You are investigating a codebase to help the user deeply understand how something works.

The user wants to explore: $ARGUMENTS

## Step 1: Clarify Scope

If the user's request is vague or could mean multiple things, use AskUserQuestion to clarify:
- What specific behavior, flow, or component they want to understand
- Whether they want breadth (architecture overview) or depth (specific code path tracing)
- Any specific questions they're trying to answer

Do NOT skip this step if there is any ambiguity. It is better to ask one good question than to investigate the wrong thing.

## Step 2: Investigate Thoroughly

Trace the code methodically. Do not skim — actually follow the execution path:

1. **Find entry points** — locate where the relevant code starts (main functions, handlers, API endpoints, CLI commands)
2. **Trace the call chain** — follow function calls through layers, reading each function. Use LSP (goToDefinition, findReferences, incomingCalls, outgoingCalls) when available to trace connections accurately.
3. **Map data flow** — track how data is created, transformed, and passed between components
4. **Identify key abstractions** — interfaces, base classes, patterns that shape the design
5. **Note configuration and side effects** — env vars, config files, external calls, state mutations
6. **Read tests** — they reveal intended behavior and edge cases

Use the Explore agent for broad searches and direct tool calls for targeted lookups. Be thorough — read the actual code, don't guess from names.

## Step 3: Build Understanding With the User

As you investigate, share findings conversationally:
- **Always provide direct code references** using `file_path:line_number` format (e.g., `domains/aaa/shared/datasetsclient/client.go:197`) when explaining any concept, behavior, or design choice. Never describe what code does without pointing to where it lives.
- Explain what you're finding in plain language
- Call out surprising or non-obvious design choices
- Highlight connections between components
- Suggest specific areas worth digging into further

## Step 4: Write Investigation Summary

Save a markdown file to `/Users/dinu.wijetunga/.claude/investigations/` with:
- A clear, descriptive filename (e.g., `auth-token-refresh-flow.md`, `kafka-consumer-retry-logic.md`)
- Use kebab-case, no dates in the filename

The file MUST follow this structure:

```markdown
# <Title>

> **Summary:** <2-3 sentence plain-english summary of what was investigated and the key findings. This should be useful to both a human skimming and an AI agent picking up context.>

## Context

- **Repo:** <repo name>
- **Area:** <package/module/component investigated>
- **Triggered by:** <the original question or problem>

## Key Findings

<Numbered list of the most important things learned, in order of importance. Each finding should be concrete and reference specific code.>

## Architecture & Flow

<How the system works at a high level. Use ASCII diagrams where they help. Show the main flow or data path.>

## Key Files

| File | Role |
|------|------|
| `path/to/file.go` | <what it does> |

## Code Details

<Deeper specifics — important functions, interfaces, patterns, config. Reference file:line where relevant.>

## Open Questions

<Things that weren't fully resolved or would need further investigation.>

## Suggested Next Investigations

<Specific follow-up areas to dig into, phrased as actionable prompts the user could give to /explore.>
```

Tell the user where the file was saved.

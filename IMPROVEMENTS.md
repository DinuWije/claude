# Improvement Log

## 2026-04-16

### Changes Made
- **Populated CLAUDE.md with global instructions**: Was empty. Added conciseness preference (observed: user interrupts verbose responses), correction handling (observed: user gives terse redirects), and portability preference (observed: user works across dd-source, dd-go, personal repos and is setting up cross-VM config sharing).

### Patterns Observed
- Snowflake MCP appears as a deferred tool in sessions but is not user-configured — it's likely injected by the environment. No action needed.
- No permission friction detected — user runs mostly in default mode with some auto/plan mode usage. No repeated permission grants to promote to global settings.
- Heavy Read/Bash/Grep usage across all sessions — standard for codebase exploration work. No optimization needed.
- User has no project-level memory files — the memory system is underutilized.

## 2026-04-17

### Changes Made
- **Updated improve-claude skill to only analyze current session**: User explicitly corrected broad multi-session data gathering. Changed Step 1a to read only the current session JSONL file.
- **Added cautious-analysis guidance to CLAUDE.md**: During CI failure investigation, Claude confidently declared failures were "pre-existing and unrelated" without verification. User pushed back with "Are you sure?". Added instruction to hedge and verify before declaring root causes.

### Patterns Observed
- User prefers scoped, focused work — don't expand scope beyond what's asked (e.g., reading 5 sessions when current session suffices).

## 2026-04-22

### Changes Made
- **Added "check for newer patterns" guidance to CLAUDE.md**: During DAC investigation, Claude found the older EVP access control mechanism (`access_control.go` restriction filters) and recommended it. User corrected by pointing to the newer `DatasetsHelper` approach in the Java event-query service. Added instruction to look for v2/newer alternatives before recommending the first match.

### Patterns Observed
- This session was a multi-day deep investigation (17 Agent launches, 53 Greps, 52 Reads, 3 Edits). User is doing architectural scoping work — asking precise questions, building understanding incrementally, and catching mistakes. The Explore agent subtype was used heavily and effectively.
- No MCP tools were used despite 3 servers configured. This is expected for a code investigation session — MCP tools are more relevant for operational tasks.
- User corrects by asking questions ("Isn't there already...?", "Are you sure...?") rather than blunt negation. The existing CLAUDE.md guidance about re-examining assumptions on pushback is working — the pattern to improve is catching the wrong recommendation before the user has to ask.

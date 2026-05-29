---
name: recap
description: Generate a recap of recent work and save it to the user's Obsidian directory. Takes "1w" (past week, saved to week_overview/) or "1d" (past day, saved to standup/; uses Friday if today is Monday). Pulls from GitHub PRs, Slack activity (work-related only), and Google Workspace / Confluence documents. Also generates a todo list of unfinished items.
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion, mcp__plugin_slack_slack__slack_search_public_and_private, mcp__plugin_slack_slack__slack_search_users, mcp__plugin_slack_slack__slack_read_thread, mcp__plugin_slack_slack__slack_read_user_profile, mcp__plugin_slack_slack__slack_read_channel, mcp__atlassian__atlassianUserInfo, mcp__atlassian__searchConfluenceUsingCql, mcp__atlassian__searchJiraIssuesUsingJql, mcp__atlassian__getConfluencePage, mcp__atlassian__getJiraIssue, mcp__datadog-google-workspace__search_files, mcp__datadog-google-workspace__list_file_comments, mcp__datadog-google-workspace__get_file_metadata, mcp__datadog-google-workspace__get_doc_as_markdown
user_invocable: true
---

The user wants a recap of their recent work: $ARGUMENTS

You are generating a recap of the user's recent work and writing it to their Obsidian vault at `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/`. The recap pulls from GitHub PRs, Slack activity, and Google Workspace / Confluence documents, and also produces a todo list of unfinished items.

## Step 0: Parse the Input

`$ARGUMENTS` should be either `1w` or `1d`. Normalize whitespace and casing.

- `1w` → **weekly mode** (past 7 days, high-level summary, save to `week_overview/`)
- `1d` → **daily mode** (past 1 day, more detailed standup, save to `standup/`)
- Anything else (including empty) → ask via AskUserQuestion:

```
Question: "Which recap do you want?"
Header: "Recap range"
Options:
1. label: "Today's standup (1d)"
   description: "Detailed recap of the past day, saved to standup/"
2. label: "Weekly overview (1w)"
   description: "High-level recap of the past week, saved to week_overview/"
```

## Step 1: Determine the Date Range

Use `date` via Bash to compute the range. Today's date is available; use it as the anchor.

```bash
date +%Y-%m-%d           # today (YYYY-MM-DD)
date +%u                 # day of week (1=Mon, 7=Sun)
```

**Important — `date` flavor varies by machine.** macOS has BSD `date` (`-v-7d`), Linux has GNU `date` (`-d '7 days ago'`). The platform string isn't reliable — some macOS-flavored shells alias `date` to GNU coreutils. Try both, or use Python as a portable fallback:

```bash
# Portable: Python
python3 -c "from datetime import date, timedelta; print((date.today() - timedelta(days=7)).strftime('%Y-%m-%d'))"

# BSD (macOS default)
date -v-7d +%Y-%m-%d

# GNU (Linux, sometimes macOS via coreutils)
date -d '7 days ago' +%Y-%m-%d
```

If the first `date` invocation errors with `invalid option -- 'v'`, you're on GNU — switch to `-d`. Do **not** assume from `Platform: darwin`.

**Daily mode (`1d`):**
- If today is Monday (`date +%u` returns `1`), the "past day" is the previous Friday — subtract 3 days.
- Otherwise the "past day" is yesterday — subtract 1 day.
- The range is `[start_of_target_day, end_of_target_day]` in ISO format. For Slack/GitHub queries that take date ranges, format as `YYYY-MM-DD..YYYY-MM-DD`.

**Weekly mode (`1w`):**
- Range is the last 7 calendar days: 7 days ago through today.

State the resolved range to the user before proceeding ("Generating <daily|weekly> recap for `<start>..<end>`").

## Step 2: Identify the User Across Systems

You need the user's identity in each system to filter to their activity only:

- **GitHub:** `gh api user --jq .login` for the GitHub username.
- **Slack:** call `mcp__plugin_slack_slack__slack_read_user_profile` with no user ID (or call `slack_search_users` for the current user) to get the user's Slack user ID and display name. Note: the Slack MCP tool description sometimes includes the current user ID inline (e.g. "Current logged in user's user_id is U..."); you can read it from there to save a call.
- **Atlassian:** call `mcp__atlassian__atlassianUserInfo` to get the Atlassian account ID and email. You **also** need a `cloudId` to query Confluence/Jira — call `mcp__atlassian__getAccessibleAtlassianResources` and use the `id` field from the result. (You can run both calls in parallel.)
- **Google Workspace:** the MCP operates as the authenticated user, so no lookup is needed — file ownership/modification queries are scoped automatically.

Cache these IDs locally in this conversation; you'll reuse them in Steps 3–5.

## Step 3: Gather Data — In Parallel

Issue these calls **in a single message** so they run concurrently. Do not chain them.

### 3a. GitHub PRs

Use `gh` to find PRs authored by the user, created or updated in the date range:

```bash
# PRs the user authored, updated in the range (across all repos they have access to)
gh search prs --author=@me --updated="<start>..<end>" --json number,title,url,repository,state,isDraft,updatedAt,createdAt --limit 50

# Also include PRs merged in the range — NOTE: the flag is --merged-at, NOT --merged.
# --merged is a boolean ("only merged PRs"); --merged-at takes a date or range.
gh search prs --author=@me --merged-at="<start>..<end>" --json number,title,url,repository,state --limit 50
```

For each PR, note: state (open/draft/merged/closed), repo, title, URL, and whether it was merged in-range. `mergedAt` is not a valid JSON field in `gh search prs` — leave it out.

### 3b. Slack — User's Messages

Use `mcp__plugin_slack_slack__slack_search_public_and_private` to find messages the user sent in the range:

- Query: `from:<user_id> after:<start> before:<end_plus_one_day>` — Slack search uses `before`/`after` modifiers, and `before` is exclusive, so use `end + 1 day`.
- Sort by timestamp, fetch as many pages as needed up to a reasonable cap (~100 messages).

For threads where the user replied, optionally call `slack_read_thread` on the most substantive ones to get context — but only spend effort here for messages that look load-bearing (e.g. decisions, action items, blockers).

**Gotchas with Slack search:**
- **Timestamps in concise/detailed search output are unreliable** — they often display as year-56391490-style garbage. Don't try to parse them or use them for sorting. Rely on `after:`/`before:` modifiers for the date window, and rely on channel name + content for prioritization.
- **`channel_types` parameter is unreliable when combined with `from:` modifier** — it has returned "No results" in cases where the same query without the parameter returned results. Don't lean on it. Instead, retrieve a broad result set and **post-filter in your head** by inspecting the channel label in each result (`DM with X` / `Group DM with X` = personal-leaning; `#channel-name` = public/private channel).
- **`-in:@username` exclude-modifier did not filter DMs effectively** in testing — same DMs reappeared. Post-filtering is more reliable than negative modifiers.

**Filter for work relevance.** Drop personal chatter, social channels, jokes, emoji-only messages, and anything in channels that are clearly non-work (e.g. `#random`, `#pets`, `#food`, `#offtopic`, DMs that are clearly social). When in doubt about a channel, prefer to include it — but skip individual messages that are clearly personal. Heuristic: if the message is in a `DM with` or `Group DM with` result and the content reads conversational (not a status update, decision, or link), drop it.

### 3c. Confluence Pages

Use `mcp__atlassian__searchConfluenceUsingCql` to find pages the user created or edited. Requires `cloudId` (see Step 2).

```
CQL: contributor = "<atlassian_account_id>" AND lastmodified >= "<start>" AND lastmodified <= "<end>" ORDER BY lastmodified DESC
```

For each result, capture: title, space, URL, last modified date, and (if needed for status) call `getConfluencePage` to peek at whether it looks draft/in-progress vs. published/final.

### 3d. Jira Issues (work tracker context)

Use `mcp__atlassian__searchJiraIssuesUsingJql` for issues the user updated or commented on. Requires `cloudId` (see Step 2).

```
JQL: (assignee = currentUser() OR commented = (currentUser(), "<start>", "<end>")) AND updated >= "<start>" ORDER BY updated DESC
```

**Do NOT use** `commented BY currentUser() during (...)` — that syntax fails with "Expecting operator but got 'BY'". The correct form is `commented = (user, startDate, endDate)`.

Capture: key, summary, status, URL. These help identify hanging work for the todo section.

### 3e. Google Workspace Documents

Use `mcp__datadog-google-workspace__search_files` to find Docs/Sheets/Slides the user modified in the range. The MCP accepts Google Drive query syntax directly. Example that works:

```
modifiedTime > '<start>T00:00:00' and 'me' in writers and (mimeType = 'application/vnd.google-apps.document' or mimeType = 'application/vnd.google-apps.spreadsheet' or mimeType = 'application/vnd.google-apps.presentation')
```

Note: the result will include files the user *edited* even if owned by someone else (e.g. shared meeting notes docs owned by a teammate). Check the `owners[0].me` field — `true` means the user owns the file; `false` means they only contributed. Both are relevant for the recap.

If a document looks substantive (large, recent, or referenced in Slack), call `get_doc_as_markdown` briefly to gauge whether it's a draft, in-review, or finalized.

### 3f. Calendar / Meetings

There is no dedicated Google Calendar MCP tool exposed. **Fallback: use Gemini-generated meeting notes as a proxy calendar feed.** Every meeting the user attends with Gemini Notetaker creates a Drive doc named like `<Meeting Title> - YYYY/MM/DD HH:MM TZ - Notes by Gemini`. These will already appear in the Step 3e Drive results — extract them into a separate "meetings" bucket.

From the filenames alone you can parse: title, date, time. To identify **cross-team / noteworthy** meetings, look for:
- Meetings with multiple non-owner contributors (call `get_file_metadata` if needed)
- Titles containing words like `Design Review`, `Planning`, `Sync`, `Sharing`, `OKR`, `Cross-team`, or another team's name
- 1:1s and routine standups → drop (low signal); only surface them in daily mode if something material was decided

For meetings that look load-bearing (design review, decision points, sharing sessions), call `get_doc_as_markdown` on the notes doc to pull out decisions/action items and feed them into the recap. Owned meeting docs (e.g. personal 1:1 templates) are usually low signal — prioritize docs you only *contributed to*.

In the recap, give cross-team meetings their own bullet or fold them under "Cross-team work / discussions." Example: `Attended Access Enforcement Design Review (5/20) — decision: <one-line outcome>`.

## Step 4: Classify and Synthesize

Take the raw data from Step 3 and build two structures: the **recap** and the **todo list**.

### Recap content

**Weekly mode (`1w`) — high level, 8–10 bullets total.** Group by theme, not by source. Example structure:
- Shipped: <thing 1>, <thing 2>
- In flight: <thing 1>, <thing 2>
- Cross-team work / discussions: <topic>
- Docs / writeups: <one or two with status>

**Daily mode (`1d`) — more granular, 8–10 bullets total.** Example structure:
- PRs: <opened / merged / reviewed>
- Slack threads of note (work-relevant only): <topic, decision, or blocker>
- Docs touched: <title — status>
- Meetings / decisions captured

For both modes:
- Use bullets, not paragraphs.
- Lead each bullet with the concrete artifact (PR title, doc name, decision) — not the verb.
- Link to URLs inline using markdown `[title](url)` so the user can click through in Obsidian.
- Don't pad. If the day was light, write fewer bullets. Max 10.

### Todo content

Generate a separate todo list capturing **unfinished work**:

- **Unfinished Slack threads:** threads where the user was @-mentioned or asked a question and didn't reply, or threads where the user asked a question and didn't get a satisfactory answer. Use `slack_read_thread` on candidate threads to confirm before adding.
- **Hanging work:** Open PRs in draft, PRs with unaddressed review comments, Jira tickets assigned to the user that are still "In Progress" with no recent update, Confluence/Docs in "draft" state that haven't been touched in a few days.
- **Cross-references:** if the user committed in Slack to do something ("I'll send the doc tomorrow", "I'll file the ticket") and you can't find evidence they did it, flag it.

Format the todo list as a markdown checklist:

```
- [ ] <task> — <source / link>
```

Keep it focused. 5–10 items max. If there's truly nothing hanging, write `- [ ] (no outstanding items detected)`.

## Step 5: Write the Files

Compute filenames based on mode:

- **Weekly (`1w`):** filename anchor is today's date.
  - Recap: `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/week_overview/<today>_week.md`
  - Todo: `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/todo/<today>_week_todo.md`
- **Daily (`1d`):** filename anchor is the target day (yesterday, or Friday if today is Monday).
  - Recap: `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/standup/<target_day>.md`
  - Todo: `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/todo/<target_day>_todo.md`

**Before writing**, check if the file already exists with `Glob` or `ls`. If it does:
- Read the existing file.
- Use AskUserQuestion to ask whether to **Overwrite**, **Append a new section dated by time**, or **Cancel**.

### Recap file format

```markdown
# <Weekly Recap | Standup> — <date or range>

<8–10 bullets, per the structure in Step 4>

---
*Generated <timestamp> covering <range>. Sources: GitHub PRs, Slack, Confluence, Google Workspace.*
```

### Todo file format

```markdown
# Todo — <date or range>

<5–10 checklist items>

---
*Generated <timestamp>.*
```

Write both files with the `Write` tool.

## Step 6: Report Back

Print a short summary to the user:

```
Wrote recap → <path>
Wrote todo  → <path>

<2–3 line preview of the recap>
```

Include the file paths so the user can click through in their terminal / open them in Obsidian.

## Behavioral Rules

1. **Work-relevance filter is mandatory for Slack.** Personal chatter, social channels, and non-work DMs must be dropped. When uncertain, prefer to exclude an individual message rather than include something the user wouldn't want surfaced.
2. **No fabrication.** If a data source returns nothing (e.g. no PRs in range), say so in the recap — don't invent activity.
3. **Don't duplicate across bullets.** If a PR is also discussed in a Slack thread, surface it once (prefer the PR bullet, mention the discussion as context).
4. **Bullets, not paragraphs.** Hard cap at 10 bullets per file. Better to have 5 sharp bullets than 10 padded ones.
5. **Daily ≠ weekly granularity.** Weekly is themes and shipped/in-flight. Daily is specific PRs, threads, and decisions from that day. Don't write a weekly recap that reads like a list of daily standups concatenated.
6. **Monday's `1d` looks back to Friday**, not Sunday. Verify the day-of-week math before computing the range.
7. **Never overwrite an existing file silently.** Always ask before overwriting.
8. **Don't push anything outside the Obsidian folder.** This skill writes only to `/Users/dinu.wijetunga/Documents/obsidian/work_tracking/{standup,week_overview,todo}/`. Don't post the recap to Slack or anywhere else unless the user asks.
9. **Cross-reference PRs and Jira tickets.** A PR title like `[AAE-115] Remove Preview Tag` maps to Jira ticket AAE-115. When the same item appears in both sources, mention it once and link both. Use Jira status (Done / In Progress / To Do) to inform the todo list — In Progress + no recent commit = hanging.
10. **Closed-but-not-merged PRs are usually noise.** If a PR was closed without being merged, it's often abandoned/superseded — don't surface it in the recap unless it represents meaningful work (e.g. an explicit decision to drop a feature). Check `state: closed` + no merge → low signal.

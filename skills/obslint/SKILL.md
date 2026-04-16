---
name: obslint
description: Use this skill when the user asks to "lint observability", "check metrics", "validate instrumentation", "lint logs", "check high-cardinality tags", "validate statsd calls", "check dogstatsd usage", "lint Go observability code", or wants to analyze Go files for observability best practices. Covers metric naming, tag validation, log correlation, and AI-powered insights.
---

# Observability Linter (obslint)

`obslint` is an observability instrumentation linter for Go that scans source files for metric calls (statsd, dogstatsd) and logging calls, then applies configurable lint rules to identify best practice violations.

## Location

```bash
obslint
```

## Basic Usage

```bash
obslint [options] <file.go> [file2.go ...]
```

### Flags

| Flag | Description |
|------|-------------|
| `-json` | Output results in JSON format (default: human-readable) |
| `-config <path>` | Path to config file (default: `.obslint.json`) |
| `-check-production`, `-p` | Check for duplicate metrics in Datadog production |
| `-ai` | Enable AI-powered insights using Claude |
| `-cost` | Enable custom metric combination analysis (counts unique metric-tag combinations per hour) |
| `-h`, `--help` | Show help message |

### Examples

```bash
# Basic analysis - single file
obslint ./pkg/handler.go

# Multiple files with shell glob
obslint -json ./pkg/*.go

# Recursive scan - all Go files (excluding tests and vendor)
obslint -json $(find . -name "*.go" -not -path "./vendor/*" -not -name "*_test.go")

# Recursive scan - specific directory
obslint -json $(find ./pkg -name "*.go" -not -name "*_test.go")

# Custom configuration
obslint -config custom.json ./pkg/handler.go

# Production validation (requires DD_API_KEY, DD_APP_KEY)
obslint -check-production ./pkg/handler.go
```

**Note:** `obslint` does not support Go-style `./...` patterns. Use `find` or shell globs to pass file paths.

## Lint Rules

| Rule | Severity | Description |
|------|----------|-------------|
| `metric-naming` | Warning | Metric names must use dot-separated lowercase format with >=2 segments |
| `metric-usage` | Error/Warning | Detects deprecated Histogram (use Distribution) and Count with +/-1 (use Incr/Decr) |
| `high-cardinality-tags` | Error/Warning | Detects unbounded IDs, ephemeral K8s tags, timestamps, IPs, URLs, PII |
| `required-tags` | Warning | Ensures unified service tags (env, service, version) are present |
| `log-trace-correlation` | Warning/Info | Ensures logs include trace context |
| `multiline-logs` | Warning | Detects logs with embedded newlines that break aggregation |
| `log-required-tags` | Warning | Ensures logs have required structured fields |
| `log-level-mismatch` | Warning/Info | Detects when log level doesn't match content |
| `low-cardinality-logs` | Info | Flags logs with no structured fields that could be metrics |

### High-Cardinality Tag Categories

- **Unbounded IDs (Error):** user_id, customer_id, account_id, tenant_id, request_id, session_id, transaction_id, order_id, trace_id, span_id, correlation_id, item_id
- **K8s Ephemeral (Warning):** pod_name, pod_uid, container_id, node_name
- **Version/Build (Warning):** commit_sha, image_sha, build_id, git_sha
- **Timestamps (Warning):** timestamp, time, created_at, updated_at
- **Network (Warning):** ip, ip_address, client_ip, source_ip
- **URLs (Warning):** url, uri, path, endpoint, query_string
- **PII (Warning):** email, username, phone
- **Host (Warning):** host, hostname

## Supported Libraries

### Metrics
| Package | Methods |
|---------|---------|
| `statsd`, `dogstatsd` | Gauge, Count, Incr, Decr, Histogram, Distribution, Timing, Set |

### Logging
| Library | Package | Context Method |
|---------|---------|----------------|
| dd-log | `log`, `github.com/DataDog/datadog-go/log` | `FromContext`, `WithContext` |
| zerolog | `zerolog`, `github.com/rs/zerolog` | `Ctx` |
| slog | `slog`, `log/slog` | Context-aware methods |
| logrus | `logrus`, `github.com/sirupsen/logrus` | `WithContext` |
| zap | `zap`, `go.uber.org/zap` | Explicit trace fields |
| stdlib | `log` | No context support |

## Configuration

Default config file: `.obslint.json`

```json
{
  "rules": {
    "metric-naming": { "enabled": true },
    "metric-usage": { "enabled": true },
    "high-cardinality-tags": { "enabled": true },
    "required-tags": {
      "enabled": true,
      "tags": ["env", "service", "version"]
    },
    "log-trace-correlation": { "enabled": true },
    "multiline-logs": { "enabled": true },
    "log-required-tags": {
      "enabled": true,
      "tags": ["service", "env"]
    },
    "log-level-mismatch": { "enabled": true },
    "low-cardinality-logs": { "enabled": true }
  },
  "ai": {
    "enabled": false,
    "analyzers": {
      "missing-error-logs": true,
      "metric-naming": true,
      "metric-tags": true,
      "metric-usage": true,
      "log-quality": true,
      "log-trace-correlation": true
    }
  }
}
```

## Environment Variables

### Production Validation (`-check-production`)
- `DD_API_KEY` - Datadog API key (required)
- `DD_APP_KEY` - Datadog application key (required)
- `DD_SITE` - Datadog site (default: `datadoghq.com`)

## Datadog Context Enrichment

When `-check-production` flag is used, the skill performs additional Datadog API queries to provide richer context. Use the Datadog MCP tools to fetch this data.

### Enrichment Checks

| Check | MCP Tool | Purpose |
|-------|----------|---------|
| Metric existence | `get_datadog_metric_context` | Verify if metric already exists in production |
| Tag cardinality | `get_datadog_metric_context` | Check actual cardinality of existing tags |
| Monitor usage | `search_datadog_monitors` | Find monitors using the metric |
| Dashboard usage | `search_datadog_dashboards` | Find dashboards using the metric |

### Enrichment Workflow

For each metric found by obslint:

1. **Check if metric exists in Datadog**
   ```
   Use get_datadog_metric_context with metric_name to check existence
   ```

2. **If metric exists, check tag cardinality**
   ```
   Use get_datadog_metric_context with include_tag_values=true
   Calculate actual cardinality for each tag
   Flag tags with cardinality > 1000 as high-cardinality
   ```

3. **Check if metric is used in monitors**
   ```
   Use search_datadog_monitors with query containing metric name
   If monitors found, warn before suggesting metric changes/removal
   ```

4. **Check if metric is used in dashboards**
   ```
   Use search_datadog_dashboards with query: widgets.metrics:<metric_name>
   If dashboards found, warn before suggesting metric changes/removal
   ```

### Enriched Output

When enrichment is enabled, add context to each metric finding:

```
[gauge] service.handler.active
  Location: ./pkg/handler.go:10:2
  Tags: env, region, user_id

  Datadog Context:
  - Exists in production: Yes
  - Tag cardinality:
    - env: 3 values (low)
    - region: 5 values (low)
    - user_id: 847,293 values (HIGH - recommend removal)
  - Used in 2 monitors:
    - "Handler Active Connections Alert" (id: 12345)
    - "Service Health Check" (id: 67890)
  - Used in 1 dashboard:
    - "Service Overview" (id: abc-123)

  ⚠️ WARNING: Modifying this metric may break existing monitors/dashboards
```

### Enrichment Severity Adjustments

Based on Datadog context, adjust issue severity:

| Condition | Severity Change |
|-----------|-----------------|
| Metric used in monitors/dashboards | Upgrade warnings to errors |
| Tag has >10,000 distinct values | Upgrade to error regardless of tag name |
| Metric doesn't exist in production | Downgrade to info (new metric, less risk) |
| Metric has no monitors/dashboards | Keep original severity (safe to modify) |

## Output Format

### Human-Readable (default)

```
Found 2 metric(s) in ./pkg/handler.go:

  [gauge] service.handler.active
    Location: ./pkg/handler.go:10:2
    Tags: env, region

Total: 2 metric(s) in 1 file(s)

LINT RESULTS

W 10:2 [metric-naming] metric name "Zoltron.invalid" contains invalid character
E 12:2 [metric-usage] histogram metric "service.handler.latency" is deprecated

Found 2 issue(s)
```

### JSON (`-json`)

```json
{
  "files_scanned": 1,
  "total_metrics": 2,
  "issues": [
    {
      "file": "./pkg/handler.go",
      "line": 10,
      "column": 2,
      "rule": "metric-naming",
      "severity": "warning",
      "message": "..."
    }
  ],
  "total_issues": 2,
  "ai_insights": []
}
```

## AI-Powered Analysis

When enabled (`-ai`), runs 6 parallel Claude analyzers:
1. **missing-error-logs** - Identifies missing error logging
2. **metric-naming** - Suggests better metric names
3. **metric-tags** - Reviews tag choices
4. **metric-usage** - Recommends metric type improvements
5. **log-quality** - Analyzes logging patterns
6. **log-trace-correlation** - Suggests trace correlation improvements

## Execution Workflow

### Step 1: Configuration

If no arguments provided, use AskUserQuestion with **3 questions**:

```
Question 1: "What do you want to analyze?"
Header: "Scope"
Options:
1. label: "Single file"
   description: "Analyze a specific Go file (will prompt for path)"
2. label: "Entire folder"
   description: "Scan all Go files recursively in current directory"
3. label: "Specific folder"
   description: "Scan all Go files in a specific directory (will prompt)"

Question 2: "Which files should be scanned?"
Header: "File Selection"
Options:
1. label: "Changed files only (Recommended)"
   description: "Only scan files modified since last commit (git diff)"
2. label: "Full scan"
   description: "Scan all matching files regardless of git status"

Question 3: "Enable AI-powered insights?"
Header: "AI Mode"
Options:
1. label: "No"
   description: "Don't include Claude-powered suggestions"
2. label: "Yes"
   description: "Include Claude-powered suggestions"

Question 4: "Enable Custom Metrics Combination Analysis?"
Header: "Combination Analysis"
Options:
1. label: "No"
   description: "Don't include combination summaries"
2. label: "Yes"
   description: "Include combination summaries (counts unique metric-tag combinations)"
```

**Note:** Question 2 only applies when scanning folders (not single files). If "Changed files only" is selected, use git to identify modified files.

### Step 2: Run Analysis

Based on configuration:

```bash
# Without AI
obslint -json <files>

# With AI (add -ai flag)
obslint -json -ai <files>

# With Combination Analysis (add -cost flag)
obslint -json -cost <files>
```

File selection:
```bash
# Single file
obslint -json [-ai] <file.go>

# Full scan - Entire/specific folder (exclude vendor, tests, generated code)
obslint -json [-ai] $(find <directory> -name "*.go" -not -path "*/vendor/*" -not -path "*/.git/*" -not -name "*_test.go" -not -name "*.pb.go" -not -name "*_gen.go")

# Changed files only - scan only modified Go files (staged + unstaged)
obslint -json [-ai] $(git diff --name-only HEAD -- '*.go' | grep -v '_test.go' | grep -v '.pb.go' | grep -v '_gen.go' | grep -v 'vendor/')

# Changed files only - include untracked new files
obslint -json [-ai] $(git diff --name-only HEAD -- '*.go'; git ls-files --others --exclude-standard -- '*.go') | grep -v '_test.go' | grep -v '.pb.go' | grep -v '_gen.go' | grep -v 'vendor/' | sort -u
```

**Git-aware scanning benefits:**
- Faster feedback during development
- Focus on code you're actively working on
- Ideal for pre-commit checks

### Step 3: Present Results Summary

**IMPORTANT:** Parse the JSON output directly in your response. Do NOT create external scripts (Python, jq, etc.) to parse the output. Read the JSON and summarize it yourself.

Present a summary including:
- Total files scanned
- Total metrics/logs found
- Issues grouped by severity (Error/Warning/Info)
- Issues grouped by rule type
- Top 5 most affected files
- Total custom metrics combinatiosn 
- Top 5 highest volume/most expensive metric names

Example format:
```
## Obslint Results

**Scan Summary:**
- Files scanned: 47
- Metrics found: 23
- Log calls found: 156
- Total issues: 18

**By Severity:**
- Error: 3
- Warning: 12
- Info: 3

**By Rule:**
- high-cardinality-tags: 8
- metric-usage: 5
- log-trace-correlation: 3
- metric-naming: 2

**Most Affected Files:**
1. pkg/handler/api.go (5 issues)
2. pkg/service/processor.go (4 issues)
...
```

### Step 4: Offer Actions

**ALWAYS** use AskUserQuestion with **exactly these 4 options** (AskUserQuestion supports max 4):

```
Question: "What would you like to do with these findings?"
Header: "Action"
Options (MUST include all 4):
1. label: "Generate local report"
   description: "Create markdown report file"
2. label: "Create Confluence page"
   description: "Publish report to Confluence (draft mode)"
3. label: "Create Jira ticket(s)"
   description: "Single ticket or parent + children for large findings"
4. label: "Fix issues now"
   description: "Interactively select and fix issues"
```

**IMPORTANT:** Always present all 4 options. The user can type "Other" to just see details without action.

### Action: Generate Local Report

1. Determine output location:
   - Ask the user
2. Generate markdown with:
   - Executive summary (files scanned, issues found)
   - Issues table grouped by severity
   - Detailed findings per file with code snippets
   - Recommended fixes for each issue type

### Action: Create Confluence Page

1. Use the Confluence MCP tool to create a page
2. Title: "Observability Lint Report - <service/folder name> - <date>"
3. Content structure:
   - Summary panel with key metrics
   - Issues table with severity, file, line, rule, message
   - Expandable sections per file with details
4. Create in draft mode

### Action: Create Jira Ticket(s)

Evaluate scope:
- **Small** (<=10 issues): Single ticket with all findings
- **Large** (>10 issues): Parent ticket + child tickets grouped by rule type

**Single ticket:**
- Summary: "Fix observability lint issues in <service/folder>"
- Description: Full report with issues table
- Labels: `observability`, `tech-debt`, `obslint`

**Parent + children:**
- Parent: "Observability cleanup for <service/folder>" with summary stats
- Children: One per rule type (e.g., "Fix high-cardinality tags", "Fix metric naming issues")
- Each child links to parent and contains relevant issues only

### Action: Fix Issues Now

1. Parse all fixable issues from the results and group by rule type
2. Present fix mode selection using AskUserQuestion:

```
Question: "How would you like to fix issues?"
Header: "Fix Mode"
Options:
1. label: "Fix by rule type (Recommended)"
   description: "Batch fix all issues of the same type together"
2. label: "Select individual issues"
   description: "Pick specific issues to fix one by one"
3. label: "Fix all automatically"
   description: "Apply all safe fixes without prompting"
```

#### Fix by Rule Type (Batch Mode)

1. Show summary of issues grouped by rule:
   ```
   Issues by rule type:
   - metric-usage: 12 issues (all auto-fixable)
   - high-cardinality-tags: 8 issues (6 auto-fixable)
   - metric-naming: 5 issues (all auto-fixable)
   ```
2. Use AskUserQuestion with multiSelect to let user choose rule types to fix
3. For each selected rule type:
   - Show all affected files and the fix that will be applied
   - Apply fixes in batch (all files for that rule)
   - Show summary of changes made
4. After all batches complete, re-run obslint to verify

#### Select Individual Issues

1. Use AskUserQuestion with multiSelect to let user choose:
   - List each issue with file:line and brief description
   - Option to "Select all"
2. For each selected issue:
   - Read the file
   - Apply the fix based on rule type:
     - `metric-naming`: Rename metric to valid format
     - `metric-usage`: Replace Histogram with Distribution, Count(+1) with Incr
     - `high-cardinality-tags`: Remove or replace high-cardinality tag
     - `required-tags`: Add missing env/service/version tags
   - Show diff and confirm before applying
3. After fixes, re-run obslint to verify

#### Fix All Automatically

1. Apply all auto-fixable issues without prompting
2. Skip issues marked as "Partial" in Fixable Rules Reference
3. Show summary of all changes made
4. Re-run obslint to verify and show remaining issues (if any)

## Fixable Rules Reference

| Rule | Auto-fixable | Fix Strategy |
|------|--------------|--------------|
| `metric-naming` | Yes | Suggest valid name, apply rename |
| `metric-usage` | Yes | Replace deprecated method |
| `high-cardinality-tags` | Partial | Remove tag or suggest alternative |
| `required-tags` | Yes | Add missing unified service tags |
| `log-trace-correlation` | Partial | Wrap with context-aware method |
| `multiline-logs` | No | Manual review required |
| `log-required-tags` | Yes | Add structured fields |
| `log-level-mismatch` | Partial | Suggest correct level |
| `low-cardinality-logs` | No | Suggest converting to metric |

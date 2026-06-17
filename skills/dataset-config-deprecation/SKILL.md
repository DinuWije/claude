---
name: dataset-config-deprecation
description: Deprecate the dataset_config_modes feature flag at a given callsite by collapsing the old (flag-off) and new (flag-on / config-modes) code paths into a single path, with the config-modes path becoming the default. Takes a Jira ticket as input, reads the target callsite from it, removes the old path, consolidates tests, opens a draft PR titled "[<ticket>] Non Dataset Config Deprecation for <callsite>", requests a Codex review (@codex review), and babysits CI. Use when the user says "deprecate dataset config", "non dataset config deprecation", "remove dataset_config_modes", "strict mode post GA cleanup", or passes an AAE-* ticket for this cleanup.
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, AskUserQuestion, Agent, Skill
user_invocable: true
---

The user wants to deprecate the `dataset_config_modes` flag at the callsite described by a Jira ticket: $ARGUMENTS

This skill was distilled from the AAE-84 cleanup of `apps/metrics-querier/internal/planner` in `dd-go`. The flag `dataset_config_modes` is GA'd everywhere, so the "config modes" code path is now the only correct behavior and the legacy (flag-off) path is dead. Your job: collapse the two paths into one, consolidate the tests, and land a PR.

## Guardrails (read first)

- **Scope discipline is the #1 rule.** Make *only* the changes required to merge the `dataset_config_modes` path with the legacy path. No drive-by refactors, no behavior changes, no touching unrelated code. The diff should be explainable as "removed the flag and its dead branch, kept the config-modes behavior."
- **If the two paths cannot be consolidated cleanly — STOP and alert the user.** Examples: the flag gates more than a simple branch, the two paths produce genuinely different outputs that callers depend on, or removing the legacy path changes a public signature in a way that ripples outside the callsite. Describe what you found and ask how to proceed rather than forcing it.
- This runs in a **Datadog workspace** (`IN_WORKSPACE=1`). Never run raw `git commit`/`git push`; use the `workspaces:create-and-push-commit` skill (see Step 6).
- Once local testing and validation (Step 5) pass, **automatically** open the PR as a **draft** (not ready for review) — no confirmation needed, since a draft isn't outward-facing. Do **not** mark it ready for review on your own. Integration/deploy to staging is a separate, explicitly-authorized action — do not do it unless the user asks.

## Step 1 — Read the ticket and find the callsite

1. Load the ticket via the Atlassian MCP. `get_issue` output is often huge and may exceed the tool token limit — when it does, it's written to a file; extract fields with `jq` instead of re-reading:
   ```bash
   jq '{summary: .fields.summary, description: .fields.description, status: .fields.status.name}' <saved-result-file>
   ```
   (Use `ToolSearch` to load `mcp__datadog-atlassian__get_issue` first.)
2. The ticket names a **File** and the cleanup scope (e.g. `dd-go/apps/metrics-querier/internal/planner/config.go (and associated tests)`). That file + its package is your callsite. Derive `<callsite>` for the PR title from the service/app dir (e.g. `metrics-querier`).
3. Sanity-check the instructions are clear; if the ticket is vague about what to remove, ask.

## Step 2 — Understand the two paths (do not skip)

Read the code thoroughly before editing. Map exactly what the flag gates.

- **The flag check** looks like a method such as `isConfigModeEnabled(ctx, orgID)` that calls `exp.IsEnabledWithFallback(..., "dataset_config_modes", func(codes.Code) bool { return true })`. Find every reference: `grep -rn "dataset_config_modes\|isConfigModeEnabled\|ConfigModeEnabled" <pkg>`.
- **Old path (flag OFF — to be deleted).** In the reference callsite this used:
  - `datasetsClient.GetDatasetFilters(ctx, &datasetsclient.GetDatasetFiltersRequest{... Authorization: datasetsclient.AuthorizationUnauthorized ...})`
  - returns `set.Set[string]`; always built `NOT IN` / ` AND ` predicates with **no surrounding parens**; empty result → `"", nil` (no error).
- **New path (flag ON — becomes the default).** Uses:
  - `datasetsClient.GetDatasets(ctx, &datasetsclient.GetDatasetRequest{... Authorization: datasetsclient.AuthorizationConfigModes ...})`
  - returns `*GetDatasetsResponse{ DatasetFilters: []DatasetFilters{ {Filters []string, Authorized bool} } }`.
  - Behavior: authorized → `IN`/` OR `; unauthorized → `NOT IN`/` AND `; result wrapped in `(...)`; `"*"` means no per-tag restriction (authorized `*` → `""` no filter; unauthorized `*` → null/no-access); **empty datasets list → error** ("no datasets found"); a dataset entry with empty `Filters` → "invalid dataset filter configuration" error.

Confirm the new path is reachable for all inputs the old path handled. If the new path errors where the old one returned empty (e.g. empty datasets), that's expected post-GA — Zoltron always returns datasets in config mode.

## Step 3 — Collapse to one path

In the config/flag file:
- Delete the flag accessor method (e.g. `isConfigModeEnabled`) entirely. Check whether imports it used (e.g. `codes`) are still needed elsewhere before assuming they can go.

In the logic file:
- Remove the `configModeEnabled` variable, its assignment, the parameter threaded into helpers, and any `span.SetTag("config_mode_enabled", ...)` derived purely from the flag.
- **Merge the two methods into one.** If there's a wrapper (`getDatasetFilters`) that branches to a `…ConfigEnabled` variant, fold the config-enabled body into the wrapper and delete the variant. Keep any non-flag gating that lived in the wrapper (e.g. an unrelated `remove-jwt-check-metrics-query` early-return — that's a *different* flag, leave it). Keep shared helpers (`mapDatasetFilters`, `sortDatasetFilters`, `buildPredicates`) — they're used by the surviving path.
- Normalize identifiers: error operation labels and span names that said `…ConfigEnabled` become the merged method's name.
- **Telemetry:** keep existing statsd metric names as-is (e.g. `metrics_querier.rbac.dataset_filters_config_enabled`) to avoid breaking dashboards/monitors. Flag renaming a now-legacy metric name to the user as an optional follow-up rather than doing it silently.

## Step 4 — Update and consolidate tests

Migrate every test off the old method's mock onto the new one. The mapping:

| Old (flag-off) | New (config-modes) |
|---|---|
| `mockClient.EXPECT().GetDatasetFilters(...).Return(set.New(filters...), nil)` | `mockClient.EXPECT().GetDatasets(...).Return(&datasetsclient.GetDatasetsResponse{DatasetFilters: []datasetsclient.DatasetFilters{{Filters: filters, Authorized: false}}}, nil)` |
| expected `"k NOT IN (v) AND ..."` (no parens) | expected `"(k NOT IN (v) AND ...)"` (**with** parens) |
| empty `set.New[string]()` meaning "no restriction" | `{Filters: []string{"*"}, Authorized: true}` → returns `""` |
| `.Return(nil, zoltronErr)` | `GetDatasets(...).Return(nil, zoltronErr)` (same wrap behavior downstream) |
| `.Times(0)` on `GetDatasetFilters` | `.Times(0)` on `GetDatasets` |
| `DoAndReturn(func(_, req *GetDatasetFiltersRequest)...)` | `DoAndReturn(func(_, req *GetDatasetRequest) (*GetDatasetsResponse, error){...})` |

Then consolidate:
- **Delete tests that only exercised the flag-off path** (and any test that is now a duplicate of an existing config-modes test).
- **Remove dead test helpers.** Deleting a test often orphans a helper (e.g. `initPlansWithFilterMappings`). An unused package-level func is a hard CI lint failure (`U1000`). After deleting tests, `grep -rn "<helper>"` to confirm callers remain; delete if none.
- **Fold standalone tests into tables.** If a `…ConfigEnabled` unit test exists separately, merge it into the main table-driven test; standalone single-case tests that differ only by one input (e.g. a `filterMappings` arg) become table rows. Add the differing input as a struct field and pass it in the loop. Drop unused struct fields you find while there (e.g. an `expectedErr` never read).
- Rename `…ConfigEnabled`-named test functions to the merged name and update the error-label assertions to match Step 3.
- **Preserve coverage.** Before claiming a fold is safe, confirm the moved rows use identical inputs/expectations to the deleted tests. If asked whether coverage dropped, prove it: `go test -run <Test> -coverprofile=/tmp/cov.out` then `go tool cover -func=/tmp/cov.out | grep <helper-func>`.

## Step 5 — Verify locally (dd-go env gotcha)

**Critical:** `dd-go` sets `GONOPROXY=github.com/DataDog`, which forces `dd-source` modules to resolve via direct git — they only exist on the magicmirror GOPROXY, so raw `go build/test` fails with `invalid version ... missing go.mod at revision`. Always prefix go commands with `GONOPROXY=none GOFLAGS=-mod=mod`:

```bash
cd <repo-root>
GONOPROXY=none GOFLAGS=-mod=mod go build ./<pkg>/
GONOPROXY=none GOFLAGS=-mod=mod go test ./<pkg>/ -run '<affected tests>' -count=1
gofmt -l <changed files>                       # must be empty
GONOPROXY=none GOFLAGS=-mod=mod go tool ddlint -errcheck ./<pkg>/   # CI's errcheck job
GONOPROXY=none GOFLAGS=-mod=mod go tool ddlint ./<pkg>/             # CI's lint (catches U1000 unused)
```
These compiles are slow (cold cache, large dep graph) and the unit test binary recompiles the whole package — run them in the background and watch with a Monitor until the process exits; don't fire redundant build+vet+test concurrently (they contend on the build cache). Run `ddlint` locally **before** pushing — the unused-helper lint is the most likely CI surprise and a full CI round-trip is expensive.

## Step 6 — Commit and open the PR (as a draft)

Once Step 5's local testing and validation pass, run this step automatically — do not stop to confirm. The PR is opened as a **draft** (not ready for review), so it's safe to create without asking.

1. Branch off the default branch (often `prod` in dd-go, not `main` — check `gh api repos/<owner>/<repo> --jq .default_branch`). Name it `<ticket>-<callsite>-dataset-config-cleanup` (lowercased).
2. Commit + push via the **`workspaces:create-and-push-commit`** skill (handles Claude co-authorship, the `Environment: Datadog workspace` trailer, and server-side re-signing). Note: the local `ddlint` pre-commit hook is usually **not installed** (`rake bootstrap` needed) and aborts the commit — `FMT` passes and ddlint runs in CI, so commit with `--no-verify`. Resolve the model identity for the trailer at runtime (e.g. `Claude Opus 4.8`).
3. Open the PR as a **draft** with `gh pr create --draft --base <default-branch>`:
   - **Title (exact format):** `[<ticket>] Non Dataset Config Deprecation for <callsite>` — e.g. `[AAE-84] Non Dataset Config Deprecation for metrics-querier`.
   - **Body** (mirror the AAE-84 PR):
     - `## What` — one line: the flag is GA'd; strict-mode/config-modes enforcement is now always-on; legacy path removed.
     - `### Changes` — bullet per file (flag accessor removed; methods merged into one; tests migrated/consolidated).
     - "No behavior change for orgs in production: the flag was already enabled everywhere."
     - `## How to test` — the `GONOPROXY=none GOFLAGS=-mod=mod go test ./<pkg>/ ...` command and a note that the targeted suite passes.
     - Link the Jira ticket; end with the Claude Code generated-with footer.
4. Trigger the review bot by posting `@codex review` as a PR comment:
   ```bash
   gh pr comment <pr-number> --body "@codex review"
   ```
   Report the PR URL to the user and note that it's a draft awaiting the Codex review.

## Step 7 — Babysit CI and review

Prefer the `dd:pr-babysit` skill if it's wired into the session. If it isn't (it's often project-scoped to `dd-source`), read its cached playbook and run its scripts directly:
`~/.claude/plugins/cache/datadog-claude-plugins/dd/*/skills/pr-babysit/scripts/poll-ci.sh <pr> 90 60` (background; blocks until an actionable state, then notifies). Fetch failing logs with the `fetch-ci-results` scripts: `get_ddci_logs.sh --list-failed <ddci-request-id>` then `get_ddci_logs.sh <job-id> <request-id> --summary`. The DDCI `request_id` is in the "DDCI Task Sourcing" check URL.

Classify and fix only PR-caused failures (in scope). Known patterns for this refactor:
- **`U1000 ... is unused`** on a test helper → you orphaned it deleting a test (Step 4). Remove it.
- **errcheck/lint failing while all unit/race/integration jobs pass** → it's a lint-only issue on the changed files, almost always the unused helper.
- **Logical conflict on the integration branch (only shows up at `ddr devflow integrate`, not on the PR):** another in-flight PR at a *different* GetDatasets callsite may still mock the old `GetDatasetFilters`. When your PR removes that method, the merged staging code fails with gomock `Unexpected call to GetDatasets ... missing call(s) to GetDatasetFilters`. This is NOT a defect in your PR (it's green on the default branch) and NOT retryable. Identify the other PR (`gh pr list --search`), and **alert the user** — whichever lands second must migrate that test; the merge-order/strategy is the user's call.

Poll review comments too and address actionable feedback (default: propose, don't auto-apply unless told).

## Quick reference — what AAE-84 touched (the reference implementation)

- `config.go`: deleted `isConfigModeEnabled`.
- `rbac.go`: dropped `configModeEnabled` var/param/span tags; folded `getDatasetFiltersConfigEnabled` into `getDatasetFilters`; deleted the old `GetDatasetFilters`/`AuthorizationUnauthorized` branch; kept `mapDatasetFilters`/`sortDatasetFilters`/`buildPredicates`.
- `config_test.go`: deleted the `isConfigModeEnabled` subtests.
- `rbac_test.go`: migrated all `GetDatasetFilters` mocks → `GetDatasets`; deleted the redundant tagMappings test; removed the orphaned `initPlansWithFilterMappings` helper; folded the `…ConfigEnabled` unit tests into the `validInputs` table.

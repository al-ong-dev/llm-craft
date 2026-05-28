# Scripts Reference (Inputs, Outputs, Edge Cases)

This document focuses on practical usage for the current scripts: expected input shape, output shape, and edge-case behavior.

All script files are located in `scripts/`.

## 1) Token utilities

### `estimate-tokens.ps1` / `estimate-tokens.sh`

Purpose: heuristic token estimate for text or file.

Example input:

```text
"Summarize auth middleware behavior."
```

Example output:

```json
{
  "characters": 35,
  "words": 4,
  "charHeuristic": 9,
  "wordHeuristic": 6,
  "tokenEstimate": 9
}
```

Edge cases:
- Empty input string -> estimate is `0`.
- File path not found -> script errors.
- Non-English / symbol-heavy text -> estimate can deviate more from provider tokenizers.

---

### `optimize-prompt.ps1` / `optimize-prompt.sh`

Purpose: compact prompt text by normalizing whitespace and dropping duplicate non-empty lines; optional token-budget trimming.

Example input:

```text
Please review this code.
Please review this code.

Focus   on   auth flow.
```

Example output:

```json
{
  "beforeTokenEstimate": 18,
  "afterTokenEstimate": 11,
  "reducedBy": 7,
  "outputFile": "",
  "optimizedText": "Please review this code.\n\nFocus on auth flow."
}
```

Edge cases:
- `--max-tokens` / `-MaxTokens` too low -> trailing sentence trimming may reduce text to near-empty.
- Prompts with intentionally repeated lines (for emphasis) -> repeats are removed.
- File mode with unreadable file -> script errors.

---

### `token-report.ps1` / `token-report.sh`

Purpose: estimate token and cost footprint for file or directory.

Example input:

```text
Target: ./docs
Input cost per 1K: 0.003
Output cost per 1K: 0.006
```

Example output:

```json
{
  "summary": {
    "fileCount": 42,
    "totalTokens": 128734,
    "totalInCost": 0.386202,
    "totalOutCost": 0.772404,
    "totalCost": 1.158606
  },
  "topFiles": [
    {
      "file": "docs/architecture.md",
      "size": 81234,
      "tokens": 21340,
      "inCost": 0.06402,
      "outCost": 0.12804,
      "totalCost": 0.19206
    }
  ]
}
```

Edge cases:
- Binary/unreadable files are skipped (or may produce empty text effects depending on platform tools).
- Very large files are ignored by some script paths (`>2MB` in PowerShell report logic).
- Costs set to `0` -> still reports token totals.

## 2) Code indexing and search

### `build-index.ps1` / `build-index.sh`

Purpose: recurse source files, chunk content, build searchable index.

Example input:

```text
Root path: .
Chunk lines: 40
Overlap: 10
```

Example output (PowerShell):

```json
{
  "root": "/repo",
  "files": 127,
  "totalChunks": 1490,
  "indexPath": "/repo/code-index.json"
}
```

Edge cases:
- Empty directory -> 0 files/chunks.
- Overlap >= chunk size -> validation error.
- Chunk boundaries are fixed windows, not semantic function/class boundaries.

---

### `smart-search.ps1` / `smart-search.sh`

Purpose: query index with TF-IDF ranking.

Example input:

```text
Query: "jwt middleware validate token header"
Top: 5
```

Example output:

```json
{
  "query": "jwt middleware validate token header",
  "mode": "keyword",
  "top": [
    {
      "score": 18.40213,
      "file": "src/auth/middleware.ts",
      "startLine": 42,
      "endLine": 80,
      "snippet": "export function validateToken(...) { ... }"
    }
  ]
}
```

Edge cases:
- Index missing -> script errors with message to build index first.
- Query with only punctuation -> "no searchable terms" error.
- Ambiguous keywords -> results may be broad unless query includes distinctive terms.

---

### `search-by-file-block.ps1` / `search-by-file-block.sh`

Purpose: search using a code snippet file as query body.

Example input:

```text
Snippet file: ./snippet.txt
```

Example output:

```json
{
  "mode": "code-block",
  "top": [
    {
      "file": "src/auth/middleware.ts",
      "startLine": 40,
      "endLine": 90
    }
  ]
}
```

Edge cases:
- Missing snippet file -> error.
- Very short snippet -> weak retrieval quality due to low term signal.

---

### Experimental pair

- `build-index.experimental.ps1`
- `smart-search.experimental.ps1`
- `search-by-file-block.experimental.ps1`

Purpose: isolate experimental retrieval behavior and data format from stable pipeline.

Default file separation:
- Stable index: `code-index.json`
- Experimental index: `code-index.experimental.json`

## 3) Copilot browser automation

### `copilot_daily_playwright.py`

Purpose: run daily Copilot prompts through browser automation with persistent session.

Example task input (`copilot-prompts.json`):

```json
{
  "tasks": [
    {
      "name": "standup-summary",
      "page_url": "https://github.com/copilot",
      "prompt": "Summarize yesterday's commits into concise standup bullets."
    }
  ]
}
```

Example output (`runs/copilot-results.json`):

```json
{
  "run_id": "20260528T032000Z",
  "task_count": 1,
  "results": [
    {
      "name": "standup-summary",
      "status": "ok",
      "response": "..."
    }
  ]
}
```

Edge cases:
- Selector drift in web UI -> task fails until selectors are updated in config.
- First run may require manual login.
- Network/latency spikes -> response timeout errors.

## 4) Atlassian sync and unified search

### `jira-sync.ps1` / `jira-sync.sh`

Purpose: fetch Jira issues by JQL into local JSON.

Example input:

```text
JQL: "project = ENG order by updated DESC"
Max: 200
```

Example output:

```json
{
  "source": "jira",
  "count": 200,
  "items": [
    {
      "key": "ENG-123",
      "summary": "Fix auth timeout",
      "status": "In Progress"
    }
  ]
}
```

Edge cases:
- Missing env vars (`ATLASSIAN_BASE_URL`, `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`) -> error.
- Invalid JQL or permissions -> API error.
- Large projects require pagination (already handled up to configured max).

---

### `confluence-sync.ps1` / `confluence-sync.sh`

Purpose: fetch Confluence pages by CQL into local JSON.

Example input:

```text
CQL: "space = ENG and type=page order by lastmodified desc"
Limit: 100
```

Example output:

```json
{
  "source": "confluence",
  "count": 100,
  "items": [
    {
      "id": "123456",
      "title": "Auth Runbook",
      "url": "https://.../wiki/..."
    }
  ]
}
```

Edge cases:
- Missing/expired API token -> 401/403 errors.
- CQL returns restricted pages -> partial result set.
- HTML stripping can remove some formatting context.

---

### `knowledge-search.ps1` / `knowledge-search.sh`

Purpose: unified relevance search across code index + Jira + Confluence snapshots.

Example input:

```text
Query: "release blocker auth regression"
Top: 10
```

Example output:

```json
{
  "query": "release blocker auth regression",
  "corpusSize": 2530,
  "top": [
    {
      "sourceType": "jira",
      "title": "Release blocker: token refresh fails",
      "url": "https://.../browse/ENG-932"
    },
    {
      "sourceType": "code",
      "title": "src/auth/refresh.ts:10-42"
    }
  ]
}
```

Edge cases:
- Missing one source file -> search still works on available sources.
- Missing all sources -> error.
- Very generic queries may over-return noisy matches.

## 5) Daily orchestration

### `daily-knowledge-refresh.ps1` / `daily-knowledge-refresh.sh`

Purpose: scheduled workflow to refresh sources and produce daily signal report.

Steps executed:
1. Build/refresh code index
2. Sync Jira snapshot
3. Sync Confluence snapshot
4. Run predefined signal queries
5. Write `reports/daily-signals.json`

Example output:

```json
{
  "generatedAt": "2026-05-28T03:30:00Z",
  "signals": [
    {
      "query": "production incident root cause",
      "top": [ { "sourceType": "jira", "title": "..." } ]
    }
  ]
}
```

Edge cases:
- Atlassian credentials missing -> sync phase fails.
- Bash path currently warns when JSON code index is absent (Jira+Confluence-only fallback).
- Query list can be customized; empty list yields empty signals array.

## 6) Local Ollama bounded generation

### `ollama-task.ps1` / `ollama-task.sh`

Purpose: run local Ollama chat with a hard input budget strategy for small-context tasks.

Default budget strategy:
- total budget: `4000`
- reserve for response: `1200`
- input allowance: `2800` minus instruction and fixed overhead
- context is line-trimmed to fit budget

Example input:

```text
Instruction: "Review this code and list top 5 bugs."
Context file: ./snippet.txt
Model: llama3.1:8b
```

Example output:

```json
{
  "model": "llama3.1:8b",
  "budgets": {
    "maxBudgetTokens": 4000,
    "reserveForResponse": 1200,
    "availableInput": 2800,
    "estimatedInput": 1640,
    "instructionTokens": 11,
    "contextBudget": 2669,
    "contextUsedTokens": 1509
  },
  "output": {
    "text": "Top risks: ...",
    "estimatedTokens": 320
  }
}
```

Edge cases:
- Ollama not running -> HTTP connection error.
- Unknown model name -> API error.
- Context too large -> automatically trimmed by line budget.
- If instruction alone is too large -> input budget failure error.

## 7) Local analyze (retrieval + local LLM)

### `local-analyze.ps1` / `local-analyze.sh`

Purpose: combine index retrieval with bounded local Ollama generation.

Inputs:
- `taskClass` (example: `risk-scan`, `snippet-summary`, `test-draft`)
- `query`
- optional custom instruction
- index path, top blocks, line cap per block
- Ollama model and budget settings

Example output:

```json
{
  "taskClass": "risk-scan",
  "query": "jwt middleware token refresh race condition",
  "retrieval": {
    "topBlocks": [
      { "file": "src/auth/middleware.ts", "startLine": 40, "endLine": 90, "score": 18.21, "snippet": "..." }
    ],
    "confidence": "medium"
  },
  "output": {
    "answer": "Likely race points are ...",
    "estimatedTokens": 420,
    "needsEscalation": false
  },
  "budgets": {
    "maxBudgetTokens": 4000,
    "availableInput": 2800,
    "estimatedInput": 1702
  }
}
```

Edge cases:
- No retrieval hits -> script errors (no evidence available).
- Ollama unavailable/model missing -> API error from `ollama-task`.
- Low retrieval confidence -> `needsEscalation` set to `true`.

## 8) Ticket triage orchestrator

### `triage-ticket.ps1` / `triage-ticket.sh`

Purpose: one-command triage for issue text, combining:
- cross-source retrieval (`knowledge-search`)
- code-grounded local analysis (`local-analyze`)
- structured report output

Input:
- ticket text
- optional task class
- index/data paths
- local model settings

Example output:

```json
{
  "generatedAt": "2026-05-28T04:05:00Z",
  "input": {
    "ticketText": "Users report random 401 after token refresh in mobile app",
    "taskClass": "risk-scan"
  },
  "summary": {
    "confidence": "medium",
    "needsEscalation": false
  },
  "knowledgeHits": [ { "sourceType": "jira", "title": "..." } ],
  "localAnalysis": { "output": { "answer": "..." } }
}
```

Edge cases:
- missing dependencies (`knowledge-search`, `local-analyze`) -> script error.
- no index hits for code analysis -> local analysis phase fails.
- local model unavailable -> report generation fails at analysis phase.

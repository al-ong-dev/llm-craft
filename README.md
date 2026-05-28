# Token Optimization Scripts (PowerShell + Bash)

These scripts help you reduce prompt size and estimate token/cost usage with PowerShell and Bash variants.

Detailed script behavior (inputs, outputs, edge cases): `SCRIPTS_REFERENCE.md`
Defined safe local task classes for Ollama: `OLLAMA_TASK_CATALOG.md`

All executable scripts now live under `scripts/`. Either:
- run commands from inside `scripts/`, or
- prefix script paths with `.\scripts\` (PowerShell) / `./scripts/` (Bash).

## 1) Estimate tokens

Estimate token usage for direct text:

```powershell
.\estimate-tokens.ps1 "Summarize this long content..."
```

Estimate token usage from a file:

```powershell
.\estimate-tokens.ps1 ".\prompt.txt" -IsFile
```

Bash equivalent:

```bash
./estimate-tokens.sh "Summarize this long content..."
./estimate-tokens.sh ./prompt.txt --file
```

## 2) Optimize prompt text

Compacts whitespace, removes duplicate lines, and optionally trims to a token budget.

From direct text:

```powershell
.\optimize-prompt.ps1 "Your very long prompt here..."
```

From file and write optimized output:

```powershell
.\optimize-prompt.ps1 ".\prompt.txt" -IsFile -MaxTokens 800 -OutputFile ".\prompt.optimized.txt"
```

Bash equivalent:

```bash
./optimize-prompt.sh "Your very long prompt here..."
./optimize-prompt.sh ./prompt.txt --file --max-tokens 800 --out ./prompt.optimized.txt
```

## 3) Create token/cost report

Analyze one file or a whole directory (recursively) and estimate input/output cost.

```powershell
.\token-report.ps1 ".\docs" -InputCostPer1k 0.003 -OutputCostPer1k 0.006
```

Bash equivalent:

```bash
./token-report.sh ./docs 0.003 0.006
```

The command returns JSON with:

- summary totals
- top files by estimated token count

## 4) Index-first code search (token saver)

Instead of scanning the whole repo each query, build an index once and search that index.

Build index:

```powershell
.\build-index.ps1 "."
```

Keyword search:

```powershell
.\smart-search.ps1 "jwt middleware validate token header" -Top 5
```

Search by code block text:

```powershell
.\smart-search.ps1 "function validateToken(req,res,next){...}" -AsCodeBlock -Top 5
```

Search by code block file:

```powershell
.\search-by-file-block.ps1 ".\snippet.txt" -Top 5
```

### Recommended daily flow for agents

1. Run `build-index.ps1` once at start of day (or after major code changes).
2. Use `smart-search.ps1` for queries instead of full directory scans.
3. Read only top 3-5 returned chunks/files.
4. Rebuild index when relevance drops (new modules/features added).

This approach sharply reduces repeated token usage from broad file reads.

## 5) Bash versions (Linux/macOS)

Scripts added:

- `estimate-tokens.sh`
- `optimize-prompt.sh`
- `token-report.sh`
- `build-index.sh`
- `smart-search.sh`
- `search-by-file-block.sh`

Make scripts executable:

```bash
chmod +x ./estimate-tokens.sh ./optimize-prompt.sh ./token-report.sh ./build-index.sh ./smart-search.sh ./search-by-file-block.sh
```

Build index:

```bash
./build-index.sh .
```

Keyword search:

```bash
./smart-search.sh "jwt middleware validate token header" ./code-index 5 keyword
```

Code-block similarity search:

```bash
./smart-search.sh "function validateToken(req,res,next){...}" ./code-index 5 code-block
```

Search by snippet file:

```bash
./search-by-file-block.sh ./snippet.txt ./code-index 5
```

## 6) Daily Copilot browser automation (Python + Playwright)

If you have Python available on the target machine, you can automate daily Copilot interactions in browser.

Files:

- `copilot_daily_playwright.py`
- `copilot-prompts.example.json`
- `copilot-config.example.json`

Setup:

```bash
python -m pip install playwright
python -m playwright install chromium
cp ./copilot-prompts.example.json ./copilot-prompts.json
cp ./copilot-config.example.json ./copilot-config.json
```

Run:

```bash
python ./copilot_daily_playwright.py --prompts ./copilot-prompts.json --config ./copilot-config.json --output ./runs/copilot-results.json
```

Notes:

- First run may require manual login in the opened browser window.
- Session is persisted in `./.pw-user-data`, so repeated runs usually skip login.
- For different Copilot pages/UIs, adjust selectors in `copilot-config.json`.
- Use `--headless` for unattended cron/CI runs after selectors are stable.

## 7) Atlassian API sync + unified search (Jira + Confluence)

These scripts sync Jira/Confluence into local JSON, then let you search code + Jira + Confluence together.

### PowerShell

Set credentials (PowerShell session):

```powershell
$env:ATLASSIAN_BASE_URL = "https://your-domain.atlassian.net"
$env:ATLASSIAN_EMAIL = "you@company.com"
$env:ATLASSIAN_API_TOKEN = "your_api_token"
```

Sync Jira and Confluence:

```powershell
.\jira-sync.ps1 -Jql "project = ENG order by updated DESC" -MaxResults 200 -OutputPath ".\data\jira-items.json"
.\confluence-sync.ps1 -Cql "space = ENG and type=page order by lastmodified desc" -Limit 100 -OutputPath ".\data\confluence-pages.json"
```

Run unified search:

```powershell
.\knowledge-search.ps1 "release bug root cause auth timeout" -Top 10
```

### Bash

Requires: `curl`, `jq`, `base64`

```bash
export ATLASSIAN_BASE_URL="https://your-domain.atlassian.net"
export ATLASSIAN_EMAIL="you@company.com"
export ATLASSIAN_API_TOKEN="your_api_token"
./jira-sync.sh "project = ENG order by updated DESC" 200 ./data/jira-items.json
./confluence-sync.sh "space = ENG and type=page order by lastmodified desc" 100 ./data/confluence-pages.json
./knowledge-search.sh "release bug root cause auth timeout" ./code-index.json ./data/jira-items.json ./data/confluence-pages.json 10
```

### Token optimization workflow

1. Build/refresh code index (`build-index`).
2. Sync Jira/Confluence snapshots once or on schedule.
3. Query `knowledge-search` first.
4. Open only top hits instead of scanning entire repos/pages/issues.

## 8) Daily scheduled refresh and signals report

Scripts:

- `daily-knowledge-refresh.ps1`
- `daily-knowledge-refresh.sh`

### PowerShell run

```powershell
.\daily-knowledge-refresh.ps1 -RootPath "." -CodeIndexPath ".\code-index.json" -JiraPath ".\data\jira-items.json" -ConfluencePath ".\data\confluence-pages.json" -ReportPath ".\reports\daily-signals.json"
```

### Bash run

```bash
./daily-knowledge-refresh.sh . ./code-index.json ./data/jira-items.json ./data/confluence-pages.json ./reports/daily-signals.json
```

Note: current Bash `build-index.sh` outputs `./code-index/` (directory index), while `knowledge-search.sh` expects JSON code index (`code-index.json`). If `code-index.json` is missing, daily signals still run using Jira + Confluence data only.

### Schedule examples

Windows Task Scheduler (daily at 8:00):

```powershell
schtasks /Create /SC DAILY /TN "DailyKnowledgeRefresh" /TR "powershell.exe -ExecutionPolicy Bypass -File C:\path\to\daily-knowledge-refresh.ps1" /ST 08:00
```

Linux/macOS cron (daily at 8:00):

```bash
0 8 * * * /absolute/path/daily-knowledge-refresh.sh /absolute/path/repo /absolute/path/repo/code-index.json /absolute/path/repo/data/jira-items.json /absolute/path/repo/data/confluence-pages.json /absolute/path/repo/reports/daily-signals.json
```

## 9) Local Ollama bounded task runner (4k budget)

Scripts:

- `ollama-task.ps1`
- `ollama-task.sh`

Goal: run local instruction + optional context with a token budget guard (default total budget: `4000`, response reserve: `1200`).

### PowerShell

```powershell
.\ollama-task.ps1 -Instruction "Summarize this file and list top 5 risks." -ContextFile ".\src\auth.ts" -Model "llama3.1:8b" -MaxBudgetTokens 4000 -ReserveForResponse 1200 -OutputPath ".\runs\ollama-result.json"
```

### Bash

```bash
./ollama-task.sh "Summarize this file and list top 5 risks." ./src/auth.ts llama3.1:8b http://127.0.0.1:11434 4000 1200 0.2 ./runs/ollama-result.json
```

Output includes:

- budget breakdown (`estimatedInput`, `contextBudget`, `contextUsedTokens`)
- model output text
- output token estimate

## 10) Local analyze pipeline (index blocks -> Ollama)

Scripts:

- `local-analyze.ps1`
- `local-analyze.sh`

Pipeline:
1. Retrieve top relevant code blocks from index search.
2. Trim each block to bounded lines.
3. Send merged context to `ollama-task`.
4. Return structured output with confidence + escalation flag.

### PowerShell

```powershell
.\local-analyze.ps1 -TaskClass "risk-scan" -Query "jwt middleware token refresh race condition" -IndexPath ".\code-index.json" -TopBlocks 5 -MaxLinesPerBlock 120 -Model "llama3.1:8b" -OutputPath ".\runs\local-analyze.json"
```

### Bash

```bash
./local-analyze.sh "risk-scan" "jwt middleware token refresh race condition" "" ./code-index 5 120 llama3.1:8b http://127.0.0.1:11434 4000 1200 0.2 ./runs/local-analyze.json
```

Response contains:
- `retrieval.topBlocks` (evidence snippets used)
- `retrieval.confidence` (`high|medium|low`)
- `output.answer`
- `output.needsEscalation` (true when retrieval confidence is low)
- `budgets` (token budget accounting from Ollama runner)

## 11) Ticket triage orchestrator (combined workflow)

Scripts:

- `triage-ticket.ps1`
- `triage-ticket.sh`

Pipeline:
1. run unified search (`knowledge-search`) for ticket context,
2. run retrieval-grounded code analysis (`local-analyze`),
3. write structured triage report JSON.

### PowerShell

```powershell
.\triage-ticket.ps1 -TicketText "Users report random 401 after token refresh in mobile app" -TaskClass "risk-scan" -IndexPath ".\code-index.json" -JiraPath ".\data\jira-items.json" -ConfluencePath ".\data\confluence-pages.json" -OutputPath ".\runs\triage-ticket.json"
```

### Bash

```bash
./triage-ticket.sh "Users report random 401 after token refresh in mobile app" risk-scan ./code-index.json ./data/jira-items.json ./data/confluence-pages.json 8 5 120 llama3.1:8b http://127.0.0.1:11434 4000 1200 0.2 ./runs/triage-ticket.json
```

Output summary includes:
- `summary.confidence`
- `summary.needsEscalation`
- `knowledgeHits` (cross-source context)
- `localAnalysis` (retrieval-backed local LLM answer)

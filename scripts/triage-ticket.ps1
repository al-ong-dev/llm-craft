param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TicketText,

    [string]$TaskClass = "risk-scan",
    [string]$IndexPath = ".\code-index.json",
    [string]$JiraPath = ".\data\jira-items.json",
    [string]$ConfluencePath = ".\data\confluence-pages.json",
    [int]$TopKnowledge = 8,
    [int]$TopCodeBlocks = 5,
    [int]$MaxLinesPerBlock = 120,
    [string]$Model = "llama3.1:8b",
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [int]$MaxBudgetTokens = 4000,
    [int]$ReserveForResponse = 1200,
    [double]$Temperature = 0.2,
    [string]$OutputPath = ".\runs\triage-ticket.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-LocalScript {
    param(
        [string]$ScriptName,
        [hashtable]$Params
    )
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing dependency script: $scriptPath"
    }
    & $scriptPath @Params
}

Write-Host "1/3 Running unified knowledge search..."
$knowledgeJson = Invoke-LocalScript -ScriptName "knowledge-search.ps1" -Params @{
    Query = $TicketText
    CodeIndexPath = $IndexPath
    JiraPath = $JiraPath
    ConfluencePath = $ConfluencePath
    Top = $TopKnowledge
}
$knowledge = $knowledgeJson | ConvertFrom-Json -Depth 10

Write-Host "2/3 Running retrieval-grounded local analysis..."
$instruction = @"
Task: $TaskClass
Goal: Triage this engineering ticket using retrieved code context and produce a practical next-step report.
Constraints:
- Keep output concise.
- Include:
  1) probable root cause areas
  2) impacted components
  3) immediate checks
  4) suggested owner role
  5) escalation recommendation

Ticket:
$TicketText
"@

$localJson = Invoke-LocalScript -ScriptName "local-analyze.ps1" -Params @{
    TaskClass = $TaskClass
    Query = $TicketText
    Instruction = $instruction
    IndexPath = $IndexPath
    TopBlocks = $TopCodeBlocks
    MaxLinesPerBlock = $MaxLinesPerBlock
    Model = $Model
    OllamaUrl = $OllamaUrl
    MaxBudgetTokens = $MaxBudgetTokens
    ReserveForResponse = $ReserveForResponse
    Temperature = $Temperature
}
$local = $localJson | ConvertFrom-Json -Depth 12

Write-Host "3/3 Writing triage report..."
$result = [pscustomobject]@{
    generatedAt = (Get-Date).ToString("o")
    input = [pscustomobject]@{
        ticketText = $TicketText
        taskClass = $TaskClass
    }
    knowledgeHits = $knowledge.top
    localAnalysis = $local
    summary = [pscustomobject]@{
        confidence = $local.retrieval.confidence
        needsEscalation = $local.output.needsEscalation
    }
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    confidence = $local.retrieval.confidence
    needsEscalation = $local.output.needsEscalation
} | ConvertTo-Json

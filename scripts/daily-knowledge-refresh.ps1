param(
    [string]$RootPath = ".",
    [string]$CodeIndexPath = ".\code-index.json",
    [string]$JiraPath = ".\data\jira-items.json",
    [string]$ConfluencePath = ".\data\confluence-pages.json",
    [string]$ReportPath = ".\reports\daily-signals.json",
    [string]$Jql = "order by updated DESC",
    [string]$Cql = "type=page order by lastmodified desc",
    [int]$JiraMax = 200,
    [int]$ConfluenceLimit = 100,
    [string[]]$Queries = @(
        "production incident root cause",
        "authentication timeout token",
        "release blocker regression",
        "oncall urgent bug",
        "test gap edge case"
    ),
    [int]$TopPerQuery = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-ScriptRelative {
    param([string]$ScriptName, [hashtable]$Params)
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Required script not found: $scriptPath"
    }
    & $scriptPath @Params
}

Write-Host "1/4 Building code index..."
Invoke-ScriptRelative -ScriptName "build-index.ps1" -Params @{
    RootPath = $RootPath
    IndexPath = $CodeIndexPath
} | Out-Null

Write-Host "2/4 Syncing Jira..."
Invoke-ScriptRelative -ScriptName "jira-sync.ps1" -Params @{
    Jql = $Jql
    MaxResults = $JiraMax
    OutputPath = $JiraPath
} | Out-Null

Write-Host "3/4 Syncing Confluence..."
Invoke-ScriptRelative -ScriptName "confluence-sync.ps1" -Params @{
    Cql = $Cql
    Limit = $ConfluenceLimit
    OutputPath = $ConfluencePath
} | Out-Null

Write-Host "4/4 Generating daily signals..."
$signals = New-Object System.Collections.Generic.List[object]
foreach ($q in $Queries) {
    $json = Invoke-ScriptRelative -ScriptName "knowledge-search.ps1" -Params @{
        Query = $q
        CodeIndexPath = $CodeIndexPath
        JiraPath = $JiraPath
        ConfluencePath = $ConfluencePath
        Top = $TopPerQuery
    }

    $parsed = $json | ConvertFrom-Json -Depth 10
    [void]$signals.Add([pscustomobject]@{
        query = $q
        top = $parsed.top
    })
}

$report = [pscustomobject]@{
    generatedAt = (Get-Date).ToString("o")
    inputs = [pscustomobject]@{
        rootPath = (Resolve-Path -LiteralPath $RootPath).Path
        codeIndexPath = $CodeIndexPath
        jiraPath = $JiraPath
        confluencePath = $ConfluencePath
    }
    signals = $signals
}

$reportDir = Split-Path -Parent $ReportPath
if ($reportDir) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8

[pscustomobject]@{
    reportPath = (Resolve-Path -LiteralPath $ReportPath).Path
    queries = $Queries.Count
} | ConvertTo-Json

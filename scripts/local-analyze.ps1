param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TaskClass,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Query,

    [string]$Instruction = "",
    [string]$IndexPath = ".\code-index.json",
    [int]$TopBlocks = 5,
    [int]$MaxLinesPerBlock = 120,
    [string]$Model = "llama3.1:8b",
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [int]$MaxBudgetTokens = 4000,
    [int]$ReserveForResponse = 1200,
    [double]$Temperature = 0.2,
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Limit-Lines {
    param([string]$Text, [int]$MaxLines)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $lines = ($Text -replace "`r`n", "`n") -split "`n"
    if ($lines.Count -le $MaxLines) { return $Text.Trim() }
    return (($lines | Select-Object -First $MaxLines) -join "`n").Trim()
}

function Build-Context {
    param([object[]]$Blocks, [int]$PerBlockLines)
    $parts = New-Object System.Collections.Generic.List[string]
    $i = 1
    foreach ($b in $Blocks) {
        $snippet = Limit-Lines -Text ([string]$b.snippet) -MaxLines $PerBlockLines
        $header = "[BLOCK {0}] file={1} lines={2}-{3} score={4}" -f $i, $b.file, $b.startLine, $b.endLine, $b.score
        [void]$parts.Add($header)
        [void]$parts.Add($snippet)
        [void]$parts.Add("")
        $i += 1
    }
    return ($parts -join "`n").Trim()
}

function Get-Confidence {
    param([object[]]$Blocks)
    if (-not $Blocks -or $Blocks.Count -eq 0) { return "low" }
    $topScore = [double]$Blocks[0].score
    $count = $Blocks.Count
    if ($topScore -ge 18 -and $count -ge 3) { return "high" }
    if ($topScore -ge 8 -and $count -ge 2) { return "medium" }
    return "low"
}

$searchScript = Join-Path $PSScriptRoot "smart-search.ps1"
if (-not (Test-Path -LiteralPath $searchScript)) {
    throw "Missing dependency: $searchScript"
}

$searchJson = & $searchScript -Query $Query -IndexPath $IndexPath -Top $TopBlocks -AsCodeBlock
$search = $searchJson | ConvertFrom-Json -Depth 10
$blocks = @($search.top)

if ($blocks.Count -eq 0) {
    throw "No relevant blocks found from index search."
}

$context = Build-Context -Blocks $blocks -PerBlockLines $MaxLinesPerBlock
$taskInstruction = if ([string]::IsNullOrWhiteSpace($Instruction)) {
@"
Task: $TaskClass
Goal: Answer the query using only the provided retrieved blocks.
Constraints:
- Be concise and actionable.
- If evidence is weak, say so explicitly.
- Output format:
  1) Answer
  2) Evidence blocks used
  3) Confidence (high|medium|low)
  4) Needs escalation (true|false)

Query:
$Query
"@
} else { $Instruction }

$tmpContext = Join-Path ([System.IO.Path]::GetTempPath()) ("local-analyze-context-{0}.txt" -f ([guid]::NewGuid().ToString("N")))
[System.IO.File]::WriteAllText($tmpContext, $context)

try {
    $ollamaScript = Join-Path $PSScriptRoot "ollama-task.ps1"
    if (-not (Test-Path -LiteralPath $ollamaScript)) {
        throw "Missing dependency: $ollamaScript"
    }

    $ollamaJson = & $ollamaScript `
        -Instruction $taskInstruction `
        -ContextFile $tmpContext `
        -Model $Model `
        -OllamaUrl $OllamaUrl `
        -MaxBudgetTokens $MaxBudgetTokens `
        -ReserveForResponse $ReserveForResponse `
        -Temperature $Temperature

    $ollama = $ollamaJson | ConvertFrom-Json -Depth 10
}
finally {
    if (Test-Path -LiteralPath $tmpContext) { Remove-Item -LiteralPath $tmpContext -Force }
}

$confidence = Get-Confidence -Blocks $blocks
$needsEscalation = ($confidence -eq "low")

$result = [pscustomobject]@{
    taskClass = $TaskClass
    query = $Query
    retrieval = [pscustomobject]@{
        topBlocks = $blocks
        confidence = $confidence
    }
    output = [pscustomobject]@{
        answer = $ollama.output.text
        estimatedTokens = $ollama.output.estimatedTokens
        needsEscalation = $needsEscalation
    }
    budgets = $ollama.budgets
}

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 12

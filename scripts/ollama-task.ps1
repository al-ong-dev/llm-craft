param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Instruction,

    [string]$ContextFile = "",
    [string]$Model = "llama3.1:8b",
    [string]$OllamaUrl = "http://127.0.0.1:11434",
    [int]$MaxBudgetTokens = 4000,
    [int]$ReserveForResponse = 1200,
    [double]$Temperature = 0.2,
    [string]$OutputPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Estimate-Tokens {
    param([string]$Text)
    $charCount = $Text.Length
    $wordCount = [regex]::Matches($Text, "\S+").Count
    $charHeuristic = [math]::Ceiling($charCount / 4.0)
    $wordHeuristic = [math]::Ceiling($wordCount / 0.75)
    return [math]::Max($charHeuristic, $wordHeuristic)
}

function Truncate-TextToBudget {
    param(
        [string]$Text,
        [int]$BudgetTokens
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    $lines = ($Text -replace "`r`n", "`n") -split "`n"
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        [void]$kept.Add($line)
        $candidate = ($kept -join "`n")
        if ((Estimate-Tokens -Text $candidate) -gt $BudgetTokens) {
            $kept.RemoveAt($kept.Count - 1)
            break
        }
    }
    return ($kept -join "`n").Trim()
}

$context = ""
if ($ContextFile) {
    if (-not (Test-Path -LiteralPath $ContextFile)) {
        throw "Context file not found: $ContextFile"
    }
    $context = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ContextFile))
}

$instructionTokens = Estimate-Tokens -Text $Instruction
$availableInputBudget = [Math]::Max(100, $MaxBudgetTokens - $ReserveForResponse)
$fixedOverhead = 120
$contextBudget = [Math]::Max(0, $availableInputBudget - $instructionTokens - $fixedOverhead)
$trimmedContext = Truncate-TextToBudget -Text $context -BudgetTokens $contextBudget

$prompt = @"
You are a local coding assistant. Keep answers concise and actionable.

Instruction:
$Instruction

Context:
$trimmedContext
"@

$estimatedInputTokens = Estimate-Tokens -Text $prompt
if ($estimatedInputTokens -gt $availableInputBudget) {
    throw "Input exceeds budget after trimming. estimatedInput=$estimatedInputTokens availableInput=$availableInputBudget"
}

$body = @{
    model = $Model
    stream = $false
    options = @{
        temperature = $Temperature
        num_predict = $ReserveForResponse
    }
    messages = @(
        @{ role = "system"; content = "You are concise, precise, and output practical steps." },
        @{ role = "user"; content = $prompt }
    )
} | ConvertTo-Json -Depth 8

$uri = "{0}/api/chat" -f $OllamaUrl.TrimEnd("/")
$resp = Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body $body

$answer = ""
if ($resp.message -and $resp.message.content) {
    $answer = [string]$resp.message.content
}

$result = [pscustomobject]@{
    model = $Model
    budgets = [pscustomobject]@{
        maxBudgetTokens = $MaxBudgetTokens
        reserveForResponse = $ReserveForResponse
        availableInput = $availableInputBudget
        estimatedInput = $estimatedInputTokens
        instructionTokens = $instructionTokens
        contextBudget = $contextBudget
        contextUsedTokens = Estimate-Tokens -Text $trimmedContext
    }
    output = [pscustomobject]@{
        text = $answer
        estimatedTokens = Estimate-Tokens -Text $answer
    }
}

if ($OutputPath) {
    $dir = Split-Path -Parent $OutputPath
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 8

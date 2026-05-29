param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputText,

    [switch]$IsFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TextContent {
    param(
        [string]$Value,
        [switch]$TreatAsFile
    )

    if ($TreatAsFile) {
        if (-not (Test-Path -LiteralPath $Value)) {
            throw "File not found: $Value"
        }

        return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Value))
    }

    return $Value
}

function Get-TokenEstimate {
    param(
        [string]$Text
    )

    $charCount = $Text.Length
    $wordMatches = [regex]::Matches($Text, "\S+")
    $wordCount = $wordMatches.Count

    # Two simple heuristics to avoid undercounting:
    # 1 token ~ 4 chars (English-heavy text)
    # 1 token ~ 0.75 words
    $charHeuristic = [math]::Ceiling($charCount / 4.0)
    $wordHeuristic = [math]::Ceiling($wordCount / 0.75)
    $estimate = [math]::Max($charHeuristic, $wordHeuristic)

    [pscustomobject]@{
        characters     = $charCount
        words          = $wordCount
        charHeuristic  = $charHeuristic
        wordHeuristic  = $wordHeuristic
        tokenEstimate  = $estimate
    }
}

$text = Get-TextContent -Value $InputText -TreatAsFile:$IsFile
$result = Get-TokenEstimate -Text $text
$result | ConvertTo-Json

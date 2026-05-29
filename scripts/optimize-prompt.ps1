param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputText,

    [switch]$IsFile,

    [int]$MaxTokens = 0,

    [string]$OutputFile = ""
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

function Estimate-Tokens {
    param([string]$Text)
    $charCount = $Text.Length
    $wordCount = [regex]::Matches($Text, "\S+").Count
    $charHeuristic = [math]::Ceiling($charCount / 4.0)
    $wordHeuristic = [math]::Ceiling($wordCount / 0.75)
    return [math]::Max($charHeuristic, $wordHeuristic)
}

function Optimize-Text {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n"
    $lines = $normalized -split "`n"

    $optimized = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]

    foreach ($line in $lines) {
        $trimmed = ($line -replace "\s+", " ").Trim()

        # Keep paragraph breaks, but collapse multiple blank lines.
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            if ($optimized.Count -eq 0 -or $optimized[$optimized.Count - 1] -eq "") {
                continue
            }
            [void]$optimized.Add("")
            continue
        }

        # Remove exact duplicate non-empty lines.
        if ($seen.Contains($trimmed)) {
            continue
        }
        [void]$seen.Add($trimmed)
        [void]$optimized.Add($trimmed)
    }

    return ($optimized -join "`n").Trim()
}

$original = Get-TextContent -Value $InputText -TreatAsFile:$IsFile
$optimized = Optimize-Text -Text $original

$beforeTokens = Estimate-Tokens -Text $original
$afterTokens = Estimate-Tokens -Text $optimized

if ($MaxTokens -gt 0) {
    while ((Estimate-Tokens -Text $optimized) -gt $MaxTokens -and $optimized.Length -gt 0) {
        # Remove one trailing sentence at a time to fit budget.
        $optimized = [regex]::Replace($optimized, "[^.!?]*[.!?]\s*$", "", 1).Trim()
        if ($optimized.Length -eq 0) {
            break
        }
    }
    $afterTokens = Estimate-Tokens -Text $optimized
}

if ($OutputFile) {
    [System.IO.File]::WriteAllText($OutputFile, $optimized)
}

[pscustomobject]@{
    beforeTokenEstimate = $beforeTokens
    afterTokenEstimate  = $afterTokens
    reducedBy           = ($beforeTokens - $afterTokens)
    outputFile          = $OutputFile
    optimizedText       = $optimized
} | ConvertTo-Json -Depth 5

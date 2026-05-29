param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TargetPath,

    [double]$InputCostPer1k = 0,
    [double]$OutputCostPer1k = 0
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

if (-not (Test-Path -LiteralPath $TargetPath)) {
    throw "Path not found: $TargetPath"
}

$files = @()
if ((Get-Item -LiteralPath $TargetPath) -is [System.IO.DirectoryInfo]) {
    $files = Get-ChildItem -LiteralPath $TargetPath -Recurse -File |
        Where-Object { $_.Length -lt 2MB }
}
else {
    $files = @(Get-Item -LiteralPath $TargetPath)
}

$rows = foreach ($file in $files) {
    try {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        $tokens = Estimate-Tokens -Text $content
        [pscustomobject]@{
            file     = $file.FullName
            size     = $file.Length
            tokens   = $tokens
            inCost   = [math]::Round(($tokens / 1000.0) * $InputCostPer1k, 6)
            outCost  = [math]::Round(($tokens / 1000.0) * $OutputCostPer1k, 6)
            totalCost = [math]::Round((($tokens / 1000.0) * ($InputCostPer1k + $OutputCostPer1k)), 6)
        }
    }
    catch {
        # Skip binary/unreadable files.
    }
}

$summary = [pscustomobject]@{
    fileCount    = $rows.Count
    totalTokens  = ($rows | Measure-Object -Property tokens -Sum).Sum
    totalInCost  = [math]::Round((($rows | Measure-Object -Property inCost -Sum).Sum), 6)
    totalOutCost = [math]::Round((($rows | Measure-Object -Property outCost -Sum).Sum), 6)
    totalCost    = [math]::Round((($rows | Measure-Object -Property totalCost -Sum).Sum), 6)
}

[pscustomobject]@{
    summary = $summary
    topFiles = $rows | Sort-Object -Property tokens -Descending | Select-Object -First 20
} | ConvertTo-Json -Depth 6

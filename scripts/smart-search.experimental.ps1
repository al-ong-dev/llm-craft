param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Query,

    [string]$IndexPath = ".\code-index.experimental.json",
    [int]$Top = 10,
    [switch]$AsCodeBlock
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Terms {
    param([string]$Text)
    $matches = [regex]::Matches($Text.ToLowerInvariant(), "[a-z0-9_]{2,}")
    $terms = New-Object System.Collections.Generic.List[string]
    foreach ($m in $matches) { [void]$terms.Add($m.Value) }
    return $terms
}

function Build-QueryTF {
    param([string[]]$Terms)
    $map = @{}
    foreach ($t in $Terms) {
        if (-not $map.ContainsKey($t)) { $map[$t] = 0 }
        $map[$t] += 1
    }
    return $map
}

if (-not (Test-Path -LiteralPath $IndexPath)) {
    throw "Experimental index file not found: $IndexPath. Run build-index.experimental.ps1 first."
}

$indexRaw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $IndexPath))
$index = $indexRaw | ConvertFrom-Json -Depth 12

$queryTerms = Get-Terms -Text $Query
if ($queryTerms.Count -eq 0) {
    throw "Query does not contain searchable terms."
}

$queryTF = Build-QueryTF -Terms $queryTerms
$N = [double]$index.totalChunks
$scores = @{}
$matches = @{}

foreach ($term in $queryTF.Keys) {
    if (-not $index.postings.PSObject.Properties.Name.Contains($term)) {
        continue
    }

    $df = [double]$index.docFreq.$term
    $idf = [Math]::Log(1 + ($N / (1 + $df)))
    $qWeight = (1 + [Math]::Log(1 + $queryTF[$term])) * $idf

    foreach ($post in $index.postings.$term) {
        $chunkId = [int]$post.chunkId
        $tf = [double]$post.tf
        $dWeight = 1 + [Math]::Log(1 + $tf)

        if (-not $scores.ContainsKey($chunkId)) { $scores[$chunkId] = 0.0 }
        $scores[$chunkId] += $qWeight * $dWeight

        if (-not $matches.ContainsKey($chunkId)) {
            $matches[$chunkId] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$matches[$chunkId].Add($term)
    }
}

if ($AsCodeBlock) {
    # For code blocks, heavily reward lexical overlap ratio.
    $querySet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($t in $queryTerms) { [void]$querySet.Add($t) }

    foreach ($k in @($scores.Keys)) {
        $chunk = $index.chunks[$k]
        $chunkSet = New-Object System.Collections.Generic.HashSet[string]
        foreach ($t in $chunk.terms) { [void]$chunkSet.Add($t) }

        $intersect = 0
        foreach ($t in $querySet) {
            if ($chunkSet.Contains($t)) { $intersect += 1 }
        }
        $union = $querySet.Count + $chunkSet.Count - $intersect
        $jaccard = if ($union -gt 0) { $intersect / $union } else { 0.0 }
        $scores[$k] = $scores[$k] + (10.0 * $jaccard)
    }
}

$results = foreach ($pair in $scores.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First $Top) {
    $chunk = $index.chunks[[int]$pair.Key]
    [pscustomobject]@{
        score         = [Math]::Round([double]$pair.Value, 5)
        file          = $chunk.relFile
        startLine     = $chunk.startLine
        endLine       = $chunk.endLine
        matchedTerms  = @($matches[[int]$pair.Key])
        snippet       = ($chunk.content -split "`n" | Select-Object -First 10) -join "`n"
    }
}

[pscustomobject]@{
    query       = $Query
    mode        = if ($AsCodeBlock) { "code-block" } else { "keyword" }
    totalChunks = $index.totalChunks
    top         = $results
} | ConvertTo-Json -Depth 6

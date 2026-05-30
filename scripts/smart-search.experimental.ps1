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

function ConvertFrom-JsonSafe {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json
    if ($command.Parameters.ContainsKey("AsHashtable")) {
        return $Json | ConvertFrom-Json -AsHashtable
    }

    return $Json | ConvertFrom-Json
}

function Get-JsonValue {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object[$Name]
    }

    return $Object.$Name
}

function Test-JsonKey {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }

    return $Object.PSObject.Properties.Name.Contains($Name)
}

if (-not (Test-Path -LiteralPath $IndexPath)) {
    throw "Experimental index file not found: $IndexPath. Run build-index.experimental.ps1 first."
}

$indexRaw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $IndexPath))
$index = ConvertFrom-JsonSafe -Json $indexRaw

$queryTerms = Get-Terms -Text $Query
if ($queryTerms.Count -eq 0) {
    throw "Query does not contain searchable terms."
}

$queryTF = Build-QueryTF -Terms $queryTerms
$postings = Get-JsonValue -Object $index -Name "postings"
$docFreq = Get-JsonValue -Object $index -Name "docFreq"
$chunks = Get-JsonValue -Object $index -Name "chunks"
$totalChunks = Get-JsonValue -Object $index -Name "totalChunks"
$N = [double]$totalChunks
$scores = @{}
$matches = @{}

foreach ($term in $queryTF.Keys) {
    if (-not (Test-JsonKey -Object $postings -Name $term)) {
        continue
    }

    $df = [double](Get-JsonValue -Object $docFreq -Name $term)
    $idf = [Math]::Log(1 + ($N / (1 + $df)))
    $qWeight = (1 + [Math]::Log(1 + $queryTF[$term])) * $idf

    foreach ($post in (Get-JsonValue -Object $postings -Name $term)) {
        $chunkId = [int](Get-JsonValue -Object $post -Name "chunkId")
        $tf = [double](Get-JsonValue -Object $post -Name "tf")
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
        $chunk = $chunks[$k]
        $chunkSet = New-Object System.Collections.Generic.HashSet[string]
        foreach ($t in (Get-JsonValue -Object $chunk -Name "terms")) { [void]$chunkSet.Add($t) }

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
    $chunk = $chunks[[int]$pair.Key]
    [pscustomobject]@{
        score         = [Math]::Round([double]$pair.Value, 5)
        file          = Get-JsonValue -Object $chunk -Name "relFile"
        startLine     = Get-JsonValue -Object $chunk -Name "startLine"
        endLine       = Get-JsonValue -Object $chunk -Name "endLine"
        matchedTerms  = @($matches[[int]$pair.Key])
        snippet       = ((Get-JsonValue -Object $chunk -Name "content") -split "`n" | Select-Object -First 10) -join "`n"
    }
}

[pscustomobject]@{
    query       = $Query
    mode        = if ($AsCodeBlock) { "code-block" } else { "keyword" }
    totalChunks = $totalChunks
    top         = @($results)
} | ConvertTo-Json -Depth 6

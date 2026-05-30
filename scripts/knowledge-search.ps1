param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Query,

    [string]$CodeIndexPath = ".\code-index.json",
    [string]$JiraPath = ".\data\jira-items.json",
    [string]$ConfluencePath = ".\data\confluence-pages.json",
    [int]$Top = 10
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

function Build-TF {
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

$docs = New-Object System.Collections.Generic.List[object]
$id = 0

if (Test-Path -LiteralPath $CodeIndexPath) {
    $code = ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $CodeIndexPath)))
    foreach ($c in (Get-JsonValue -Object $code -Name "chunks")) {
        $relFile = Get-JsonValue -Object $c -Name "relFile"
        $startLine = Get-JsonValue -Object $c -Name "startLine"
        $endLine = Get-JsonValue -Object $c -Name "endLine"
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "code"
            title = ("{0}:{1}-{2}" -f $relFile, $startLine, $endLine)
            path  = $relFile
            url   = ""
            text  = [string](Get-JsonValue -Object $c -Name "content")
        })
        $id += 1
    }
}

if (Test-Path -LiteralPath $JiraPath) {
    $jira = ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $JiraPath)))
    foreach ($j in (Get-JsonValue -Object $jira -Name "items")) {
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "jira"
            title = [string](Get-JsonValue -Object $j -Name "summary")
            path  = [string](Get-JsonValue -Object $j -Name "key")
            url   = [string](Get-JsonValue -Object $j -Name "url")
            text  = [string](Get-JsonValue -Object $j -Name "text")
        })
        $id += 1
    }
}

if (Test-Path -LiteralPath $ConfluencePath) {
    $conf = ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfluencePath)))
    foreach ($p in (Get-JsonValue -Object $conf -Name "items")) {
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "confluence"
            title = [string](Get-JsonValue -Object $p -Name "title")
            path  = [string](Get-JsonValue -Object $p -Name "space")
            url   = [string](Get-JsonValue -Object $p -Name "url")
            text  = [string](Get-JsonValue -Object $p -Name "text")
        })
        $id += 1
    }
}

if ($docs.Count -eq 0) {
    throw "No sources found. Provide code index and/or Jira/Confluence data files."
}

$tfByDoc = @{}
$df = @{}

foreach ($d in $docs) {
    $terms = Get-Terms -Text $d.text
    $tf = Build-TF -Terms $terms
    $tfByDoc[$d.id] = $tf
    foreach ($term in $tf.Keys) {
        if (-not $df.ContainsKey($term)) { $df[$term] = 0 }
        $df[$term] += 1
    }
}

$qTerms = Get-Terms -Text $Query
if ($qTerms.Count -eq 0) { throw "Query has no searchable terms." }
$qtf = Build-TF -Terms $qTerms

$N = [double]$docs.Count
$scores = @{}
$matched = @{}

foreach ($term in $qtf.Keys) {
    if (-not $df.ContainsKey($term)) { continue }
    $idf = [Math]::Log(1 + ($N / (1 + [double]$df[$term])))
    $qWeight = (1 + [Math]::Log(1 + $qtf[$term])) * $idf

    foreach ($d in $docs) {
        $tf = $tfByDoc[$d.id]
        if (-not $tf.ContainsKey($term)) { continue }
        $dWeight = 1 + [Math]::Log(1 + [double]$tf[$term])
        if (-not $scores.ContainsKey($d.id)) { $scores[$d.id] = 0.0 }
        $scores[$d.id] += $qWeight * $dWeight
        if (-not $matched.ContainsKey($d.id)) {
            $matched[$d.id] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$matched[$d.id].Add($term)
    }
}

$byId = @{}
foreach ($d in $docs) { $byId[$d.id] = $d }

$topResults = foreach ($pair in $scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top) {
    $d = $byId[[int]$pair.Key]
    [pscustomobject]@{
        score        = [Math]::Round([double]$pair.Value, 5)
        sourceType   = $d.type
        title        = $d.title
        path         = $d.path
        url          = $d.url
        matchedTerms = @($matched[[int]$pair.Key])
        snippet      = (($d.text -split "`n" | Select-Object -First 6) -join "`n")
    }
}

[pscustomobject]@{
    query = $Query
    corpusSize = $docs.Count
    top = @($topResults)
} | ConvertTo-Json -Depth 6

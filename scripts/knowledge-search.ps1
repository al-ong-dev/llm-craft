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

$docs = New-Object System.Collections.Generic.List[object]
$id = 0

if (Test-Path -LiteralPath $CodeIndexPath) {
    $code = ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $CodeIndexPath))) | ConvertFrom-Json -Depth 12
    foreach ($c in $code.chunks) {
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "code"
            title = "{0}:{1}-{2}" -f $c.relFile, $c.startLine, $c.endLine
            path  = $c.relFile
            url   = ""
            text  = [string]$c.content
        })
        $id += 1
    }
}

if (Test-Path -LiteralPath $JiraPath) {
    $jira = ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $JiraPath))) | ConvertFrom-Json -Depth 10
    foreach ($j in $jira.items) {
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "jira"
            title = [string]$j.summary
            path  = [string]$j.key
            url   = [string]$j.url
            text  = [string]$j.text
        })
        $id += 1
    }
}

if (Test-Path -LiteralPath $ConfluencePath) {
    $conf = ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfluencePath))) | ConvertFrom-Json -Depth 10
    foreach ($p in $conf.items) {
        [void]$docs.Add([pscustomobject]@{
            id    = $id
            type  = "confluence"
            title = [string]$p.title
            path  = [string]$p.space
            url   = [string]$p.url
            text  = [string]$p.text
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

$top = foreach ($pair in $scores.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $Top) {
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
    top = $top
} | ConvertTo-Json -Depth 6

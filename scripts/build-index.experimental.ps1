param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$IndexPath = ".\code-index.experimental.json",

    [int]$ChunkLines = 40,
    [int]$ChunkOverlap = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FileList {
    param([string]$BasePath)

    $allowed = @(
        "*.ps1", "*.psm1", "*.py", "*.js", "*.jsx", "*.ts", "*.tsx",
        "*.java", "*.go", "*.rs", "*.cs", "*.cpp", "*.c", "*.h",
        "*.json", "*.md", "*.yaml", "*.yml", "*.toml", "*.sql", "*.sh"
    )

    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($pattern in $allowed) {
        Get-ChildItem -LiteralPath $BasePath -Recurse -File -Filter $pattern |
            ForEach-Object { [void]$files.Add($_) }
    }

    return $files | Sort-Object -Property FullName -Unique
}

function Get-Terms {
    param([string]$Text)

    $normalized = $Text.ToLowerInvariant()
    $matches = [regex]::Matches($normalized, "[a-z0-9_]{2,}")
    $terms = New-Object System.Collections.Generic.List[string]

    foreach ($m in $matches) {
        $t = $m.Value
        if ($t.Length -ge 2 -and $t.Length -le 40) {
            [void]$terms.Add($t)
        }
    }

    return $terms
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $method = [System.IO.Path].GetMethods() |
        Where-Object { $_.Name -eq "GetRelativePath" -and $_.GetParameters().Count -eq 2 } |
        Select-Object -First 1

    if ($method) {
        return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath)
    }

    $baseFull = [System.IO.Path]::GetFullPath($BasePath)
    if (-not $baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $targetFull = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relativeUri = $baseUri.MakeRelativeUri($targetUri)
    $relativePath = [System.Uri]::UnescapeDataString($relativeUri.ToString())

    return $relativePath -replace '/', [System.IO.Path]::DirectorySeparatorChar
}

function New-Chunks {
    param(
        [string]$Text,
        [int]$Window,
        [int]$Overlap
    )

    $lines = ($Text -replace "`r`n", "`n") -split "`n"
    if ($lines.Count -eq 0) {
        return @()
    }

    $step = [Math]::Max(1, $Window - $Overlap)
    $chunks = New-Object System.Collections.Generic.List[object]

    for ($start = 0; $start -lt $lines.Count; $start += $step) {
        $endExclusive = [Math]::Min($lines.Count, $start + $Window)
        $slice = $lines[$start..($endExclusive - 1)]
        $content = ($slice -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }

        [void]$chunks.Add([pscustomobject]@{
            startLine = $start + 1
            endLine   = $endExclusive
            content   = $content
        })

        if ($endExclusive -eq $lines.Count) {
            break
        }
    }

    return $chunks
}

if (-not (Test-Path -LiteralPath $RootPath)) {
    throw "Path not found: $RootPath"
}

$root = (Resolve-Path -LiteralPath $RootPath).Path
$files = Get-FileList -BasePath $root

$chunks = New-Object System.Collections.Generic.List[object]
$postings = @{}
$docFreq = @{}
$totalChunks = 0
$chunkId = 0

foreach ($file in $files) {
    $text = ""
    try {
        $text = [System.IO.File]::ReadAllText($file.FullName)
    }
    catch {
        continue
    }

    $fileChunks = New-Chunks -Text $text -Window $ChunkLines -Overlap $ChunkOverlap
    foreach ($c in $fileChunks) {
        $terms = Get-Terms -Text $c.content
        if ($terms.Count -eq 0) {
            continue
        }

        $tf = @{}
        foreach ($term in $terms) {
            if (-not $tf.ContainsKey($term)) { $tf[$term] = 0 }
            $tf[$term] += 1
        }

        $distinct = @($tf.Keys | ForEach-Object { [string]$_ })
        foreach ($term in $distinct) {
            if (-not $postings.ContainsKey($term)) {
                $postings[$term] = New-Object System.Collections.Generic.List[object]
            }
            [void]$postings[$term].Add([pscustomobject]@{
                chunkId = $chunkId
                tf      = $tf[$term]
            })

            if (-not $docFreq.ContainsKey($term)) { $docFreq[$term] = 0 }
            $docFreq[$term] += 1
        }

        [void]$chunks.Add([pscustomobject]@{
            id        = $chunkId
            file      = $file.FullName
            relFile   = Get-RelativePathCompat -BasePath $root -TargetPath $file.FullName
            startLine = $c.startLine
            endLine   = $c.endLine
            length    = $terms.Count
            content   = $c.content
            terms     = $distinct
        })

        $chunkId += 1
        $totalChunks += 1
    }
}

$index = [pscustomobject]@{
    version     = 1
    root        = $root
    generatedAt = (Get-Date).ToString("o")
    totalChunks = $totalChunks
    docFreq     = $docFreq
    postings    = $postings
    chunks      = $chunks
}

$json = $index | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($IndexPath, $json)

[pscustomobject]@{
    root       = $root
    files      = $files.Count
    totalChunks = $totalChunks
    indexPath  = (Resolve-Path -LiteralPath $IndexPath).Path
} | ConvertTo-Json

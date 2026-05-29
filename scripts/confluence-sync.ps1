param(
    [string]$BaseUrl = $env:ATLASSIAN_BASE_URL,
    [string]$Email = $env:ATLASSIAN_EMAIL,
    [string]$ApiToken = $env:ATLASSIAN_API_TOKEN,
    [string]$Cql = "type=page order by lastmodified desc",
    [int]$Limit = 100,
    [string]$OutputPath = ".\data\confluence-pages.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-AuthHeader {
    param([string]$User, [string]$Token)
    $raw = "{0}:{1}" -f $User, $Token
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
    return @{ Authorization = "Basic $b64"; Accept = "application/json" }
}

function Remove-Html {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return "" }
    $text = [regex]::Replace($Html, "<script[\s\S]*?</script>", "", "IgnoreCase")
    $text = [regex]::Replace($text, "<style[\s\S]*?</style>", "", "IgnoreCase")
    $text = [regex]::Replace($text, "<[^>]+>", " ")
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text = [regex]::Replace($text, "\s+", " ")
    return $text.Trim()
}

if ([string]::IsNullOrWhiteSpace($BaseUrl) -or [string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($ApiToken)) {
    throw "Missing auth env vars. Set ATLASSIAN_BASE_URL, ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN."
}

$headers = New-AuthHeader -User $Email -Token $ApiToken
$items = New-Object System.Collections.Generic.List[object]
$start = 0
$pageSize = [Math]::Min(50, [Math]::Max(1, $Limit))

while ($items.Count -lt $Limit) {
    $remaining = $Limit - $items.Count
    $take = [Math]::Min($pageSize, $remaining)
    $uri = "{0}/wiki/rest/api/search?cql={1}&start={2}&limit={3}" -f $BaseUrl.TrimEnd("/"), [uri]::EscapeDataString($Cql), $start, $take
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if (-not $resp.results -or $resp.results.Count -eq 0) { break }

    foreach ($r in $resp.results) {
        if (-not $r.content -or -not $r.content.id) { continue }
        $contentId = [string]$r.content.id
        $pageUri = "{0}/wiki/rest/api/content/{1}?expand=body.storage,version,space" -f $BaseUrl.TrimEnd("/"), $contentId
        $page = Invoke-RestMethod -Method Get -Uri $pageUri -Headers $headers
        $html = ""
        if ($page.body -and $page.body.storage) { $html = [string]$page.body.storage.value }
        $text = Remove-Html -Html $html

        $webPath = ""
        if ($page._links -and $page._links.webui) { $webPath = [string]$page._links.webui }
        $fullUrl = if ($webPath) { "{0}/wiki{1}" -f $BaseUrl.TrimEnd("/"), $webPath } else { "" }

        [void]$items.Add([pscustomobject]@{
            source     = "confluence"
            id         = $contentId
            title      = $page.title
            space      = if ($page.space) { $page.space.key } else { "" }
            updated    = if ($page.version) { $page.version.when } else { "" }
            url        = $fullUrl
            excerpt    = if ($r.excerpt) { Remove-Html -Html ([string]$r.excerpt) } else { "" }
            bodyText   = $text
            text       = @($page.title, $text) -join "`n"
        })
    }

    $start += $resp.results.Count
    if ($resp.results.Count -lt $take) { break }
}

$payload = [pscustomobject]@{
    source      = "confluence"
    generatedAt = (Get-Date).ToString("o")
    baseUrl     = $BaseUrl
    cql         = $Cql
    count       = $items.Count
    items       = $items
}

$outDir = Split-Path -Parent $OutputPath
if ($outDir) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8

[pscustomobject]@{
    outputPath = (Resolve-Path -LiteralPath $OutputPath).Path
    count      = $items.Count
} | ConvertTo-Json

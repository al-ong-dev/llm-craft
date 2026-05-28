param(
    [string]$BaseUrl = $env:ATLASSIAN_BASE_URL,
    [string]$Email = $env:ATLASSIAN_EMAIL,
    [string]$ApiToken = $env:ATLASSIAN_API_TOKEN,
    [string]$Jql = "order by updated DESC",
    [int]$MaxResults = 200,
    [string]$OutputPath = ".\data\jira-items.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-AuthHeader {
    param([string]$User, [string]$Token)
    $raw = "{0}:{1}" -f $User, $Token
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($raw))
    return @{ Authorization = "Basic $b64"; Accept = "application/json" }
}

function Get-TextFromAdfNode {
    param([object]$Node)
    if ($null -eq $Node) { return "" }

    if ($Node -is [string]) { return $Node }
    if ($Node.PSObject.Properties.Name -contains "text") {
        return [string]$Node.text
    }

    $parts = New-Object System.Collections.Generic.List[string]
    if ($Node.PSObject.Properties.Name -contains "content" -and $Node.content) {
        foreach ($child in $Node.content) {
            $t = Get-TextFromAdfNode -Node $child
            if (-not [string]::IsNullOrWhiteSpace($t)) {
                [void]$parts.Add($t)
            }
        }
    }

    return ($parts -join " ").Trim()
}

if ([string]::IsNullOrWhiteSpace($BaseUrl) -or [string]::IsNullOrWhiteSpace($Email) -or [string]::IsNullOrWhiteSpace($ApiToken)) {
    throw "Missing auth env vars. Set ATLASSIAN_BASE_URL, ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN."
}

$headers = New-AuthHeader -User $Email -Token $ApiToken
$items = New-Object System.Collections.Generic.List[object]
$startAt = 0
$pageSize = [Math]::Min(100, [Math]::Max(1, $MaxResults))

while ($items.Count -lt $MaxResults) {
    $remaining = $MaxResults - $items.Count
    $take = [Math]::Min($pageSize, $remaining)
    $uri = "{0}/rest/api/3/search?jql={1}&startAt={2}&maxResults={3}&fields=summary,status,assignee,updated,description,comment" -f $BaseUrl.TrimEnd("/"), [uri]::EscapeDataString($Jql), $startAt, $take
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if (-not $resp.issues -or $resp.issues.Count -eq 0) { break }

    foreach ($issue in $resp.issues) {
        $desc = Get-TextFromAdfNode -Node $issue.fields.description
        $comments = @()
        if ($issue.fields.comment -and $issue.fields.comment.comments) {
            foreach ($c in $issue.fields.comment.comments | Select-Object -First 5) {
                $body = Get-TextFromAdfNode -Node $c.body
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    $comments += $body
                }
            }
        }

        [void]$items.Add([pscustomobject]@{
            source      = "jira"
            key         = $issue.key
            id          = $issue.id
            url         = ("{0}/browse/{1}" -f $BaseUrl.TrimEnd("/"), $issue.key)
            summary     = $issue.fields.summary
            status      = $issue.fields.status.name
            assignee    = if ($issue.fields.assignee) { $issue.fields.assignee.displayName } else { "" }
            updated     = $issue.fields.updated
            description = $desc
            comments    = $comments
            text        = @($issue.key, $issue.fields.summary, $desc, ($comments -join " ")) -join "`n"
        })
    }

    $startAt += $resp.issues.Count
    if ($resp.issues.Count -lt $take) { break }
}

$payload = [pscustomobject]@{
    source      = "jira"
    generatedAt = (Get-Date).ToString("o")
    baseUrl     = $BaseUrl
    jql         = $Jql
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

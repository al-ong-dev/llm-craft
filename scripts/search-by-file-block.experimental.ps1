param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$CodeFile,

    [string]$IndexPath = ".\code-index.experimental.json",
    [int]$Top = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $CodeFile)) {
    throw "Code file not found: $CodeFile"
}

$query = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $CodeFile))

& "$PSScriptRoot\smart-search.experimental.ps1" -Query $query -IndexPath $IndexPath -Top $Top -AsCodeBlock

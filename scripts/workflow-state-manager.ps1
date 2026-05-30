param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
    @"
Usage:
  pwsh -File scripts\workflow-state-manager.ps1 <command> [args]

Commands:
  list                                List all active workflows
  status <workflow_id>                Show workflow status and votes
  phase <workflow_id> [phase_num]     Show votes for phase
  agent <workflow_id> <agent> [phase] Show an agent's votes
  escalation <workflow_id>            Show escalation details
  escalations                         List all escalated workflows
  export <workflow_id> [txt|json]     Export workflow report
  consensus <workflow_id> <phase>     Check consensus for phase
  cleanup [days]                      Remove workflows older than N days
"@
}

function Write-Log {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"), $Message)
}

function ConvertFrom-JsonSafe {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json
    if ($command.Parameters.ContainsKey("AsHashtable")) {
        return $Json | ConvertFrom-Json -AsHashtable
    }

    return $Json | ConvertFrom-Json
}

function Read-JsonFile {
    param([string]$Path)
    return ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path)))
}

function Get-JsonValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }

    return $Default
}

function ConvertTo-PrettyJson {
    param([object]$Value)
    return $Value | ConvertTo-Json -Depth 20
}

function Require-Arg {
    param(
        [string[]]$Values,
        [int]$Index,
        [string]$Usage
    )

    if ($Index -ge $Values.Count) {
        throw "Usage: $Usage"
    }

    return $Values[$Index]
}

function Get-StateFile {
    param([string]$WorkflowId)
    return Join-Path $script:StateDir "$WorkflowId.json"
}

function Get-VotesFile {
    param([string]$WorkflowId)
    return Join-Path $script:StateDir "$WorkflowId-votes.json"
}

function Get-EscalationFile {
    param([string]$WorkflowId)
    return Join-Path $script:LogDir "$WorkflowId-escalation.log"
}

function Get-Votes {
    param([string]$WorkflowId)

    $votesFile = Get-VotesFile -WorkflowId $WorkflowId
    if (-not (Test-Path -LiteralPath $votesFile)) {
        return @()
    }

    $votesJson = Read-JsonFile -Path $votesFile
    return @(Get-JsonValue -Object $votesJson -Name "votes" -Default @())
}

function Command-List {
    Write-Log "Active workflows:"
    if (-not (Test-Path -LiteralPath $script:StateDir)) {
        Write-Host "  (no workflows)"
        return
    }

    $files = Get-ChildItem -LiteralPath $script:StateDir -Filter "wf-*.json" -File |
        Where-Object { $_.Name -notlike "*-votes.json" }

    if (-not $files) {
        Write-Host "  (no workflows)"
        return
    }

    foreach ($file in $files) {
        $state = Read-JsonFile -Path $file.FullName
        $workflowId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $created = Get-JsonValue -Object $state -Name "created_at" -Default "unknown"
        $status = Get-JsonValue -Object $state -Name "status" -Default "unknown"
        $phase = Get-JsonValue -Object $state -Name "current_phase" -Default "0"
        "{0,-30} | Status: {1,-12} | Phase: {2} | Created: {3}" -f $workflowId, $status, $phase, $created
    }
}

function Command-Status {
    param([string]$WorkflowId)

    $stateFile = Get-StateFile -WorkflowId $WorkflowId
    if (-not (Test-Path -LiteralPath $stateFile)) {
        throw "Workflow not found: $WorkflowId"
    }

    Write-Log "=== Workflow: $WorkflowId ==="
    ConvertTo-PrettyJson -Value (Read-JsonFile -Path $stateFile)

    Write-Host ""
    Write-Log "=== Votes ==="
    $votes = Get-Votes -WorkflowId $WorkflowId
    if ($votes.Count -eq 0) {
        Write-Log "No votes recorded"
    }
    else {
        $votes |
            ForEach-Object {
                "{0}:{1}={2}" -f (Get-JsonValue $_ "phase"), (Get-JsonValue $_ "agent_id"), (Get-JsonValue $_ "decision")
            } |
            Sort-Object -Unique
    }

    Write-Host ""
    Write-Log "=== Escalations ==="
    $escalationFile = Get-EscalationFile -WorkflowId $WorkflowId
    if (Test-Path -LiteralPath $escalationFile) {
        ConvertTo-PrettyJson -Value (Read-JsonFile -Path $escalationFile)
    }
    else {
        Write-Log "No escalations"
    }
}

function Command-Phase {
    param(
        [string]$WorkflowId,
        [string]$PhaseNumber
    )

    $votes = Get-Votes -WorkflowId $WorkflowId
    if ($votes.Count -eq 0) {
        throw "Workflow not found or has no votes: $WorkflowId"
    }

    if (-not $PhaseNumber) {
        Write-Log "=== All Phases ==="
        $votes |
            Group-Object { Get-JsonValue $_ "phase" } |
            Sort-Object Name |
            ForEach-Object {
                $decisions = $_.Group |
                    ForEach-Object { Get-JsonValue $_ "decision" } |
                    Sort-Object -Unique
                "Phase {0}: {1}" -f $_.Name, ($decisions -join ", ")
            }
    }
    else {
        Write-Log "=== Phase $PhaseNumber ==="
        $votes |
            Where-Object { [string](Get-JsonValue $_ "phase") -eq [string]$PhaseNumber } |
            ForEach-Object {
                "{0}: {1} ({2}) // {3}" -f (Get-JsonValue $_ "agent_id"), (Get-JsonValue $_ "decision"), (Get-JsonValue $_ "confidence"), (Get-JsonValue $_ "rationale")
            }
    }
}

function Command-Agent {
    param(
        [string]$WorkflowId,
        [string]$AgentId,
        [string]$PhaseNumber
    )

    $votes = Get-Votes -WorkflowId $WorkflowId
    $agentVotes = $votes | Where-Object { [string](Get-JsonValue $_ "agent_id") -eq $AgentId }
    if ($PhaseNumber) {
        $agentVotes = $agentVotes | Where-Object { [string](Get-JsonValue $_ "phase") -eq [string]$PhaseNumber }
    }

    ConvertTo-PrettyJson -Value @($agentVotes)
}

function Command-Escalation {
    param([string]$WorkflowId)

    $escalationFile = Get-EscalationFile -WorkflowId $WorkflowId
    if (-not (Test-Path -LiteralPath $escalationFile)) {
        throw "No escalation recorded for workflow: $WorkflowId"
    }

    Write-Log "=== Escalation Details ==="
    ConvertTo-PrettyJson -Value (Read-JsonFile -Path $escalationFile)
}

function Command-Escalations {
    Write-Log "Escalated workflows:"
    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        Write-Host "  (no escalations)"
        return
    }

    $files = Get-ChildItem -LiteralPath $script:LogDir -Filter "*-escalation.log" -File
    if (-not $files) {
        Write-Host "  (no escalations)"
        return
    }

    foreach ($file in $files) {
        $esc = Read-JsonFile -Path $file.FullName
        $workflowId = $file.Name -replace "-escalation\.log$", ""
        $phase = Get-JsonValue -Object $esc -Name "phase_reached" -Default "unknown"
        $reason = Get-JsonValue -Object $esc -Name "escalation_reason" -Default "unknown"
        "{0,-30} | Phase: {1,-2} | Reason: {2}" -f $workflowId, $phase, $reason
    }
}

function Command-Export {
    param(
        [string]$WorkflowId,
        [string]$Format = "txt"
    )

    $stateFile = Get-StateFile -WorkflowId $WorkflowId
    $votesFile = Get-VotesFile -WorkflowId $WorkflowId
    if (-not (Test-Path -LiteralPath $stateFile)) {
        throw "Workflow not found: $WorkflowId"
    }

    $state = Read-JsonFile -Path $stateFile
    $votes = if (Test-Path -LiteralPath $votesFile) { Read-JsonFile -Path $votesFile } else { @{ votes = @() } }

    if ($Format -eq "json") {
        ConvertTo-PrettyJson -Value ([pscustomobject]@{
            state = $state
            votes = $votes
        })
        return
    }

    Write-Host "=== WORKFLOW REPORT: $WorkflowId ==="
    Write-Host ""
    Write-Host "STATE:"
    (ConvertTo-PrettyJson -Value $state) -split "`n" | ForEach-Object { "  $_" }
    Write-Host ""
    Write-Host "VOTES:"
    foreach ($vote in @(Get-JsonValue -Object $votes -Name "votes" -Default @())) {
        "  {0}:{1}={2} ({3})" -f (Get-JsonValue $vote "phase"), (Get-JsonValue $vote "agent_id"), (Get-JsonValue $vote "decision"), (Get-JsonValue $vote "confidence")
    }
}

function Command-Consensus {
    param(
        [string]$WorkflowId,
        [string]$PhaseNumber
    )

    $votes = Get-Votes -WorkflowId $WorkflowId |
        Where-Object { [string](Get-JsonValue $_ "phase") -eq [string]$PhaseNumber }
    $voteCount = @($votes).Count
    $proceedCount = @($votes | Where-Object { (Get-JsonValue $_ "decision") -eq "proceed" }).Count

    Write-Log "Phase $PhaseNumber Consensus Check:"
    Write-Log "  Total votes: $voteCount"
    Write-Log "  Proceed votes: $proceedCount"

    if ($voteCount -eq 5 -and $proceedCount -eq 5) {
        Write-Log "  CONSENSUS REACHED"
        return
    }

    Write-Log "  CONSENSUS FAILED"
    Write-Log ""
    Write-Log "  Votes:"
    $votes | ForEach-Object {
        "  {0}: {1}" -f (Get-JsonValue $_ "agent_id"), (Get-JsonValue $_ "decision")
    }
    exit 1
}

function Command-Cleanup {
    param([int]$KeepDays = 7)

    Write-Log "Cleaning up workflows older than $KeepDays days..."
    $cutoff = (Get-Date).AddDays(-$KeepDays)
    foreach ($dir in @($script:StateDir, $script:LogDir)) {
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -File |
                Where-Object { $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force
        }
    }
    Write-Log "Cleanup complete"
}

$scriptDir = $PSScriptRoot
$projectDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..")).Path
$script:StateDir = Join-Path $projectDir "workflow-state"
$script:LogDir = Join-Path $projectDir "workflow-logs"

$command = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "list" }

switch ($command) {
    "list" { Command-List }
    "status" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "status <workflow_id>"
        Command-Status -WorkflowId $workflowId
    }
    "phase" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "phase <workflow_id> [phase_num]"
        $phaseNumber = if ($Arguments.Count -gt 2) { $Arguments[2] } else { "" }
        Command-Phase -WorkflowId $workflowId -PhaseNumber $phaseNumber
    }
    "agent" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "agent <workflow_id> <agent> [phase]"
        $agentId = Require-Arg -Values $Arguments -Index 2 -Usage "agent <workflow_id> <agent> [phase]"
        $phaseNumber = if ($Arguments.Count -gt 3) { $Arguments[3] } else { "" }
        Command-Agent -WorkflowId $workflowId -AgentId $agentId -PhaseNumber $phaseNumber
    }
    "escalation" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "escalation <workflow_id>"
        Command-Escalation -WorkflowId $workflowId
    }
    "escalations" { Command-Escalations }
    "export" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "export <workflow_id> [txt|json]"
        $format = if ($Arguments.Count -gt 2) { $Arguments[2] } else { "txt" }
        Command-Export -WorkflowId $workflowId -Format $format
    }
    "consensus" {
        $workflowId = Require-Arg -Values $Arguments -Index 1 -Usage "consensus <workflow_id> <phase>"
        $phaseNumber = Require-Arg -Values $Arguments -Index 2 -Usage "consensus <workflow_id> <phase>"
        Command-Consensus -WorkflowId $workflowId -PhaseNumber $phaseNumber
    }
    "cleanup" {
        $keepDays = if ($Arguments.Count -gt 1) { [int]$Arguments[1] } else { 7 }
        Command-Cleanup -KeepDays $keepDays
    }
    "--help" { Show-Help }
    "-h" { Show-Help }
    default {
        Show-Help
        exit 1
    }
}

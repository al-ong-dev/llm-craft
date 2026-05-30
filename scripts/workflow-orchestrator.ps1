param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
    @"
Run the 9-phase consensus workflow.

USAGE:
  pwsh -File scripts\workflow-orchestrator.ps1 <task_file> [--headless]

OPTIONS:
  --headless      Create the psmux session, run, then clean it up
  --no-session    Run without creating a psmux session
  --help          Show this help message
"@
}

function ConvertTo-JsonFile {
    param(
        [object]$Value,
        [string]$Path,
        [int]$Depth = 20
    )

    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth $Depth))
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

function Set-JsonValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    $Object.$Name = $Value
}

function New-WorkflowId {
    $randomBytes = [byte[]]::new(4)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
    $random = [System.BitConverter]::ToString($randomBytes).Replace("-", "").ToLowerInvariant()
    return "wf-{0}-{1}" -f ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()), $random
}

function Write-WorkflowLog {
    param(
        [string]$Level,
        [string]$Message
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ"), $Level, $Message
    Add-Content -LiteralPath $script:WorkflowLog -Value $line
    Write-Host $line
}

function Get-TmuxCommand {
    $command = Get-Command tmux -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command psmux -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Neither tmux nor psmux was found on PATH."
}

function Invoke-Tmux {
    param([string[]]$TmuxArgs)

    & $script:Tmux @TmuxArgs
    if ($LASTEXITCODE -ne 0) {
        throw "tmux command failed: $($TmuxArgs -join ' ')"
    }
}

function Invoke-TmuxOptional {
    param([string[]]$TmuxArgs)
    & $script:Tmux @TmuxArgs | Out-Null
}

function Send-PaneLine {
    param(
        [int]$Pane,
        [string]$Text
    )

    $escaped = $Text -replace "'", "''"
    Invoke-Tmux -TmuxArgs @("send-keys", "-t", "$($script:SessionName):0.$Pane", "Write-Host '$escaped'", "Enter")
}

function Initialize-WorkflowState {
    param([string]$TaskFile)

    # Load task file
    $taskJson = ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $TaskFile)))
     
    # Extract task description (try multiple property names for compatibility)
    $script:TaskDescription = Get-JsonValue -Object $taskJson -Name "task" -Default ""
    if ([string]::IsNullOrEmpty($script:TaskDescription)) {
        $script:TaskDescription = Get-JsonValue -Object $taskJson -Name "title" -Default ""
    }
    if ([string]::IsNullOrEmpty($script:TaskDescription)) {
        $script:TaskDescription = Get-JsonValue -Object $taskJson -Name "description" -Default ""
    }
    if ([string]::IsNullOrEmpty($script:TaskDescription)) {
        $script:TaskDescription = "Task: $($taskJson | ConvertTo-Json -Compress)"
    }
     
    $script:ScriptDir = $PSScriptRoot

    $agents = @(
        [pscustomobject]@{ id = "researcher"; status = "pending"; pane = "0"; phase = 0 },
        [pscustomobject]@{ id = "implementer"; status = "pending"; pane = "1"; phase = 0 },
        [pscustomobject]@{ id = "reviewer-quality"; status = "pending"; pane = "2"; phase = 0 },
        [pscustomobject]@{ id = "reviewer-security"; status = "pending"; pane = "3"; phase = 0 },
        [pscustomobject]@{ id = "ops"; status = "pending"; pane = "4"; phase = 0 }
    )

    $state = [pscustomobject]@{
        workflow_id = $script:WorkflowId
        created_at = $script:Timestamp
        status = "initialized"
        current_phase = 1
        task_file = $TaskFile
        task_description = $script:TaskDescription
        agents = $agents
    }

    ConvertTo-JsonFile -Value $state -Path $script:StateFile

    $votes = [pscustomobject]@{
        workflow_id = $script:WorkflowId
        votes = @()
        consensus_history = @()
    }
    ConvertTo-JsonFile -Value $votes -Path $script:VotesFile

    Write-WorkflowLog -Level "INFO" -Message "Workflow state initialized: $($script:WorkflowId)"
}

function Update-WorkflowStatus {
    param(
        [string]$Status,
        [int]$CurrentPhase
    )

    $state = Read-JsonFile -Path $script:StateFile
    Set-JsonValue -Object $state -Name "status" -Value $Status
    Set-JsonValue -Object $state -Name "current_phase" -Value $CurrentPhase
    ConvertTo-JsonFile -Value $state -Path $script:StateFile
}

function Create-PsmuxSession {
    if ($script:NoSession) {
        Write-WorkflowLog -Level "INFO" -Message "Skipping psmux session creation"
        return
    }

    $script:Tmux = Get-TmuxCommand
    Write-WorkflowLog -Level "INFO" -Message "Creating psmux session: $($script:SessionName)"
    Invoke-TmuxOptional -TmuxArgs @("kill-session", "-t", $script:SessionName)
    Invoke-Tmux -TmuxArgs @("new-session", "-d", "-s", $script:SessionName, "-x", "200", "-y", "50")
    Invoke-Tmux -TmuxArgs @("split-window", "-h", "-t", $script:SessionName, "-p", "50")
    Invoke-Tmux -TmuxArgs @("split-window", "-v", "-t", $script:SessionName, "-p", "66")
    Invoke-Tmux -TmuxArgs @("split-window", "-v", "-t", $script:SessionName, "-p", "50")
    Invoke-Tmux -TmuxArgs @("select-pane", "-t", "${script:SessionName}:0")
    Invoke-Tmux -TmuxArgs @("split-window", "-v", "-t", $script:SessionName, "-p", "50")
    Write-WorkflowLog -Level "INFO" -Message "psmux session created with 5 panes"

    if (-not $script:Headless) {
        Write-Host "psmux session '$($script:SessionName)' created"
        Write-Host "Attach with: tmux attach -t $($script:SessionName)"
    }
}

function Submit-AgentVote {
    param(
        [string]$AgentId,
        [int]$Phase,
        [string]$Decision,
        [string]$Confidence,
        [string]$Rationale
    )

    $votes = Read-JsonFile -Path $script:VotesFile
    $currentVotes = @(Get-JsonValue -Object $votes -Name "votes" -Default @())
    $vote = [pscustomobject]@{
        workflow_id = $script:WorkflowId
        phase = $Phase
        agent_id = $AgentId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        status = "submitted"
        decision = $Decision
        confidence = $Confidence
        rationale = $Rationale
        findings = @()
        questions = @()
    }

    Set-JsonValue -Object $votes -Name "votes" -Value @($currentVotes + $vote)
    ConvertTo-JsonFile -Value $votes -Path $script:VotesFile
}

function Run-AgentPhase {
    param(
        [string]$AgentId,
        [int]$Phase,
        [int]$Pane
    )

    Write-WorkflowLog -Level "INFO" -Message "Running agent '$AgentId' for phase $Phase"
     
    # Define phase names outside try block to avoid scoping issues
    $phaseNames = @("intake", "research", "plan", "quality_review", "security_review", "ops_review", "decision", "execute", "verify")
    $phaseName = $phaseNames[$Phase - 1]
    $taskDesc = $script:TaskDescription
     
    # Call copilot CLI to get agent vote
    try {
        # Build agent-specific prompt for each phase
        $agentPrompt = switch ($AgentId) {
            "researcher" { ("As a researcher agent analyzing: '{0}'. For the {1} phase, should we proceed, escalate, block, or request more info? Reply with ONLY the word: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
            "implementer" { ("As an implementer reviewing: '{0}'. Can this be implemented in the {1} phase? Reply with ONLY: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
            "reviewer-quality" { ("As a quality reviewer for: '{0}'. Is code quality acceptable for {1}? Reply with ONLY: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
            "reviewer-security" { ("As a security reviewer of: '{0}'. Are security concerns addressed for {1}? Reply with ONLY: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
            "ops" { ("As an ops agent for: '{0}'. Is operational readiness met for {1}? Reply with ONLY: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
            default { ("Review task: '{0}'. Vote for phase {1}. Reply with ONLY: proceed, escalate, blocked, or needs_info" -f $taskDesc, $phaseName) }
        }
         
        if (-not $script:NoSession) {
            Send-PaneLine -Pane $Pane -Text "copilot -p (agent $AgentId)"
        }
         
        # Call copilot CLI (non-interactive with -p flag)
        $copilotOutput = & copilot -p $agentPrompt 2>&1 | Out-String
         
        # Parse decision from first line (Copilot returns answer first, then metadata)
        $lines = $copilotOutput -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        $firstLine = if ($lines.Count -gt 0) { $lines[0] } else { $copilotOutput.Trim() }
         
        # Extract decision from response
        $decision = "proceed"
        if ($firstLine -match '\b(proceed|escalate|blocked|needs_info)\b') {
            $decision = $matches[1]
        } elseif ($firstLine -match '(cannot|blocked|fail|issue|problem|concern)') {
            $decision = "escalate"
        }
         
        $confidence = if ($copilotOutput -match 'high|certain|clear|definitely') { "high" } else { "medium" }
        $rationale = $firstLine.Substring(0, [Math]::Min(200, $firstLine.Length))
         
        Submit-AgentVote -AgentId $AgentId -Phase $Phase -Decision $decision -Confidence $confidence -Rationale $rationale
        Write-WorkflowLog -Level "INFO" -Message "Agent '$AgentId' voted: $decision (confidence: $confidence)"
    }
    catch {
        Write-WorkflowLog -Level "WARN" -Message "Copilot call failed for agent '$AgentId' phase $Phase, escalating: $_"
        Submit-AgentVote -AgentId $AgentId -Phase $Phase -Decision "escalate" -Confidence "low" -Rationale "Copilot call failed"
    }
}

function Check-Consensus {
    param([int]$Phase)

    $votes = Read-JsonFile -Path $script:VotesFile
    $phaseVotes = @(Get-JsonValue -Object $votes -Name "votes" -Default @() |
        Where-Object { [int](Get-JsonValue $_ "phase") -eq $Phase })
    $proceedVotes = @($phaseVotes | Where-Object { (Get-JsonValue $_ "decision") -eq "proceed" })

    Write-WorkflowLog -Level "INFO" -Message "Phase ${Phase}: $($phaseVotes.Count) votes collected"
    if ($phaseVotes.Count -eq 5 -and $proceedVotes.Count -eq 5) {
        Write-WorkflowLog -Level "INFO" -Message "CONSENSUS REACHED: All agents vote 'proceed'"
        return $true
    }

    Write-WorkflowLog -Level "WARN" -Message "CONSENSUS FAILED: $($proceedVotes.Count)/5 agents vote 'proceed'"
    return $false
}

function Escalate-Workflow {
    param(
        [int]$Phase,
        [string]$Reason
    )

    Write-WorkflowLog -Level "WARN" -Message "Escalating workflow at phase ${Phase}: $Reason"
    $escalation = [pscustomobject]@{
        workflow_id = $script:WorkflowId
        escalated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        phase_reached = $Phase
        escalation_reason = $Reason
        state_file = $script:StateFile
        votes_file = $script:VotesFile
        human_action_required = $true
        resumable = $true
        next_steps = @(
            "Review escalation log: $($script:EscalationLog)",
            "Read agent opinions: $($script:VotesFile)",
            "Modify task or agent instructions",
            "Run workflow-orchestrator.ps1 again with the updated task file"
        )
    }
    ConvertTo-JsonFile -Value $escalation -Path $script:EscalationLog
    Update-WorkflowStatus -Status "escalated" -CurrentPhase $Phase
}

function Run-WorkflowPhases {
    $phaseNames = @(
        "intake",
        "research",
        "plan",
        "quality_review",
        "security_review",
        "ops_review",
        "decision",
        "execute",
        "verify"
    )
    $agents = @("researcher", "implementer", "reviewer-quality", "reviewer-security", "ops")

    for ($phase = 1; $phase -le 9; $phase++) {
        Update-WorkflowStatus -Status "running" -CurrentPhase $phase
        Write-WorkflowLog -Level "INFO" -Message "========== PHASE $phase`: $($phaseNames[$phase - 1]) =========="

        for ($i = 0; $i -lt $agents.Count; $i++) {
            Run-AgentPhase -AgentId $agents[$i] -Phase $phase -Pane $i
        }

        if (-not (Check-Consensus -Phase $phase)) {
            Escalate-Workflow -Phase $phase -Reason "dissent"
            return $false
        }

        Write-WorkflowLog -Level "INFO" -Message "Phase $phase complete: consensus reached"
    }

    Update-WorkflowStatus -Status "complete" -CurrentPhase 9
    Write-WorkflowLog -Level "INFO" -Message "========== WORKFLOW COMPLETE =========="
    return $true
}

function Cleanup-Psmux {
    if ($script:Headless -and -not $script:NoSession) {
        Write-WorkflowLog -Level "INFO" -Message "Killing psmux session $($script:SessionName)"
        Invoke-TmuxOptional -TmuxArgs @("kill-session", "-t", $script:SessionName)
    }
}

$headless = $false
$noSession = $false
$taskFileArg = ""

for ($i = 0; $i -lt $Arguments.Count; $i++) {
    switch ($Arguments[$i]) {
        "--headless" { $headless = $true }
        "--no-session" { $noSession = $true }
        "--help" {
            Show-Help
            exit 0
        }
        "-h" {
            Show-Help
            exit 0
        }
        default {
            if (-not $taskFileArg) {
                $taskFileArg = $Arguments[$i]
            }
            else {
                throw "Unknown option: $($Arguments[$i])"
            }
        }
    }
}

if (-not $taskFileArg) {
    Show-Help
    exit 1
}

if (-not (Test-Path -LiteralPath $taskFileArg)) {
    throw "Task file not found: $taskFileArg"
}

$scriptDir = $PSScriptRoot
$projectDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..")).Path
$stateDir = Join-Path $projectDir "workflow-state"
$logDir = Join-Path $projectDir "workflow-logs"
New-Item -ItemType Directory -Path $stateDir, $logDir -Force | Out-Null

$script:WorkflowId = New-WorkflowId
$script:SessionName = "agent-consensus-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$script:Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$script:StateFile = Join-Path $stateDir "$($script:WorkflowId).json"
$script:VotesFile = Join-Path $stateDir "$($script:WorkflowId)-votes.json"
$script:WorkflowLog = Join-Path $logDir "$($script:WorkflowId).log"
$script:EscalationLog = Join-Path $logDir "$($script:WorkflowId)-escalation.log"
$script:Headless = $headless
$script:NoSession = $noSession
$script:Tmux = $null

New-Item -ItemType File -Path $script:WorkflowLog -Force | Out-Null

Write-WorkflowLog -Level "INFO" -Message "Starting workflow orchestrator"
Initialize-WorkflowState -TaskFile (Resolve-Path -LiteralPath $taskFileArg).Path
Create-PsmuxSession

$ok = $false
try {
    $ok = Run-WorkflowPhases
}
finally {
    Cleanup-Psmux
}

if ($ok) {
    Write-Host ""
    Write-Host "Workflow complete: $($script:WorkflowId)"
    Write-Host "State: $($script:StateFile)"
    Write-Host "Votes: $($script:VotesFile)"
    Write-Host "Log: $($script:WorkflowLog)"
    exit 0
}

Write-Host ""
Write-Host "Workflow escalated: $($script:WorkflowId)"
Write-Host "Escalation: $($script:EscalationLog)"
exit 1

param(
    [Parameter(Mandatory = $true)]
    [string]$SessionName,

    [Parameter(Mandatory = $true)]
    [string]$WorkflowId,

    [string]$Task = "",
    [string]$Provider = "claude",
    [int]$Budget = 100000,
    [switch]$NoAttach
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Escape-SingleQuotedString {
    param([string]$Value)
    return $Value -replace "'", "''"
}

function Send-Line {
    param(
        [string]$Pane,
        [string]$Command
    )

    Invoke-Tmux -TmuxArgs @("send-keys", "-t", $Pane, $Command, "Enter")
}

function Send-WriteHostLines {
    param(
        [string]$Pane,
        [string[]]$Lines
    )

    foreach ($line in $Lines) {
        $escaped = Escape-SingleQuotedString -Value $line
        Send-Line -Pane $Pane -Command "Write-Host '$escaped'"
    }
}

$script:Tmux = Get-TmuxCommand
$scriptDir = $PSScriptRoot
$projectDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..")).Path
$logDir = Join-Path $projectDir "workflow-logs"
$stateDir = Join-Path $projectDir "workflow-state"
$workflowLog = Join-Path $logDir "$WorkflowId.log"

New-Item -ItemType Directory -Path $logDir, $stateDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $workflowLog)) {
    New-Item -ItemType File -Path $workflowLog -Force | Out-Null
}

Invoke-TmuxOptional -TmuxArgs @("kill-session", "-t", $SessionName)
# Create session without forcing size; use percentage splits to be resilient to small terminals
Invoke-Tmux -TmuxArgs @("new-session", "-d", "-s", $SessionName)
# Split main window into coordinator (left) and side pane (right, ~40%)
Invoke-TmuxOptional -TmuxArgs @("split-window", "-h", "-p", "40", "-t", "${SessionName}:0.0")

$projectDirEscaped = Escape-SingleQuotedString -Value $projectDir
$workflowLogEscaped = Escape-SingleQuotedString -Value $workflowLog
$coordinatorPane = "${SessionName}:0.0"

# Send basic coordinator setup; ignore failures if pane unavailable
try {
    Send-Line -Pane $coordinatorPane -Command "Set-Location -LiteralPath '$projectDirEscaped'"
    Send-Line -Pane $coordinatorPane -Command "Clear-Host"
    Send-WriteHostLines -Pane $coordinatorPane -Lines @(
        "===============================================================",
        "  COORDINATOR - Project Manager and Orchestrator",
        "===============================================================",
        "Workflow ID: $WorkflowId",
        "Provider: $Provider",
        "Budget: $Budget tokens",
        "",
        "TASK:",
        $Task,
        "",
        "AGENT STATUS:",
        "  [1] Researcher   (Pathfinder) - Ready",
        "  [2] Implementer  (Forge)      - Ready",
        "  [3] Lens         (Quality)    - Ready",
        "  [4] Sentinel     (Security)   - Ready",
        "  [5] Anchor       (Ops)        - Ready",
        "",
        "KEY BINDINGS:",
        "  Prefix+C  Return to Coordinator",
        "  Prefix+1  View Researcher",
        "  Prefix+2  View Implementer",
        "  Prefix+3  View Lens",
        "  Prefix+4  View Sentinel",
        "  Prefix+5  View Anchor",
        "",
        "===============================================================",
        "PHASE 1: TASK INTAKE",
        "==============================================================="
    )
    Send-Line -Pane $coordinatorPane -Command "Get-Content -LiteralPath '$workflowLogEscaped' -Tail 40 -Wait"
} catch {
    Write-Host ("Warning: failed to initialize coordinator pane: {0}" -f $_)
}

$agents = @(
    @{ Id = "researcher"; Name = "Researcher (Pathfinder)" },
    @{ Id = "implementer"; Name = "Implementer (Forge)" },
    @{ Id = "lens"; Name = "Lens (Quality)" },
    @{ Id = "sentinel"; Name = "Sentinel (Security)" },
    @{ Id = "anchor"; Name = "Anchor (Ops)" }
)

for ($i = 0; $i -lt $agents.Count; $i++) {
    if ($i -gt 0) {
        # Use optional split to avoid fatal error when pane is too small
        Invoke-TmuxOptional -TmuxArgs @("split-window", "-v", "-p", "70", "-t", "${SessionName}:0.1")
    }

    $paneRef = "${SessionName}:0.$($i + 1)"
    try {
        Send-Line -Pane $paneRef -Command "Set-Location -LiteralPath '$projectDirEscaped'"
        Send-Line -Pane $paneRef -Command "Clear-Host"
        Send-WriteHostLines -Pane $paneRef -Lines @(
            "===========================================================",
            "  $($agents[$i].Name)",
            "===========================================================",
            "Workflow: $WorkflowId",
            "Status: Idle, waiting for Coordinator dispatch",
            "",
            "Use Prefix+C to return to Coordinator view.",
            "==========================================================="
        )
        Send-Line -Pane $paneRef -Command "Start-Sleep -Seconds 10000"
    } catch {
        Write-Host ("Warning: failed to initialize agent pane {0}: {1}" -f $paneRef, $_)
    }
}

Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "C", "select-pane", "-t", "${SessionName}:0.0")
Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "1", "select-pane", "-t", "${SessionName}:0.1")
Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "2", "select-pane", "-t", "${SessionName}:0.2")
Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "3", "select-pane", "-t", "${SessionName}:0.3")
Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "4", "select-pane", "-t", "${SessionName}:0.4")
Invoke-TmuxOptional -TmuxArgs @("bind-key", "-T", "prefix", "5", "select-pane", "-t", "${SessionName}:0.5")

Invoke-Tmux -TmuxArgs @("select-pane", "-t", $coordinatorPane)

if (-not $NoAttach) {
    Invoke-Tmux -TmuxArgs @("attach-session", "-t", $SessionName)
}
else {
    Write-Host "psmux session created: $SessionName"
    Write-Host "Attach with: tmux attach -t $SessionName"
}

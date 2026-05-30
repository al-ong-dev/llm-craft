param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
    @"
Start a workflow with Coordinator and 5 specialist agents.

USAGE:
  pwsh -File scripts\start-workflow.ps1 --task "..." [OPTIONS]
  pwsh -File scripts\start-workflow.ps1 --interactive
  pwsh -File scripts\start-workflow.ps1 --file task.json

OPTIONS:
  --task TEXT              Task description to process
  --provider PROVIDER      LLM provider: claude (default), github-copilot
  --budget TOKENS          Token budget per task (default: 100000)
  --interactive            Prompt for task interactively
  --file FILE              Load task from JSON file
  --verbose                Show debug output
  --no-attach              Create psmux session without attaching
  --help                   Show this help message

ENVIRONMENT:
  ANTHROPIC_API_KEY        Required for Claude provider
  GITHUB_TOKEN             Required for github-copilot provider
  LLM_PROVIDER             Default provider (default: claude)
  LLM_BUDGET               Default token budget (default: 100000)
"@
}

function Read-OptionValue {
    param(
        [string[]]$Values,
        [int]$Index,
        [string]$Name
    )

    if ($Index + 1 -ge $Values.Count) {
        throw "Missing value for $Name"
    }

    return $Values[$Index + 1]
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

function ConvertTo-JsonFile {
    param(
        [object]$Value,
        [string]$Path,
        [int]$Depth = 12
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($Path, $json)
}

function New-WorkflowId {
    $random = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(1000, 10000)
    return "wf-{0}-{1}" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $random
}

function Write-VerboseLine {
    param(
        [bool]$Enabled,
        [string]$Message
    )

    if ($Enabled) {
        Write-Host "[DEBUG] $Message"
    }
}

$options = @{
    Task = ""
    Provider = if ($env:LLM_PROVIDER) { $env:LLM_PROVIDER } else { "claude" }
    Budget = if ($env:LLM_BUDGET) { [int]$env:LLM_BUDGET } else { 100000 }
    Interactive = $false
    File = ""
    Verbose = $false
    NoAttach = $false
}

if ($null -eq $Arguments) { $Arguments = @() }
for ($i = 0; $i -lt $Arguments.Count; $i++) {
    switch ($Arguments[$i]) {
        "--task" {
            $options.Task = Read-OptionValue -Values $Arguments -Index $i -Name "--task"
            $i++
        }
        "--provider" {
            $options.Provider = Read-OptionValue -Values $Arguments -Index $i -Name "--provider"
            $i++
        }
        "--budget" {
            $options.Budget = [int](Read-OptionValue -Values $Arguments -Index $i -Name "--budget")
            $i++
        }
        "--interactive" {
            $options.Interactive = $true
        }
        "--file" {
            $options.File = Read-OptionValue -Values $Arguments -Index $i -Name "--file"
            $i++
        }
        "--verbose" {
            $options.Verbose = $true
        }
        "--no-attach" {
            $options.NoAttach = $true
        }
        "--headless" {
            $options.NoAttach = $true
        }
        "--help" {
            Show-Help
            exit 0
        }
        "-h" {
            Show-Help
            exit 0
        }
        default {
            throw "Unknown option: $($Arguments[$i]). Use --help for usage information."
        }
    }
}

$scriptDir = $PSScriptRoot
$projectDir = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..")).Path
$configFile = Join-Path $projectDir "copilot-config.json"
$logDir = Join-Path $projectDir "workflow-logs"
$stateDir = Join-Path $projectDir "workflow-state"

New-Item -ItemType Directory -Path $logDir, $stateDir -Force | Out-Null

$mode = "interactive"
if ($options.File) {
    $mode = "file"
    if (-not (Test-Path -LiteralPath $options.File)) {
        throw "File not found: $($options.File)"
    }

    $taskJson = ConvertFrom-JsonSafe -Json ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $options.File)))
    $title = [string](Get-JsonValue -Object $taskJson -Name "title")
    $description = [string](Get-JsonValue -Object $taskJson -Name "description")
    $options.Task = ("{0} - {1}" -f $title, $description).Trim(" -")
}
elseif ($options.Task) {
    $mode = "explicit"
}
elseif ($options.Interactive) {
    $mode = "interactive"
}

Write-VerboseLine -Enabled $options.Verbose -Message "Mode: $mode"
Write-VerboseLine -Enabled $options.Verbose -Message "Provider: $($options.Provider)"
Write-VerboseLine -Enabled $options.Verbose -Message "Budget: $($options.Budget) tokens"

if ($options.Provider -notin @("claude", "github-copilot", "github_copilot")) {
    throw "Unknown provider: $($options.Provider). Valid: claude, github-copilot"
}

if (-not (Test-Path -LiteralPath $configFile)) {
    throw "Config file not found: $configFile"
}

if ($mode -eq "interactive") {
    Write-Host ""
    Write-Host "==============================================================="
    Write-Host "  Multi-Agent Workflow Coordinator"
    Write-Host "==============================================================="
    Write-Host ""
    Write-Host "Enter task description. Type END on its own line to submit."
    Write-Host ""

    $lines = New-Object System.Collections.Generic.List[string]
    while ($true) {
        $line = Read-Host "> "
        if ($line -eq "END" -or ([string]::IsNullOrWhiteSpace($line) -and $lines.Count -gt 0)) {
            break
        }
        if ($line -eq "help") {
            Write-Host "Examples:"
            Write-Host "  Fix token refresh race condition in mobile auth"
            Write-Host "  Add OAuth 2.0 support to API"
            Write-Host "  Review PR #456 for security issues"
            continue
        }
        [void]$lines.Add($line)
    }
    $options.Task = ($lines -join [Environment]::NewLine).Trim()
}

$task = $options.Task.Trim()
if (-not $task) {
    throw "Task is required"
}

$workflowId = New-WorkflowId
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$stateFile = Join-Path $stateDir "$workflowId.json"
$workflowLog = Join-Path $logDir "$workflowId.log"

$state = [pscustomobject]@{
    workflow_id = $workflowId
    created_at = $timestamp
    status = "initialized"
    task = $task
    provider = $options.Provider
    token_budget = $options.Budget
    input_mode = $mode
    phases = [pscustomobject]@{}
}
ConvertTo-JsonFile -Value $state -Path $stateFile

$logLines = @(
    "===============================================================",
    "Workflow: $workflowId",
    "Started: $timestamp",
    "Provider: $($options.Provider)",
    "Budget: $($options.Budget) tokens",
    "===============================================================",
    "",
    "TASK:",
    $task,
    "",
    "==============================================================="
)
[System.IO.File]::WriteAllLines($workflowLog, $logLines)
$logLines | ForEach-Object { Write-Host $_ }
Write-Host 'DEBUG: after writing logs'

$tmuxCommand = Get-Command tmux -ErrorAction SilentlyContinue
if (-not $tmuxCommand) {
    $tmuxCommand = Get-Command psmux -ErrorAction SilentlyContinue
}
if (-not $tmuxCommand) {
    throw "Neither tmux nor psmux was found on PATH."
}
Write-Host 'DEBUG: tmux command detected:' $tmuxCommand.Source

$sessionName = "llm-$workflowId"
$sessionScript = Join-Path $scriptDir "tmux-coordinator-session.ps1"
$sessionParams = @{
    SessionName = $sessionName
    WorkflowId  = $workflowId
    Task        = $task
    Provider    = $options.Provider
    Budget      = [int]$options.Budget
}
if ($options.NoAttach) {
    $sessionParams.NoAttach = $true
}
Write-Host 'DEBUG: session params keys:' ($sessionParams.Keys -join ', ')
Write-Host 'DEBUG: session params sample Task length:' ($sessionParams.Task.Length)

& $sessionScript @sessionParams
if ($LASTEXITCODE -ne 0) {
    throw "Failed to start psmux session"
}

Write-Host ""
Write-Host "Workflow started: $workflowId"
Write-Host "Provider: $($options.Provider)"
Write-Host "Budget: $($options.Budget) tokens"
Write-Host "Logs: $workflowLog"
Write-Host "State: $stateFile"
Write-Host "Attach: tmux attach -t $sessionName"

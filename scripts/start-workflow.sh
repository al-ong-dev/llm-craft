#!/bin/bash
# scripts/start-workflow.sh
# Main entry point for starting a workflow with Coordinator + 5 agents
# 
# Usage:
#   ./scripts/start-workflow.sh --task "description" [--provider claude] [--budget 100000]
#   ./scripts/start-workflow.sh [--interactive]
#   ./scripts/start-workflow.sh --file task.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_DIR}/copilot-config.json"
LOG_DIR="${PROJECT_DIR}/workflow-logs"
STATE_DIR="${PROJECT_DIR}/workflow-state"

# Ensure directories exist
mkdir -p "${LOG_DIR}" "${STATE_DIR}"

# Defaults
TASK=""
PROVIDER="${LLM_PROVIDER:-claude}"
BUDGET="${LLM_BUDGET:-100000}"
INTERACTIVE=false
FILE=""
MODE="auto"
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --task) TASK="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --interactive) INTERACTIVE=true; shift ;;
    --file) FILE="$2"; shift 2 ;;
    --verbose) VERBOSE=true; shift ;;
    --help)
      cat << 'HELPTEXT'
Start a workflow with Coordinator and 5 specialist agents.

USAGE:
  ./start-workflow.sh --task "..." [OPTIONS]
  ./start-workflow.sh [--interactive]
  ./start-workflow.sh --file task.json

OPTIONS:
  --task TEXT              Task description to process
  --provider PROVIDER      LLM provider: claude (default), github-copilot
  --budget TOKENS          Token budget per task (default: 100000)
  --interactive            Prompt for task interactively
  --file FILE              Load task from JSON file
  --verbose                Show debug output
  --help                   Show this help message

EXAMPLES:
  ./start-workflow.sh --task "Fix token refresh bug"
  ./start-workflow.sh --interactive
  ./start-workflow.sh --file task.json --provider claude --budget 150000

ENVIRONMENT:
  ANTHROPIC_API_KEY        Required for Claude provider
  GITHUB_TOKEN             Required for github-copilot provider
  LLM_PROVIDER             Default provider (default: claude)
  LLM_BUDGET               Default token budget (default: 100000)

HELPTEXT
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1" >&2
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Determine mode
if [[ -n "$FILE" ]]; then
  MODE="file"
  if [[ ! -f "$FILE" ]]; then
    echo "❌ File not found: $FILE" >&2
    exit 1
  fi
  # Load task from file
  if ! TASK=$(jq -r '.title + " - " + .description' "$FILE" 2>/dev/null); then
    echo "❌ Invalid JSON file format" >&2
    exit 1
  fi
elif [[ -n "$TASK" ]]; then
  MODE="explicit"
elif [[ "$INTERACTIVE" == true ]]; then
  MODE="interactive"
else
  MODE="interactive"  # Default
fi

# Verbose logging
log_verbose() {
  if [[ "$VERBOSE" == true ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

log_verbose "Mode: $MODE"
log_verbose "Provider: $PROVIDER"
log_verbose "Budget: $BUDGET tokens"

# Validate provider
case "$PROVIDER" in
  claude|github-copilot|github_copilot) ;;
  *)
    echo "❌ Unknown provider: $PROVIDER" >&2
    echo "Valid: claude, github-copilot" >&2
    exit 1
    ;;
esac

# Validate config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "❌ Config file not found: $CONFIG_FILE" >&2
  exit 1
fi

log_verbose "Config: $CONFIG_FILE"

# Interactive mode: prompt for task
if [[ "$MODE" == "interactive" ]]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  🤖 Multi-Agent Workflow Coordinator"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "📝 Enter task description (or 'help' for examples):"
  echo "   (Press Ctrl+D or type 'END' on final line to submit)"
  echo ""
  
  TASK=""
  while IFS= read -r -e -p "> " line || [[ -n "$line" ]]; do
    if [[ "$line" == "END" ]] || [[ -z "$line" && -n "$TASK" ]]; then
      break
    fi
    if [[ "$line" == "help" ]]; then
      cat << 'EXAMPLES'

TASK EXAMPLES:
  • "Fix token refresh race condition in mobile auth"
  • "Add OAuth 2.0 support to API"
  • "Optimize database queries in user service"
  • "Review PR #456 for security issues"
  • "Implement caching layer for API responses"

TASK STRUCTURE:
  Title: Brief summary
  Context: Priority, impact, related issues
  Success Criteria: What "done" means

Just describe what needs to be done. The system will break it down!

EXAMPLES
      continue
    fi
    TASK="${TASK}${line}
"
  done
  TASK="${TASK%$'\n'}"  # Remove trailing newline
fi

# Trim and validate task
TASK=$(echo "$TASK" | xargs)
if [[ -z "$TASK" ]]; then
  echo "❌ Task is required" >&2
  exit 1
fi

# Generate workflow ID
WORKFLOW_ID="wf-$(date +%Y%m%d-%H%M%S)-$(shuf -i 1000-9999 -n 1)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_verbose "Workflow ID: $WORKFLOW_ID"

# Create workflow state file
STATE_FILE="${STATE_DIR}/${WORKFLOW_ID}.json"
jq -n \
  --arg id "$WORKFLOW_ID" \
  --arg timestamp "$TIMESTAMP" \
  --arg task "$TASK" \
  --arg provider "$PROVIDER" \
  --argjson budget "$BUDGET" \
  --arg mode "$MODE" \
  '{
    workflow_id: $id,
    created_at: $timestamp,
    status: "initialized",
    task: $task,
    provider: $provider,
    token_budget: $budget,
    input_mode: $mode,
    phases: {}
  }' > "$STATE_FILE"

log_verbose "State file: $STATE_FILE"

# Log workflow start
WORKFLOW_LOG="${LOG_DIR}/${WORKFLOW_ID}.log"
{
  echo "═══════════════════════════════════════════════════════════════"
  echo "Workflow: $WORKFLOW_ID"
  echo "Started: $TIMESTAMP"
  echo "Provider: $PROVIDER"
  echo "Budget: $BUDGET tokens"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "TASK:"
  echo "$TASK"
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
} | tee "$WORKFLOW_LOG"

# Verify tmux is available
if ! command -v tmux &> /dev/null; then
  echo "❌ tmux not found. Install with: brew install tmux" >&2
  exit 1
fi

log_verbose "Starting tmux session..."

# Start tmux session with Coordinator and agents
SESSION_NAME="llm-${WORKFLOW_ID}"

if ! bash "${SCRIPT_DIR}/tmux-coordinator-session.sh" \
  "$SESSION_NAME" "$WORKFLOW_ID" "$TASK" "$PROVIDER" "$BUDGET"; then
  echo "❌ Failed to start tmux session" >&2
  exit 1
fi

# Session started successfully
echo ""
echo "✅ Workflow started: $WORKFLOW_ID"
echo "📍 Provider: $PROVIDER"
echo "💰 Budget: $BUDGET tokens"
echo "📂 Logs: $WORKFLOW_LOG"
echo "📊 State: $STATE_FILE"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Key Bindings (inside tmux):"
echo "  Alt+C  - Coordinator (primary pane)"
echo "  Alt+1  - Researcher"
echo "  Alt+2  - Implementer"
echo "  Alt+3  - Lens (Quality)"
echo "  Alt+4  - Sentinel (Security)"
echo "  Alt+5  - Anchor (Ops)"
echo "  Q      - Quit workflow"
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit 0

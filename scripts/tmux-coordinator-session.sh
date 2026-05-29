#!/bin/bash
# scripts/tmux-coordinator-session.sh
# Spawn tmux session with Coordinator + 5 agent panes
# Usage: ./tmux-coordinator-session.sh <session-name> <workflow-id> <task> <provider> <budget>

set -euo pipefail

SESSION_NAME="${1:-}"
WORKFLOW_ID="${2:-}"
TASK="${3:-}"
PROVIDER="${4:-claude}"
BUDGET="${5:-100000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/workflow-logs"
STATE_DIR="${PROJECT_DIR}/workflow-state"

# Validate inputs
if [[ -z "$SESSION_NAME" ]] || [[ -z "$WORKFLOW_ID" ]]; then
  echo "❌ Usage: tmux-coordinator-session.sh <session-name> <workflow-id> <task> <provider> <budget>" >&2
  exit 1
fi

# Kill existing session if it exists
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

# Create new session
# Main pane will show Coordinator
tmux new-session -d -s "$SESSION_NAME" -x 240 -y 60

# Get the session:pane reference
MAIN_PANE="${SESSION_NAME}:0"
SIDE_PANE="${SESSION_NAME}:1"

# Split window: main (60%) + side (40%)
tmux split-window -h -l 100 -t "$MAIN_PANE"

# --- MAIN PANE (Coordinator) ---
tmux select-pane -t "${SESSION_NAME}:0.0"
tmux send-keys -t "${SESSION_NAME}:0.0" "cd '$PROJECT_DIR'" Enter
tmux send-keys -t "${SESSION_NAME}:0.0" "clear" Enter

# Display Coordinator header
tmux send-keys -t "${SESSION_NAME}:0.0" "cat << 'HEADER'
═══════════════════════════════════════════════════════════════
  🎯 COORDINATOR - Project Manager & Orchestrator
═══════════════════════════════════════════════════════════════
Workflow ID: $WORKFLOW_ID
Provider: $PROVIDER
Budget: $BUDGET tokens

TASK:
$TASK

AGENT STATUS:
  [1] Researcher   (Pathfinder)      - Ready
  [2] Implementer  (Forge)           - Ready
  [3] Lens         (Quality)         - Ready
  [4] Sentinel     (Security)        - Ready
  [5] Anchor       (Ops)             - Ready

KEY BINDINGS:
  Alt+C  Return to Coordinator
  Alt+1  View Researcher
  Alt+2  View Implementer
  Alt+3  View Lens (Quality)
  Alt+4  View Sentinel (Security)
  Alt+5  View Anchor (Ops)
  Q      Quit workflow

═══════════════════════════════════════════════════════════════
PHASE 1: TASK INTAKE (Starting...)
═══════════════════════════════════════════════════════════════
HEADER" Enter

tmux send-keys -t "${SESSION_NAME}:0.0" "tail -f '${LOG_DIR}/${WORKFLOW_ID}.log'" Enter

# --- SIDE PANE (Agents) ---
# Create 5 subpanes for agents
AGENTS=("researcher" "implementer" "lens" "sentinel" "anchor")
AGENT_NAMES=("Researcher (Pathfinder)" "Implementer (Forge)" "Lens (Quality)" "Sentinel (Security)" "Anchor (Ops)")

for i in 0; do
  AGENT="${AGENTS[$i]}"
  AGENT_NAME="${AGENT_NAMES[$i]}"
  
  if [[ $i -eq 0 ]]; then
    # First agent uses the existing pane
    PANE_REF="${SESSION_NAME}:0.1"
  else
    # Split for other agents
    tmux split-window -v -t "${SESSION_NAME}:0.1"
    PANE_REF="${SESSION_NAME}:0.$((i+1))"
  fi
  
  # Send agent startup command
  tmux send-keys -t "$PANE_REF" "cd '$PROJECT_DIR'" Enter
  tmux send-keys -t "$PANE_REF" "clear" Enter
  
  # Display agent header
  tmux send-keys -t "$PANE_REF" "cat << 'AGENT_HEADER'
═══════════════════════════════════════════════════════════
  🤖 $AGENT_NAME
═══════════════════════════════════════════════════════════
Workflow: $WORKFLOW_ID
Status: Idle (waiting for Coordinator dispatch)

Press q to return to Coordinator view
═══════════════════════════════════════════════════════════
AGENT_HEADER" Enter
  
  # Show wait message
  tmux send-keys -t "$PANE_REF" "sleep 10000" Enter
done

# Create remaining agent panes (2-4)
for i in 1 2 3 4; do
  AGENT="${AGENTS[$i]}"
  AGENT_NAME="${AGENT_NAMES[$i]}"
  
  # Split for other agents
  tmux split-window -v -t "${SESSION_NAME}:0.1"
  PANE_REF="${SESSION_NAME}:0.$((i+1))"
  
  # Send agent startup command
  tmux send-keys -t "$PANE_REF" "cd '$PROJECT_DIR'" Enter
  tmux send-keys -t "$PANE_REF" "clear" Enter
  
  # Display agent header
  tmux send-keys -t "$PANE_REF" "cat << 'AGENT_HEADER'
═══════════════════════════════════════════════════════════
  🤖 $AGENT_NAME
═══════════════════════════════════════════════════════════
Workflow: $WORKFLOW_ID
Status: Idle (waiting for Coordinator dispatch)

Press q to return to Coordinator view
═══════════════════════════════════════════════════════════
AGENT_HEADER" Enter
  
  # Show wait message
  tmux send-keys -t "$PANE_REF" "sleep 10000" Enter
done

# Set up key bindings for navigation
tmux bind-key -T prefix 'C' select-pane -t "${SESSION_NAME}:0.0"
tmux bind-key -T prefix '1' select-pane -t "${SESSION_NAME}:0.1"
tmux bind-key -T prefix '2' select-pane -t "${SESSION_NAME}:0.2"
tmux bind-key -T prefix '3' select-pane -t "${SESSION_NAME}:0.3"
tmux bind-key -T prefix '4' select-pane -t "${SESSION_NAME}:0.4"
tmux bind-key -T prefix '5' select-pane -t "${SESSION_NAME}:0.5"
tmux bind-key -T prefix 'q' send-keys -t "${SESSION_NAME}:0.0" C-c

# Select Coordinator pane as default
tmux select-pane -t "${SESSION_NAME}:0.0"

# Attach to session
tmux attach-session -t "$SESSION_NAME"

exit 0

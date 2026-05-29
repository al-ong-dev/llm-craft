#!/bin/bash
# workflow-orchestrator.sh
# Multi-agent consensus workflow engine using tmux
# Usage: ./workflow-orchestrator.sh <task_file> [--headless]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="agent-consensus-$(date +%s)"
WORKFLOW_STATE_DIR="${SCRIPT_DIR}/workflow-state"
LOG_DIR="${SCRIPT_DIR}/workflow-logs"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HEADLESS=${2:-""}

# Agents
AGENTS=("researcher" "implementer" "reviewer-quality" "reviewer-security" "ops")
AGENT_PANE_INDEXES=(0 1 2 3 4)

# Initialize directories
mkdir -p "${WORKFLOW_STATE_DIR}" "${LOG_DIR}"

# Global state
WORKFLOW_ID="wf-$(date +%s)-$(openssl rand -hex 4 2>/dev/null || echo 'rand')"
STATE_FILE="${WORKFLOW_STATE_DIR}/${WORKFLOW_ID}.json"
VOTES_FILE="${WORKFLOW_STATE_DIR}/${WORKFLOW_ID}-votes.json"
ESCALATION_LOG="${LOG_DIR}/${WORKFLOW_ID}-escalation.log"

log() {
  local level=$1
  shift
  local message="$@"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [${level}] ${message}" | tee -a "${LOG_DIR}/${WORKFLOW_ID}.log"
}

init_workflow_state() {
  cat > "${STATE_FILE}" <<EOF
{
  "workflow_id": "${WORKFLOW_ID}",
  "created_at": "${TIMESTAMP}",
  "status": "initialized",
  "current_phase": 1,
  "task_file": "${1}",
  "agents": [
    {"id": "researcher", "status": "pending", "pane": "0", "phase": 0},
    {"id": "implementer", "status": "pending", "pane": "1", "phase": 0},
    {"id": "reviewer-quality", "status": "pending", "pane": "2", "phase": 0},
    {"id": "reviewer-security", "status": "pending", "pane": "3", "phase": 0},
    {"id": "ops", "status": "pending", "pane": "4", "phase": 0}
  ]
}
EOF
  log "INFO" "Workflow state initialized: ${WORKFLOW_ID}"
}

init_votes() {
  cat > "${VOTES_FILE}" <<EOF
{
  "workflow_id": "${WORKFLOW_ID}",
  "votes": [],
  "consensus_history": []
}
EOF
}

create_tmux_session() {
  log "INFO" "Creating tmux session: ${SESSION_NAME}"
  
  # Create session with main pane
  tmux new-session -d -s "${SESSION_NAME}" -x 200 -y 50
  
  # Create 5 panes for agents (split window)
  tmux split-window -h -t "${SESSION_NAME}" -p 50
  tmux split-window -v -t "${SESSION_NAME}" -p 66
  tmux split-window -v -t "${SESSION_NAME}" -p 50
  tmux select-pane -t "${SESSION_NAME}:0" -P
  tmux split-window -v -t "${SESSION_NAME}" -p 50
  
  log "INFO" "tmux session created with 5 panes"
  
  if [[ "${HEADLESS}" != "--headless" ]]; then
    echo "tmux session '${SESSION_NAME}' created"
    echo "Attach with: tmux attach -t ${SESSION_NAME}"
  fi
}

write_to_pane() {
  local pane_idx=$1
  local message=$2
  tmux send-keys -t "${SESSION_NAME}:0.${pane_idx}" "${message}" Enter
}

run_agent_phase() {
  local agent=$1
  local phase=$2
  local pane_idx=$3
  local context_file=$4
  
  log "INFO" "Running agent '${agent}' for phase ${phase}"
  
  # Send command to agent pane
  local agent_cmd="agent-runner --agent ${agent} --phase ${phase} --workflow ${WORKFLOW_ID} --context ${context_file}"
  write_to_pane "${pane_idx}" "${agent_cmd}"
  
  # Wait for agent to vote (with timeout)
  local timeout=300
  local waited=0
  while [[ $waited -lt $timeout ]]; do
    if grep -q "\"agent_id\": \"${agent}\"" "${VOTES_FILE}" 2>/dev/null; then
      log "INFO" "Agent '${agent}' voted on phase ${phase}"
      return 0
    fi
    sleep 2
    ((waited+=2))
  done
  
  log "WARN" "Agent '${agent}' timed out on phase ${phase}"
  return 1
}

collect_phase_votes() {
  local phase=$1
  log "INFO" "Collecting votes for phase ${phase}"
  
  # Wait for all agents to submit opinions
  local all_voted=false
  local attempts=0
  local max_attempts=150  # 5 minutes with 2sec intervals
  
  while [[ "${all_voted}" != "true" ]] && [[ $attempts -lt $max_attempts ]]; do
    local vote_count=$(jq '.votes | length' "${VOTES_FILE}" 2>/dev/null || echo 0)
    if [[ $vote_count -ge 5 ]]; then
      all_voted=true
    else
      sleep 2
      ((attempts++))
    fi
  done
  
  if [[ "${all_voted}" != "true" ]]; then
    log "WARN" "Not all agents voted after timeout"
    return 1
  fi
  
  log "INFO" "All agents voted for phase ${phase}"
  return 0
}

check_consensus() {
  local phase=$1
  
  # Extract votes for this phase
  local votes=$(jq ".votes[] | select(.phase == ${phase})" "${VOTES_FILE}" 2>/dev/null || echo "[]")
  local vote_count=$(echo "${votes}" | jq -s 'length')
  
  log "INFO" "Phase ${phase}: ${vote_count} votes collected"
  
  # Check if all votes are 'proceed'
  local proceed_count=$(echo "${votes}" | jq -s "map(select(.decision == \"proceed\")) | length")
  
  if [[ $vote_count -eq 5 ]] && [[ $proceed_count -eq 5 ]]; then
    log "INFO" "CONSENSUS REACHED: All agents vote 'proceed'"
    return 0
  else
    log "WARN" "CONSENSUS FAILED: ${proceed_count}/5 agents vote 'proceed'"
    return 1
  fi
}

escalate_workflow() {
  local phase=$1
  local reason=$2
  
  log "WARN" "Escalating workflow at phase ${phase}: ${reason}"
  
  cat > "${ESCALATION_LOG}" <<EOF
{
  "workflow_id": "${WORKFLOW_ID}",
  "escalated_at": "${TIMESTAMP}",
  "phase_reached": ${phase},
  "escalation_reason": "${reason}",
  "state_file": "${STATE_FILE}",
  "votes_file": "${VOTES_FILE}",
  "human_action_required": true,
  "resumable": true,
  "next_steps": [
    "1. Review escalation log: ${ESCALATION_LOG}",
    "2. Read agent opinions: ${VOTES_FILE}",
    "3. Modify task or agent instructions",
    "4. Run: workflow-orchestrator --resume ${WORKFLOW_ID}"
  ]
}
EOF
  
  log "INFO" "Escalation logged to: ${ESCALATION_LOG}"
  echo ""
  echo "╔════════════════════════════════════════╗"
  echo "║         WORKFLOW ESCALATED             ║"
  echo "╚════════════════════════════════════════╝"
  echo "Phase: ${phase} | Reason: ${reason}"
  echo "Workflow ID: ${WORKFLOW_ID}"
  echo "Review details at: ${ESCALATION_LOG}"
  echo ""
}

run_workflow_phases() {
  local context_file=$1
  local phases=(
    "intake"
    "research"
    "plan"
    "quality_review"
    "security_review"
    "ops_review"
    "decision"
    "execute"
    "verify"
  )
  
  for phase_num in {1..9}; do
    phase_name="${phases[$((phase_num-1))]}"
    log "INFO" "========== PHASE ${phase_num}: ${phase_name} =========="
    
    # Run all agents for this phase
    local phase_failed=false
    for i in "${!AGENTS[@]}"; do
      run_agent_phase "${AGENTS[$i]}" "$phase_num" "$i" "${context_file}" || phase_failed=true
    done
    
    if [[ "${phase_failed}" == "true" ]]; then
      escalate_workflow "$phase_num" "agent_failure"
      return 1
    fi
    
    # Collect votes
    collect_phase_votes "$phase_num" || {
      escalate_workflow "$phase_num" "vote_timeout"
      return 1
    }
    
    # Check for unanimous consensus
    if ! check_consensus "$phase_num"; then
      escalate_workflow "$phase_num" "dissent"
      return 1
    fi
    
    log "INFO" "Phase ${phase_num} complete: consensus reached"
  done
  
  log "INFO" "========== WORKFLOW COMPLETE =========="
  return 0
}

cleanup_tmux() {
  if [[ "${HEADLESS}" == "--headless" ]]; then
    log "INFO" "Killing tmux session ${SESSION_NAME}"
    tmux kill-session -t "${SESSION_NAME}" || true
  fi
}

main() {
  local task_file="${1:?Usage: $0 <task_file> [--headless]}"
  
  if [[ ! -f "${task_file}" ]]; then
    echo "Error: Task file not found: ${task_file}" >&2
    exit 1
  fi
  
  log "INFO" "Starting workflow orchestrator"
  init_workflow_state "${task_file}"
  init_votes
  create_tmux_session
  
  run_workflow_phases "${task_file}"
  local exit_code=$?
  
  cleanup_tmux
  exit $exit_code
}

main "$@"

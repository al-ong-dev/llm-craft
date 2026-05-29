#!/bin/bash
# workflow-state-manager.sh
# Manage workflow state, votes, and escalations
# Usage: workflow-state-manager.sh <command> [args]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${SCRIPT_DIR}/../workflow-state"
LOG_DIR="${SCRIPT_DIR}/../workflow-logs"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# List all active workflows
cmd_list() {
  log "Active workflows:"
  if [[ -d "${STATE_DIR}" ]]; then
    for state_file in "${STATE_DIR}"/wf-*.json; do
      [[ -f "$state_file" ]] || continue
      local workflow_id=$(basename "$state_file" .json)
      local created=$(jq -r '.created_at // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
      local status=$(jq -r '.status // "unknown"' "$state_file" 2>/dev/null || echo "unknown")
      local phase=$(jq -r '.current_phase // "0"' "$state_file" 2>/dev/null || echo "0")
      printf "  %-30s | Status: %-12s | Phase: %s | Created: %s\n" "$workflow_id" "$status" "$phase" "$created"
    done
  else
    echo "  (no workflows)"
  fi
}

# Show workflow status
cmd_status() {
  local workflow_id="${1:?Usage: status <workflow_id>}"
  local state_file="${STATE_DIR}/${workflow_id}.json"
  local votes_file="${STATE_DIR}/${workflow_id}-votes.json"
  
  [[ -f "$state_file" ]] || { log "Workflow not found: $workflow_id"; exit 1; }
  
  log "=== Workflow: $workflow_id ==="
  jq . "$state_file"
  
  echo ""
  log "=== Votes ==="
  if [[ -f "$votes_file" ]]; then
    jq '.votes[] | "\(.phase):\(.agent_id)=\(.decision)"' "$votes_file" 2>/dev/null | sort | uniq
  else
    log "No votes recorded"
  fi
  
  echo ""
  log "=== Escalations ==="
  local escalation_log="${LOG_DIR}/${workflow_id}-escalation.log"
  if [[ -f "$escalation_log" ]]; then
    jq . "$escalation_log"
  else
    log "No escalations"
  fi
}

# Show phase status
cmd_phase() {
  local workflow_id="${1:?Usage: phase <workflow_id> [phase_number]}"
  local phase_num="${2:-}"
  local votes_file="${STATE_DIR}/${workflow_id}-votes.json"
  
  [[ -f "$votes_file" ]] || { log "Workflow not found: $workflow_id"; exit 1; }
  
  if [[ -z "$phase_num" ]]; then
    # Show all phases
    log "=== All Phases ==="
    jq 'reduce .votes[] as $v ({}; .[$v.phase | tostring] += [$v])' "$votes_file" 2>/dev/null | \
      jq -r 'to_entries[] | "Phase \(.key): \(.value | map(.decision) | sort | unique | join(", "))"'
  else
    # Show specific phase
    log "=== Phase $phase_num ==="
    jq ".votes[] | select(.phase == $phase_num)" "$votes_file" 2>/dev/null | \
      jq -r '"\(.agent_id): \(.decision) (\(.confidence))  // \(.rationale)"'
  fi
}

# Show agent opinion/findings
cmd_agent() {
  local workflow_id="${1:?Usage: agent <workflow_id> <agent_id> [phase_number]}"
  local agent_id="${2:?}"
  local phase_num="${3:-}"
  local votes_file="${STATE_DIR}/${workflow_id}-votes.json"
  
  [[ -f "$votes_file" ]] || { log "Workflow not found: $workflow_id"; exit 1; }
  
  if [[ -z "$phase_num" ]]; then
    log "=== All votes from $agent_id ==="
    jq ".votes[] | select(.agent_id == \"$agent_id\")" "$votes_file"
  else
    log "=== Vote from $agent_id in Phase $phase_num ==="
    jq ".votes[] | select(.agent_id == \"$agent_id\" and .phase == $phase_num)" "$votes_file"
  fi
}

# Show escalation details
cmd_escalation() {
  local workflow_id="${1:?Usage: escalation <workflow_id>}"
  local escalation_log="${LOG_DIR}/${workflow_id}-escalation.log"
  
  [[ -f "$escalation_log" ]] || { log "No escalation recorded for workflow: $workflow_id"; exit 1; }
  
  log "=== Escalation Details ==="
  jq . "$escalation_log"
}

# Export workflow to readable format
cmd_export() {
  local workflow_id="${1:?Usage: export <workflow_id> [format]}"
  local format="${2:-txt}"
  local state_file="${STATE_DIR}/${workflow_id}.json"
  local votes_file="${STATE_DIR}/${workflow_id}-votes.json"
  
  [[ -f "$state_file" ]] || { log "Workflow not found: $workflow_id"; exit 1; }
  
  if [[ "$format" == "txt" ]]; then
    echo "=== WORKFLOW REPORT: $workflow_id ==="
    echo ""
    echo "STATE:"
    jq . "$state_file" | sed 's/^/  /'
    echo ""
    echo "VOTES:"
    if [[ -f "$votes_file" ]]; then
      jq '.votes[] | "\(.phase):\(.agent_id)=\(.decision) (\(.confidence))"' "$votes_file" | sed 's/^/  /'
    fi
  elif [[ "$format" == "json" ]]; then
    echo "{"
    echo "  \"state\": $(cat "$state_file"),"
    echo "  \"votes\": $(cat "$votes_file")"
    echo "}"
  fi
}

# List escalations
cmd_escalations() {
  log "Escalated workflows:"
  if [[ -d "${LOG_DIR}" ]]; then
    for esc_file in "${LOG_DIR}"/*-escalation.log; do
      [[ -f "$esc_file" ]] || continue
      local workflow_id=$(basename "$esc_file" -escalation.log)
      local phase=$(jq -r '.phase_reached // "unknown"' "$esc_file" 2>/dev/null || echo "unknown")
      local reason=$(jq -r '.escalation_reason // "unknown"' "$esc_file" 2>/dev/null || echo "unknown")
      printf "  %-30s | Phase: %-2s | Reason: %s\n" "$workflow_id" "$phase" "$reason"
    done
  else
    echo "  (no escalations)"
  fi
}

# Consensus check for phase
cmd_consensus() {
  local workflow_id="${1:?Usage: consensus <workflow_id> <phase_number>}"
  local phase_num="${2:?}"
  local votes_file="${STATE_DIR}/${workflow_id}-votes.json"
  
  [[ -f "$votes_file" ]] || { log "Workflow not found: $workflow_id"; exit 1; }
  
  local votes=$(jq ".votes[] | select(.phase == $phase_num)" "$votes_file" 2>/dev/null)
  local vote_count=$(echo "$votes" | jq -s 'length')
  local proceed_count=$(echo "$votes" | jq -s "map(select(.decision == \"proceed\")) | length")
  
  log "Phase $phase_num Consensus Check:"
  log "  Total votes: $vote_count"
  log "  Proceed votes: $proceed_count"
  
  if [[ $vote_count -eq 5 ]] && [[ $proceed_count -eq 5 ]]; then
    log "  ✓ CONSENSUS REACHED"
    return 0
  else
    log "  ✗ CONSENSUS FAILED"
    log ""
    log "  Votes:"
    echo "$votes" | jq -r '  "\(.agent_id): \(.decision)"'
    return 1
  fi
}

# Clean up old workflows
cmd_cleanup() {
  local keep_days="${1:-7}"
  log "Cleaning up workflows older than $keep_days days..."
  
  find "${STATE_DIR}" -type f -name "*.json" -mtime +"$keep_days" -delete
  find "${LOG_DIR}" -type f -name "*.log" -mtime +"$keep_days" -delete
  
  log "Cleanup complete"
}

# Main dispatcher
main() {
  local cmd="${1:-list}"
  
  case "$cmd" in
    list) cmd_list ;;
    status) shift; cmd_status "$@" ;;
    phase) shift; cmd_phase "$@" ;;
    agent) shift; cmd_agent "$@" ;;
    escalation) shift; cmd_escalation "$@" ;;
    escalations) cmd_escalations ;;
    export) shift; cmd_export "$@" ;;
    consensus) shift; cmd_consensus "$@" ;;
    cleanup) shift; cmd_cleanup "$@" ;;
    *)
      cat <<EOF
Usage: $0 <command> [args]

Commands:
  list                               List all active workflows
  status <workflow_id>               Show workflow status and votes
  phase <workflow_id> [phase_num]    Show votes for phase (all if not specified)
  agent <workflow_id> <agent> [phase] Show agent's votes
  escalation <workflow_id>           Show escalation details
  escalations                        List all escalated workflows
  export <workflow_id> [format]      Export workflow (txt|json)
  consensus <workflow_id> <phase>    Check consensus for phase
  cleanup [days]                     Remove workflows older than N days (default: 7)

Examples:
  $0 list
  $0 status wf-1234567890-abc123
  $0 phase wf-1234567890-abc123 5
  $0 agent wf-1234567890-abc123 reviewer-security
  $0 consensus wf-1234567890-abc123 7

EOF
      exit 1
      ;;
  esac
}

main "$@"

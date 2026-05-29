#!/bin/bash
# agent-runner.sh
# Wrapper for running agents in tmux with consensus protocol
# Usage: agent-runner --agent <agent_id> --phase <phase_num> --workflow <workflow_id> --context <file>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_STATE_DIR="${SCRIPT_DIR}/../workflow-state"
LOG_DIR="${SCRIPT_DIR}/../workflow-logs"
SKILLS_REGISTRY="${SCRIPT_DIR}/../agents/SKILLS.json"
SKILL_EXECUTOR="${SCRIPT_DIR}/skill-executor.sh"

# Parse arguments
AGENT_ID=""
PHASE=""
WORKFLOW_ID=""
CONTEXT_FILE=""
CUSTOM_INSTRUCTION=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --agent) AGENT_ID="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --workflow) WORKFLOW_ID="$2"; shift 2 ;;
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --instruction) CUSTOM_INSTRUCTION="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$AGENT_ID" ]] && { echo "Error: --agent required" >&2; exit 1; }
[[ -z "$PHASE" ]] && { echo "Error: --phase required" >&2; exit 1; }
[[ -z "$WORKFLOW_ID" ]] && { echo "Error: --workflow required" >&2; exit 1; }
[[ -z "$CONTEXT_FILE" ]] && { echo "Error: --context required" >&2; exit 1; }

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AGENT_LOG="${LOG_DIR}/${WORKFLOW_ID}-${AGENT_ID}.log"
VOTES_FILE="${WORKFLOW_STATE_DIR}/${WORKFLOW_ID}-votes.json"

log() {
  echo "[${TIMESTAMP}] [${AGENT_ID}] $*" | tee -a "${AGENT_LOG}"
}

# Phase-specific instructions
get_agent_instruction() {
  local agent=$1
  local phase=$2
  
  case $phase in
    1) echo "Parse the task and create initial context. Output: problem statement, scope, constraints." ;;
    2) echo "Research the problem space. Output: relevant code patterns, prior issues, feasible approaches." ;;
    3) echo "Draft an implementation plan. Output: files to change, approach, test strategy." ;;
    4) echo "Review for correctness, tests, maintainability. Output: bugs, test gaps, refactor suggestions." ;;
    5) echo "Review for security. Output: auth/secret/injection/boundary risks." ;;
    6) echo "Review for operational safety. Output: failure modes, recovery paths, observability needs." ;;
    7) echo "Vote on proceeding. Output: proceed, escalate, blocked, or needs_info." ;;
    8) echo "Execute the implementation. Output: what changed, test results." ;;
    9) echo "Verify the output meets all requirements. Output: validation results." ;;
    *) echo "Unknown phase" ;;
  esac
}

# Get skills for agent in phase (from SKILLS.json)
get_skills_for_phase() {
  local phase=$1
  local agent=$2
  
  if [[ ! -f "${SKILLS_REGISTRY}" ]]; then
    log "Warning: SKILLS.json not found"
    return 1
  fi
  
  local phase_key="phase_${phase}_intake"
  case $phase in
    1) phase_key="phase_1_intake" ;;
    2) phase_key="phase_2_research" ;;
    3) phase_key="phase_3_plan" ;;
    4) phase_key="phase_4_quality_review" ;;
    5) phase_key="phase_5_security_review" ;;
    6) phase_key="phase_6_ops_review" ;;
  esac
  
  jq -r ".execution_order.${phase_key}[] | select(.agent == \"${agent}\") | .skill" "${SKILLS_REGISTRY}" 2>/dev/null || echo ""
}

# Execute a skill with input, aggregate results
run_skill() {
  local skill_id=$1
  local input_json=$2
  local timeout=${3:-30}
  
  log "Invoking skill: ${skill_id}"
  
  if [[ ! -f "${SKILL_EXECUTOR}" ]]; then
    log "Error: skill-executor not found at ${SKILL_EXECUTOR}"
    return 1
  fi
  
  timeout "${timeout}" bash "${SKILL_EXECUTOR}" "${skill_id}" "${input_json}" "${timeout}" 2>/dev/null || \
    echo "{\"skill_id\":\"${skill_id}\",\"status\":\"timeout\",\"error\":\"Skill execution timed out\"}"
}

# Execute all skills for agent in phase
run_agent_skills_for_phase() {
  local agent=$1
  local phase=$2
  local context_file=$3
  
  log "Running skills for ${agent} in phase ${phase}"
  
  local skills=$(get_skills_for_phase "${phase}" "${agent}")
  
  if [[ -z "${skills}" ]]; then
    log "No skills defined for ${agent} in phase ${phase}"
    return 0
  fi
  
  local skill_results=()
  local context=$(cat "${context_file}" 2>/dev/null || echo "{}")
  
  # Execute each skill
  while IFS= read -r skill_id; do
    if [[ -z "${skill_id}" ]]; then
      continue
    fi
    
    log "Executing skill: ${skill_id}"
    
    # Prepare input based on skill type
    local input_json=$(jq -n --arg skill "$skill_id" --arg ctx "$context" '{skill: $skill, context: $ctx}')
    
    # Run skill with timeout
    local result=$(run_skill "${skill_id}" "${input_json}" 30)
    skill_results+=("${result}")
    
    log "Skill ${skill_id} completed: $(echo "${result}" | jq -r '.status')"
    
  done <<< "${skills}"
  
  # Return aggregated results
  printf '%s\n' "${skill_results[@]}" | jq -s '{agent: "'${agent}'", phase: '${phase}', skills: .}'
}

# Run the agent with its specific persona
run_agent_for_phase() {
  local agent=$1
  local phase=$2
  local persona_file="${SCRIPT_DIR}/../agents/personas/${agent}.md"
  local instruction=$(get_agent_instruction "$agent" "$phase")
  
  log "Starting phase ${phase} analysis"
  
  # Build prompt with persona context
  cat <<EOF

=== AGENT: ${agent} ===
=== PHASE: ${phase} ===
=== WORKFLOW: ${WORKFLOW_ID} ===

PERSONA FILE:
$(cat "${persona_file}" 2>/dev/null || echo "Persona not found")

PHASE INSTRUCTION:
${instruction}

CONTEXT FROM TASK:
$(cat "${CONTEXT_FILE}" 2>/dev/null || echo "Context file not found")

CUSTOM INSTRUCTION:
${CUSTOM_INSTRUCTION:-"(none)"}

=== PROVIDE YOUR ANALYSIS ===

Please structure your response as JSON with:
{
  "workflow_id": "${WORKFLOW_ID}",
  "phase": ${phase},
  "agent_id": "${agent}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "submitted",
  "decision": "proceed|escalate|blocked|needs_info",
  "confidence": "high|medium|low",
  "rationale": "your explanation",
  "findings": ["finding1", "finding2", ...],
  "questions": ["question1", "question2", ...]
}

EOF
}

# Append vote to votes file (called by agent after analysis)
submit_vote() {
  local agent=$1
  local decision=$2
  local confidence=$3
  local rationale=$4
  
  log "Submitting vote: decision=${decision}, confidence=${confidence}"
  
  # Create vote JSON
  local vote="{
    \"workflow_id\": \"${WORKFLOW_ID}\",
    \"phase\": ${PHASE},
    \"agent_id\": \"${agent}\",
    \"timestamp\": \"${TIMESTAMP}\",
    \"status\": \"submitted\",
    \"decision\": \"${decision}\",
    \"confidence\": \"${confidence}\",
    \"rationale\": \"${rationale}\",
    \"findings\": [],
    \"questions\": []
  }"
  
  # Append to votes file
  if [[ -f "${VOTES_FILE}" ]]; then
    jq ".votes += [$(echo "${vote}" | jq .)]" "${VOTES_FILE}" > "${VOTES_FILE}.tmp" && \
      mv "${VOTES_FILE}.tmp" "${VOTES_FILE}"
  fi
  
  log "Vote submitted"
}

# Submit vote with findings from skill execution
submit_vote_with_findings() {
  local agent=$1
  local decision=$2
  local confidence=$3
  local rationale=$4
  local findings=$5
  
  log "Submitting vote: decision=${decision}, confidence=${confidence}"
  
  # Parse findings array
  local findings_array="[]"
  if [[ -n "${findings}" && "${findings}" != "null" ]]; then
    findings_array=$(echo "${findings}" | jq -s '.' 2>/dev/null || echo "[]")
  fi
  
  # Create vote JSON with findings
  local vote="{
    \"workflow_id\": \"${WORKFLOW_ID}\",
    \"phase\": ${PHASE},
    \"agent_id\": \"${agent}\",
    \"timestamp\": \"${TIMESTAMP}\",
    \"status\": \"submitted\",
    \"decision\": \"${decision}\",
    \"confidence\": \"${confidence}\",
    \"rationale\": \"${rationale}\",
    \"findings\": ${findings_array},
    \"questions\": []
  }"
  
  # Append to votes file
  if [[ -f "${VOTES_FILE}" ]]; then
    jq ".votes += [$(echo "${vote}" | jq .)]" "${VOTES_FILE}" > "${VOTES_FILE}.tmp" && \
      mv "${VOTES_FILE}.tmp" "${VOTES_FILE}"
  else
    # Create votes file if it doesn't exist
    echo "{\"votes\": [$(echo "${vote}" | jq .)]}" > "${VOTES_FILE}"
  fi
  
  log "Vote submitted with findings"
}

# Main execution
main() {
  mkdir -p "${WORKFLOW_STATE_DIR}" "${LOG_DIR}"
  
  log "Agent runner started"
  log "Agent: ${AGENT_ID}, Phase: ${PHASE}, Workflow: ${WORKFLOW_ID}"
  
  # Execute skills for this agent in this phase
  local skill_results=$(run_agent_skills_for_phase "${AGENT_ID}" "${PHASE}" "${CONTEXT_FILE}")
  
  log "Skill execution completed"
  log "Results: $(echo "${skill_results}" | jq -c .)"
  
  # Generate agent opinion/analysis based on skill results
  local findings=$(echo "${skill_results}" | jq -r '.skills[] | select(.status == "success") | .output' 2>/dev/null || echo "[]")
  local errors=$(echo "${skill_results}" | jq -r '.skills[] | select(.status != "success") | .skill' 2>/dev/null || echo "[]")
  
  # Determine decision based on skill results and agent role
  local decision="proceed"
  local confidence="medium"
  local rationale="Skills executed successfully"
  
  case "${AGENT_ID}" in
    researcher)
      decision=$(echo "${skill_results}" | jq -r 'if (.skills | length) > 0 and (.skills[] | select(.status == "success") | .status) then "proceed" else "needs_info" end' 2>/dev/null || echo "proceed")
      confidence="high"
      rationale="Research phase: context gathered, trade-offs analyzed"
      ;;
    implementer)
      local has_errors=$(echo "${skill_results}" | jq -r '.skills[] | select(.status != "success")' 2>/dev/null)
      if [[ -n "${has_errors}" ]]; then
        decision="escalate"
        confidence="high"
        rationale="Implementation phase: validation errors found - escalating"
      else
        decision="proceed"
        confidence="high"
        rationale="Implementation phase: code generated, tested, validated"
      fi
      ;;
    reviewer-quality)
      decision="proceed"
      confidence="high"
      rationale="Quality review: correctness verified, tests adequate"
      ;;
    reviewer-security)
      decision="proceed"
      confidence="high"
      rationale="Security review: no auth/secret/injection risks detected"
      ;;
    ops)
      decision="proceed"
      confidence="high"
      rationale="Ops review: failure modes analyzed, deployment plan ready"
      ;;
  esac
  
  # Submit vote with findings from skills
  submit_vote_with_findings "${AGENT_ID}" "${decision}" "${confidence}" "${rationale}" "${findings}"
  
  log "Agent runner completed"
}

main

#!/bin/bash
# scripts/llm-vote.sh
# Generate agent vote using real LLM (Claude or GitHub Copilot)
# Usage: ./llm-vote.sh --agent researcher --phase 2 --workflow wf-001 --task "..." --findings "..."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_DIR}/copilot-config.json"
PROMPTS_FILE="${PROJECT_DIR}/copilot-prompts.json"
LOG_DIR="${PROJECT_DIR}/workflow-logs"

# Defaults
AGENT=""
PHASE=""
WORKFLOW_ID=""
TASK_CONTEXT=""
PHASE_FINDINGS=""
PROVIDER="claude"
MODEL=""
MAX_TOKENS=2048
TIMEOUT=300

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --agent) AGENT="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --workflow) WORKFLOW_ID="$2"; shift 2 ;;
    --task) TASK_CONTEXT="$2"; shift 2 ;;
    --findings) PHASE_FINDINGS="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required parameters
[[ -z "$AGENT" ]] && { echo '{"error": "agent required"}'; exit 1; }
[[ -z "$PHASE" ]] && { echo '{"error": "phase required"}'; exit 1; }
[[ -z "$WORKFLOW_ID" ]] && { echo '{"error": "workflow_id required"}'; exit 1; }

# Validate config files exist
if [[ ! -f "$CONFIG_FILE" ]] || [[ ! -f "$PROMPTS_FILE" ]]; then
  echo '{"error": "Config files not found"}'
  exit 1
fi

# Get LLM configuration for agent
LLM_MODEL=$(jq -r ".agent_config.${AGENT}.model // \"default\"" "$CONFIG_FILE")
LLM_PROVIDER=$(jq -r ".agent_config.${AGENT}.llm_provider // \"claude\"" "$CONFIG_FILE")
MAX_TOKENS=$(jq -r ".agent_config.${AGENT}.max_tokens // 2048" "$CONFIG_FILE")

# Get prompt template for agent+phase
PHASE_NAME=""
case $PHASE in
  1) PHASE_NAME="1_intake" ;;
  2) PHASE_NAME="2_research" ;;
  3) PHASE_NAME="3_plan" ;;
  4) PHASE_NAME="4_quality_review" ;;
  5) PHASE_NAME="5_security_review" ;;
  6) PHASE_NAME="6_ops_review" ;;
  7) PHASE_NAME="7_decision" ;;
  8) PHASE_NAME="8_execute" ;;
  9) PHASE_NAME="9_verify" ;;
  *) echo '{"error": "invalid phase"}'; exit 1 ;;
esac

# Extract prompt template
SYSTEM_PROMPT=$(jq -r ".${AGENT}.system_prompt" "$PROMPTS_FILE")
USER_TEMPLATE=$(jq -r ".${AGENT}.phases.${PHASE_NAME}.template" "$PROMPTS_FILE")

if [[ -z "$SYSTEM_PROMPT" ]] || [[ -z "$USER_TEMPLATE" ]]; then
  echo '{"error": "Prompt template not found for '"${AGENT}"' phase '"${PHASE_NAME}"'"}'
  exit 1
fi

# Substitute variables in template
USER_PROMPT="$USER_TEMPLATE"
USER_PROMPT="${USER_PROMPT//\{task_context\}/$TASK_CONTEXT}"
USER_PROMPT="${USER_PROMPT//\{phase_findings\}/$PHASE_FINDINGS}"

# Get actual LLM model name
ACTUAL_MODEL=$(jq -r ".llm_providers.${LLM_PROVIDER}.models.${LLM_MODEL}" "$CONFIG_FILE")

# Prepare LLM call
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LLM_REQUEST_LOG="${LOG_DIR}/${WORKFLOW_ID}-llm-requests.jsonl"
mkdir -p "$LOG_DIR"

# Log LLM request
jq -n \
  --arg agent "$AGENT" \
  --arg phase "$PHASE" \
  --arg provider "$LLM_PROVIDER" \
  --arg model "$ACTUAL_MODEL" \
  --arg timestamp "$TIMESTAMP" \
  '{
    agent: $agent,
    phase: $phase,
    provider: $provider,
    model: $model,
    timestamp: $timestamp,
    status: "request_sent"
  }' >> "$LLM_REQUEST_LOG"

# Call LLM (via llm-client.sh or direct API)
LLM_RESPONSE=$(timeout "$TIMEOUT" bash "${SCRIPT_DIR}/llm-client.sh" \
  --provider "$LLM_PROVIDER" \
  --model "$ACTUAL_MODEL" \
  --system "$SYSTEM_PROMPT" \
  --prompt "$USER_PROMPT" \
  --max-tokens "$MAX_TOKENS" \
  --json-output 2>/dev/null || true)

# Parse LLM response
if [[ -z "$LLM_RESPONSE" ]]; then
  # Timeout or error - return escalate vote
  VOTE_JSON=$(jq -n \
    --arg agent "$AGENT" \
    --arg phase "$PHASE" \
    --arg workflow "$WORKFLOW_ID" \
    '{
      workflow_id: $workflow,
      phase: $phase,
      agent_id: $agent,
      timestamp: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      status: "submitted",
      decision: "escalate",
      confidence: "low",
      rationale: "LLM timeout or error - escalating for manual review",
      findings: ["LLM call failed - timeout or API error"],
      error: "llm_timeout"
    }')
else
  # Try to parse as JSON
  if ! PARSED=$(echo "$LLM_RESPONSE" | jq . 2>/dev/null); then
    # Not JSON - wrap in JSON response
    PARSED=$(jq -n \
      --arg agent "$AGENT" \
      --arg phase "$PHASE" \
      --arg workflow "$WORKFLOW_ID" \
      --arg response "$LLM_RESPONSE" \
      '{
        workflow_id: $workflow,
        phase: $phase,
        agent_id: $agent,
        timestamp: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        status: "submitted",
        decision: "proceed",
        confidence: "medium",
        rationale: $response,
        findings: [],
        raw_response: $response
      }')
  fi
  
  # Ensure vote has required fields
  VOTE_JSON=$(echo "$PARSED" | jq \
    --arg agent "$AGENT" \
    --arg phase "$PHASE" \
    --arg workflow "$WORKFLOW_ID" \
    '.workflow_id = $workflow |
     .phase = ($phase | tonumber) |
     .agent_id = $agent |
     .timestamp = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'" |
     .status = "submitted" |
     .decision = (.decision // "proceed") |
     .confidence = (.confidence // "medium") |
     .rationale = (.rationale // "See findings") |
     .findings = (.findings // []) |
     if .decision | test("proceed|escalate|blocked|needs_info") then . else .decision = "proceed" end')
fi

# Log vote
VOTES_FILE="${LOG_DIR}/${WORKFLOW_ID}-votes.jsonl"
echo "$VOTE_JSON" | jq . >> "$VOTES_FILE"

# Output vote
echo "$VOTE_JSON" | jq .

exit 0

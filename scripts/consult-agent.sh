#!/bin/bash
# scripts/consult-agent.sh
# RPC handler: Allow one agent to consult another for opinion
# Usage: ./consult-agent.sh --from implementer --to sentinel --question "Is this secure?" --workflow wf-001

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STATE_DIR="${PROJECT_DIR}/workflow-state"
LOG_DIR="${PROJECT_DIR}/workflow-logs"

# Parse arguments
FROM_AGENT=""
TO_AGENT=""
QUESTION=""
WORKFLOW_ID=""
PHASE=0
CONTEXT_FILE=""
DEPTH=0
TIMEOUT=60

while [[ $# -gt 0 ]]; do
  case $1 in
    --from) FROM_AGENT="$2"; shift 2 ;;
    --to) TO_AGENT="$2"; shift 2 ;;
    --question) QUESTION="$2"; shift 2 ;;
    --workflow) WORKFLOW_ID="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --context) CONTEXT_FILE="$2"; shift 2 ;;
    --depth) DEPTH="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate inputs
[[ -z "$FROM_AGENT" ]] && { echo '{"error": "from_agent required"}'; exit 1; }
[[ -z "$TO_AGENT" ]] && { echo '{"error": "to_agent required"}'; exit 1; }
[[ -z "$QUESTION" ]] && { echo '{"error": "question required"}'; exit 1; }
[[ -z "$WORKFLOW_ID" ]] && { echo '{"error": "workflow_id required"}'; exit 1; }

# Validate agents
VALID_AGENTS=("coordinator" "researcher" "implementer" "lens" "sentinel" "anchor")
for agent in "${FROM_AGENT}" "${TO_AGENT}"; do
  if [[ ! " ${VALID_AGENTS[@]} " =~ " ${agent} " ]]; then
    echo '{"error": "invalid_agent: '"${agent}"'"}'
    exit 1
  fi
done

# Prevent circular calls (A→B→A prevention)
CONSULTATION_LOG="/tmp/consultation_chain_${WORKFLOW_ID}.log"
mkdir -p /tmp

# Check depth (max 2)
if [[ $DEPTH -gt 2 ]]; then
  jq -n \
    --arg from "$FROM_AGENT" \
    --arg to "$TO_AGENT" \
    --arg question "$QUESTION" \
    '{
      type: "consultation_response",
      from_agent: $to,
      to_agent: $from,
      status: "failed",
      error: "max_depth_exceeded",
      reason: "Consultation depth limit (2) exceeded"
    }' | jq .
  exit 0
fi

# Check for circular calls
if [[ -f "$CONSULTATION_LOG" ]]; then
  if grep -q "^${TO_AGENT}$" "$CONSULTATION_LOG" 2>/dev/null; then
    jq -n \
      --arg from "$FROM_AGENT" \
      --arg to "$TO_AGENT" \
      --arg question "$QUESTION" \
      '{
        type: "consultation_response",
        from_agent: $to,
        to_agent: $from,
        status: "failed",
        error: "circular_call_prevented",
        reason: "Circular call detected: '"${TO_AGENT}"' already in call chain"
      }' | jq .
    exit 0
  fi
fi

# Log consultation chain
echo "${TO_AGENT}" >> "$CONSULTATION_LOG"
trap "sed -i '$ d' '$CONSULTATION_LOG'" EXIT

# Create consultation request
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONSULTATION_ID="cons-${WORKFLOW_ID}-$(shuf -i 1000-9999 -n 1)"

CONSULTATION_REQUEST=$(jq -n \
  --arg type "consultation_request" \
  --arg id "$CONSULTATION_ID" \
  --arg from "$FROM_AGENT" \
  --arg to "$TO_AGENT" \
  --arg question "$QUESTION" \
  --arg workflow "$WORKFLOW_ID" \
  --argjson phase "$PHASE" \
  --argjson depth "$DEPTH" \
  --argjson timeout "$TIMEOUT" \
  --arg timestamp "$TIMESTAMP" \
  '{
    type: $type,
    id: $id,
    from_agent: $from,
    to_agent: $to,
    workflow_id: $workflow,
    phase: $phase,
    question: $question,
    depth: $depth,
    timeout: $timeout,
    timestamp: $timestamp
  }')

# Load context if provided
if [[ -n "$CONTEXT_FILE" && -f "$CONTEXT_FILE" ]]; then
  CONSULTATION_REQUEST=$(echo "$CONSULTATION_REQUEST" | jq \
    --slurpfile context "$CONTEXT_FILE" \
    '.context = $context[0]')
fi

# Get brief consultation response from LLM
# Use fast model (Haiku) for quick consultation
CONFIG_FILE="${PROJECT_DIR}/copilot-config.json"
PROMPTS_FILE="${PROJECT_DIR}/copilot-prompts.json"

# Extract LLM provider
PROVIDER=$(jq -r '.llm_providers | keys[0]' "$CONFIG_FILE" 2>/dev/null || echo "claude")
MODEL=$(jq -r ".llm_providers.${PROVIDER}.models.fast" "$CONFIG_FILE" 2>/dev/null || echo "claude-3-5-haiku-20241022")

# Build consultation prompt
CONSULTATION_PROMPT="Quick opinion requested:
Agent: ${TO_AGENT}
Question: ${QUESTION}
Context: $(echo "$CONSULTATION_REQUEST" | jq -r '.context // "None"' 2>/dev/null)

Respond with JSON:
{
  \"opinion\": \"brief response (1-2 sentences)\",
  \"concern_level\": \"low|medium|high|critical\",
  \"recommendation\": \"proceed|request_changes|escalate|blocked\",
  \"issues\": [\"issue1\"],
  \"fixes\": [\"fix1\"]
}"

# Call LLM for consultation
LLM_RESPONSE=$(timeout 60 bash "${SCRIPT_DIR}/llm-client.sh" \
  --provider "$PROVIDER" \
  --model "$MODEL" \
  --prompt "$CONSULTATION_PROMPT" \
  --max-tokens 500 \
  --json-output 2>/dev/null || echo '{}')

# Parse response
if echo "$LLM_RESPONSE" | jq . > /dev/null 2>&1; then
  # Extract text from LLM response
  LLM_TEXT=$(echo "$LLM_RESPONSE" | jq -r '.content[0].text // .choices[0].message.content // .' 2>/dev/null)
  
  # Try to parse as JSON
  if PARSED_RESPONSE=$(echo "$LLM_TEXT" | jq . 2>/dev/null); then
    # Valid JSON response from LLM
    CONSULTATION_RESPONSE=$(jq -n \
      --arg type "consultation_response" \
      --arg id "$CONSULTATION_ID" \
      --arg from "$TO_AGENT" \
      --arg to "$FROM_AGENT" \
      --arg question "$QUESTION" \
      --argjson parsed "$PARSED_RESPONSE" \
      '{
        type: $type,
        id: $id,
        from_agent: $from,
        to_agent: $to,
        question: $question,
        status: "success",
        opinion: ($parsed.opinion // "Opinion pending"),
        concern_level: ($parsed.concern_level // "medium"),
        recommendation: ($parsed.recommendation // "proceed"),
        issues: ($parsed.issues // []),
        fixes: ($parsed.fixes // []),
        timestamp: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
      }')
  else
    # Fallback: LLM returned text, create response
    CONSULTATION_RESPONSE=$(jq -n \
      --arg type "consultation_response" \
      --arg id "$CONSULTATION_ID" \
      --arg from "$TO_AGENT" \
      --arg to "$FROM_AGENT" \
      --arg question "$QUESTION" \
      --arg text "$LLM_TEXT" \
      '{
        type: $type,
        id: $id,
        from_agent: $from,
        to_agent: $to,
        question: $question,
        status: "success",
        opinion: $text,
        concern_level: "medium",
        recommendation: "proceed",
        timestamp: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
      }')
  fi
else
  # LLM call failed - fallback
  CONSULTATION_RESPONSE=$(jq -n \
    --arg type "consultation_response" \
    --arg id "$CONSULTATION_ID" \
    --arg from "$TO_AGENT" \
    --arg to "$FROM_AGENT" \
    --arg question "$QUESTION" \
    '{
      type: $type,
      id: $id,
      from_agent: $from,
      to_agent: $to,
      question: $question,
      status: "failed",
      error: "llm_timeout",
      recommendation: "request_changes",
      timestamp: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }')
fi

# Log consultation
CONSULTATION_LOG_FILE="${LOG_DIR}/${WORKFLOW_ID}-consultations.jsonl"
echo "$CONSULTATION_REQUEST" | jq . >> "$CONSULTATION_LOG_FILE"
echo "$CONSULTATION_RESPONSE" | jq . >> "$CONSULTATION_LOG_FILE"

# Return response
echo "$CONSULTATION_RESPONSE" | jq .

exit 0

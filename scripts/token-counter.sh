#!/bin/bash
# scripts/token-counter.sh
# Estimate and count tokens for LLM calls
# Usage: ./token-counter.sh --text "..." --model claude-3-5-sonnet --estimate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEXT=""
MODEL="claude-3-5-sonnet-20241022"
ESTIMATE=false
ACTUAL=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --text) TEXT="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --estimate) ESTIMATE=true; shift ;;
    --actual) ACTUAL=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$TEXT" ]] && { echo '{"error": "Text is required"}'; exit 1; }

# Estimate tokens (rough approximation: 1 token ≈ 4 chars for English)
estimate_tokens() {
  local text=$1
  local chars=${#text}
  local estimated=$((chars / 4))
  echo $estimated
}

# Output
if [[ "$ESTIMATE" == true ]]; then
  TOKENS=$(estimate_tokens "$TEXT")
  jq -n \
    --arg model "$MODEL" \
    --argjson tokens "$TOKENS" \
    --argjson text_length "${#TEXT}" \
    '{
      model: $model,
      estimated_tokens: $tokens,
      text_length: $text_length,
      method: "estimation"
    }' | jq .
elif [[ "$ACTUAL" == true ]]; then
  # For actual counting, we'd need to call Claude's API with token counting
  # For now, return estimation with note
  TOKENS=$(estimate_tokens "$TEXT")
  jq -n \
    --arg model "$MODEL" \
    --argjson tokens "$TOKENS" \
    --argjson text_length "${#TEXT}" \
    '{
      model: $model,
      estimated_tokens: $tokens,
      text_length: $text_length,
      method: "estimation_only",
      note: "Actual counting requires Claude API call"
    }' | jq .
else
  TOKENS=$(estimate_tokens "$TEXT")
  echo $TOKENS
fi

#!/bin/bash
# scripts/llm-client.sh
# Unified LLM client for calling Claude or GitHub Copilot
# Usage: ./llm-client.sh --provider claude --model default --prompt "..." --max-tokens 2048

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../copilot-config.json"

# Defaults
PROVIDER="${PROVIDER:-claude}"
MODEL=""
PROMPT=""
MAX_TOKENS=2048
TEMPERATURE=0.7
SYSTEM_PROMPT=""
JSON_OUTPUT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --provider) PROVIDER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --system) SYSTEM_PROMPT="$2"; shift 2 ;;
    --max-tokens) MAX_TOKENS="$2"; shift 2 ;;
    --temperature) TEMPERATURE="$2"; shift 2 ;;
    --json-output) JSON_OUTPUT=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$PROMPT" ]] && { echo "Error: --prompt required" >&2; exit 1; }

# Load config
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo '{"error": "Config file not found"}' | jq . 2>/dev/null || echo "Error: Config file not found"
  exit 1
fi

# Get model if not specified
if [[ -z "$MODEL" ]]; then
  MODEL=$(jq -r ".llm_providers.${PROVIDER}.models.default" "$CONFIG_FILE")
fi

# Function to call Claude API
call_claude() {
  local model=$1
  local system=$2
  local user_prompt=$3
  
  local api_key="${ANTHROPIC_API_KEY:-}"
  [[ -z "$api_key" ]] && { echo '{"error": "ANTHROPIC_API_KEY not set"}' | jq . 2>/dev/null || echo "Error: API key not set"; exit 1; }
  
  local payload=$(jq -n \
    --arg model "$model" \
    --arg system "$system" \
    --arg prompt "$user_prompt" \
    --argjson max_tokens "$MAX_TOKENS" \
    --argjson temperature "$TEMPERATURE" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      temperature: $temperature,
      system: $system,
      messages: [
        {
          role: "user",
          content: $prompt
        }
      ]
    }')
  
  local response=$(curl -s \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: $api_key" \
    -H "anthropic-version: 2023-06-01" \
    -d "$payload")
  
  echo "$response"
}

# Function to call GitHub Copilot API
call_github_copilot() {
  local model=$1
  local system=$2
  local user_prompt=$3
  
  local token="${GITHUB_TOKEN:-}"
  [[ -z "$token" ]] && { echo '{"error": "GITHUB_TOKEN not set"}' | jq . 2>/dev/null || echo "Error: GitHub token not set"; exit 1; }
  
  local payload=$(jq -n \
    --arg model "$model" \
    --arg system "$system" \
    --arg prompt "$user_prompt" \
    --argjson max_tokens "$MAX_TOKENS" \
    --argjson temperature "$TEMPERATURE" \
    '{
      model: $model,
      max_tokens: $max_tokens,
      temperature: $temperature,
      system: $system,
      messages: [
        {
          role: "user",
          content: $prompt
        }
      ]
    }')
  
  local response=$(curl -s \
    -X POST "https://api.github.com/models/copilot/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "$payload")
  
  echo "$response"
}

# Call appropriate provider
case "$PROVIDER" in
  claude)
    RESPONSE=$(call_claude "$MODEL" "$SYSTEM_PROMPT" "$PROMPT")
    ;;
  github_copilot|github-copilot)
    RESPONSE=$(call_github_copilot "$MODEL" "$SYSTEM_PROMPT" "$PROMPT")
    ;;
  *)
    echo '{"error": "Unknown provider"}' | jq . 2>/dev/null || echo "Error: Unknown provider"
    exit 1
    ;;
esac

# Output response
if [[ "$JSON_OUTPUT" == true ]]; then
  echo "$RESPONSE" | jq .
else
  # Extract text content from response
  echo "$RESPONSE" | jq -r '.content[0].text // .choices[0].message.content // .error' 2>/dev/null || echo "$RESPONSE"
fi

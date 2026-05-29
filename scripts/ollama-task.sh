#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <instruction> [context-file] [model] [ollama-url] [max-budget] [reserve-response] [temperature] [output-json]" >&2
  exit 1
fi

for cmd in curl jq awk wc grep; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

INSTRUCTION="$1"
CONTEXT_FILE="${2:-}"
MODEL="${3:-llama3.1:8b}"
OLLAMA_URL="${4:-http://127.0.0.1:11434}"
MAX_BUDGET="${5:-4000}"
RESERVE_RESPONSE="${6:-1200}"
TEMPERATURE="${7:-0.2}"
OUTPUT_JSON="${8:-}"

estimate_tokens() {
  local text="$1"
  local chars words c w
  chars="$(printf '%s' "$text" | wc -m | awk '{print $1}')"
  words="$(printf '%s' "$text" | grep -Eo '\S+' | wc -l | awk '{print $1}')"
  c=$(( (chars + 3) / 4 ))
  w=$(( (words * 4 + 2) / 3 ))
  if (( c > w )); then echo "$c"; else echo "$w"; fi
}

truncate_to_budget() {
  local text="$1"
  local budget="$2"
  local out=""
  while IFS= read -r line; do
    local candidate
    if [[ -z "$out" ]]; then
      candidate="$line"
    else
      candidate="$out"$'\n'"$line"
    fi
    local t
    t="$(estimate_tokens "$candidate")"
    if (( t > budget )); then
      break
    fi
    out="$candidate"
  done <<< "$text"
  printf '%s' "$out"
}

CONTEXT=""
if [[ -n "$CONTEXT_FILE" ]]; then
  [[ -f "$CONTEXT_FILE" ]] || { echo "Context file not found: $CONTEXT_FILE" >&2; exit 1; }
  CONTEXT="$(cat "$CONTEXT_FILE")"
fi

instruction_tokens="$(estimate_tokens "$INSTRUCTION")"
available_input=$((MAX_BUDGET - RESERVE_RESPONSE))
(( available_input < 100 )) && available_input=100
fixed_overhead=120
context_budget=$((available_input - instruction_tokens - fixed_overhead))
(( context_budget < 0 )) && context_budget=0
trimmed_context="$(truncate_to_budget "$CONTEXT" "$context_budget")"

PROMPT=$'You are a local coding assistant. Keep answers concise and actionable.\n\nInstruction:\n'"$INSTRUCTION"$'\n\nContext:\n'"$trimmed_context"
estimated_input="$(estimate_tokens "$PROMPT")"
if (( estimated_input > available_input )); then
  echo "Input exceeds budget after trimming. estimatedInput=$estimated_input availableInput=$available_input" >&2
  exit 1
fi

payload="$(jq -n \
  --arg model "$MODEL" \
  --arg prompt "$PROMPT" \
  --argjson temp "$TEMPERATURE" \
  --argjson predict "$RESERVE_RESPONSE" \
  '{
    model: $model,
    stream: false,
    options: {temperature: $temp, num_predict: $predict},
    messages: [
      {role: "system", content: "You are concise, precise, and output practical steps."},
      {role: "user", content: $prompt}
    ]
  }')"

resp="$(curl -fsS -X POST "$OLLAMA_URL/api/chat" -H "Content-Type: application/json" -d "$payload")"
answer="$(printf '%s' "$resp" | jq -r '.message.content // ""')"
answer_tokens="$(estimate_tokens "$answer")"
context_used="$(estimate_tokens "$trimmed_context")"

result="$(jq -n \
  --arg model "$MODEL" \
  --arg text "$answer" \
  --argjson maxBudget "$MAX_BUDGET" \
  --argjson reserve "$RESERVE_RESPONSE" \
  --argjson available "$available_input" \
  --argjson estInput "$estimated_input" \
  --argjson inst "$instruction_tokens" \
  --argjson cb "$context_budget" \
  --argjson cu "$context_used" \
  --argjson outTok "$answer_tokens" \
  '{
    model: $model,
    budgets: {
      maxBudgetTokens: $maxBudget,
      reserveForResponse: $reserve,
      availableInput: $available,
      estimatedInput: $estInput,
      instructionTokens: $inst,
      contextBudget: $cb,
      contextUsedTokens: $cu
    },
    output: {
      text: $text,
      estimatedTokens: $outTok
    }
  }')"

if [[ -n "$OUTPUT_JSON" ]]; then
  mkdir -p "$(dirname "$OUTPUT_JSON")"
  printf '%s\n' "$result" > "$OUTPUT_JSON"
fi

printf '%s\n' "$result"

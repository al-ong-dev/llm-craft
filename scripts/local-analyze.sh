#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <task-class> <query> [instruction] [index-path] [top-blocks] [max-lines-per-block] [model] [ollama-url] [max-budget] [reserve-response] [temperature] [output-json]" >&2
  exit 1
fi

for cmd in jq mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

TASK_CLASS="$1"
QUERY="$2"
INSTRUCTION="${3:-}"
INDEX_PATH="${4:-./code-index}"
TOP_BLOCKS="${5:-5}"
MAX_LINES_PER_BLOCK="${6:-120}"
MODEL="${7:-llama3.1:8b}"
OLLAMA_URL="${8:-http://127.0.0.1:11434}"
MAX_BUDGET="${9:-4000}"
RESERVE_RESPONSE="${10:-1200}"
TEMPERATURE="${11:-0.2}"
OUTPUT_JSON="${12:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_SCRIPT="$SCRIPT_DIR/smart-search.sh"
OLLAMA_SCRIPT="$SCRIPT_DIR/ollama-task.sh"

[[ -f "$SEARCH_SCRIPT" ]] || { echo "Missing dependency: $SEARCH_SCRIPT" >&2; exit 1; }
[[ -f "$OLLAMA_SCRIPT" ]] || { echo "Missing dependency: $OLLAMA_SCRIPT" >&2; exit 1; }

search_json="$("$SEARCH_SCRIPT" "$QUERY" "$INDEX_PATH" "$TOP_BLOCKS" "code-block")"
hits="$(printf '%s' "$search_json" | jq '.top | length')"
(( hits > 0 )) || { echo "No relevant blocks found from index search." >&2; exit 1; }

tmp_context="$(mktemp)"
tmp_result="$(mktemp)"
trap 'rm -f "$tmp_context" "$tmp_result"' EXIT

printf '%s' "$search_json" | jq -r --argjson maxLines "$MAX_LINES_PER_BLOCK" '
  .top
  | to_entries
  | map(
      "[BLOCK \(.key + 1)] file=\(.value.file) lines=\(.value.startLine)-\(.value.endLine) score=\(.value.score)\n"
      + (
          (.value.snippet // "")
          | split("\n")
          | .[0:$maxLines]
          | join("\n")
        )
    )
  | join("\n\n")
' > "$tmp_context"

if [[ -z "$INSTRUCTION" ]]; then
  INSTRUCTION=$'Task: '"$TASK_CLASS"$'\nGoal: Answer the query using only the provided retrieved blocks.\nConstraints:\n- Be concise and actionable.\n- If evidence is weak, say so explicitly.\n- Output format:\n  1) Answer\n  2) Evidence blocks used\n  3) Confidence (high|medium|low)\n  4) Needs escalation (true|false)\n\nQuery:\n'"$QUERY"
fi

ollama_json="$("$OLLAMA_SCRIPT" "$INSTRUCTION" "$tmp_context" "$MODEL" "$OLLAMA_URL" "$MAX_BUDGET" "$RESERVE_RESPONSE" "$TEMPERATURE")"

confidence="$(printf '%s' "$search_json" | jq -r '
  .top as $t
  | if ($t|length) == 0 then "low"
    elif (($t[0].score // 0) >= 18 and ($t|length) >= 3) then "high"
    elif (($t[0].score // 0) >= 8 and ($t|length) >= 2) then "medium"
    else "low" end
')"

needs_escalation="false"
[[ "$confidence" == "low" ]] && needs_escalation="true"

result="$(jq -n \
  --arg taskClass "$TASK_CLASS" \
  --arg query "$QUERY" \
  --arg confidence "$confidence" \
  --argjson topBlocks "$(printf '%s' "$search_json" | jq '.top')" \
  --arg answer "$(printf '%s' "$ollama_json" | jq -r '.output.text')" \
  --argjson ansTok "$(printf '%s' "$ollama_json" | jq '.output.estimatedTokens')" \
  --argjson budgets "$(printf '%s' "$ollama_json" | jq '.budgets')" \
  --argjson escalate "$needs_escalation" \
  '{
    taskClass: $taskClass,
    query: $query,
    retrieval: { topBlocks: $topBlocks, confidence: $confidence },
    output: { answer: $answer, estimatedTokens: $ansTok, needsEscalation: $escalate },
    budgets: $budgets
  }')"

if [[ -n "$OUTPUT_JSON" ]]; then
  mkdir -p "$(dirname "$OUTPUT_JSON")"
  printf '%s\n' "$result" > "$OUTPUT_JSON"
fi

printf '%s\n' "$result"

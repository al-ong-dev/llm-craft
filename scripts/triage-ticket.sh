#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ticket-text> [task-class] [code-index] [jira-json] [confluence-json] [top-knowledge] [top-code-blocks] [max-lines-per-block] [model] [ollama-url] [max-budget] [reserve-response] [temperature] [output-json]" >&2
  exit 1
fi

for cmd in jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

TICKET_TEXT="$1"
TASK_CLASS="${2:-risk-scan}"
CODE_INDEX="${3:-./code-index.json}"
JIRA_JSON="${4:-./data/jira-items.json}"
CONF_JSON="${5:-./data/confluence-pages.json}"
TOP_KNOWLEDGE="${6:-8}"
TOP_CODE_BLOCKS="${7:-5}"
MAX_LINES_PER_BLOCK="${8:-120}"
MODEL="${9:-llama3.1:8b}"
OLLAMA_URL="${10:-http://127.0.0.1:11434}"
MAX_BUDGET="${11:-4000}"
RESERVE_RESPONSE="${12:-1200}"
TEMPERATURE="${13:-0.2}"
OUTPUT_JSON="${14:-./runs/triage-ticket.json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOWLEDGE_SCRIPT="$SCRIPT_DIR/knowledge-search.sh"
LOCAL_ANALYZE_SCRIPT="$SCRIPT_DIR/local-analyze.sh"

[[ -f "$KNOWLEDGE_SCRIPT" ]] || { echo "Missing dependency: $KNOWLEDGE_SCRIPT" >&2; exit 1; }
[[ -f "$LOCAL_ANALYZE_SCRIPT" ]] || { echo "Missing dependency: $LOCAL_ANALYZE_SCRIPT" >&2; exit 1; }

echo "1/3 Running unified knowledge search..."
knowledge_json="$("$KNOWLEDGE_SCRIPT" "$TICKET_TEXT" "$CODE_INDEX" "$JIRA_JSON" "$CONF_JSON" "$TOP_KNOWLEDGE")"

echo "2/3 Running retrieval-grounded local analysis..."
instruction=$'Task: '"$TASK_CLASS"$'\nGoal: Triage this engineering ticket using retrieved code context and produce a practical next-step report.\nConstraints:\n- Keep output concise.\n- Include:\n  1) probable root cause areas\n  2) impacted components\n  3) immediate checks\n  4) suggested owner role\n  5) escalation recommendation\n\nTicket:\n'"$TICKET_TEXT"
local_json="$("$LOCAL_ANALYZE_SCRIPT" "$TASK_CLASS" "$TICKET_TEXT" "$instruction" "$CODE_INDEX" "$TOP_CODE_BLOCKS" "$MAX_LINES_PER_BLOCK" "$MODEL" "$OLLAMA_URL" "$MAX_BUDGET" "$RESERVE_RESPONSE" "$TEMPERATURE")"

echo "3/3 Writing triage report..."
mkdir -p "$(dirname "$OUTPUT_JSON")"

result="$(jq -n \
  --arg generatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg ticketText "$TICKET_TEXT" \
  --arg taskClass "$TASK_CLASS" \
  --argjson knowledge "$(printf '%s' "$knowledge_json" | jq '.top')" \
  --argjson local "$local_json" \
  '{
    generatedAt: $generatedAt,
    input: {ticketText: $ticketText, taskClass: $taskClass},
    knowledgeHits: $knowledge,
    localAnalysis: $local,
    summary: {
      confidence: $local.retrieval.confidence,
      needsEscalation: $local.output.needsEscalation
    }
  }')"

printf '%s\n' "$result" > "$OUTPUT_JSON"

jq -n \
  --arg outputPath "$OUTPUT_JSON" \
  --arg confidence "$(printf '%s' "$result" | jq -r '.summary.confidence')" \
  --argjson needsEscalation "$(printf '%s' "$result" | jq '.summary.needsEscalation')" \
  '{outputPath: $outputPath, confidence: $confidence, needsEscalation: $needsEscalation}'

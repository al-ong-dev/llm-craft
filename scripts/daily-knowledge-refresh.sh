#!/usr/bin/env bash
set -euo pipefail

ROOT_PATH="${1:-.}"
CODE_INDEX="${2:-./code-index.json}"
JIRA_PATH="${3:-./data/jira-items.json}"
CONF_PATH="${4:-./data/confluence-pages.json}"
REPORT_PATH="${5:-./reports/daily-signals.json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$(dirname "$REPORT_PATH")"

echo "1/4 Building code index..."
"$SCRIPT_DIR/build-index.sh" "$ROOT_PATH"

# build-index.sh writes ./code-index directory format, while knowledge-search.sh
# expects json code-index. Keep compatibility by preferring existing JSON index
# and generating one via PowerShell workflow when available.
if [[ ! -f "$CODE_INDEX" ]]; then
  echo "Warning: $CODE_INDEX not found. knowledge-search.sh will use Jira/Confluence only." >&2
fi

echo "2/4 Syncing Jira..."
"$SCRIPT_DIR/jira-sync.sh" "order by updated DESC" 200 "$JIRA_PATH"

echo "3/4 Syncing Confluence..."
"$SCRIPT_DIR/confluence-sync.sh" "type=page order by lastmodified desc" 100 "$CONF_PATH"

echo "4/4 Generating daily signals..."
queries=(
  "production incident root cause"
  "authentication timeout token"
  "release blocker regression"
  "oncall urgent bug"
  "test gap edge case"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
echo '[]' > "$tmp"

for q in "${queries[@]}"; do
  result="$("$SCRIPT_DIR/knowledge-search.sh" "$q" "$CODE_INDEX" "$JIRA_PATH" "$CONF_PATH" 5)"
  jq -n --arg query "$q" --argjson result "$result" '{query:$query, top:$result.top}' > "$tmp.item"
  jq -s '.[0] + [.[1]]' "$tmp" "$tmp.item" > "$tmp.new"
  mv "$tmp.new" "$tmp"
done

jq -n \
  --arg generated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg root "$ROOT_PATH" \
  --arg code "$CODE_INDEX" \
  --arg jira "$JIRA_PATH" \
  --arg conf "$CONF_PATH" \
  --slurpfile signals "$tmp" \
  '{
    generatedAt: $generated,
    inputs: {
      rootPath: $root,
      codeIndexPath: $code,
      jiraPath: $jira,
      confluencePath: $conf
    },
    signals: $signals[0]
  }' > "$REPORT_PATH"

echo "Wrote $REPORT_PATH"

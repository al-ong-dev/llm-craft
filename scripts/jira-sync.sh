#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${ATLASSIAN_BASE_URL:-}"
EMAIL="${ATLASSIAN_EMAIL:-}"
API_TOKEN="${ATLASSIAN_API_TOKEN:-}"
JQL="${1:-order by updated DESC}"
MAX_RESULTS="${2:-200}"
OUT="${3:-./data/jira-items.json}"

for cmd in curl jq base64; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

[[ -n "$BASE_URL" && -n "$EMAIL" && -n "$API_TOKEN" ]] || {
  echo "Set ATLASSIAN_BASE_URL, ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN" >&2
  exit 1
}

auth="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64)"
mkdir -p "$(dirname "$OUT")"

start=0
page_size=100
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
echo '[]' > "$tmp"

while :; do
  remaining=$((MAX_RESULTS - start))
  (( remaining <= 0 )) && break
  (( remaining < page_size )) && take="$remaining" || take="$page_size"

  resp="$(curl -fsS -H "Authorization: Basic $auth" -H "Accept: application/json" \
    "$BASE_URL/rest/api/3/search?jql=$(printf '%s' "$JQL" | jq -sRr @uri)&startAt=$start&maxResults=$take&fields=summary,status,assignee,updated,description")"

  count="$(printf '%s' "$resp" | jq '.issues | length')"
  (( count == 0 )) && break

  chunk="$(printf '%s' "$resp" | jq --arg base "$BASE_URL" '
    .issues | map({
      source: "jira",
      key: .key,
      id: .id,
      url: ($base + "/browse/" + .key),
      summary: .fields.summary,
      status: (.fields.status.name // ""),
      assignee: (.fields.assignee.displayName // ""),
      updated: (.fields.updated // ""),
      description: (.fields.description | tostring),
      text: ([.key, (.fields.summary // ""), ((.fields.description | tostring) // "")] | join("\n"))
    })
  ')"

  jq -s '.[0] + .[1]' "$tmp" <(printf '%s' "$chunk") > "$tmp.new"
  mv "$tmp.new" "$tmp"

  start=$((start + count))
  (( count < take )) && break
done

jq -n --arg base "$BASE_URL" --arg jql "$JQL" --arg generated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --slurpfile items "$tmp" '
{
  source: "jira",
  generatedAt: $generated,
  baseUrl: $base,
  jql: $jql,
  count: ($items[0] | length),
  items: $items[0]
}' > "$OUT"

echo "Wrote $OUT"

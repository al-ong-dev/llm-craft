#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${ATLASSIAN_BASE_URL:-}"
EMAIL="${ATLASSIAN_EMAIL:-}"
API_TOKEN="${ATLASSIAN_API_TOKEN:-}"
CQL="${1:-type=page order by lastmodified desc}"
LIMIT="${2:-100}"
OUT="${3:-./data/confluence-pages.json}"

for cmd in curl jq base64; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

[[ -n "$BASE_URL" && -n "$EMAIL" && -n "$API_TOKEN" ]] || {
  echo "Set ATLASSIAN_BASE_URL, ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN" >&2
  exit 1
}

auth="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64)"
mkdir -p "$(dirname "$OUT")"

resp="$(curl -fsS -H "Authorization: Basic $auth" -H "Accept: application/json" \
  "$BASE_URL/wiki/rest/api/search?cql=$(printf '%s' "$CQL" | jq -sRr @uri)&limit=$LIMIT")"

items="$(printf '%s' "$resp" | jq --arg base "$BASE_URL" '
  .results
  | map(select(.content.id != null))
  | map({
      source: "confluence",
      id: .content.id,
      title: (.title // ""),
      url: (if .url then ($base + .url) else "" end),
      excerpt: (.excerpt // ""),
      text: ([.title, (.excerpt // "")] | join("\n"))
    })
')"

jq -n --arg base "$BASE_URL" --arg cql "$CQL" --arg generated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" --argjson items "$items" '
{
  source: "confluence",
  generatedAt: $generated,
  baseUrl: $base,
  cql: $cql,
  count: ($items | length),
  items: $items
}' > "$OUT"

echo "Wrote $OUT"

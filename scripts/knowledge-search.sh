#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <query> [code-index.json] [jira-items.json] [confluence-pages.json] [top]" >&2
  exit 1
fi

for cmd in jq awk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

QUERY="$1"
CODE_INDEX="${2:-./code-index.json}"
JIRA_JSON="${3:-./data/jira-items.json}"
CONF_JSON="${4:-./data/confluence-pages.json}"
TOP="${5:-10}"

tmp_docs="$(mktemp)"
tmp_q="$(mktemp)"
tmp_scores="$(mktemp)"
trap 'rm -f "$tmp_docs" "$tmp_q" "$tmp_scores"' EXIT

echo '[]' > "$tmp_docs"

if [[ -f "$CODE_INDEX" ]]; then
  jq '.chunks | map({type:"code", title:(.relFile + ":" + (.startLine|tostring) + "-" + (.endLine|tostring)), path:.relFile, url:"", text:.content})' "$CODE_INDEX" > "$tmp_scores"
  jq -s '.[0] + .[1]' "$tmp_docs" "$tmp_scores" > "$tmp_docs.new" && mv "$tmp_docs.new" "$tmp_docs"
fi

if [[ -f "$JIRA_JSON" ]]; then
  jq '.items | map({type:"jira", title:(.summary // ""), path:(.key // ""), url:(.url // ""), text:(.text // "")})' "$JIRA_JSON" > "$tmp_scores"
  jq -s '.[0] + .[1]' "$tmp_docs" "$tmp_scores" > "$tmp_docs.new" && mv "$tmp_docs.new" "$tmp_docs"
fi

if [[ -f "$CONF_JSON" ]]; then
  jq '.items | map({type:"confluence", title:(.title // ""), path:(.space // ""), url:(.url // ""), text:(.text // "")})' "$CONF_JSON" > "$tmp_scores"
  jq -s '.[0] + .[1]' "$tmp_docs" "$tmp_scores" > "$tmp_docs.new" && mv "$tmp_docs.new" "$tmp_docs"
fi

count="$(jq 'length' "$tmp_docs")"
(( count > 0 )) || { echo "No documents found from provided sources." >&2; exit 1; }

printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | grep -Eo '[a-z0-9_]{2,}' | sort | uniq -c | awk '{print $2 "\t" $1}' > "$tmp_q"
[[ -s "$tmp_q" ]] || { echo "Query has no searchable terms." >&2; exit 1; }

jq -r '.[] | [.type, .title, .path, .url, .text] | @tsv' "$tmp_docs" \
| awk -F'\t' -v q="$tmp_q" '
BEGIN{
  while ((getline < q) > 0) { qtf[$1]=$2 }
}
{
  type=$1; title=$2; path=$3; url=$4; text=tolower($5)
  docid=NR
  docs[docid]=$0
  n=split(text, arr, /[^a-z0-9_]+/)
  delete seen
  for(i=1;i<=n;i++){
    t=arr[i]
    if(length(t)<2) continue
    tf[docid SUBSEP t]++
    seen[t]=1
  }
  for (t in seen) df[t]++
}
END{
  N=NR+0.0
  for (d=1; d<=NR; d++) {
    s=0
    for (t in qtf) {
      if (df[t] <= 0) continue
      idf=log(1 + (N / (1 + df[t])))
      qw=(1 + log(1 + qtf[t])) * idf
      dtf=tf[d SUBSEP t] + 0.0
      if (dtf <= 0) continue
      dw=(1 + log(1 + dtf))
      s += qw * dw
    }
    if (s > 0) print d "\t" s "\t" docs[d]
  }
}' | sort -k2,2nr | head -n "$TOP" > "$tmp_scores"

awk -F'\t' '
BEGIN { print "{\n  \"query\": \"" ENVIRON["QUERY"] "\",\n  \"top\": ["; first=1 }
{
  score=$2; type=$3; title=$4; path=$5; url=$6; text=$7
  gsub(/"/, "\\\"", title); gsub(/"/, "\\\"", path); gsub(/"/, "\\\"", url); gsub(/"/, "\\\"", text)
  if (!first) print "    ,"
  first=0
  print "    {"
  print "      \"score\": " score ","
  print "      \"sourceType\": \"" type "\","
  print "      \"title\": \"" title "\","
  print "      \"path\": \"" path "\","
  print "      \"url\": \"" url "\","
  print "      \"snippet\": \"" substr(text,1,400) "\""
  print "    }"
}
END { print "  ]\n}" }' QUERY="$QUERY" "$tmp_scores"

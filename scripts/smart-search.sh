#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <query> [index-dir] [top-n] [mode]" >&2
  echo "mode: keyword (default) | code-block" >&2
  exit 1
fi

QUERY="$1"
INDEX_DIR="${2:-./code-index}"
TOP_N="${3:-10}"
MODE="${4:-keyword}"

META="$INDEX_DIR/meta.env"
POSTINGS="$INDEX_DIR/postings.tsv"
DOCFREQ="$INDEX_DIR/docfreq.tsv"
CHUNKS="$INDEX_DIR/chunks.tsv"

for f in "$META" "$POSTINGS" "$DOCFREQ" "$CHUNKS"; do
  [[ -f "$f" ]] || { echo "Missing index file: $f" >&2; exit 1; }
done

# shellcheck disable=SC1090
source "$META"
N="${TOTAL_CHUNKS:-0}"
(( N > 0 )) || { echo "Index appears empty." >&2; exit 1; }

qfile="$(mktemp)"
scores="$(mktemp)"
matched="$(mktemp)"
trap 'rm -f "$qfile" "$scores" "$matched"' EXIT

printf '%s\n' "$QUERY" \
  | tr '[:upper:]' '[:lower:]' \
  | grep -Eo '[a-z0-9_]{2,}' \
  | sort \
  | uniq -c \
  | awk '{print $2 "\t" $1}' > "$qfile"

[[ -s "$qfile" ]] || { echo "Query has no searchable terms." >&2; exit 1; }

awk -F'\t' -v qfile="$qfile" -v docf="$DOCFREQ" -v N="$N" '
BEGIN {
  while ((getline < qfile) > 0) {
    qtf[$1] = $2
  }
  close(qfile)

  while ((getline < docf) > 0) {
    df[$1] = $2
  }
  close(docf)
}
{
  term=$1; cid=$2; tf=$3
  if (!(term in qtf)) next

  qf=qtf[term]+0.0
  dfi=(term in df ? df[term] : 0.0)
  idf=log(1.0 + (N / (1.0 + dfi)))
  qw=(1.0 + log(1.0 + qf)) * idf
  dw=(1.0 + log(1.0 + tf))

  score[cid] += (qw * dw)
  seen[cid,term] = 1
}
END {
  for (k in score) {
    print k "\t" score[k]
  }
  print "--TERMS--"
  for (st in seen) {
    split(st, a, SUBSEP)
    print a[1] "\t" a[2]
  }
}
' "$POSTINGS" > "$scores"

split_line="$(awk '/^--TERMS--$/{print NR; exit}' "$scores")"
[[ -n "$split_line" ]] || { echo "Search failed." >&2; exit 1; }

awk -F'\t' -v stop="$split_line" 'NR < stop {print $1 "\t" $2}' "$scores" \
  | sort -k2,2nr > "$matched"

if [[ "$MODE" == "code-block" ]]; then
  # Lightweight overlap boost: prioritize chunks that match many query terms.
  tmp="$(mktemp)"
  qcount="$(awk 'END{print NR}' "$qfile")"
  awk -F'\t' -v terms_file="$scores" -v split="$split_line" -v qc="$qcount" '
  BEGIN {
    while ((getline < terms_file) > 0) {
      if (NR <= split) continue
      hits[$1]++
    }
    close(terms_file)
  }
  {
    cid=$1; base=$2+0.0
    overlap=(qc>0 ? hits[cid]/qc : 0.0)
    boosted=base + (10.0 * overlap)
    print cid "\t" boosted
  }' "$matched" | sort -k2,2nr > "$tmp"
  mv "$tmp" "$matched"
fi

echo "{"
echo "  \"query\": \"${QUERY//\"/\\\"}\","
echo "  \"mode\": \"${MODE}\","
echo "  \"top\": ["

first=1
while IFS=$'\t' read -r cid score; do
  [[ -n "$cid" ]] || continue
  meta_line="$(awk -F'\t' -v id="$cid" '$1==id {print; exit}' "$CHUNKS")"
  [[ -n "$meta_line" ]] || continue

  IFS=$'\t' read -r _ rel start end <<< "$meta_line"
  snippet="$(sed -n '1,10p' "$INDEX_DIR/chunks/$cid.txt" | sed 's/"/\\"/g')"

  if (( first == 0 )); then
    echo "    ,"
  fi
  first=0
  echo "    {"
  echo "      \"score\": $score,"
  echo "      \"file\": \"${rel//\"/\\\"}\","
  echo "      \"startLine\": $start,"
  echo "      \"endLine\": $end,"
  echo "      \"snippet\": \"${snippet//$'\n'/\\n}\""
  echo "    }"
done < <(head -n "$TOP_N" "$matched")

echo "  ]"
echo "}"

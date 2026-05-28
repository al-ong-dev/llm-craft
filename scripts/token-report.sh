#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-path> [input-cost-per-1k] [output-cost-per-1k]" >&2
  exit 1
fi

TARGET="$1"
INPUT_COST="${2:-0}"
OUTPUT_COST="${3:-0}"

[[ -e "$TARGET" ]] || { echo "Path not found: $TARGET" >&2; exit 1; }

tmp_rows="$(mktemp)"
trap 'rm -f "$tmp_rows"' EXIT

estimate_tokens() {
  local file="$1"
  local chars words c w
  chars="$(wc -m < "$file" | awk '{print $1}')"
  words="$(grep -Eo '\S+' "$file" | wc -l | awk '{print $1}')"
  c=$(( (chars + 3) / 4 ))
  w=$(( (words * 4 + 2) / 3 ))
  if (( c > w )); then echo "$c"; else echo "$w"; fi
}

emit_row() {
  local f="$1"
  local size tokens in_cost out_cost total_cost
  size="$(wc -c < "$f" | awk '{print $1}')"
  (( size > 2097152 )) && return 0

  tokens="$(estimate_tokens "$f")"
  in_cost="$(awk -v t="$tokens" -v c="$INPUT_COST" 'BEGIN {printf "%.6f", (t/1000.0)*c}')"
  out_cost="$(awk -v t="$tokens" -v c="$OUTPUT_COST" 'BEGIN {printf "%.6f", (t/1000.0)*c}')"
  total_cost="$(awk -v a="$in_cost" -v b="$out_cost" 'BEGIN {printf "%.6f", a+b}')"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$size" "$tokens" "$in_cost" "$out_cost" "$total_cost" >> "$tmp_rows"
}

if [[ -f "$TARGET" ]]; then
  emit_row "$TARGET"
else
  while IFS= read -r -d '' f; do
    emit_row "$f"
  done < <(find "$TARGET" -type f -print0)
fi

file_count="$(wc -l < "$tmp_rows" | awk '{print $1}')"
total_tokens="$(awk -F'\t' '{s+=$3} END {print s+0}' "$tmp_rows")"
total_in="$(awk -F'\t' '{s+=$4} END {printf "%.6f", s+0}' "$tmp_rows")"
total_out="$(awk -F'\t' '{s+=$5} END {printf "%.6f", s+0}' "$tmp_rows")"
total_cost="$(awk -F'\t' '{s+=$6} END {printf "%.6f", s+0}' "$tmp_rows")"

echo "{"
echo "  \"summary\": {"
echo "    \"fileCount\": $file_count,"
echo "    \"totalTokens\": $total_tokens,"
echo "    \"totalInCost\": $total_in,"
echo "    \"totalOutCost\": $total_out,"
echo "    \"totalCost\": $total_cost"
echo "  },"
echo "  \"topFiles\": ["

first=1
sort -t$'\t' -k3,3nr "$tmp_rows" | head -n 20 | while IFS=$'\t' read -r file size tokens in_cost out_cost total; do
  escaped_file="$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  if (( first == 0 )); then
    echo "    ,"
  fi
  first=0
  echo "    {"
  echo "      \"file\": \"$escaped_file\","
  echo "      \"size\": $size,"
  echo "      \"tokens\": $tokens,"
  echo "      \"inCost\": $in_cost,"
  echo "      \"outCost\": $out_cost,"
  echo "      \"totalCost\": $total"
  echo "    }"
done

echo "  ]"
echo "}"

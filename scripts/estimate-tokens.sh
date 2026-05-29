#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <text-or-file> [--file]" >&2
  exit 1
fi

INPUT="$1"
IS_FILE="${2:-}"

if [[ "$IS_FILE" == "--file" ]]; then
  [[ -f "$INPUT" ]] || { echo "File not found: $INPUT" >&2; exit 1; }
  TEXT="$(cat "$INPUT")"
else
  TEXT="$INPUT"
fi

chars="$(printf '%s' "$TEXT" | wc -m | awk '{print $1}')"
words="$(printf '%s' "$TEXT" | grep -Eo '\S+' | wc -l | awk '{print $1}')"

char_heuristic=$(( (chars + 3) / 4 ))
# ceil(words / 0.75) = ceil(words * 4 / 3)
word_heuristic=$(( (words * 4 + 2) / 3 ))

if (( char_heuristic > word_heuristic )); then
  estimate="$char_heuristic"
else
  estimate="$word_heuristic"
fi

cat <<EOF
{
  "characters": $chars,
  "words": $words,
  "charHeuristic": $char_heuristic,
  "wordHeuristic": $word_heuristic,
  "tokenEstimate": $estimate
}
EOF

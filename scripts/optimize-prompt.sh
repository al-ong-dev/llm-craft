#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <text-or-file> [--file] [--max-tokens N] [--out FILE]" >&2
  exit 1
fi

INPUT="$1"
shift || true

IS_FILE=0
MAX_TOKENS=0
OUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      IS_FILE=1
      shift
      ;;
    --max-tokens)
      MAX_TOKENS="${2:-0}"
      shift 2
      ;;
    --out)
      OUT_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

estimate_tokens() {
  local t="$1"
  local chars words c w
  chars="$(printf '%s' "$t" | wc -m | awk '{print $1}')"
  words="$(printf '%s' "$t" | grep -Eo '\S+' | wc -l | awk '{print $1}')"
  c=$(( (chars + 3) / 4 ))
  w=$(( (words * 4 + 2) / 3 ))
  if (( c > w )); then echo "$c"; else echo "$w"; fi
}

if (( IS_FILE == 1 )); then
  [[ -f "$INPUT" ]] || { echo "File not found: $INPUT" >&2; exit 1; }
  ORIGINAL="$(cat "$INPUT")"
else
  ORIGINAL="$INPUT"
fi

# Normalize spaces per line, remove duplicate non-empty lines,
# keep single blank-line separators.
OPTIMIZED="$(
  printf '%s\n' "$ORIGINAL" \
    | awk '
      {
        gsub(/[[:space:]]+/, " ");
        sub(/^ /, "", $0);
        sub(/ $/, "", $0);

        if ($0 == "") {
          if (last_blank == 1) next;
          print "";
          last_blank = 1;
          next;
        }

        if (!seen[$0]++) print $0;
        last_blank = 0;
      }
    ' \
    | sed '/^[[:space:]]*$/N;/^\n$/D'
)"

BEFORE="$(estimate_tokens "$ORIGINAL")"
AFTER="$(estimate_tokens "$OPTIMIZED")"

if (( MAX_TOKENS > 0 )); then
  while (( AFTER > MAX_TOKENS )); do
    next="$(printf '%s' "$OPTIMIZED" | sed -E 's/[^.!?]*[.!?][[:space:]]*$//')"
    [[ "$next" == "$OPTIMIZED" ]] && break
    OPTIMIZED="$next"
    AFTER="$(estimate_tokens "$OPTIMIZED")"
    [[ -z "$OPTIMIZED" ]] && break
  done
fi

if [[ -n "$OUT_FILE" ]]; then
  printf '%s' "$OPTIMIZED" > "$OUT_FILE"
fi

escaped="$(printf '%s' "$OPTIMIZED" | sed 's/\\/\\\\/g; s/"/\\"/g; :a;N;$!ba;s/\n/\\n/g')"

cat <<EOF
{
  "beforeTokenEstimate": $BEFORE,
  "afterTokenEstimate": $AFTER,
  "reducedBy": $((BEFORE - AFTER)),
  "outputFile": "$(printf '%s' "$OUT_FILE" | sed 's/"/\\"/g')",
  "optimizedText": "$escaped"
}
EOF

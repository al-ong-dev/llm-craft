#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <root-path> [index-dir] [chunk-lines] [chunk-overlap]" >&2
  exit 1
fi

ROOT_PATH="$1"
INDEX_DIR="${2:-./code-index}"
CHUNK_LINES="${3:-40}"
CHUNK_OVERLAP="${4:-10}"

if [[ ! -d "$ROOT_PATH" ]]; then
  echo "Path not found: $ROOT_PATH" >&2
  exit 1
fi

if (( CHUNK_LINES <= 0 )); then
  echo "chunk-lines must be > 0" >&2
  exit 1
fi

if (( CHUNK_OVERLAP < 0 || CHUNK_OVERLAP >= CHUNK_LINES )); then
  echo "chunk-overlap must be >= 0 and < chunk-lines" >&2
  exit 1
fi

ROOT_PATH="$(cd "$ROOT_PATH" && pwd)"
STEP=$((CHUNK_LINES - CHUNK_OVERLAP))

rm -rf "$INDEX_DIR"
mkdir -p "$INDEX_DIR/chunks"
CHUNKS_TSV="$INDEX_DIR/chunks.tsv"
TERMS_RAW="$INDEX_DIR/terms.raw.tsv"
: > "$CHUNKS_TSV"
: > "$TERMS_RAW"

chunk_id=0

while IFS= read -r -d '' file; do
  case "$file" in
    *.ps1|*.psm1|*.py|*.js|*.jsx|*.ts|*.tsx|*.java|*.go|*.rs|*.cs|*.cpp|*.c|*.h|*.json|*.md|*.yaml|*.yml|*.toml|*.sql|*.sh) ;;
    *) continue ;;
  esac

  rel="${file#$ROOT_PATH/}"
  mapfile -t lines < "$file" || continue
  total="${#lines[@]}"
  (( total == 0 )) && continue

  start=0
  while (( start < total )); do
    end=$((start + CHUNK_LINES))
    (( end > total )) && end=$total

    chunk_file="$INDEX_DIR/chunks/$chunk_id.txt"
    : > "$chunk_file"
    for ((i=start; i<end; i++)); do
      printf '%s\n' "${lines[$i]}" >> "$chunk_file"
    done

    if [[ ! -s "$chunk_file" ]]; then
      rm -f "$chunk_file"
    else
      start_line=$((start + 1))
      end_line=$end
      printf '%s\t%s\t%s\t%s\n' "$chunk_id" "$rel" "$start_line" "$end_line" >> "$CHUNKS_TSV"

      tr '[:upper:]' '[:lower:]' < "$chunk_file" \
        | grep -Eo '[a-z0-9_]{2,}' \
        | sort \
        | uniq -c \
        | awk -v cid="$chunk_id" '{print $2 "\t" cid "\t" $1}' >> "$TERMS_RAW" || true

      chunk_id=$((chunk_id + 1))
    fi

    (( end == total )) && break
    start=$((start + STEP))
  done
done < <(find "$ROOT_PATH" -type f -print0)

# postings.tsv: term, chunk_id, tf
sort -k1,1 -k2,2n "$TERMS_RAW" > "$INDEX_DIR/postings.tsv"

# docfreq.tsv: term, document frequency
awk -F'\t' '{print $1 "\t" $2}' "$INDEX_DIR/postings.tsv" \
  | sort -u \
  | awk -F'\t' '{df[$1]++} END {for (t in df) print t "\t" df[t]}' \
  | sort -k1,1 > "$INDEX_DIR/docfreq.tsv"

cat > "$INDEX_DIR/meta.env" <<EOF
ROOT=$ROOT_PATH
TOTAL_CHUNKS=$chunk_id
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CHUNK_LINES=$CHUNK_LINES
CHUNK_OVERLAP=$CHUNK_OVERLAP
EOF

rm -f "$TERMS_RAW"

echo "Built index in $INDEX_DIR"
echo "Total chunks: $chunk_id"

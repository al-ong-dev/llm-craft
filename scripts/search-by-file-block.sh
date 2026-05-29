#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <code-file> [index-dir] [top-n]" >&2
  exit 1
fi

CODE_FILE="$1"
INDEX_DIR="${2:-./code-index}"
TOP_N="${3:-10}"

[[ -f "$CODE_FILE" ]] || { echo "Code file not found: $CODE_FILE" >&2; exit 1; }

QUERY="$(cat "$CODE_FILE")"
"$(dirname "$0")/smart-search.sh" "$QUERY" "$INDEX_DIR" "$TOP_N" "code-block"

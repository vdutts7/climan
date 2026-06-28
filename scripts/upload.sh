#!/bin/zsh
# Upload mac man page JSON to MAC KV - deploy-policy enforced
# Usage: ./scripts/upload.sh [--dir /path/to/man-pages]
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CUR="${CUR:-$HOME/.cursor}"
MANPAGES_DIR="$REPO_ROOT/data/man-pages"
JQ="$(/usr/bin/which jq 2>/dev/null)" || { echo "🔴 jq not found" >&2; exit 1; }

source "$CUR/tools/climan/wrangler-kv-guard.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) MANPAGES_DIR="$2"; shift 2 ;;
        *) echo "🔴 unknown: $1" >&2; exit 1 ;;
    esac
done

[[ -d "$MANPAGES_DIR" ]] || { echo "🔴 man pages dir not found: $MANPAGES_DIR" >&2; exit 1; }
[[ -f "$MANPAGES_DIR/_manifest.json" ]] || { echo "🔴 _manifest.json not found in $MANPAGES_DIR" >&2; exit 1; }

wrangler_kv_assert_binding MAC "$REPO_ROOT/wrangler.toml" >/dev/null

echo "🌕 building bulk upload payload..."
BULK_FILE="$(/usr/bin/mktemp)"
trap "/bin/rm -f '$BULK_FILE'" EXIT

echo "[" > "$BULK_FILE"
COUNT=0

printf '{"key":"_manifest","value":' >> "$BULK_FILE"
"$JQ" -c '@json' "$MANPAGES_DIR/_manifest.json" >> "$BULK_FILE"
printf '}' >> "$BULK_FILE"
COUNT=$((COUNT + 1))

for f in "$MANPAGES_DIR"/*.json; do
    BASENAME="$(/usr/bin/basename "$f" .json)"
    [[ "$BASENAME" == "_manifest" ]] && continue
    KEY="cmd:${BASENAME}"
    printf ',\n{"key":"%s","value":' "$KEY" >> "$BULK_FILE"
    "$JQ" -c '@json' "$f" >> "$BULK_FILE"
    printf '}' >> "$BULK_FILE"
    COUNT=$((COUNT + 1))
    (( COUNT % 500 == 0 )) && echo "🌕 prepared $COUNT entries..."
done

printf '\n]' >> "$BULK_FILE"
echo "🌕 uploading $COUNT entries..."
wrangler_kv_bulk_put_safe MAC "$BULK_FILE" "$REPO_ROOT/wrangler.toml"

echo "🟢 uploaded $COUNT man page entries to KV"
echo "next: wrangler deploy (only if worker.js changed)"

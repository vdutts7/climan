#!/bin/zsh
# Extract ALL macOS man pages into JSON for CF Worker upload
# Usage: ./scripts/extract.sh [--out /path/to/dir]
set -eo pipefail
cleanup() { [[ -n "${TMPDIR_WORK:-}" ]] && /bin/rm -rf "$TMPDIR_WORK" 2>/dev/null; }
trap cleanup EXIT SIGTERM SIGINT SIGHUP

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUTDIR="$2"; shift 2 ;;
        *) echo "🔴 unknown: $1" >&2; exit 1 ;;
    esac
done
OUTDIR="${OUTDIR:-$REPO_ROOT/data/man-pages}"
/bin/mkdir -p "$OUTDIR"

JQ="$(/usr/bin/which jq 2>/dev/null)" || { echo "🔴 jq not found - brew install jq" >&2; exit 1; }
TMPDIR_WORK="$(/usr/bin/mktemp -d)"

# extract_section: pull named section from rendered man output
extract_section() {
    /usr/bin/awk -v sect="$1" '
        BEGIN { found=0; collecting=0 }
        /^[A-Z][A-Z _-]+$/ {
            if ($0 == sect || $0 ~ "^" sect "$") { collecting=1; next }
            else if (collecting) { exit }
        }
        collecting { print }
    '
}

echo "🌕 scanning man page directories..."
MANDIRS=(/usr/share/man /opt/homebrew/share/man)
PAGES=()
for mdir in "${MANDIRS[@]}"; do
    [[ -d "$mdir" ]] || continue
    for section_dir in "$mdir"/man*; do
        [[ -d "$section_dir" ]] || continue
        for page in "$section_dir"/*; do
            [[ -f "$page" ]] || continue
            PAGES+=("$page")
        done
    done
done

TOTAL=${#PAGES[@]}
[[ $TOTAL -eq 0 ]] && { echo "🔴 no man pages found in any directory" >&2; exit 1; }
echo "🌕 found $TOTAL man page files across ${#MANDIRS[@]} directories"
echo "🌕 extracting..."

EXTRACTED=0
FAILED=0
MANIFEST_ENTRIES=()

for page in "${PAGES[@]}"; do
    BASENAME="$(/usr/bin/basename "$page")"
    BASENAME="${BASENAME%.gz}"
    SECTION="${BASENAME##*.}"
    CMD="${BASENAME%.*}"
    [[ -z "$CMD" ]] && continue

    KEY="${CMD}.${SECTION}"
    OUTFILE="$TMPDIR_WORK/${KEY}.json"
    [[ -f "$OUTFILE" ]] && continue

    RAW="$(MANWIDTH=120 /usr/bin/man "$page" 2>/dev/null | /usr/bin/col -bx 2>/dev/null)" || {
        FAILED=$((FAILED + 1))
        continue
    }
    [[ -z "$RAW" ]] && { FAILED=$((FAILED + 1)); continue; }

    NAME_SEC="$(printf '%s' "$RAW" | extract_section "NAME" | /usr/bin/head -5)"
    SYNOPSIS_SEC="$(printf '%s' "$RAW" | extract_section "SYNOPSIS" | /usr/bin/head -30)"
    DESC_SEC="$(printf '%s' "$RAW" | extract_section "DESCRIPTION" | /usr/bin/head -c 3000)"

    "$JQ" -n \
        --arg cmd "$CMD" \
        --arg section "$SECTION" \
        --arg name "$NAME_SEC" \
        --arg synopsis "$SYNOPSIS_SEC" \
        --arg desc "$DESC_SEC" \
        --arg manpath "$page" \
        '{
            cmd: $cmd,
            section: $section,
            name: ($name | gsub("^\\s+|\\s+$"; "")),
            synopsis: ($synopsis | gsub("^\\s+|\\s+$"; "")),
            description: (if $desc == "" then null else ($desc | gsub("^\\s+|\\s+$"; "")) end),
            manpath: $manpath
        }' > "$OUTFILE"

    MANIFEST_ENTRIES+=("$KEY")
    EXTRACTED=$((EXTRACTED + 1))

    if (( EXTRACTED % 100 == 0 )); then
        echo "🌕 $EXTRACTED/$TOTAL extracted..."
    fi
done

echo "🌕 building manifest..."

MANIFEST_FILE="$TMPDIR_WORK/_manifest.json"
"$JQ" -n \
    --arg extracted_at "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg os "$(sw_vers -productName 2>/dev/null || echo macOS) $(sw_vers -productVersion 2>/dev/null || echo unknown)" \
    --arg arch "$(uname -m)" \
    --argjson count "$EXTRACTED" \
    '{
        _about: "macOS man pages - full corpus for CF Worker serving",
        extracted_at: $extracted_at,
        os: $os,
        arch: $arch,
        count: $count,
        commands: []
    }' > "$MANIFEST_FILE"

for key in "${MANIFEST_ENTRIES[@]}"; do
    "$JQ" -n --arg cmd "${key%.*}" --arg section "${key##*.}" \
        --arg name "$(${JQ} -r '.name // ""' "$TMPDIR_WORK/${key}.json" 2>/dev/null)" \
        '{cmd: $cmd, section: $section, name: $name}'
done | "$JQ" -s '.' | "$JQ" --slurpfile manifest "$MANIFEST_FILE" \
    '$manifest[0] | .commands = input' > "$TMPDIR_WORK/_manifest_final.json"
/bin/mv "$TMPDIR_WORK/_manifest_final.json" "$MANIFEST_FILE"

/bin/cp "$TMPDIR_WORK"/*.json "$OUTDIR/"

SIZE=$(/usr/bin/du -sh "$OUTDIR" | /usr/bin/awk '{print $1}')
echo "🟢 extracted $EXTRACTED man pages ($FAILED failed) -> $OUTDIR ($SIZE)"
echo "🟢 manifest: $OUTDIR/_manifest.json"
echo ""
echo "next: ./scripts/upload.sh"

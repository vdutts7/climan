#!/bin/zsh
# Upload pwsh-namespace entities to PWSH KV - delta-aware, deploy-policy enforced
# Usage: ./scripts/kv-sync-pwsh.sh [--full] [--dry-run] [--since <git-ref>]
set -eo pipefail

A="${A:-$HOME/Documents/a}"
PWSH_REPO="$A/climan-namespaces/pwsh-namespace"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CUR="${CUR:-$HOME/.cursor}"
CURTOOLS="${CURTOOLS:-$CUR/tools}"
OUT="/tmp/pwsh-kv.json"
META="/tmp/pwsh-kv.meta.json"
MODE="delta"
DRY=0
SINCE=""

source "$CURTOOLS/climan/wrangler-kv-guard.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --full) MODE="full"; shift ;;
        --dry-run) DRY=1; shift ;;
        --since) SINCE="$2"; shift 2 ;;
        *) echo "🔴 unknown: $1" >&2; exit 1 ;;
    esac
done

[[ -d "$PWSH_REPO" ]] || { echo "🔴 pwsh-namespace not found: $PWSH_REPO" >&2; exit 1; }

typeset -a build_args=(--mode "$MODE" --out "$OUT" --meta "$META")
(( DRY )) && build_args+=(--dry-run)
[[ -n "$SINCE" ]] && build_args+=(--since "$SINCE")

echo "🌕 building KV bulk (mode=$MODE) from $PWSH_REPO..."
CURTOOLS="$CURTOOLS" python3 "$PWSH_REPO/lib/kv_bulk.py" "${build_args[@]}" || exit $?

KEY_COUNT="$(python3 -c "import json; print(json.load(open('$META')).get('key_count',0))")"
SYNC_MODE="$(python3 -c "import json; print(json.load(open('$META')).get('mode',''))")"

if [[ "$SYNC_MODE" == "skip" || "$KEY_COUNT" -eq 0 ]]; then
    echo "🟢 pwsh KV sync: nothing to upload"
    exit 0
fi

(( DRY )) && { echo "🟢 dry-run complete ($KEY_COUNT keys would upload)"; exit 0; }

[[ -f "$REPO_ROOT/wrangler.toml" ]] || { echo "🔴 missing $REPO_ROOT/wrangler.toml" >&2; exit 1; }

(
  cd "$REPO_ROOT"
  wrangler_kv_assert_binding PWSH wrangler.toml >/dev/null
  wrangler_kv_bulk_put_chunked PWSH "$OUT" wrangler.toml
)

python3 - <<PY
import json, sys
from pathlib import Path
sys.path.insert(0, "$CURTOOLS/climan")
from kv_delta import save_state, git_head
repo = Path("$PWSH_REPO")
meta = json.load(open("$META"))
save_state(
    repo,
    binding="PWSH",
    commit=git_head(repo),
    key_count=meta["key_count"],
    mode=meta["mode"],
    paths=[],
)
print("🟢 recorded sync state @", git_head(repo))
PY

echo "🟢 pwsh KV sync complete ($KEY_COUNT keys, mode=$MODE)"
echo "next: wrangler deploy if worker.js routing changed"

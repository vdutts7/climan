#!/usr/bin/env bash
# Regenerate architecture SVGs from consumer spec + visual-tokens vt-gcard renderer.
#   architecture-glass.svg        animated (landing <object>)
#   architecture-glass-static.svg idle-only (README <img>, GitHub sanitizers)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="$ROOT/docs/architecture-glass.spec.json"
VT="${SKILLS:-$HOME/claude-ai/skills}/visual-tokens"
RENDER=(python3 "$VT/scripts/render_glass_card.py" --compose)

"${RENDER[@]}" "$SPEC" --out "$ROOT/docs/architecture-glass.svg"

STATIC="$(mktemp "${TMPDIR:-/tmp}/architecture-glass-static.XXXXXX.json")"
trap 'rm -f "$STATIC"' EXIT
python3 - "$SPEC" "$STATIC" <<'PY'
import json, sys
spec = json.loads(open(sys.argv[1]).read())
flow = dict(spec.get("flow") or {})
flow["enabled"] = False
spec["flow"] = flow
json.dump(spec, open(sys.argv[2], "w"), indent=2)
PY

"${RENDER[@]}" "$STATIC" --out "$ROOT/docs/architecture-glass-static.svg"
echo "wrote $ROOT/docs/architecture-glass.svg"
echo "wrote $ROOT/docs/architecture-glass-static.svg"

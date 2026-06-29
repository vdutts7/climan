#!/usr/bin/env bash
# Regenerate docs/architecture-glass.svg from consumer spec + visual-tokens vt-gcard renderer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VT="${SKILLS:-$HOME/claude-ai/skills}/visual-tokens"
python3 "$VT/scripts/render_glass_card.py" \
  --compose "$ROOT/docs/architecture-glass.spec.json" \
  --out "$ROOT/docs/architecture-glass.svg"
echo "wrote $ROOT/docs/architecture-glass.svg"

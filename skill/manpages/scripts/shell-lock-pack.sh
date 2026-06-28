#!/usr/bin/env zsh
# manpages skill - shell-lock pack gate
set -euo pipefail

SKILL_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SKILL_NAME="manpages"

echo "🌕 shell-lock-pack: $SKILL_NAME"

# run gates in order
bash "$SKILL_ROOT/scripts/validate-skill-bundle.sh" "$SKILL_ROOT" || exit 1
bash "$SKILL_ROOT/scripts/shelljson-gate.sh" "$SKILL_ROOT" || exit 1
bash "$SKILL_ROOT/tests/smoke.sh" || exit 1

echo ""
echo "🟢 MSK-SHELL-LOCK-OK: $SKILL_NAME ready to pack"
echo "   pack: tar -czf $SKILL_NAME.skill $SKILL_NAME/"

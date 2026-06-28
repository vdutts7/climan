#!/usr/bin/env zsh
# Pack skill/manpages/ -> ~/Downloads/manpages.skill for Claude.ai upload
# Usage: ./scripts/pack-skill.sh [output-path]
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$HOME/Downloads/manpages.skill}"
SKILL_SRC="$REPO_ROOT/skill/manpages"

[[ -f "$SKILL_SRC/SKILL.md" ]] || { echo "🔴 missing $SKILL_SRC/SKILL.md" >&2; exit 1; }

/bin/mkdir -p "$(/usr/bin/dirname "$OUT")"

(
  cd "$REPO_ROOT/skill"
  /usr/bin/zip -r "$OUT" manpages -x "*.DS_Store" -x "*__pycache__*"
)

echo "🟢 wrote $OUT"
echo ""
echo "Claude.ai: Project → Skills → Upload skill → select manpages.skill"
echo "Invoke: /manpages"

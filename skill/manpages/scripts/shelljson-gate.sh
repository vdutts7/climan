#!/usr/bin/env zsh
# manpages skill - shelljson compliance gate
set -euo pipefail

SKILL_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PASS=0; FAIL=0

_check() {
  local label="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "🟢 $label"
    (( PASS++ ))
  else
    echo "🔴 $label"
    (( FAIL++ ))
  fi
}

echo "🌕 shelljson-gate: manpages skill"

# SHELL-001: shebang on executables
for f in "$SKILL_ROOT"/scripts/*.sh "$SKILL_ROOT"/tests/*.sh; do
  [[ -f "$f" ]] || continue
  _check "SHELL-001 shebang: $(basename $f)" "head -1 '$f' | grep -q '#!/usr/bin/env zsh'"
done

# SHELL-004: no bare ~ in scripts
for f in "$SKILL_ROOT"/scripts/*.sh "$SKILL_ROOT"/tests/*.sh; do
  [[ -f "$f" ]] || continue
  _check "SHELL-004 no-tilde: $(basename $f)" "! grep -q '[^$]~/' '$f'"
done

echo ""
echo "shelljson-gate: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "🟢 MSK-SHELLJSON-OK" || { echo "🔴 MSK-SHELLJSON-FAIL"; exit 1; }

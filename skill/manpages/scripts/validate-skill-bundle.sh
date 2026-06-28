#!/usr/bin/env zsh
# manpages skill - bundle structure validator
set -euo pipefail

SKILL_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PASS=0; FAIL=0

_req() {
  local path="$SKILL_ROOT/$1"
  if [[ -e "$path" ]]; then
    echo "🟢 exists: $1"
    (( PASS++ ))
  else
    echo "🔴 missing: $1"
    (( FAIL++ ))
  fi
}

_forbidden() {
  local path="$SKILL_ROOT/$1"
  if [[ ! -e "$path" ]]; then
    echo "🟢 absent (correct): $1"
    (( PASS++ ))
  else
    echo "🔴 forbidden present: $1"
    (( FAIL++ ))
  fi
}

echo "🌕 validate-skill-bundle: manpages"

# required paths
_req "SKILL.md"
_req "registry/"
_req "scripts/"
_req "tests/"
_req "tests/smoke.sh"
_req "registry/manifest.json"
_req "registry/lookup-cascade.json"
_req "registry/command-policy.json"
_req "registry/fetch-cascade.json"
_req "scripts/fetch.sh"
_req "scripts/lookup.sh"
_req "registry/shelljson-compliance.yaml"
_req "scripts/shelljson-gate.sh"
_req "scripts/validate-skill-bundle.sh"
_req "scripts/shell-lock-pack.sh"

# forbidden
_forbidden "README.md"
_forbidden "readme.md"
_forbidden "references/"
_forbidden "refs/"
_forbidden "docs/"

echo ""
echo "validate-skill-bundle: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "🟢 MSK-VALIDATE-OK" || { echo "🔴 MSK-VALIDATE-FAIL"; exit 1; }

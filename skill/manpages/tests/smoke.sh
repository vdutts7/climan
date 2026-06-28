#!/usr/bin/env bash
# manpages skill - smoke test
# verifies live worker endpoint; safe commands only (TW-003)
set -uo pipefail

BASE="${1:-https://climan.dev}"
PASS=0; FAIL=0

_hit() {
  local label="$1" url="$2" jq_filter="$3"
  local out
  out=$(curl -sf "$url" 2>/dev/null) || {
    # check proxy block
    local raw
    raw=$(curl -s "$url" 2>/dev/null)
    if echo "$raw" | grep -q "Host not in allowlist" 2>/dev/null; then
      echo "🔴 $label: L3_PROXY_BLOCK (TW-004)"
    else
      echo "🔴 $label: no response"
    fi
    FAIL=$((FAIL+1)); return
  }
  if echo "$out" | jq -e "$jq_filter" >/dev/null 2>&1; then
    echo "🟢 $label"
    PASS=$((PASS+1))
  else
    echo "🔴 $label: unexpected response"
    echo "   got: $(echo "$out" | head -c 120)"
    FAIL=$((FAIL+1))
  fi
}

echo "🌕 smoke: manpages worker @ $BASE"

# root
_hit "GET /" "$BASE/" '.service != null'

# /mac namespace lookups (safe commands - TW-003)
_hit "GET /mac/ls"             "$BASE/mac/ls"             '.name != null'
_hit "GET /mac/networksetup"   "$BASE/mac/networksetup"   '.name != null'
_hit "GET /mac/defaults"       "$BASE/mac/defaults"       '.name != null'
_hit "GET /mac/sw_vers"        "$BASE/mac/sw_vers"        '.name != null'

# legacy /man/ backward compat
_hit "GET /man/ls (legacy)"    "$BASE/man/ls"             '.name != null'

# manifest
_hit "GET /mac manifest"       "$BASE/mac"                '.count > 1000'

# search
_hit "GET /search?q=network"   "$BASE/search?q=network"   '.count > 0'

# robots.txt (WARCH-350)
robots=$(curl -sf "$BASE/robots.txt" 2>/dev/null || true)
if echo "$robots" | grep -q "Allow: /"; then
  echo "🟢 robots.txt: Allow: / present"
  PASS=$((PASS+1))
else
  echo "🔴 robots.txt: missing Allow: /"
  FAIL=$((FAIL+1))
fi

echo ""
echo "smoke: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "🟢 smoke OK" || { echo "🔴 smoke FAIL"; exit 1; }

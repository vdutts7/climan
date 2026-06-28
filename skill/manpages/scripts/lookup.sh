#!/usr/bin/env bash
# lookup.sh - single entry point for /manpages skill
# Usage: lookup.sh <cmd>
# Exit 0=JSON stdout | 1=not found | 2=proxy block | 3=blocked command (TW-003)
set -uo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FETCH="$SKILL_ROOT/scripts/fetch.sh"
POLICY="$SKILL_ROOT/registry/command-policy.json"
BASE="https://climan.dev"
CMD="${1:?usage: lookup.sh <cmd>}"
CMD_LC="$(printf '%s' "$CMD" | tr '[:upper:]' '[:lower:]')"

# TW-003 policy gate
blocked=$(python3 -c "
import json,sys
cmd=sys.argv[1].lower()
p=json.load(open(sys.argv[2]))
if cmd in p.get('never_commands',[]):
    sys.exit(0)
for s in p.get('never_substrings',[]):
    if s in cmd:
        sys.exit(0)
sys.exit(1)
" "$CMD_LC" "$POLICY" 2>/dev/null && echo yes || echo no)

if [[ "$blocked" == yes ]]; then
  echo '{"error":"TW-003","detail":"command blocked as demo/test case","cmd":"'"$CMD"'"}' >&2
  exit 3
fi

run_fetch() {
  local c="$1"
  bash "$FETCH" "$c"
}

try_search_refetch() {
  local term="$1"
  local tmp best
  tmp="$(mktemp "${TMPDIR:-/tmp}/manpages-search.XXXXXX")"
  curl -sf --max-time 15 "${BASE}/search?q=${term}" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  best=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
r=d.get('results') or []
if not r: sys.exit(1)
print(r[0].get('cmd') or r[0].get('name','').split()[0])
" "$tmp" 2>/dev/null) || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  [[ -n "$best" ]] || return 1
  run_fetch "$best"
}

if run_fetch "$CMD"; then
  exit 0
fi
rc=$?

if [[ $rc -eq 2 ]]; then
  echo '{"error":"L3_PROXY_BLOCK","detail":"egress proxy blocked climan.dev","fallback":"curl -s '"${BASE}/mac/${CMD}"' | jq .","ref":"TW-004"}' >&2
  exit 2
fi

if try_search_refetch "$CMD"; then
  exit 0
fi

echo '{"error":"not_found","cmd":"'"$CMD"'","detail":"no man page and search had no hits"}' >&2
exit 1

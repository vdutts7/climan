#!/usr/bin/env bash
# fetch.sh - HTTP cascade with proxy block detection
# Usage: fetch.sh <cmd> [section]
# Exit codes: 0=success (valid JSON on stdout), 1=down/not found, 2=L3 proxy block
set -uo pipefail

SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$SKILL_ROOT/registry/fetch-cascade.json"
CMD="${1:?usage: fetch.sh <cmd> [section]}"
SECTION="${2:-}"
PRIMARY="https://climan.dev"
FALLBACK="https://manpages.manpages.workers.dev"
PROXY_BLOCK_SIG="Host not in allowlist"

[[ -n "$SECTION" ]] && SUFFIX="/mac/${CMD}.${SECTION}" || SUFFIX="/mac/${CMD}"

_curl()           { curl --max-time 15 --connect-timeout 5 --retry 3 --retry-delay 1 --retry-all-errors --compressed --location -sf -A 'Mozilla/5.0' -H 'Accept: application/json' -H 'Accept-Encoding: gzip, deflate, br' -o "$1" "$2"; }
_wget()           { wget -qO "$1" --timeout=15 --tries=3 --user-agent='Mozilla/5.0' --header='Accept: application/json' "$2"; }
_python3_urllib() { python3 -c "
import urllib.request,ssl,gzip as gz
ctx=ssl.create_default_context()
req=urllib.request.Request('$2',headers={'User-Agent':'Mozilla/5.0','Accept':'application/json','Accept-Encoding':'gzip, deflate'})
with urllib.request.urlopen(req,timeout=15,context=ctx) as r:
    raw=r.read()
    if r.info().get('Content-Encoding')=='gzip': raw=gz.decompress(raw)
    open('$1','wb').write(raw)
"; }
_python3_requests() { python3 -c "
import requests
s=requests.Session()
s.headers.update({'User-Agent':'Mozilla/5.0','Accept':'application/json','Accept-Encoding':'gzip, deflate, br'})
r=s.get('$2',timeout=(5,15),allow_redirects=True)
r.raise_for_status()
open('$1','w',encoding='utf-8').write(r.text)
"; }
_node_https() { node -e "
const https=require('https'),zlib=require('zlib'),fs=require('fs'),url=new URL('$2');
https.request({hostname:url.hostname,path:url.pathname+url.search,method:'GET',timeout:15000,
  headers:{'User-Agent':'Mozilla/5.0','Accept':'application/json','Accept-Encoding':'gzip, deflate'}},
res=>{const chunks=[];
  const s=res.headers['content-encoding']==='gzip'?res.pipe(zlib.createGunzip()):res;
  s.on('data',c=>chunks.push(c));
  s.on('end',()=>fs.writeFileSync('$1',Buffer.concat(chunks)));
}).on('error',()=>process.exit(1)).end();
"; }

validate_json_file() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  if grep -q "$PROXY_BLOCK_SIG" "$file" 2>/dev/null; then
    return 2
  fi
  python3 -c "
import json,sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
except json.JSONDecodeError:
    sys.exit(1)
if isinstance(d,dict) and d.get('error'):
    sys.exit(1)
" "$file"
}

try_url() {
  local url="$1"
  local tmp rc client fn
  tmp="$(mktemp "${TMPDIR:-/tmp}/manpages-fetch.XXXXXX")"

  local ORDER
  ORDER=$(python3 -c "import json; print('\n'.join(json.load(open('$REGISTRY'))['order']))")

  while IFS= read -r client; do
    fn="_${client}"
    rm -f "$tmp"
    $fn "$tmp" "$url" 2>/dev/null || continue
    [[ -s "$tmp" ]] || continue
    validate_json_file "$tmp"
    rc=$?
    if [[ $rc -eq 2 ]]; then
      rm -f "$tmp"
      echo "L3_PROXY_BLOCK: $url" >&2
      return 2
    fi
    if [[ $rc -eq 0 ]]; then
      cat "$tmp"
      rm -f "$tmp"
      return 0
    fi
  done <<< "$ORDER"

  rm -f "$tmp"
  return 1
}

if try_url "${PRIMARY}${SUFFIX}"; then
  exit 0
fi
rc=$?

if [[ $rc -eq 2 ]]; then
  [[ -n "$SECTION" ]] && FB_SUFFIX="/man/${CMD}.${SECTION}" || FB_SUFFIX="/man/${CMD}"
  if try_url "${FALLBACK}${FB_SUFFIX}"; then
    exit 0
  fi
  rc=$?
  if [[ $rc -eq 2 ]]; then
    echo '{"error":"L3_PROXY_BLOCK","detail":"both climan.dev and workers.dev blocked by egress proxy","ref":"TW-004"}' >&2
    exit 2
  fi
fi

echo '{"error":"all clients failed"}' >&2
exit 1

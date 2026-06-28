#!/bin/zsh
# Validates deployed climan.dev worker endpoints
# Usage: ./test.sh [worker-url]
#   default: https://climan.dev
set -eo pipefail

URL="${1:-https://climan.dev}"
URL="${URL%/}"
PASS=0
FAIL=0
JQ="$(/usr/bin/which jq 2>/dev/null)" || { echo "🔴 jq not found" >&2; exit 1; }

t() {
    local name="$1" endpoint="$2" expect="$3"
    RESP="$(curl -sf "${URL}${endpoint}" 2>/dev/null)" || { echo "🔴 $name - curl failed: ${URL}${endpoint}"; FAIL=$((FAIL+1)); return; }
    if echo "$RESP" | "$JQ" -e "$expect" >/dev/null 2>&1; then
        echo "🟢 $name"
        PASS=$((PASS+1))
    else
        echo "🔴 $name - expected: $expect"
        echo "   got: $(echo "$RESP" | /usr/bin/head -c 200)"
        FAIL=$((FAIL+1))
    fi
}

echo "testing $URL ..."
echo ""

# root
t "root returns service name"    "/"              '.service != null'
t "root shows namespaces"        "/"              '.namespaces.mac != null'
t "root shows pwsh namespace"    "/"              '.namespaces.pwsh != null'
t "root shows ansi namespace"    "/"              '.namespaces.ansi != null'

# /ansi
t "ansi manifest returns entities"  "/ansi"       '.count > 0'
t "ansi csi/J mnemonic ED"          "/ansi/csi/J" '.mnemonic == "ED"'

# /mac
t "mac manifest returns commands"   "/mac"               '.count > 0'
t "mac manifest has >1000"          "/mac"               '.count > 1000'
t "mac ls lookup"                   "/mac/ls"            '.cmd == "ls"'
t "mac ls.1 explicit section"       "/mac/ls.1"          '.section == "1"'
t "mac networksetup lookup"         "/mac/networksetup"  '.cmd == "networksetup"'

# /pwsh exact lookup
t "pwsh manifest returns cmdlets"   "/pwsh"                   '.cmdlets != null'
t "pwsh Get-ChildItem exact"        "/pwsh/Get-ChildItem"     '.cmd == "Get-ChildItem" or .cmdlet == "Get-ChildItem"'
t "pwsh case-insensitive"           "/pwsh/get-childitem"     '. != null and .error == null'
t "pwsh alias gci"                  "/pwsh/gci"               '. != null'
t "pwsh /ps alias route"            "/ps/Get-ChildItem"       '. != null and .error == null'

# /search hybrid (pwsh)
t "pwsh search find files"          "/search?q=find+files+recursively&ns=pwsh"  '.count > 0'
t "pwsh search top result correct"  "/search?q=find+files+recursively&ns=pwsh"  '.results[0].key == "Get-ChildItem"'
t "pwsh search returns scores"      "/search?q=get+process&ns=pwsh"             '.results[0].score != null'
t "pwsh search missing q param"     "/search?ns=pwsh"                           '.error != null'

# /search keyword (mac)
t "mac search wifi"                 "/search?q=wifi"           '.count > 0'
t "mac search returns results"      "/search?q=network"        '.results | length > 0'

# LEGACY
t "legacy /man/ls still works"      "/man/ls"                  '.cmd == "ls"'

# robots.txt
ROBOTS="$(curl -sf "${URL}/robots.txt" 2>/dev/null)" || true
if echo "$ROBOTS" | grep -q "Allow: /"; then
    echo "🟢 robots.txt: Allow: / present"
    PASS=$((PASS+1))
else
    echo "🔴 robots.txt: missing Allow: /"
    FAIL=$((FAIL+1))
fi

# 404 shape
HTTP_CODE="$(curl -so /dev/null -w '%{http_code}' "${URL}/mac/zzzznotreal" 2>/dev/null)" || true
if [[ "$HTTP_CODE" == "404" ]]; then
    echo "🟢 404 on nonexistent command"
    PASS=$((PASS+1))
else
    echo "🔴 expected 404, got $HTTP_CODE"
    FAIL=$((FAIL+1))
fi

echo ""
echo "results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "🟢 all tests passed" || echo "🔴 $FAIL tests failed"
exit $FAIL
#!/bin/zsh
# climan shell functions — add to .zshrc or .zshrc-aliases.sh
# API: https://climan.dev
# Docs: https://github.com/vdutts7/climan

CLIMAN_BASE="${CLIMAN_BASE:-https://climan.dev}"

# cm <ns> <key> — exact lookup
# examples:
#   cm mac networksetup
#   cm pwsh Get-ChildItem
#   cm ansi csi/J
cm() {
  local ns="${1:?usage: cm <ns> <key>}"
  local key="${2:?usage: cm <ns> <key>}"
  curl -s "${CLIMAN_BASE}/${ns}/${key}" | jq .
}

# cms [ns] <query...> — hybrid search (default ns: pwsh)
# examples:
#   cms find files recursively
#   cms pwsh stop a process
#   cms mac wifi
cms() {
  local ns="pwsh"
  # if first arg is a known namespace, use it
  if [[ "$1" == "mac" || "$1" == "pwsh" || "$1" == "ansi" ]]; then
    ns="$1"
    shift
  fi
  local q="${*:?usage: cms [ns] <query>}"
  curl -s "${CLIMAN_BASE}/search?q=${q// /+}&ns=${ns}" \
    | jq -r '.results[] | "\(.score)\t\(.key)\t\(.synopsis // "" | .[0:80])"' \
    | column -t -s $'\t'
}

# cmns — list available namespaces
cmns() {
  curl -s "${CLIMAN_BASE}/" | jq '.namespaces'
}

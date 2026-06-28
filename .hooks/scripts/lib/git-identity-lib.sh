#!/usr/bin/env bash
# Shared identity-routing lookup (host, ssh alias, username -> name/email).
set -euo pipefail

git_identity_routes_file() {
  if [[ -n "${GIT_IDENTITY_ROUTES_FILE:-}" && -f "${GIT_IDENTITY_ROUTES_FILE}" ]]; then
    printf '%s' "${GIT_IDENTITY_ROUTES_FILE}"
    return
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" && -f "$top/.hooks/scripts/identity-routing.json" ]]; then
    printf '%s' "$top/.hooks/scripts/identity-routing.json"
    return
  fi
}

git_identity_parse_remote_url() {
  local url="$1"
  host="" username=""
  if [[ "$url" =~ ^git@([^:]+):([^/]+)/[^/]+(\.git)?$ ]]; then
    host="${BASH_REMATCH[1]}"
    username="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^ssh://git@([^/]+)/([^/]+)/[^/]+(\.git)?$ ]]; then
    host="${BASH_REMATCH[1]}"
    username="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^https?://([^/]+)/([^/]+)/[^/]+(\.git)?$ ]]; then
    host="${BASH_REMATCH[1]}"
    username="${BASH_REMATCH[2]}"
  else
    return 1
  fi
  return 0
}

git_identity_lookup_route() {
  local host="$1" username="$2"
  local routes_file
  routes_file="$(git_identity_routes_file)"
  if [[ ! -f "$routes_file" ]] || ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  jq -r --arg host "$host" --arg user "$username" '
    (.routes[] | select(.username == $user and (.host == $host or .ssh_host_alias == $host))
      | "\(.name)\t\(.email)\t\(.namespace)") // empty
  ' "$routes_file" | head -n1
}

git_identity_route_for_remote() {
  local target="$1" remote="$2"
  local url line host username
  url="$(git -C "$target" config --get "remote.${remote}.url" 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  git_identity_parse_remote_url "$url" || return 1
  line="$(git_identity_lookup_route "$host" "$username")"
  [[ -n "$line" ]] || return 1
  printf '%s' "$line"
}

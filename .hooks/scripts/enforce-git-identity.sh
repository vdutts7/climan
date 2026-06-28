#!/usr/bin/env bash
# Machine-wide: sync + verify repo-local identity against identity-routing for all routed remotes.
set -euo pipefail

TARGET="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
MODE="${2:-}"

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

ROOT_TOP="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"
HOOK_LIB="${ROOT_TOP}/.hooks/scripts/lib/git-identity-lib.sh"
[[ -f "$HOOK_LIB" ]] && LIB="$HOOK_LIB"
SETUP="${ROOT_TOP}/.hooks/scripts/setup-git-identity.sh"
[[ -f "$LIB" ]] && source "$LIB"

remotes=()
while IFS= read -r r; do
  [[ -n "$r" ]] && remotes+=("$r")
done < <(git -C "$TARGET" remote 2>/dev/null || true)

if [[ ${#remotes[@]} -eq 0 ]]; then
  exit 0
fi

expect_line=""
canonical=""
for remote in "${remotes[@]}"; do
  line="$(git_identity_route_for_remote "$TARGET" "$remote" 2>/dev/null || true)"
  [[ -n "$line" ]] || continue
  if [[ -z "$expect_line" ]]; then
    expect_line="$line"
    canonical="$remote"
  elif [[ "$line" != "$expect_line" ]]; then
    echo "[enforce-git-identity] BLOCKED: multiple conflicting identity routes on remotes" >&2
    for r in "${remotes[@]}"; do
      l="$(git_identity_route_for_remote "$TARGET" "$r" 2>/dev/null || true)"
      [[ -n "$l" ]] && echo "  $r -> $l" >&2
    done
    exit 1
  fi
  [[ "$remote" == "origin" ]] && canonical="origin"
done

[[ -n "$expect_line" ]] || exit 0

[[ -n "$canonical" ]] || canonical="${remotes[0]}"
if [[ -x "$SETUP" ]]; then
  "$SETUP" "$TARGET" "$canonical" >/dev/null
fi

IFS=$'\t' read -r want_name want_email want_ns <<< "$expect_line"
actual_name="$(git -C "$TARGET" config --local user.name 2>/dev/null || true)"
actual_email="$(git -C "$TARGET" config --local user.email 2>/dev/null || true)"

if [[ "$actual_name" != "$want_name" || "$actual_email" != "$want_email" ]]; then
  echo "[enforce-git-identity] BLOCKED: identity mismatch (route ${want_ns:-unknown})" >&2
  echo "  want:   $want_name <$want_email>" >&2
  echo "  actual: ${actual_name:-<unset>} <${actual_email:-unset}>" >&2
  echo "  fix:    $SETUP \"$TARGET\" $canonical" >&2
  exit 1
fi

url="$(git -C "$TARGET" config --get "remote.${canonical}.url" 2>/dev/null || true)"
if git_identity_parse_remote_url "$url" 2>/dev/null; then
  if [[ "$username" == "fakukucur" && "$actual_email" == *"fakuku@"* ]]; then
    echo "[enforce-git-identity] BLOCKED: fakuku email on fakukucur remote" >&2
    exit 1
  fi
fi

[[ "$MODE" == "--quiet" ]] || echo "[enforce-git-identity] OK $want_name <$want_email> via $canonical"
exit 0

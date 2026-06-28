#!/bin/zsh
# deploy.sh - full climan pipeline
# usage: ./scripts/deploy.sh [--skip-seed] [--skip-enrich]
#
# requires .env at repo root with CF_ACCOUNT, CF_TOKEN, PGPASSWORD set
# or export those vars manually before running

set -eo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# load .env if present
[[ -f "$REPO_ROOT/.env" ]] && export $(grep -v '^#' "$REPO_ROOT/.env" | xargs)

SKIP_ENRICH=false
SKIP_SEED=false
for arg in "$@"; do
  [[ "$arg" == "--skip-enrich" ]] && SKIP_ENRICH=true
  [[ "$arg" == "--skip-seed" ]]   && SKIP_SEED=true
done

echo "🌕 climan deploy pipeline"
echo ""

# ── step 1: enrich pwsh records from vendor markdown ─────────────────────────
if [[ "$SKIP_ENRICH" == "false" ]]; then
  echo "=== 1/3: enrich pwsh records ==="
  python3 "$REPO_ROOT/scripts/enrich_pwsh_records.py"
  echo ""
else
  echo "=== 1/3: enrich -- skipped ==="
fi

# ── step 2: seed Postgres ─────────────────────────────────────────────────────
if [[ "$SKIP_SEED" == "false" ]]; then
  echo "=== 2/3: seed Postgres ==="
  : "${CF_ACCOUNT:?CF_ACCOUNT not set}"
  : "${CF_TOKEN:?CF_TOKEN not set}"
  : "${PGPASSWORD:?PGPASSWORD not set}"
  python3 "$REPO_ROOT/scripts/seed_pwsh.py"
  echo ""
else
  echo "=== 2/3: seed -- skipped ==="
fi

# ── step 3: deploy worker ─────────────────────────────────────────────────────
echo "=== 3/3: deploy worker ==="
cd "$REPO_ROOT"
npx wrangler deploy
echo ""

echo "🟢 deploy complete"
echo ""
echo "smoke test:"
echo "  curl -s https://climan.dev/pwsh/Get-ChildItem | jq .cmdlet"
echo "  curl -s 'https://climan.dev/search?q=find+files+recursively&ns=pwsh' | jq '.results[0].key'"
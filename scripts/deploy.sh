#!/bin/zsh
# One-shot: extract all man pages -> upload to KV -> deploy worker
# Usage: ./scripts/deploy.sh
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "============================================"
echo "  climan.dev worker - full deploy pipeline"
echo "============================================"
echo ""

echo "=== STEP 1/3: EXTRACT ==="
"$REPO_ROOT/scripts/extract.sh"
echo ""

echo "=== STEP 2/3: UPLOAD TO KV ==="
"$REPO_ROOT/scripts/upload.sh"
echo ""

echo "=== STEP 3/3: DEPLOY WORKER ==="
cd "$REPO_ROOT"
wrangler deploy 2>&1
echo ""

echo "🟢 full pipeline complete"
echo ""
echo "test:"
echo "  curl https://climan.dev/mac/networksetup"
echo "  curl https://climan.dev/search?q=wifi"
echo "  $REPO_ROOT/test.sh"

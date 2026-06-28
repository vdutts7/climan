<div align="center">
<h1>climan</h1>
<p><strong>CLI documentation hub for AI agents</strong></p>
<p>
  <code>/pwsh</code> &nbsp;·&nbsp;
  <code>/mac</code> &nbsp;·&nbsp;
  <code>/ansi</code> &nbsp;·&nbsp;
  <code>/aws</code>
</p>
<p>
  <strong>302</strong> PowerShell 7.4 cmdlets &nbsp;·&nbsp;
  hybrid semantic + keyword search &nbsp;·&nbsp;
  no API key &nbsp;·&nbsp;
  just curl
</p>
</div>

---

## What

A public HTTP API serving CLI documentation as JSON. Designed for AI agents that need authoritative, searchable CLI docs without hallucinating flags.

```bash
# exact lookup
curl https://climan.dev/pwsh/Get-ChildItem
curl https://climan.dev/pwsh/gci              # alias resolution
curl https://climan.dev/pwsh/get-childitem    # case-insensitive

# hybrid semantic + keyword search
curl "https://climan.dev/search?q=find+files+recursively&ns=pwsh"
curl "https://climan.dev/search?q=kill+process+by+name&ns=pwsh"
curl "https://climan.dev/search?q=download+file+from+url&ns=pwsh"
```

## Status

| Namespace | Records | Search | Status |
|-----------|---------|--------|--------|
| `/pwsh` | 302 | hybrid vector+BM25 | live |
| `/mac` | 15,299 | coming soon | pending seed |
| `/ansi` | 651 | coming soon | pending seed |
| `/aws` | 17,856 | coming soon | pending seed |

## Architecture

<p align="center">
  <img src="docs/architecture-glass.svg" alt="climan architecture: curl to CF Worker, Hyperdrive Postgres, Workers AI search embed" width="720">
</p>

**Stack:** Cloudflare Workers + Hyperdrive · Azure Postgres 16 + pgvector · Workers AI

**No KV.** All lookups and search go through Postgres via Hyperdrive.

## API

### Lookup
```
GET /pwsh/{cmdlet}    case-insensitive, alias-aware
GET /ps/{cmdlet}      alias for /pwsh
GET /mac/{cmd}
GET /ansi/{alias}
GET /{ns}             namespace manifest
GET /                 service manifest
```

### Search
```
GET /search?q={query}&ns={pwsh|mac|ansi|all}
GET /search?q={query}&ns=pwsh&cat=file-system
```

Search uses: `BM25(0.3) + GREATEST(vec_func, vec_flags)(0.7)` where `vec_func` embeds what the command does and `vec_flags` embeds its parameters as prose.

## Setup

### Prerequisites
- Node.js 18+
- Python 3.9+
- `wrangler` (Cloudflare CLI)
- `psql` client
- Azure Postgres instance with pgvector extension

### 1. Clone and install

```bash
git clone https://github.com/vdutts7/climan
cd climan
npm install
pip install psycopg2-binary requests pyyaml
```

### 2. Configure

```bash
cp .env.example .env
# fill in CF_ACCOUNT, CF_TOKEN, PGPASSWORD, PGHOST, PGUSER
```

### 3. Create schema

```bash
psql "$PGCONN" -f db/schema.sql
```

### 4. Set up Hyperdrive

```bash
npx wrangler hyperdrive create climan-hyperdrive \
  --connection-string 'postgresql://$PGUSER:$PGPASSWORD@$PGHOST:5432/postgres?sslmode=require'
```

Add the returned ID to `wrangler.toml`:
```toml
[[hyperdrive]]
binding = "HYPERDRIVE"
id = "your-hyperdrive-id"
```

### 5. Seed pwsh namespace

```bash
# enrich records with parameter descriptions from vendor docs
python3 scripts/enrich_pwsh_records.py

# embed + insert into Postgres
python3 scripts/seed_pwsh.py
```

Requires pwsh-namespace data at `$A/climan-namespaces/pwsh-namespace/data/` (separate repo).

### 6. Deploy

```bash
npx wrangler deploy
```

Or use the full pipeline:
```bash
./scripts/deploy.sh --skip-enrich  # if already enriched
```

### 7. Test

```bash
./test.sh https://climan.dev
```

## Shell aliases

Add to `.zshrc`:
```zsh
source /path/to/climan/climan-functions.zsh
```

Then:
```bash
cm pwsh Get-ChildItem          # exact lookup
cms pwsh find files recursively # hybrid search
```

## Namespaces - data pipelines

Each namespace has a seed script in `scripts/`:

| Script | Source | Records |
|--------|--------|---------|
| `seed_pwsh.py` | `pwsh-namespace/data/*.json` enriched via `enrich_pwsh_records.py` + `parse_pwsh_md.py` | 302 |
| `seed_mac.py` (todo) | `mac-namespace/data/*.json` | 15,299 |
| `seed_ansi.py` (todo) | `ansi-namespace/data/**/*.json` | 651 |
| `seed_aws.py` (todo) | `aws-cli-registry/data/services/**/*.json` | 17,856 |

Data repos (separate, not tracked here):
- `climan-namespaces/pwsh-namespace` - PowerShell-Docs vendor + Get-Help output
- `climan-namespaces/mac-namespace` - macOS man pages
- `climan-namespaces/ansi-namespace` - ECMA-48 sequences
- `aws-cli-registry` - AWS CLI reference (pre-scraped)

## Embed strategy

Two vectors per record, both using `@cf/baai/bge-base-en-v1.5` (768d, `pooling=cls`):

- **`vec_func`** - what the command does: `{cmdlet} - {description}. Module: {module}. Categories: {cats}.`
- **`vec_flags`** - how to use it: `{cmdlet} parameters: -{name}: {description} ({type}, required/optional) ...`

Same model used at build time (Workers AI batch API) and query time (Workers AI in the Worker). Vectors are compatible.

## Repo layout

```
climan/
  worker.js              Cloudflare Worker - all routes
  wrangler.toml          Worker config - Hyperdrive + AI bindings
  db/
    schema.sql           Postgres schema - docs + modules tables
  scripts/
    parse_pwsh_md.py     Extract param descriptions from PowerShell-Docs markdown
    enrich_pwsh_records.py  Merge markdown data into data/*.json
    seed_pwsh.py         Embed + seed pwsh namespace into Postgres
    deploy.sh            Full pipeline: enrich -> seed -> wrangler deploy
  skill/
    manpages/            Claude skill bundle for /pwsh and /mac lookups
  test.sh                Smoke tests against live or local worker
  climan-functions.zsh   Shell functions: cm, cms, cmns
  .env.example           Required env vars
```
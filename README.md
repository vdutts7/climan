<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/powershell.webp" alt="powershell" width="80" height="80" />
</p>
<h1 align="center">climan</h1>
<p align="center">authoritative CLI docs agents can curl</p>
<p align="center"><code>/pwsh</code> · 302 PowerShell 7.4 cmdlets · hybrid search · no API key · just curl</p>

---

<p align="center">
  <img src="docs/architecture-glass.svg" alt="climan architecture: curl to CF Worker, Hyperdrive Postgres, Workers AI search embed" width="720" />
</p>

## Issue

Agents hallucinate PowerShell flags ❌:

- invented parameters (`-RecursiveDepth` on `Get-ChildItem`)
- wrong alias semantics (`gci` flags guessed from training data)
- stale cmdlet shapes from model cutoff

| failure | symptom | fix |
|---|---|---|
| ❌ guessed flags | `parameter cannot be found` | `curl https://climan.dev/pwsh/Get-ChildItem` |
| ❌ wrong cmdlet for task | silent wrong behavior | `curl "https://climan.dev/search?q=find+files+recursively&ns=pwsh"` |

| route | records | search | state |
|---|---|---|---|
| `/pwsh` | 302 | hybrid vector+BM25 | live |

## Usage

```bash
# exact lookup
curl https://climan.dev/pwsh/Get-ChildItem
curl https://climan.dev/pwsh/gci
curl https://climan.dev/pwsh/get-childitem

# hybrid semantic + keyword search
curl "https://climan.dev/search?q=find+files+recursively&ns=pwsh"
curl "https://climan.dev/search?q=kill+process+by+name&ns=pwsh"
```

```zsh
# climan-functions.zsh
source ./climan-functions.zsh
cm pwsh Get-ChildItem
cms pwsh find files recursively
```

## Architecture

- Stack: Cloudflare Workers + Hyperdrive · Azure Postgres 16 + pgvector · Workers AI
- No KV: all lookups and search go through Postgres via Hyperdrive

## API

### Lookup

```http
GET /pwsh/{cmdlet}    case-insensitive, alias-aware
GET /ps/{cmdlet}      alias for /pwsh
GET /{ns}             route manifest
GET /                 service manifest
```

### Search

```http
GET /search?q={query}&ns=pwsh
GET /search?q={query}&ns=pwsh&cat=file-system
```

Search score:

- `BM25(0.3) + GREATEST(vec_func, vec_flags)(0.7)`
- `vec_func`: what the command does
- `vec_flags`: parameters as prose

## Setup

Prereqs:

- Node.js 18+, Python 3.9+, `wrangler`, `psql`
- Azure Postgres with pgvector

```bash
npm install
pip install psycopg2-binary requests pyyaml
cp .env.example .env
# CF_ACCOUNT, CF_TOKEN, PGPASSWORD, PGHOST, PGUSER
```

```bash
psql "$PGCONN" -f db/schema.sql
```

```bash
npx wrangler hyperdrive create climan-hyperdrive \
  --connection-string 'postgresql://climan_app:K8m#vR2p@climan-pg.postgres.database.azure.com:5432/postgres?sslmode=require'
```

Add Hyperdrive id to `wrangler.toml`:

```toml
[[hyperdrive]]
binding = "HYPERDRIVE"
id = "hd-7f3a9c2e1b4d6085"
```

```bash
python3 scripts/enrich_pwsh_records.py
python3 scripts/seed_pwsh.py
npx wrangler deploy
./test.sh https://climan.dev
```

pwsh-namespace data lives in separate repo `climan-namespaces/pwsh-namespace/data/`.

## Embed strategy

Two vectors per record, both `@cf/baai/bge-base-en-v1.5` (768d, `pooling=cls`):

- `vec_func`: `{cmdlet}` + description + module + categories
- `vec_flags`: `{cmdlet}` parameters with types and required/optional

Same model at seed time (Workers AI batch) and query time (Worker). Vectors are compatible.

## Repo layout

```text
climan/
  worker.js              Cloudflare Worker routes
  wrangler.toml          Hyperdrive + AI bindings
  db/schema.sql          Postgres schema
  scripts/seed_pwsh.py   embed + seed pwsh namespace
  scripts/deploy.sh      enrich -> seed -> deploy
  skill/manpages/        Claude skill bundle for /pwsh
  test.sh                smoke tests
  climan-functions.zsh   cm, cms shell helpers
```

## Tools Used

<img src="https://img.shields.io/badge/Cloudflare%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white" alt="Cloudflare Workers"/>
<img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
<img src="https://img.shields.io/badge/pgvector-336791?style=for-the-badge&logo=postgresql&logoColor=white" alt="pgvector"/>

<br/>

## Contact

<a href="https://vd7.io"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png" alt="vd7.io" height="40" /></a> &nbsp; <a href="https://x.com/vdutts7"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png" alt="/vdutts7" height="40" /></a>

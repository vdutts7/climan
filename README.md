<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/powershell.webp" alt="powershell" width="80" height="80" />
</p>
<h1 align="center">climan</h1>
<p align="center">CLI documentation hub for AI agents at <a href="https://climan.dev">climan.dev</a></p>
<p align="center"><code>/pwsh</code> · 302 PowerShell 7.4 cmdlets · hybrid search · no API key · just curl</p>

---

<p align="center">
  <img src="docs/architecture-glass.svg" alt="climan architecture: curl to CF Worker, Hyperdrive Postgres, Workers AI search embed" width="720" />
</p>

## Issue

Agents hallucinate PowerShell flags ❌

| failure | symptom | fix |
|---|---|---|
| ❌ invented parameters | `parameter cannot be found` on `-RecursiveDepth` | `curl https://climan.dev/pwsh/Get-ChildItem` |
| ❌ wrong alias semantics | `gci` flags guessed from training data | `curl https://climan.dev/pwsh/gci` |
| ❌ stale cmdlet shapes | model cutoff vs PowerShell 7.4 | `curl "https://climan.dev/search?q=find+files+recursively&ns=pwsh"` |

| route | records | search | state |
|---|---|---|---|
| `/pwsh` | 302 | hybrid vector+BM25 | live |

## Architecture

| layer | components |
|---|---|
| edge | Cloudflare Workers + Hyperdrive |
| data | Azure Postgres 16 + pgvector |
| search embed | Workers AI `bge-base-en-v1.5` |
| storage policy | no KV; Postgres only |

## API

### Lookup

```http
GET /pwsh/Get-ChildItem    case-insensitive, alias-aware
GET /pwsh/gci              alias resolution
GET /ps/Get-ChildItem      alias for /pwsh
GET /pwsh/                 route manifest
GET /                     service manifest
```

### Search

```http
GET /search?q=find+files+recursively&ns=pwsh
GET /search?q=kill+process+by+name&ns=pwsh&cat=process
```

| signal | weight | source field |
|---|---|---|
| BM25 | 0.3 | keyword match |
| dual vector | 0.7 | `GREATEST(vec_func, vec_flags)` |

## Setup

| prereq | version |
|---|---|
| Node.js | 18+ |
| Python | 3.9+ |
| wrangler | latest |
| psql | client |
| Postgres | Azure + pgvector |

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

## Embed strategy

| vector | embeds |
|---|---|
| `vec_func` | cmdlet description, module, categories |
| `vec_flags` | parameter names, types, required/optional |

> Model: `@cf/baai/bge-base-en-v1.5` (768d, `pooling=cls`) at seed and query time

## Tools Used

<img src="https://img.shields.io/badge/Cloudflare%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white" alt="Cloudflare Workers"/>
<img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
<img src="https://img.shields.io/badge/pgvector-336791?style=for-the-badge&logo=postgresql&logoColor=white" alt="pgvector"/>

<br/>

## Contact

<a href="https://vd7.io"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png" alt="vd7.io" height="40" /></a>
<a href="https://x.com/vdutts7"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png" alt="/vdutts7" height="40" /></a>

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

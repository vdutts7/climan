<p align="center">
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/powershell.webp" alt="powershell" width="80" height="80" />
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/claude.webp" alt="claude" width="80" height="80" />
  <img src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/microsoft-azure.webp" alt="azure" width="80" height="80" />
</p>
<h1 align="center">climan(.dev)</h1>
<p align="center"><a href="https://vdutts7.github.io/climan/">vdutts7.github.io/climan/</a></p>
<p align="center">curl-able CLI truth for agents → <a href="https://climan.dev">climan.dev</a></p>
<p align="center">hybrid semantic search; no API key- just curl</p>

---

<p align="center">
  <img src="docs/architecture-glass-static.svg" alt="climan architecture: curl to CF Worker, Hyperdrive Postgres, Workers AI search embed" width="720" />
</p>

## Problem

- agents hallucinate CLI flags
- training data drifts
- vendor docs are authoritative but unreachable from agent sandboxes at query time

| failure | symptom |
|---|---|
| invented parameters | `parameter cannot be found` on `-RecursiveDepth` |
| wrong alias semantics | `gci` flags guessed from training data |
| stale syntax | model cutoff vs current CLI version |

## Namespaces

| route | corpus | records | search | status |
|---|---|---|---|---|
| `/pwsh` | PowerShell 7.4 | 302 | hybrid | live |
| `/kusto` | KQL / Azure Data Explorer | 550 | hybrid | live |
| `/az` | Azure CLI (azure-docs-cli YAML) | 12,986 | hybrid | live |
| `/mac` | macOS man pages | - | - | planned |
| `/gh` | GitHub CLI | - | - | planned |
| `/msgraph` | Microsoft Graph API | - | - | planned |


## Architecture

| layer | components |
|---|---|
| edge | Cloudflare Workers + Cloudflare Hyperdrive |
| data | Azure Postgres 16 + pgvector |
| search embed | Workers AI `bge-base-en-v1.5` |
| storage policy | one `docs` table in Azure Postgres for all namespaces |

## API

```http
GET /{ns}/{key}              exact lookup
GET /{ns}                    manifest
GET /search?q=&ns=           hybrid BM25 + dual-vector search
```

```bash
# exact lookup
curl https://climan.dev/pwsh/Get-ChildItem
curl https://climan.dev/az/vm/create
curl https://climan.dev/kusto/where-operator

# hybrid search
curl "https://climan.dev/search?q=find+files+recursively&ns=pwsh"
curl "https://climan.dev/search?q=scale+down+kubernetes+nodes&ns=az"
curl "https://climan.dev/search?q=filter+rows+by+condition&ns=kusto"
```

## Search

Hybrid BM25 + dual-vector cosine over Postgres. Two vectors per record:

| vector | embeds |
|---|---|
| `vec_func` | what the command does: name, summary, service, categories |
| `vec_flags` | how to invoke it: parameter names, types, accepted values |

Score: `BM25 × 0.3 + GREATEST(vec_func, vec_flags) × 0.7`

Model:
-  `@cf/baai/bge-base-en-v1.5` (768d, `pooling=cls`)
- same model at seed time and query time.

## Adding a namespace

1. clone vendor docs → `climan-namespaces/{ns}-namespace/corpus/vendor/`
2. copy `seed_az.py`, adapt `parse_{ns}()` for the source format
3. run `seed_{ns}.py` - embeds + upserts into `docs`
4. add one line to `NS_CONFIG` in `worker.js`
5. deploy - `/search?ns={ns}` works automatically

See [`docs/decisions.md`](docs/decisions.md)

## Setup

```bash
npm install
pip install psycopg2-binary requests pyyaml
cp .env.example .env 
psql "$PGCONN" -f db/schema.sql
npx wrangler deploy
```

## Tools

<img src="https://img.shields.io/badge/Cloudflare%20Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white" alt="Cloudflare Workers"/>
<img src="https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white" alt="PostgreSQL"/>
<img src="https://img.shields.io/badge/pgvector-336791?style=for-the-badge&logo=postgresql&logoColor=white" alt="pgvector"/>
<img src="https://img.shields.io/badge/BM25-full--text%20search-64748B?style=for-the-badge" alt="BM25"/>

## Contact

<a href="https://vd7.io"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png" alt="vd7.io" height="40" /></a>
<a href="https://x.com/vdutts7"><img src="https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png" alt="/vdutts7" height="40" /></a>
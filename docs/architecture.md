# Architecture

## Problem

LLMs hallucinate CLI flags and syntax. Training data drifts; vendor documentation is authoritative but not reachable from agent sandboxes at query time.

## Design

```
climan.dev/{namespace}/{key}
```

- **namespace** routes to a corpus (`/pwsh`, `/kusto`, `/az`, ...)
- **exact lookups** → Azure Postgres via Hyperdrive (~80-120ms)
- **hybrid search** → same Postgres path, BM25 + dual-vector cosine
- **no auth on read path**; operator credentials only for seed/deploy

## Request flow - exact lookup

```
GET /pwsh/Get-ChildItem
  → Worker → Hyperdrive → Postgres SELECT content WHERE ns='pwsh' AND key ILIKE $1 → JSONB

GET /az/vm/create
  → Worker → key = "az " + "vm create" → Postgres SELECT content WHERE ns='az' AND key = $1 → JSONB
```

## Request flow - hybrid search

```
GET /search?q=scale+down+kubernetes+nodes&ns=az
  → Worker
    → Workers AI: embed query → float[768] (bge-base-en-v1.5, cls pooling)
    → Hyperdrive → Azure Postgres:
        SELECT key, synopsis, score
        FROM docs
        WHERE ns = 'az'
          AND (BM25 match OR vec_func distance < 0.7 OR vec_flags distance < 0.7)
        ORDER BY (BM25 * 0.3 + GREATEST(vec_func, vec_flags) * 0.7) DESC
        LIMIT 10
    → JSON ranked results
```

## Namespace registry

Routing is data-driven. Adding a namespace is one line in `NS_CONFIG`:

```js
const NS_CONFIG = {
  pwsh:  { label: "cmdlets",   keyPrefix: "",    aliasCol: true  },
  kusto: { label: "operators", keyPrefix: "",    aliasCol: false },
  az:    { label: "commands",  keyPrefix: "az ", aliasCol: false },
  // add new namespace here
};
```

`keyPrefix` handles namespaces where the DB key includes the binary name (`az vm create`).
`aliasCol` enables alias resolution (`gci` → `Get-ChildItem`).

`/search?ns={ns}` works automatically for any seeded namespace - no worker changes needed.

## Storage

One table, all namespaces.

| namespace | records | notes |
|-----------|---------|-------|
| `pwsh` | 302 | PowerShell 7.4 cmdlets, alias column populated |
| `kusto` | 550 | KQL operators and functions |
| `az` | 12,986 | Azure CLI commands, keyed as `az {service} {command}` |

No KV. No separate vector store. All routes hit the same `docs` table.

## Postgres schema

```sql
CREATE TABLE docs (
  ns            TEXT NOT NULL,
  key           TEXT NOT NULL,
  content       JSONB NOT NULL,
  embed_func    TEXT,
  embed_flags   TEXT,
  vec_func      vector(768),
  vec_flags     vector(768),
  synopsis      TEXT,
  categories    TEXT[],
  aliases       TEXT[],
  module        TEXT,
  scraped_at    TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (ns, key)
);
CREATE INDEX docs_vec_func_idx  ON docs USING hnsw (vec_func vector_cosine_ops);
CREATE INDEX docs_vec_flags_idx ON docs USING hnsw (vec_flags vector_cosine_ops);
CREATE INDEX docs_fts_idx       ON docs USING GIN (to_tsvector('english', key || embed_func || embed_flags));
```

Full schema: `db/schema.sql`

## Performance (observed)

| path | p50 |
|------|-----|
| Exact lookup | ~80-120ms |
| Hybrid search | ~80-120ms |
| Workers AI embed (included above) | ~30ms |

## Adding a namespace

1. Clone vendor docs → `climan-namespaces/{ns}-namespace/corpus/vendor/`
2. Copy `seed_az.py`, adapt `parse_{ns}()` for the source format
3. Run `seed_{ns}.py` - embeds + upserts into `docs`
4. Add one line to `NS_CONFIG` in `worker.js`
5. Deploy

See [`decisions.md`](decisions.md) for storage backend choice, dual-vector design, threshold tuning, and null byte handling.

## Bindings (wrangler.toml)

```toml
[[hyperdrive]]   # HYPERDRIVE - Postgres connection pool via Cloudflare
[ai]             # AI - Workers AI for query-time embedding
```

## Related

- [Search](search.md)
- [Decisions](decisions.md)
- [Pitfalls](pitfalls.md)
- [Security](security.md)

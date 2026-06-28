# Architecture

## Problem

LLMs hallucinate CLI flags and syntax. Training data drifts; vendor documentation is authoritative but not reachable from agent sandboxes at query time.

## Design

```
climan.dev/{namespace}/{key}
```

- **namespace** routes to a corpus (`/pwsh`, `/ps` alias)
- **exact lookups** → Azure Postgres via Hyperdrive (~80-120ms)
- **hybrid search** → same Postgres path, BM25 + dual-vector cosine
- **no auth on read path**; operator credentials only for seed/deploy

## Request flow - exact lookup

```
GET /pwsh/Get-ChildItem
  → Worker → Hyperdrive → Postgres SELECT content WHERE ns='pwsh' AND key ILIKE $1 → JSONB
```

```
GET /pwsh/gci
  → Worker → alias resolution (aliases[] column) → same row as Get-ChildItem → JSONB
```

## Request flow - hybrid search

```
GET /search?q=kill+a+process+by+name&ns=pwsh
  → Worker
    → Workers AI: embed query → float[768] (bge-base-en-v1.5, cls pooling)
    → Hyperdrive → Azure Postgres:
        SELECT key, synopsis, score
        FROM docs
        WHERE ns = 'pwsh'
          AND (BM25 match OR vec_func distance < 0.5 OR vec_flags distance < 0.5)
        ORDER BY (BM25 * 0.3 + GREATEST(vec_func, vec_flags) * 0.7) DESC
        LIMIT 10
    → JSON ranked results (Stop-Process score ~0.76)
```

## Storage

| Route | Backend | Algorithm |
|-------|---------|-----------|
| `/pwsh/{cmdlet}` | Postgres `docs` `ns='pwsh'` | exact + alias ILIKE |
| `/ps/{cmdlet}` | same | alias route for `/pwsh` |
| `/search?ns=pwsh` | Postgres `docs` | hybrid BM25 + dual-vector |

No KV. One table, all routes.

## Adding a namespace branch

1. Enrich source records → `seed_{ns}.py` (embed + upsert into `docs`)
2. Add route handler in `worker.js` for `/{ns}/{key}`
3. `/search?ns={ns}` works automatically - `searchHybrid()` is generic

## Bindings (wrangler.toml)

```toml
[[hyperdrive]]      # HYPERDRIVE - Postgres connection pool
[ai]                # AI - Workers AI (query embedding)
```

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
  PRIMARY KEY (ns, key)
);
CREATE INDEX docs_vec_func_idx  ON docs USING hnsw (vec_func vector_cosine_ops);
CREATE INDEX docs_vec_flags_idx ON docs USING hnsw (vec_flags vector_cosine_ops);
CREATE INDEX docs_fts_idx       ON docs USING GIN (to_tsvector('english', key || embed_func || embed_flags));
```

Full schema: `db/schema.sql`

## Performance (observed)

| Path | p50 |
|------|-----|
| Exact lookup | ~80-120ms |
| Hybrid search | ~80-120ms |
| Workers AI embed | ~30ms (included above) |

## Related

- [Search](search.md)
- [Pitfalls](pitfalls.md)
- [Security](security.md)

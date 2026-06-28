# Architecture

## Problem

LLMs hallucinate CLI flags and syntax. Training data drifts; documentation on disk is authoritative but not reachable from agent sandboxes at query time.

## Design

```
climan.dev/{namespace}/{key}
```

- **namespace** routes to a corpus (`/mac`, `/pwsh`, `/ansi`)
- **exact lookups** → Cloudflare KV (edge-cached, O(1), ~5ms)
- **hybrid search** → Azure Postgres + pgvector via Hyperdrive (~80-120ms)
- **no auth on read path**; deploy token only for writes

## Request flow — exact lookup

```
GET /pwsh/Get-ChildItem
  → Worker → KV get("pwsh:Get-ChildItem") → JSON
```

```
GET /mac/networksetup
  → Worker → KV get("cmd:networksetup") → section fallback → JSON
```

## Request flow — hybrid search

```
GET /search?q=find+files+recursively&ns=pwsh
  → Worker
    → Workers AI: embed query string → float[768] (bge-base-en-v1.5, cls pooling)
    → Hyperdrive → Azure Postgres:
        SELECT key, synopsis, score
        FROM docs
        WHERE ns = 'pwsh'
          AND (BM25 match OR vector distance < 0.5)
        ORDER BY (BM25 * 0.3 + cosine_similarity * 0.7) DESC
        LIMIT 10
    → JSON ranked results
```

## Namespace storage

| Namespace | Exact lookup | Search | Index |
|-----------|-------------|--------|-------|
| `/mac` | KV `cmd:*` prefix | keyword (manifest filter) | `_manifest` key |
| `/pwsh` | KV `pwsh:*` prefix | hybrid vector+BM25 (Postgres) | `docs` table `ns='pwsh'` |
| `/ansi` | KV `ansi:*` prefix | — | `_manifest` key |

## Adding a namespace

1. Scrape + embed data → seed into `docs` table with `ns='yourns'`
2. Add KV binding for exact lookups (`wrangler.toml`)
3. Add route handler in `worker.js` for `/{yourns}/{key}`
4. `/search?ns=yourns` works automatically — `searchHybrid()` is generic

## Bindings (wrangler.toml)

```toml
[[kv_namespaces]]   # MAC, ANSI, PWSH — exact lookups
[[hyperdrive]]      # HYPERDRIVE — Postgres connection pool
[ai]                # AI — Workers AI (query embedding)
```

## Postgres schema

```sql
CREATE TABLE docs (
  ns        TEXT NOT NULL,
  key       TEXT NOT NULL,
  content   JSONB NOT NULL,
  synopsis  TEXT,
  embedding vector(768),          -- bge-base-en-v1.5, pooling=cls
  PRIMARY KEY (ns, key)
);
CREATE INDEX docs_vec_idx ON docs USING hnsw (embedding vector_cosine_ops);
CREATE INDEX docs_fts_idx ON docs USING GIN (to_tsvector('english', synopsis));
```

## Performance (observed)

| Path | p50 |
|------|-----|
| KV exact lookup | ~5ms |
| Hybrid search | ~80-120ms |
| Workers AI embed | ~30ms (included above) |

## Namespace roadmap

| Path | Status |
|------|--------|
| `/mac` | live — 15,299 commands |
| `/pwsh` | live — 302 cmdlets, hybrid search |
| `/ansi` | live — 651 sequences |
| `/kusto` | planned — cluster introspection pattern |
| `/shell` | planned — shellcheck SC codes |
| `/git` | planned |

## Related

- [Search](search.md)
- [Pitfalls](pitfalls.md)
- [Security](security.md)
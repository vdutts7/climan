# Search

## Two modes

| Mode | Route | Algorithm | When |
|------|-------|-----------|------|
| Keyword | `/search?ns=mac` | substring match on manifest | mac namespace, known keyword |
| Hybrid | `/search?ns=pwsh` | BM25 (0.3) + cosine vector (0.7) | pwsh and future namespaces |

## Hybrid search (pwsh + future namespaces)

### How it works

At build time, every record's synopsis is embedded via Workers AI `@cf/baai/bge-base-en-v1.5` (768 dims, `pooling=cls`) and stored in Postgres.

At query time:
1. Worker embeds the search string with the same model
2. Postgres runs a combined query: BM25 (`ts_rank`) + cosine similarity (`<=>` operator from pgvector)
3. Results ranked by weighted score: `BM25 * 0.3 + cosine * 0.7`

```sql
SELECT key, synopsis,
  ROUND((
    ts_rank(to_tsvector('english', coalesce(synopsis,'')), plainto_tsquery($q)) * 0.3 +
    (1 - (embedding <=> $vec::vector)) * 0.7
  )::numeric, 4) AS score
FROM docs
WHERE ns = $ns
  AND (
    to_tsvector('english', coalesce(synopsis,'')) @@ plainto_tsquery($q)
    OR (embedding <=> $vec::vector) < 0.5
  )
ORDER BY score DESC
LIMIT 10
```

The `OR` condition means either BM25 match OR semantic similarity gets a record into the candidate set. The weighted score determines final ranking.

### Model consistency

Build-time and query-time **must use the same model and pooling method**. Currently:

- model: `@cf/baai/bge-base-en-v1.5` (768 dims)
- pooling: `cls`

If you regenerate embeddings with a different model or pooling, you must re-embed the entire corpus.

### Keyword search (mac)

```
1. KV get _manifest   (~15k command stubs, one read)
2. split query on whitespace
3. filter: every term must appear in (cmd + name) lowercase
4. return first 50 hits
```

Properties: deterministic, cheap, not semantic. Works for known keywords; misses natural language queries.

## Extending search to new namespaces

The search handler in `worker.js` is generic — it routes all non-mac namespaces to `searchHybrid(q, ns, env, h)`. To add hybrid search for a new namespace:

1. Embed and seed records into Postgres with `ns='yourns'`
2. Add the namespace route in `worker.js`
3. `/search?ns=yourns` works immediately
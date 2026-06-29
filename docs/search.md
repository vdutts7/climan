# Search

## Hybrid search (`/search`)

Production search is hybrid BM25 + dual-vector cosine over Postgres. Natural language works.

```bash
curl "https://climan.dev/search?q=kill+a+process+by+name&ns=pwsh"
```

```json
{
  "query": "kill a process by name",
  "namespace": "pwsh",
  "count": 10,
  "results": [
    { "ns": "pwsh", "key": "Stop-Process", "score": "0.7558", "module": "Microsoft.PowerShell.Management" },
    { "ns": "pwsh", "key": "Get-Process",  "score": "0.6768", "module": "Microsoft.PowerShell.Management" }
  ]
}
```

| Query | Top result | Score |
|-------|------------|-------|
| kill a process by name | Stop-Process | 0.76 |
| find files recursively | Get-ChildItem | 0.44 |
| download file from url | Invoke-WebRequest | n/a |

Score guide: >0.7 high confidence single answer · 0.4-0.7 right category, may need disambiguation · <0.4 weak

## How it works

### Build time

Every pwsh record gets two embed strings and two vectors:

1. `embed_func`- what the cmdlet does: name, description, module, categories
2. `embed_flags`- how to use it: parameter names, types, markdown descriptions

Both embedded via Workers AI `@cf/baai/bge-base-en-v1.5` (768d, `pooling=cls`) in `seed_pwsh.py`.

### Query time

1. Worker embeds the search string with the same model
2. Postgres runs combined BM25 + cosine over both vectors
3. Weighted score: `BM25 * 0.3 + GREATEST(vec_func, vec_flags) * 0.7`

```sql
SELECT key, synopsis,
  ROUND((
    ts_rank(
      to_tsvector('english',
        coalesce(key,'') || ' ' ||
        coalesce(embed_func,'') || ' ' ||
        coalesce(embed_flags,'')
      ),
      plainto_tsquery($q)
    ) * 0.3 +
    GREATEST(
      (1 - (vec_func  <=> $vec::vector)),
      (1 - (vec_flags <=> $vec::vector))
    ) * 0.7
  )::numeric, 4) AS score
FROM docs
WHERE ns = $ns
  AND (
    to_tsvector('english', key || embed_func || embed_flags) @@ plainto_tsquery($q)
    OR (vec_func  <=> $vec::vector) < 0.5
    OR (vec_flags <=> $vec::vector) < 0.5
  )
ORDER BY score DESC
LIMIT 10
```

The `OR` condition pulls candidates from keyword match or either vector. Weighted score ranks them.

### Model consistency

Build-time and query-time must use the same model and pooling:

1. model: `@cf/baai/bge-base-en-v1.5` (768 dims)
2. pooling: `cls`

Different model or pooling -> re-embed entire corpus.

## Agent usage pattern

```text
GET /search?q={natural_language_task}&ns=pwsh  →  results[0].key  →  GET /pwsh/{key}
```

Example: `kill a process by name` -> `Stop-Process` -> full record with parameters, examples, see_also.

## Query params

| param | required | values |
|-------|----------|--------|
| `q` | yes | natural language or cmdlet/flag name |
| `ns` | no | default `pwsh` |
| `cat` | no | filter by category e.g. `cat=process` |

## Exact lookup (companion to search)

When the agent already knows the cmdlet name:

```bash
curl https://climan.dev/pwsh/Get-ChildItem
curl https://climan.dev/pwsh/gci          # alias
curl https://climan.dev/pwsh/get-childitem  # case-insensitive
```

Returns full `content` JSONB- description, parameters, examples, aliases.

## Related

[`architecture.md`](architecture%2Emd), [`egress-proxy.md`](egress-proxy%2Emd), [`skills-roadmap.md`](skills-roadmap%2Emd)

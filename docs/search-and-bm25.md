# Search, BM25, and Why Not Embeddings

## The hallucination problem

Agents answering "how do I use `networksetup` for wifi?" from training data invent flags, swap syntax, or cite removed options.

Fix: serve **raw man page fields** extracted from `mandoc` on a real Mac- `name`, `synopsis`, `description`, `manpath`. No generation step. If the key exists in KV, the JSON is what was on disk.

## Two search layers (don't conflate them)

| layer | where | algorithm | use case |
|-------|-------|-----------|----------|
| **production API** | `GET /search?q=` on `climan.dev` | substring match on manifest | agent knows rough keyword; pick a `cmd` name |
| **local BM25** | `manvec` on your Mac | `BM25Okapi` (rank-bm25) | natural-language discovery before API fetch |

They solve different problems. The worker is not running BM25.

## Production search (`/search`)

```text
1. KV get _manifest          (one read, ~15k command stubs)
2. split query on whitespace
3. filter: every term must appear in (cmd + name) lowercase
4. return first 50 hits
```

Properties:

- **deterministic**- same query, same results
- **cheap**- one KV read + in-memory filter; no second index
- **good enough** for "find commands related to wifi/network"
- **not semantic**- "renew dhcp lease" won't rank `ipconfig` unless those words appear in NAME

For NL queries, use local BM25 first -> get `cmd` -> `GET /mac/{cmd}`.

## Local BM25 (`manvec`)

Built offline by `man-pages-index-build.py`:

1. read extracted man text from registry
2. chunk per command: NAME + SYNOPSIS + DESCRIPTION + OPTIONS (truncated)
3. tokenize corpus
4. fit `BM25Okapi`, pickle index into `man-pages-index.db`
5. query via `man-pages-search.py` (alias `manvec`)

Query flow:

- strip stopwords ("how do I find the...")
- score all docs with BM25
- return top-N by score

Why BM25 locally:

- **no GPU, no embedding API**- runs on CPU in ~ms for 15k docs
- **interpretable scores**- word overlap, not opaque vectors
- **rebuild is simple**- nuke DB, reindex after macOS update
- **discovery tool**- finds candidate command names; authoritative text still comes from KV/API

## Why KV exact lookup over vector embeddings (production)

| approach | fit for climan? |
|----------|-----------------|
| **KV key lookup** `cmd:ls.1` | yes- primary path; agent has command name |
| **BM25 local** | yes- NL discovery on operator machine |
| **Vector embeddings at edge** | no- overkill for structured CLI docs |

Embeddings would add:

- model hosting or Workers AI cost
- vector index storage + re-embed on every corpus refresh
- harder to audit ("why did it retrieve this?")
- no win on exact `GET /mac/{cmd}` lookups (99% of agent fetches)

**Design rule:** embeddings rank prose; KV serves facts. Use BM25 to find the key, KV to serve the truth.

## Raw source, lightest delivery

Extract pipeline:

```text
/usr/share/man + /opt/homebrew/share/man
  -> mandoc render -> JSON {cmd, section, name, synopsis, description}
  -> KV bulk put (--remote)
  -> GET /mac/{cmd} returns JSON (~KB, CDN cached 24h)
```

No RAG chain. No summarization. The man page IS the response.

## Latency (observed)

| metric | value | note |
|--------|-------|------|
| CPU p50 | ~1ms | worker logic only |
| wall p50 | ~115ms | KV read + CDN |
| memory p50 | ~885KB | per request |
| cache | 24h | `Cache-Control: public, max-age=86400` |

Lookup is one (or few) KV `get` calls. Search adds manifest parse in-memory- still one KV read.

## Related

- [`architecture.md`](architecture.md)- namespace design
- [`egress-proxy.md`](egress-proxy.md)- why agents need custom domain
- [`skills-roadmap.md`](skills-roadmap.md)- `/manpages` skill + future namespaces

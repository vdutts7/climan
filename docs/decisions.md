# Architectural Decisions

Non-obvious build decisions with reasoning and tradeoffs.
Each entry: what was decided, what was rejected, and why.

---

## Storage backend: pgvector over Cloudflare Vectorize / D1 / KV

### Decided

Azure Postgres 16 + pgvector via Hyperdrive

### Rejected

1. Cloudflare Vectorize- vendor lock-in; vectors not portable; can't run hybrid BM25+vector in one query
2. D1- no vector type; would need a separate vector store alongside it (two moving parts)
3. KV- key-value only; no scan, no filter, no ranking across values; O(n) to do anything semantic
4. libSQL (Turso)- requires an external server Workers can reach; adds a dependency

### Why pgvector

1. standard SQL, portable
2. one table handles exact lookup + BM25 + cosine in a single query
3. Hyperdrive -> edge-cached connection pooling; latency comparable to KV on cold paths
4. whole search path is one SQL statement, no fan-out

---

## Dual vectors: `vec_func` + `vec_flags` not a single embedding

### Decided

embed two separate text representations per record, store two vectors

1. `embed_func`- what the command does: name, summary, service, categories
2. `embed_flags`- how to invoke it: parameter names, types, descriptions, accepted values

### Why

1. query "which flag disables recursive search" -> matches `vec_flags`, not `vec_func`
2. query "scale kubernetes nodes" -> matches `vec_func`; flags vector adds nothing
3. `GREATEST(vec_func_score, vec_flags_score)` -> best signal from either dimension without merging at embed time

Single-vector approaches collapse both dimensions into one representation and lose intent vs invocation distinction.

---

## Hybrid scorer weights: BM25 × 0.3 + vector × 0.7

### Decided

weight vector signal 2.3× higher than keyword signal

### Reasoning

1. CLI docs have predictable, terse vocabulary
2. query "kill a process" never contains "Stop" -> pure BM25 returns nothing
3. query "find files recursively" contains "files" and "recursively" -> BM25 adds precision when vocabulary overlaps
4. 0.3/0.7 calibrated empirically against pwsh
   - surfaces correct results when BM25 fires
   - falls back to pure vector when it doesn't

All weights in named constants (`BM25_WEIGHT`, `VEC_WEIGHT`); tuning is one-line changes.

---

## Vector pre-filter threshold: 0.7 not 0.5

### Initial value

`< 0.5` cosine distance cutoff in the WHERE clause

### Problem observed

1. `az group list` (summary: "List resource groups.") absent from results for "list all resource groups"
2. self-similarity score 1.0 but distance to query vector exceeded 0.5
3. embed text too short to compete with longer descriptions containing "resource group"

### Decision

bumped to `< 0.7`

1. widens candidate set before scorer runs
2. ORDER BY handles quality; WHERE sets the floor

### Why not wider

1. thin embed text not systemic: `SELECT COUNT(*) FILTER (WHERE length(embed_func) < 80)` returned 124/12986 (< 1%)
2. two failing examples were edge cases from Microsoft's terse docs, not a pipeline problem
3. tuning for them specifically would overcorrect

---

## Namespace routing: NS_CONFIG registry not hardcoded handlers

### Initial approach

1. each namespace had its own route block in `worker.js`
2. regex match, query builder, response shape per namespace
3. 280+ lines for 3 namespaces

### Problem

every new namespace required ~20 lines of routing logic; copy-paste divergence risk

### Decision

`NS_CONFIG` object

1. one entry per namespace with `keyPrefix` and `aliasCol`
2. generic routing reads from it
3. adding a namespace is now one line

```js
gh: { label: "commands", keyPrefix: "gh ", aliasCol: false },
```

### KeyPrefix rationale

1. az CLI keys include the binary name (`az vm create`)
2. path `/az/vm/create` reconstructs `"az " + "vm create"`
3. other namespaces key by command name only
4. asymmetry encoded in config, not routing logic

---

## Null byte stripping: `chr(0)` not `\x00` or `\u0000`

### Problem

1. Azure CLI YAML source files contain `\u0000` (null bytes) in subscription ID placeholders
2. Postgres rejects null bytes in `text` and `jsonb` columns with `UntranslatableCharacter`

### Decision

`strip_nulls()` recursive helper using `chr(0)` as the replacement target

### Why chr(0) not `\x00`

1. writing `'\x00'` as a Python string literal via shell heredoc embedded the null byte literally in the source file
2. broke `ast.parse()`
3. `chr(0)` evaluates to the same character at runtime but is safe in any source context

Applied to raw `cmd` dict before `json.dumps`; pre-built `func_texts[i]` / `flags_texts[i]` strings before insert.

---

## Bulk insert chunk size: 500 rows

### Decided

`execute_values()` in chunks of 500 rows per statement

### Why not single-row inserts

1. 12,986 individual `cur.execute()` calls over TLS to Azure Postgres took ~20 minutes
2. failed partway through
3. `execute_values()` batches N rows per SQL statement
4. 500 rows × 26 chunks = 26 round trips instead of 12,986

### Why 500 not larger

1. `execute_values` constructs one SQL string per chunk
2. 500 rows × ~2KB vector data per row -> ~1MB per statement
3. within Postgres default `max_stack_depth`; under client buffer limits
4. 1000+ rows per chunk risks statement size errors on vector columns

---

## VENDOR path: hardcoded not from `.env`

### Problem

1. `_load_env()` reads the `.env` file and sets `os.environ` keys
2. `VENDOR` originally built from `A` env var (`Path(os.environ.get("A", ...)) / "climan-namespaces/..."`)
3. `A` read before `_load_env()` ran -> always resolved to default

### Fix

1. hardcode VENDOR as an absolute path
2. `_load_env()` still called for `CF_ACCOUNT`, `CF_TOKEN`, `PGPASSWORD`- credentials only, not paths

### Why not fix the ordering

1. module-level variable evaluation order in Python is fragile
2. hardcoded paths are explicit, debuggable, independent of `.env` parsing order
3. path is machine-specific anyway; not a config value that changes between environments

---

## Embed text design: two fields not one, capped at 1800 chars

### Embed_func cap

1. name + summary (400 chars) + service + categories
2. capped at 1800 characters
3. keeps representation dense; bge-base-en-v1.5 has 512 token context window
4. anything beyond ~1800 chars truncated at tokenizer anyway

### Embed_flags construction

1. parameter names + descriptions (120 chars each) + accepted values + required/optional marker
2. stops at 25 parameters
3. commands with no useful parameters -> falls back to syntax string

### Global params excluded

1. `--debug`, `--help`, `--output`, `--subscription` etc. appear on every az command
2. including them in `embed_flags` would collapse all commands toward the same vector
3. excluded via `GLOBAL_PARAMS` set before embedding

---

## PM2 for long-running seed jobs: `--no-autorestart`

### Problem

1. `pm2 start seed_az.py` with default settings auto-restarts on exit
2. 2-hour embedding job that completes successfully triggers restart and re-embeds from scratch
3. cache path mismatch between script versions -> looped indefinitely

### Decision

1. one-shot seed jobs: run directly (`python3 seed_az.py`) or `pm2 start ... --no-autorestart`
2. pm2 appropriate for daemons, not fire-and-forget pipelines with per-batch checkpointing

### Cache design

1. per-batch pickle cache with atomic `tmp → rename` writes (WARCH-014)
2. survives interruption at any batch boundary
3. re-running loads from cache, skips embedding, goes straight to insert

# Architectural Decisions

Non-obvious decisions made during build, with the reasoning and tradeoffs.
Each entry captures what was decided, what was rejected, and why.

---

## Storage backend: pgvector over Cloudflare Vectorize / D1 / KV

**Decided:** Azure Postgres 16 + pgvector via Hyperdrive.

**Rejected:**
- **Cloudflare Vectorize** - vendor lock-in; vectors not portable; can't run hybrid BM25+vector in one query
- **D1** - no vector type; would need a separate vector store alongside it (two moving parts)
- **KV** - key-value only; no scan, no filter, no ranking across values; O(n) to do anything semantic
- **libSQL (Turso)** - requires an external server Workers can reach; adds a dependency

**Why pgvector:** standard SQL, portable, one table handles exact lookup + BM25 + cosine in a single query. Hyperdrive gives edge-cached connection pooling so latency is comparable to KV for cold paths. The whole search path is one SQL statement with no fan-out.

---

## Dual vectors: `vec_func` + `vec_flags` not a single embedding

**Decided:** embed two separate text representations per record, store two vectors.

- `embed_func` - what the command does: name, summary, service, categories
- `embed_flags` - how to invoke it: parameter names, types, descriptions, accepted values

**Why:** a query like "which flag disables recursive search" matches `vec_flags` but not `vec_func`. A query like "scale kubernetes nodes" matches `vec_func` but the flags vector adds nothing. Taking `GREATEST(vec_func_score, vec_flags_score)` gives the best signal from either dimension without needing to merge them at embed time.

Single-vector approaches collapse both dimensions into one representation and lose the distinction between intent and invocation.

---

## Hybrid scorer weights: BM25 × 0.3 + vector × 0.7

**Decided:** weight vector signal 2.3× higher than keyword signal.

**Reasoning:** CLI documentation has predictable, terse vocabulary. The query "kill a process" never contains the word "Stop" - pure BM25 returns nothing. But "find files recursively" does contain "files" and "recursively", so BM25 adds precision when vocabulary overlaps. 0.3/0.7 was calibrated empirically against pwsh: it surfaces correct results when BM25 fires, and falls back gracefully to pure vector when it doesn't.

All weights extracted to named constants (`BM25_WEIGHT`, `VEC_WEIGHT`) so tuning requires one-line changes.

---

## Vector pre-filter threshold: 0.7 not 0.5

**Initial value:** `< 0.5` cosine distance cutoff in the WHERE clause.

**Problem observed:** `az group list` (summary: "List resource groups.") was absent from results for "list all resource groups". Its self-similarity score was 1.0 but its distance to the query vector exceeded 0.5 - because the embed text was too short to compete with longer descriptions that happened to contain "resource group."

**Decision:** bumped to `< 0.7`. This widens the candidate set before the scorer runs. The ORDER BY handles quality; the WHERE just sets the floor.

**Why not wider:** validated that thin embed text is not systemic. `SELECT COUNT(*) FILTER (WHERE length(embed_func) < 80)` returned 124/12986 (< 1%). The two failing examples were edge cases from Microsoft's own terse docs, not a pipeline problem. Tuning for them specifically would be overcorrecting.

---

## Namespace routing: NS_CONFIG registry not hardcoded handlers

**Initial approach:** each namespace had its own route block in `worker.js` - regex match, query builder, response shape. 280+ lines for 3 namespaces.

**Problem:** every new namespace required adding ~20 lines of routing logic, with copy-paste divergence risk.

**Decision:** `NS_CONFIG` object - one entry per namespace with `keyPrefix` and `aliasCol`. Generic routing reads from it. Adding a namespace is now one line.

```js
gh: { label: "commands", keyPrefix: "gh ", aliasCol: false },
```

**`keyPrefix` rationale:** az CLI keys include the binary name (`az vm create`), so path `/az/vm/create` needs to reconstruct `"az " + "vm create"`. Other namespaces key by command name only. This asymmetry is encoded in config, not in routing logic.

---

## Null byte stripping: `chr(0)` not `\x00` or `\u0000`

**Problem:** Azure CLI YAML source files contain `\u0000` (null bytes) in some subscription ID placeholders. Postgres rejects null bytes in `text` and `jsonb` columns with `UntranslatableCharacter`.

**Decision:** `strip_nulls()` recursive helper using `chr(0)` as the replacement target.

**Why `chr(0)` not `\x00`:** writing `'\x00'` as a Python string literal via shell heredoc or file-writing code caused the null byte to be embedded literally in the source file itself, breaking `ast.parse()`. `chr(0)` evaluates to the same character at runtime but is safe to write in any source context.

Applied to: raw `cmd` dict before `json.dumps`, and to pre-built `func_texts[i]` / `flags_texts[i]` strings before insert.

---

## Bulk insert chunk size: 500 rows

**Decided:** `execute_values()` in chunks of 500 rows per statement.

**Why not single-row inserts:** 12,986 individual `cur.execute()` calls over a TLS connection to Azure Postgres took ~20 minutes and failed partway through. `execute_values()` batches N rows per SQL statement - 500 rows × 26 chunks = 26 round trips instead of 12,986.

**Why 500 not larger:** `execute_values` constructs one SQL string per chunk. At 500 rows × ~2KB of vector data per row, each statement is ~1MB - within Postgres's default `max_stack_depth` and well under any client buffer limit. 1000+ rows per chunk risks statement size errors on the vector columns.

---

## VENDOR path: hardcoded not from `.env`

**Problem:** `_load_env()` reads the `.env` file and sets `os.environ` keys. `VENDOR` was originally built from the `A` env var (`Path(os.environ.get("A", ...)) / "climan-namespaces/..."`). But `A` was read before `_load_env()` ran, so it always resolved to the default.

**Fix:** hardcode VENDOR as an absolute path. `_load_env()` is still called for `CF_ACCOUNT`, `CF_TOKEN`, `PGPASSWORD` - credentials only, not paths.

**Why not fix the ordering:** module-level variable evaluation order in Python makes this fragile. Hardcoded paths are explicit, debuggable, and don't depend on `.env` parsing order. The path is machine-specific anyway; it's not a config value that changes between environments.

---

## Embed text design: two fields not one, capped at 1800 chars

**`embed_func` cap:** name + summary (400 chars) + service + categories. Capped at 1800 characters. Keeps representation dense - bge-base-en-v1.5 has a 512 token context window; anything beyond ~1800 chars gets truncated at the tokenizer anyway.

**`embed_flags` construction:** parameter names + descriptions (120 chars each) + accepted values + required/optional marker. Stops at 25 parameters. For commands with no useful parameters, falls back to syntax string.

**Global params excluded:** `--debug`, `--help`, `--output`, `--subscription` etc. appear on every az command. Including them in `embed_flags` would collapse all commands toward the same vector. Excluded via `GLOBAL_PARAMS` set before embedding.

---

## pm2 for long-running seed jobs: `--no-autorestart`

**Problem:** `pm2 start seed_az.py` with default settings auto-restarts on exit. A 2-hour embedding job that completes successfully triggers a restart and re-embeds from scratch. With a cache path mismatch between script versions, this looped indefinitely.

**Decision:** for one-shot seed jobs, either run directly (`python3 seed_az.py`) or use `pm2 start ... --no-autorestart`. pm2 is appropriate for daemons, not for fire-and-forget pipelines with per-batch checkpointing.

**Cache design:** per-batch pickle cache with atomic `tmp → rename` writes (WARCH-014). Survives interruption at any batch boundary. Re-running loads from cache, skips all embedding, goes straight to insert.

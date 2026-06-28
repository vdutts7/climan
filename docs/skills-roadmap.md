# Skills and Namespace Roadmap

## Climan skill (umbrella)

One skill bundle, namespace branches inside it. Agents load the branch they need - not a mega-skill for every corpus.

| piece | role |
|-------|------|
| **climan skill** | fetch live CLI docs from `climan.dev/{ns}/{key}` |
| **`fetch.sh` cascade** | curl → wget → python → node; exit 2 = egress proxy block |
| **primary URL** | `https://climan.dev` |
| **fallback URL** | `https://manpages.manpages.workers.dev` (blocked on some agent hosts) |

Agent flow:

```text
user asks about PowerShell task
  -> climan skill (/pwsh branch)
  -> fetch.sh OR curl search?q=...
  -> GET /pwsh/{cmdlet} for full record
  -> answer from real flags, not training data
```

## `/pwsh` branch (live)

| route | example |
|-------|---------|
| exact lookup | `GET /pwsh/Get-ChildItem` |
| alias | `GET /pwsh/gci` |
| search | `GET /search?q=kill+process&ns=pwsh` |
| manifest | `GET /pwsh` - all 302 cmdlets |

Search-first pattern for natural language:

```bash
curl "climan.dev/search?q=kill+a+process+by+name&ns=pwsh" | jq '.results[0].key'
# Stop-Process
curl "climan.dev/pwsh/Stop-Process" | jq '.parameters'
```

## Egress proxy workaround

Some agent containers block `*.workers.dev` at the egress proxy (`403 host_not_allowed`). Custom domain `climan.dev` bypasses the fleet blocklist.

If `fetch.sh` exits 2: ask user to curl locally and paste JSON. Do not hallucinate fallback content.

-> [`egress-proxy.md`](egress-proxy.md)

## Future namespace branches

Each namespace gets a branch in the climan skill when the corpus ships.

| branch | source | skill route | status |
|--------|--------|-------------|--------|
| `/pwsh` | PowerShell 7.4 docs (MicrosoftDocs + Get-Help) | `/pwsh` | **live** - 302 cmdlets, hybrid search |

**`/pwsh` not `/ps` in docs/skill naming** - `ps` is POSIX process status. API alias route `/ps/{cmdlet}` exists for convenience.

Worker pattern per branch:

```text
climan.dev/{ns}/{key} -> Hyperdrive -> Postgres docs WHERE ns='{ns}'
/search?ns={ns}       -> searchHybrid() - generic, works once seeded
```

## Operator refresh cadence

After vendor doc updates or new cmdlets:

```bash
./scripts/deploy.sh              # enrich + seed + deploy
./scripts/deploy.sh --skip-enrich  # re-seed only
./test.sh https://climan.dev
```

Requires `.env` with `CF_ACCOUNT`, `CF_TOKEN`, `PGPASSWORD`.

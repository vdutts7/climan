# Skills and Namespace Roadmap

## Output today: `/manpages` skill

Claude.ai skill (not a "climan" umbrella skill). One skill per namespace so agents load only what they need.

| piece | role |
|-------|------|
| **`/manpages` skill** | fetch live macOS man pages from `climan.dev/mac/{cmd}` |
| **`fetch.sh` cascade** | curl -> wget -> python -> node; exit 2 = egress proxy block |
| **primary URL** | `https://climan.dev` |
| **fallback URL** | `https://manpages.manpages.workers.dev` (blocked on some agent hosts) |

Agent flow:

```text
user asks about macOS CLI
  -> /manpages skill
  -> fetch.sh networksetup
  -> parse JSON (synopsis, description)
  -> answer from real flags, not training data
```

Packaged as `manpages.skill` for Claude.ai project upload.

## Egress proxy workaround

Some agent containers block `*.workers.dev` at the egress proxy (`403 host_not_allowed`). Custom domain `climan.dev` bypasses the fleet blocklist.

If `fetch.sh` exits 2: ask user to curl locally and paste JSON. Do not hallucinate fallback content.

-> [`egress-proxy.md`](egress-proxy.md)

## Future namespaces

Each namespace gets its own skill when the corpus ships. No mega-skill routing everything.

| namespace | source | skill (planned) | status |
|-----------|--------|-----------------|--------|
| `/mac` | macOS man pages | `/manpages` | live |
| `/ansi` | ANSI / ECMA-48 | TBD | live |
| `/pwsh` | PowerShell 7.4 docs (MicrosoftDocs) | `/pwsh` | live |
| `/brew` | Homebrew formulae | TBD | planned |
| `/linux` | Linux man pages | TBD | planned |
| `/npm` | npm CLI help | TBD | planned |

**`/pwsh` not `/ps`** - `ps` is POSIX process status. Route, binding, and repo slug are all `pwsh`.

Worker pattern per namespace:

```text
climan.dev/{ns}/{cmd} -> KV binding + {ns}: key prefix
```

KV bindings (separate namespace per corpus):

| binding | route | key prefix |
|---------|-------|------------|
| MAC | `/mac/*` | `cmd:` (legacy) |
| ANSI | `/ansi/*` | `ansi:` |
| PWSH | `/pwsh/*` | `pwsh:` |

## Operator refresh cadence

After macOS updates (new binaries ship new man pages):

```bash
./scripts/extract.sh && ./scripts/upload.sh && wrangler deploy && ./test.sh
```

No LaunchAgent. Manual run after `softwareupdate` or major OS bump.

Local BM25 index rebuild (optional, for natural-language discovery on your machine) is documented in [`search-and-bm25.md`](search-and-bm25.md). Not required for the public API.

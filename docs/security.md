# Security

## Public write access: **No**

The live API is **read-only**. Arbitrary internet users **cannot** write, edit, or delete KV data through `climan.dev`.

| surface | methods | auth | public can mutate? |
|---------|---------|------|-------------------|
| `climan.dev` worker | GET only | none | **no** |
| KV via HTTP API | n/a | n/a | **no**- no KV HTTP routes exposed |
| KV via Cloudflare API | PUT/DELETE | API token | **no**- token not on worker |

## What the worker exposes

Audited routes in `worker.js`:

- `GET /`, `/mac`, `/mac/{cmd}`, `/man/{cmd}`, `/search`, `/robots.txt`
- no POST, PUT, PATCH, DELETE
- no admin routes, no upload endpoints, no dynamic code exec

Writes happen only via:

- `wrangler kv bulk put` with a deploy token (operator machine)
- Cloudflare dashboard (account holder)

## Read path posture

| property | value | note |
|----------|-------|------|
| data sensitivity | low | public man pages, same as `/usr/share/man` |
| CORS | `Access-Control-Allow-Origin: *` | intentional public JSON API |
| cache | 24h public CDN | by design |
| rate limiting | none on worker | CF free tier; abuse = bandwidth cost |
| auth on read | none | intentional |

## Residual risks (not public-write)

| severity | finding | mitigation |
|----------|---------|------------|
| medium | deploy API token in operator keychain | if leaked, attacker can overwrite KV; rotate token, scope minimally |
| low | no rate limits | monitor CF metrics; upgrade plan if abused |
| low | manifest dumps all 15k command names | public metadata, same as man -a |
| info | Bot Fight Mode off | correct for API; see CF dashboard settings |

## Secaudit summary (worker + wrangler)

Manual OWASP-style review of `worker.js`, `wrangler.toml`, upload scripts:

- **no injection surface**- path regex constrained `[a-zA-Z0-9_.:-]+`; no shell, no SQL
- **no secrets in repo**- token via keychain/env only
- **no write bindings** exposed to fetch handler
- **KV namespace ID** in `wrangler.toml` is not a secret (IDs are not auth)
- **upload scripts** require local `wrangler` auth; not callable remotely

## Answer

**Can random people write/edit/delete your KV via the endpoint?**

No

**Is the read API "secure" in the sense of private?**

Also no- it's a **public read API** by design. Security model = world-readable man pages, operator-only writes.

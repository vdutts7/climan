# Security

## Public write access: **No**

The live API is **read-only**. Arbitrary internet users **cannot** write, edit, or delete Postgres data through `climan.dev`.

| surface | methods | auth | public can mutate? |
|---------|---------|------|-------------------|
| `climan.dev` worker | GET only | none | **no** |
| Postgres via worker | SELECT only | Hyperdrive binding | **no** - no INSERT/UPDATE/DELETE routes |
| Postgres direct | DML | connection string | **no** - credentials not exposed |

## What the worker exposes

Audited routes in `worker.js`:

- `GET /`, `/pwsh`, `/pwsh/{cmdlet}`, `/ps/{cmdlet}`, `/search`, `/robots.txt`
- no POST, PUT, PATCH, DELETE
- no admin routes, no upload endpoints, no dynamic code exec

Writes happen only via:

- `seed_pwsh.py` with operator `CF_TOKEN` + `PGPASSWORD` (local machine)
- Azure portal / `psql` with database credentials (operator only)

## Read path posture

| property | value | note |
|----------|-------|------|
| data sensitivity | low | public PowerShell vendor docs |
| CORS | `Access-Control-Allow-Origin: *` | intentional public JSON API |
| cache | 24h public CDN | by design |
| rate limiting | none on worker | CF free tier; abuse = bandwidth cost |
| auth on read | none | intentional |

## Residual risks (not public-write)

| severity | finding | mitigation |
|----------|---------|------------|
| medium | `CF_TOKEN` + `PGPASSWORD` in operator `.env` | gitignore `.env`; rotate if leaked; scope CF token to Workers AI + deploy only |
| low | no rate limits | monitor CF metrics; upgrade plan if abused |
| low | `/pwsh` manifest dumps all 302 cmdlet names | public metadata, same as vendor docs |
| info | Hyperdrive ID in `wrangler.toml` | not a secret - config reference only |

## Secaudit summary (worker + wrangler)

Manual review of `worker.js`, `wrangler.toml`, seed scripts:

- **no injection surface** - path regex constrained; parameterized SQL via `postgres` driver
- **no secrets in repo** - credentials via `.env` only (gitignored)
- **no write bindings** exposed to fetch handler
- **seed scripts** require local env vars; not callable remotely

## Answer

**Can random people write/edit/delete your database via the endpoint?**

No

**Is the read API "secure" in the sense of private?**

Also no - it's a **public read API** by design. Security model = world-readable CLI docs, operator-only writes.

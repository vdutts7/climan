# Pitfalls

Forward-looking gotchas. Not a build diary.

## Egress proxy blocks `*.workers.dev`

**symptom:** curl returns HTTP 403, body `Host not in allowlist`, header `x-deny-reason: host_not_allowed`

**looks like:** endpoint down, cert issue, project misconfig

**actually:** fleet-level blocklist on some agent hosts; `Allowed Domains: *` in system prompt does not override it

**fix:** use custom domain `climan.dev`. Custom domains are not on the blanket blocklist

**detect:** grep response body for `Host not in allowlist`; exit code 2 in fetch cascade = proxy block, not endpoint failure

-> [egress-proxy.md](egress-proxy.md)

## Postgres SSL from local wrangler dev

**symptom:** `no pg_hba.conf entry for host "x.x.x.x", no encryption`

**cause:** local `wrangler dev` connects to Azure Postgres without SSL; Azure requires it

**fix:** test against deployed worker (`https://climan.dev`) or add firewall rule for your IP in Azure portal with `sslmode=require`

## Password with `!` in `.env`

**symptom:** seed script or shell fails to connect; password truncated at `!`

**cause:** unquoted or double-quoted `!` triggers history expansion in zsh/bash

**fix:** single-quote the password in `.env`: `PGPASSWORD='YourPass!123'`

## Embedding model mismatch

**symptom:** search returns wrong cmdlets or uniformly low scores after re-seed

**cause:** build-time embed used different model/pooling than query-time Workers AI

**fix:** both must be `@cf/baai/bge-base-en-v1.5` with `pooling=cls`. Re-seed entire corpus if changed.

## Hyperdrive connection limit

**symptom:** intermittent `db error` under load

**cause:** worker opens postgres client per request with `max: 1`; connection churn under burst

**fix:** expected at low traffic. For scale, tune Hyperdrive pool settings or add connection reuse pattern.

## Stale vectors after record edit

**symptom:** exact lookup correct, search ranks wrong cmdlet

**cause:** edited `content` or enrich data but did not re-run `seed_pwsh.py`

**fix:** `./scripts/deploy.sh` or `--skip-enrich` if only re-seed needed

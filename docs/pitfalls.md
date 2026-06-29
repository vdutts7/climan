# Pitfalls

Forward-looking gotchas. Not a build diary.

## Egress proxy blocks `*.workers.dev`

### Symptom

curl returns HTTP 403, body `Host not in allowlist`, header `x-deny-reason: host_not_allowed`

### Looks like

endpoint down, cert issue, project misconfig

### Actually

fleet-level blocklist on some agent hosts; `Allowed Domains: *` in system prompt does not override it

### Fix

use custom domain `climan.dev`. Custom domains are not on the blanket blocklist

### Detect

grep response body for `Host not in allowlist`; exit code 2 in fetch cascade = proxy block, not endpoint failure

-> [`egress-proxy.md`](egress-proxy%2Emd)

## Postgres SSL from local wrangler dev

### Symptom

`no pg_hba.conf entry for host "x.x.x.x", no encryption`

### Cause

local `wrangler dev` connects to Azure Postgres without SSL; Azure requires it

### Fix

test against deployed worker (`https://climan.dev`) or add firewall rule for your IP in Azure portal with `sslmode=require`

## Password with `!` in `.env`

### Symptom

seed script or shell fails to connect; password truncated at `!`

### Cause

unquoted or double-quoted `!` triggers history expansion in zsh/bash

### Fix

single-quote the password in `.env`: `PGPASSWORD='YourPass!123'`

## Embedding model mismatch

### Symptom

search returns wrong cmdlets or uniformly low scores after re-seed

### Cause

build-time embed used different model/pooling than query-time Workers AI

### Fix

both must be `@cf/baai/bge-base-en-v1.5` with `pooling=cls`. Re-seed entire corpus if changed.

## Hyperdrive connection limit

### Symptom

intermittent `db error` under load

### Cause

worker opens postgres client per request with `max: 1`; connection churn under burst

### Fix

expected at low traffic. For scale, tune Hyperdrive pool settings or add connection reuse pattern.

## Stale vectors after record edit

### Symptom

exact lookup correct, search ranks wrong cmdlet

### Cause

edited `content` or enrich data but did not re-run `seed_pwsh.py`

### Fix

`./scripts/deploy.sh` or `--skip-enrich` if only re-seed needed

# Pitfalls

Forward-looking gotchas. Not a build diary.

## Egress proxy blocks `*.workers.dev`

**symptom:** curl returns HTTP 403, body `Host not in allowlist`, header `x-deny-reason: host_not_allowed`

**looks like:** endpoint down, cert issue, project misconfig

**actually:** fleet-level blocklist on some agent hosts; `Allowed Domains: *` in system prompt does not override it

**fix:** deploy worker on a custom domain you own (`climan.dev`). Custom domains are not on the blanket blocklist

**detect:** grep response body for `Host not in allowlist`; exit code 2 in fetch cascade = proxy block, not endpoint failure

-> [egress-proxy.md](egress-proxy.md)

## `wrangler kv bulk put` without `--remote`

**symptom:** 500 Internal Server Error on bulk upload

**fix:** always pass `--remote`. Default targets local dev KV

## Parallel `wrangler kv bulk put`

**symptom:** race conditions; 3 of 4 chunks fail with 500

**fix:** sequential uploads only; no backgrounding with `&`

## ~15% extraction failures

**symptom:** `man-pages-extract.sh` reports 2,681 failed of 18,019 files

**cause:** compressed pages, symlinks, mandoc-incompatible formats

**severity:** expected. 15,299 usable entries is the full macOS CLI corpus

## `/mac/` 404 but `/man/` works

**symptom:** namespace route missing after domain setup

**cause:** worker code not deployed; custom domain wired but old handler still live

**fix:** deploy worker with `/mac/` routes (GUI Edit code or `wrangler deploy`)

## KV key prefix before multi-namespace

**symptom:** future `/linux` namespace collides with mac keys

**fix:** decide now: separate KV namespaces per corpus vs `{namespace}:` key prefix before shipping namespace #2

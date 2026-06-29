# Egress proxy and custom domains

## Why this exists

Agent sandboxes need live CLI docs without hallucination.

1. Cloudflare Worker + Postgres via Hyperdrive serves authoritative JSON
2. agents fetch over HTTP from inside containers with Anthropic egress proxy in the path

## What fails

```text
agent -> curl https://manpages.manpages.workers.dev/pwsh/Get-ChildItem
      -> TLS ok (O=Anthropic egress CA)
      -> HTTP 403 host_not_allowed
```

Same project, same curl, different container host -> sometimes works, sometimes blocked. Not deterministic from inside the container.

## What works

```text
agent -> curl https://climan.dev/pwsh/Get-ChildItem
      -> 200 JSON
```

Custom domain on same worker, same Postgres backend. Blocklist targets `*.workers.dev` (phishing abuse vector), not arbitrary owned domains.

## Practical rules for integrators

1. primary URL: custom domain (`climan.dev`)
2. fallback: `*.workers.dev` only when primary fails for non-proxy reasons
3. if all cascade clients return identical 403 + allowlist body -> classify as proxy block, not endpoint down
4. do not retry same URL hoping for different result on same container
5. do not invent explanations (cert rotation, project config) when proxy signature matches
6. last resort: user runs curl locally and pastes JSON

## Detection snippet

```bash
curl -s URL | grep -q 'Host not in allowlist' && echo L3_PROXY_BLOCK
```

## Scope

Applies to any agent/tooling that fetches external endpoints from Claude.ai-style containers.

1. not specific to climan
2. any `*.workers.dev` or likely `*.pages.dev` endpoint inherits the same risk

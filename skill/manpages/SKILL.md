---
name: manpages
description: >
  Live macOS man page lookup via Cloudflare Worker + KV at climan.dev.
  Fetches real man page content instead of hallucinating flags/syntax.
  Trigger on: /manpages, /man, any question about macOS CLI flags/options/syntax/behavior
  where Claude would otherwise guess. Also trigger when user asks "what does -X flag do",
  "how do I use networksetup", "what are the flags for defaults write", or any macOS
  command reference question. NOT for: Linux-only commands, Apple developer APIs, GUI docs.
---

# /manpages

## Mandatory (no bypass)

```yaml
run: bash scripts/lookup.sh {cmd}
forbidden_before_run: [web_search, web_fetch, answering from training data]
forbidden_on_nonzero_exit: [hallucinating flags or syntax]
ref: registry/lookup-cascade.json
```

## Exit codes (agent is a switch, not a reasoner)

| exit | action |
|------|--------|
| 0 | parse stdout JSON; answer ONLY from those fields |
| 1 | say not found; stop |
| 2 | say egress blocked; give stderr fallback curl cmd; stop |
| 3 | TW-003 blocked command; pick a different cmd; stop |

## Response fields (exit 0)

`cmd`, `section`, `name`, `synopsis`, `description`, `manpath`

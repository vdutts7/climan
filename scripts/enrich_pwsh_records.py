#!/usr/bin/env python3
"""
enrich_pwsh_records.py — merge vendor markdown param descriptions into pwsh data JSONs
reads:  ~/Documents/a/climan-namespaces/pwsh-namespace/data/*.json
merges: PowerShell-Docs/reference/7.4/{module}/{Cmdlet}.md
writes: enriched records back to data/*.json (in-place)

usage: python3 enrich_pwsh_records.py [--dry-run] [--limit N] [--cmdlet CmdletName]
"""

import json, sys, os, argparse
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_pwsh_md import parse_cmdlet_md

A = Path(os.environ.get("A", Path.home() / "Documents/a"))
DATA_DIR   = A / "climan-namespaces/pwsh-namespace/data"
VENDOR_DIR = A / "climan-namespaces/pwsh-namespace/corpus/vendor/PowerShell-Docs/reference/7.4"

def find_md(cmdlet, module):
    if module:
        p = VENDOR_DIR / module / f"{cmdlet}.md"
        if p.exists():
            return p
    for d in VENDOR_DIR.iterdir():
        if not d.is_dir():
            continue
        p = d / f"{cmdlet}.md"
        if p.exists():
            return p
    return None

def enrich(rec, md_path):
    parsed = parse_cmdlet_md(md_path)

    # description
    if parsed["description"] and len(parsed["description"]) > len(rec.get("description", "")):
        rec["description"] = parsed["description"]

    # parameters — guard against malformed records where parameters is not a list of dicts
    md_params = {p["name"]: p for p in parsed["parameters"]}
    raw_params = rec.get("parameters", [])
    if not isinstance(raw_params, list):
        raw_params = []
    # filter to dicts only — some records have strings or nested structures
    existing = {}
    for p in raw_params:
        if isinstance(p, dict) and "name" in p:
            existing[p["name"]] = p

    merged = []
    for name, ep in existing.items():
        mp = md_params.get(name, {})
        merged.append({
            "name":           name,
            "description":    mp.get("description", ""),
            "type":           mp.get("type") or ep.get("type", ""),
            "type_full":      mp.get("type_full") or ep.get("type", ""),
            "required":       mp.get("required", ep.get("mandatory", False)),
            "position":       mp.get("position", "Named"),
            "default":        mp.get("default", ""),
            "pipeline_input": mp.get("pipeline_input", False),
            "wildcard":       mp.get("wildcard", False),
            "aliases":        mp.get("aliases", []),
        })

    for name, mp in md_params.items():
        if name not in existing:
            merged.append(mp)

    rec["parameters"] = merged

    if parsed["examples"]:
        rec["examples"] = parsed["examples"]

    if parsed["links"]:
        rec["see_also"] = parsed["links"]

    return rec


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit",   type=int, default=0)
    parser.add_argument("--cmdlet",  type=str, default="")
    args = parser.parse_args()

    json_files = sorted(DATA_DIR.glob("*.json"))
    if args.cmdlet:
        json_files = [f for f in json_files if f.stem == args.cmdlet]
    if args.limit:
        json_files = json_files[:args.limit]

    ok = skip = fail = 0

    for jf in json_files:
        try:
            rec = json.loads(jf.read_text())
        except Exception as e:
            print(f"🔴 {jf.stem}: bad JSON: {e}")
            fail += 1
            continue

        cmdlet = rec.get("cmdlet") or rec.get("cmd") or jf.stem
        module = rec.get("module", "")

        md_path = find_md(cmdlet, module)
        if not md_path:
            print(f"🌕 no md found: {cmdlet}")
            skip += 1
            continue

        try:
            enriched = enrich(rec, md_path)
        except Exception as e:
            print(f"🔴 {cmdlet}: {e}")
            fail += 1
            continue

        params_with_desc = sum(1 for p in enriched.get("parameters", []) if p.get("description"))
        total_params     = len(enriched.get("parameters", []))

        if args.dry_run:
            print(f"🟢 {cmdlet}: {params_with_desc}/{total_params} params have descriptions")
            for p in enriched.get("parameters", []):
                if p.get("description"):
                    print(f"   -{p['name']}: {p['description'][:80]}")
                    break
        else:
            jf.write_text(json.dumps(enriched, indent=2, ensure_ascii=False))
            print(f"🟢 {cmdlet}: {params_with_desc}/{total_params} params enriched")
            ok += 1

    print(f"\n{'dry-run' if args.dry_run else 'done'}: ok={ok} skip={skip} fail={fail} / {len(json_files)} total")


if __name__ == "__main__":
    main()

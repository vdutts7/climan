#!/usr/bin/env python3
"""
seed_pwsh.py — seed enriched pwsh records into Azure Postgres
reads:  ~/Documents/a/climan-namespaces/pwsh-namespace/data/*.json (post-enrich)
embeds: two vectors per record via Workers AI bge-base-en-v1.5
writes: docs table in Azure Postgres

usage: python3 seed_pwsh.py [--limit N] [--dry-run]

env vars required:
  CF_ACCOUNT   Cloudflare account ID
  CF_TOKEN     Cloudflare API token (Workers AI)
  PGPASSWORD   Azure Postgres password
"""

import os, json, sys, time, pathlib, re, requests, psycopg2, argparse
from pathlib import Path

# ── config ────────────────────────────────────────────────────────────────────
A          = Path(os.environ.get("A", Path.home() / "Documents/a"))
DATA_DIR   = A / "climan-namespaces/pwsh-namespace/data"
EMBED_URL  = "https://api.cloudflare.com/client/v4/accounts/{acct}/ai/run/@cf/baai/bge-base-en-v1.5"
BATCH_SIZE = 50
SKIP_PARAMS = {
    "Verbose","Debug","ErrorAction","WarningAction","InformationAction",
    "ErrorVariable","WarningVariable","InformationVariable","OutVariable",
    "OutBuffer","PipelineVariable","WhatIf","Confirm","ProgressAction",
}

ALIASES = {
    "Get-ChildItem":    ["gci","ls","dir"],
    "Get-Content":      ["gc","cat","type"],
    "Get-Process":      ["gps","ps"],
    "Stop-Process":     ["kill","spps"],
    "Set-Location":     ["cd","sl","chdir"],
    "Get-Location":     ["pwd","gl"],
    "Copy-Item":        ["cp","copy","cpi"],
    "Move-Item":        ["mv","move","mi"],
    "Remove-Item":      ["rm","rmdir","del","erase","rd","ri"],
    "New-Item":         ["ni"],
    "Get-Alias":        ["gal"],
    "Get-Command":      ["gcm"],
    "Get-Help":         ["help","man"],
    "Get-Member":       ["gm"],
    "Get-Variable":     ["gv"],
    "Set-Variable":     ["sv","set"],
    "Write-Output":     ["echo","write"],
    "Where-Object":     ["where","?"],
    "ForEach-Object":   ["%","foreach"],
    "Select-Object":    ["select"],
    "Sort-Object":      ["sort"],
    "Select-String":    ["sls"],
    "Invoke-WebRequest":["iwr","wget","curl"],
    "Invoke-Expression":["iex"],
    "Get-Item":         ["gi"],
    "Set-Item":         ["si"],
    "Clear-Host":       ["cls","clear"],
    "Get-History":      ["h","history"],
    "Invoke-History":   ["r","ihy"],
    "Push-Location":    ["pushd"],
    "Pop-Location":     ["popd"],
    "Out-Host":         ["oh"],
    "ForEach-Object":   ["%","foreach"],
    "Tee-Object":       ["tee"],
    "Measure-Object":   ["measure"],
    "Compare-Object":   ["diff","compare"],
    "Group-Object":     ["group"],
    "Format-Table":     ["ft"],
    "Format-List":      ["fl"],
    "Format-Wide":      ["fw"],
    "Format-Custom":    ["fc"],
}

CATEGORIES = {
    "file-system":   ["ChildItem","Item","Content","Path","File","Directory","Archive","Compress","Expand","Catalog"],
    "process":       ["Process","Job","Thread"],
    "network":       ["WebRequest","RestMethod","Connection","Uri","WSMan","NetTCP"],
    "string":        ["String","Format","Join","Split","Replace","Match"],
    "data":          ["Object","Property","Member","Sort","Group","Measure","Compare","ConvertTo","ConvertFrom","Select"],
    "system":        ["Service","EventLog","HotFix","ComputerInfo","Restart","Computer","TimeZone"],
    "security":      ["Acl","Credential","SecureString","Certificate","Signature","CmsMessage","ExecutionPolicy"],
    "session":       ["PSSession","PSHost","Runspace","PSBreakpoint"],
    "module":        ["Module","Command","Alias","Function","Script","ModuleManifest"],
    "output":        ["Write","Out-","Tee","Format-","Host","Debug","Verbose","Warning","Error","Progress"],
    "flow":          ["ForEach","Where","Select","Measure","Group","Sort"],
    "event":         ["Event","Subscriber","CimIndication","WinEvent"],
    "environment":   ["Variable","Env","Path","Location","PSDrive","PSProvider"],
    "datetime":      ["Date","Time","Sleep","Uptime","TimeSpan"],
    "xml-json":      ["Xml","Json","Csv","Clixml","StringData","Html"],
    "cim-wmi":       ["Cim","WinEvent"],
    "history":       ["History","Transcript"],
    "clipboard":     ["Clipboard"],
    "markdown":      ["Markdown"],
}

STDIN_MAP = {
    True:  "objects",
    False: "none",
}
STDOUT_MAP = {
    "Get": "objects",
    "New": "objects",
    "Set": "none",
    "Remove": "none",
    "Clear": "none",
    "Copy": "objects",
    "Move": "objects",
    "Rename": "objects",
    "Test": "bool",
    "Convert": "objects",
    "Export": "none",
    "Import": "objects",
    "Write": "none",
    "Out":   "none",
    "Format": "objects",
    "Select": "objects",
    "Where":  "objects",
    "Sort":   "objects",
    "Group":  "objects",
    "Measure":"objects",
    "Invoke": "objects",
    "Start":  "objects",
    "Stop":   "none",
    "Wait":   "objects",
}

def infer_categories(cmdlet, desc):
    text = (cmdlet + " " + desc).lower()
    cats = []
    for cat, kws in CATEGORIES.items():
        if any(kw.lower() in text for kw in kws):
            cats.append(cat)
    return cats[:6] or ["utility"]

def infer_pipe(cmdlet, verb):
    stdin = "objects" if verb not in ("New","Clear","Start","Enable","Disable","Set") else "none"
    stdout = STDOUT_MAP.get(verb, "objects")
    pipe_into = ["Where-Object","ForEach-Object","Sort-Object","Select-Object",
                 "Format-Table","Out-File","Export-Csv"] if stdout != "none" else []
    pipe_from = ["Get-ChildItem","Get-Process","Get-Service","Select-Object",
                 "Where-Object"] if stdin != "none" else []
    return stdin, stdout, pipe_into[:5], pipe_from[:4]

def build_embed_func(rec):
    cmdlet = rec.get("cmdlet","")
    verb   = rec.get("verb","")
    noun   = rec.get("noun","")
    module = rec.get("module","")
    desc   = re.sub(r"`([^`]+)`", r"\1", rec.get("description",""))
    desc   = re.sub(r"\*\*([^*]+)\*\*", r"\1", desc)
    desc   = " ".join(desc.split())[:500]
    aliases = ALIASES.get(cmdlet, [])
    cats   = infer_categories(cmdlet, desc)

    parts = [f"{cmdlet} \u2014 {verb} {noun}"]
    if desc:
        parts.append(desc)
    if module:
        parts.append(f"Module: {module}")
    if aliases:
        parts.append(f"Alias: {', '.join(aliases)}")
    parts.append(f"Categories: {', '.join(cats)}")
    return " ".join(parts)[:1800]

TYPE_PROSE = {
    "SwitchParameter":  "boolean switch flag",
    "String[]":         "one or more string values",
    "String":           "string value",
    "UInt32":           "unsigned integer",
    "Int32":            "integer",
    "Int64":            "integer",
    "ActionPreference": "error handling: Stop Continue SilentlyContinue Inquire",
    "PSObject":         "pipeline objects",
    "PSObject[]":       "pipeline objects",
    "Object":           "any object",
    "Object[]":         "array of objects",
    "ScriptBlock":      "script block { }",
    "Hashtable":        "hashtable @{}",
    "Boolean":          "true or false",
}

def type_prose(t):
    for k, v in TYPE_PROSE.items():
        if k in t:
            return v
    return t.split(".")[-1].strip("[]`1234567890[],")

def build_embed_flags(rec):
    cmdlet = rec.get("cmdlet","")
    params = rec.get("parameters",[])
    parts  = [f"{cmdlet} parameters:"]
    for p in params:
        if not isinstance(p, dict):
            continue
        name = p.get("name","")
        if name in SKIP_PARAMS or not name:
            continue
        desc = p.get("description","").strip()
        typ  = type_prose(p.get("type_full") or p.get("type",""))
        req  = "required" if p.get("required") else "optional"
        if desc:
            parts.append(f"-{name}: {desc[:120]} ({typ}, {req})")
        else:
            parts.append(f"-{name}: {typ}, {req}")
    if len(parts) < 3:
        # fallback: use raw synopsis
        syn = (rec.get("synopsis","") or "").split("\n")[0][:400]
        if syn:
            parts.append(f"Syntax: {syn}")
    return " ".join(parts)[:1800]

# ── Workers AI ────────────────────────────────────────────────────────────────
def embed_batch(texts, acct, token):
    url = EMBED_URL.format(acct=acct)
    r = requests.post(
        url,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"text": texts, "pooling": "cls"},
        timeout=60,
    )
    r.raise_for_status()
    d = r.json()
    if not d.get("success"):
        raise RuntimeError(f"Workers AI error: {d}")
    return d["result"]["data"]

def embed_all(texts, acct, token):
    out = []
    for i in range(0, len(texts), BATCH_SIZE):
        batch = texts[i:i+BATCH_SIZE]
        print(f"  🌕 batch {i//BATCH_SIZE+1}/{(len(texts)-1)//BATCH_SIZE+1} ({len(batch)} texts)...")
        out.extend(embed_batch(batch, acct, token))
        if i + BATCH_SIZE < len(texts):
            time.sleep(0.3)
    return out

# ── main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit",   type=int, default=0)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    CF_ACCOUNT = os.environ["CF_ACCOUNT"]
    CF_TOKEN   = os.environ["CF_TOKEN"]
    PGPASSWORD = os.environ["PGPASSWORD"]
    PGHOST     = os.environ.get("PGHOST", "climan-db.postgres.database.azure.com")
    PGUSER     = os.environ.get("PGUSER", "climanadmin")

    files = sorted(DATA_DIR.glob("*.json"))
    if args.limit:
        files = files[:args.limit]
    # skip manifest
    files = [f for f in files if f.stem != "manifest"]

    records = []
    for f in files:
        try:
            records.append(json.loads(f.read_text()))
        except Exception as e:
            print(f"🔴 skip {f.stem}: {e}")

    print(f"🌕 loaded {len(records)} records")

    # build text blobs
    func_texts  = [build_embed_func(r)  for r in records]
    flags_texts = [build_embed_flags(r) for r in records]

    if args.dry_run:
        print("\n--- dry run: first 3 records ---")
        for i in range(min(3, len(records))):
            cmdlet = records[i].get("cmdlet","?")
            print(f"\n[{cmdlet}]")
            print(f"embed_func:  {func_texts[i][:200]}")
            print(f"embed_flags: {flags_texts[i][:200]}")
        return

    # embed
    print(f"🌕 embedding {len(records)} embed_func texts...")
    t0 = time.time()
    vec_func  = embed_all(func_texts,  CF_ACCOUNT, CF_TOKEN)
    print(f"🟢 vec_func done in {time.time()-t0:.1f}s")

    print(f"🌕 embedding {len(records)} embed_flags texts...")
    t0 = time.time()
    vec_flags = embed_all(flags_texts, CF_ACCOUNT, CF_TOKEN)
    print(f"🟢 vec_flags done in {time.time()-t0:.1f}s")

    # connect
    print(f"🌕 connecting to {PGHOST}...")
    conn = psycopg2.connect(
        host=PGHOST, user=PGUSER, password=PGPASSWORD,
        dbname="postgres", sslmode="require", connect_timeout=10,
    )
    conn.autocommit = False
    cur = conn.cursor()

    print(f"🌕 upserting {len(records)} rows...")
    inserted = 0
    for rec, ef, el, vf, vl in zip(records, func_texts, flags_texts, vec_func, vec_flags):
        cmdlet   = rec.get("cmdlet","")
        if not cmdlet:
            continue
        verb     = rec.get("verb","")
        noun     = rec.get("noun","")
        module   = rec.get("module","")
        desc     = rec.get("description","")
        synopsis = f"{cmdlet} \u2014 {desc[:120]}" if desc else cmdlet
        sig      = (rec.get("synopsis","") or "").split("\n")[0][:500]
        cats     = infer_categories(cmdlet, desc)
        aliases  = ALIASES.get(cmdlet, [])
        flags_j  = json.dumps([
            {k: v for k, v in p.items()}
            for p in rec.get("parameters",[])
            if isinstance(p, dict) and p.get("name","") not in SKIP_PARAMS
        ])
        examples_j = json.dumps(rec.get("examples", []))
        see_also   = rec.get("see_also", [])
        stdin_acc, stdout_sh, pipe_into, pipe_from = infer_pipe(cmdlet, verb)

        vf_str = "[" + ",".join(str(x) for x in vf) + "]"
        vl_str = "[" + ",".join(str(x) for x in vl) + "]"

        cur.execute("""
            INSERT INTO docs (
              ns, key, content, synopsis, signature, description,
              embed_func, embed_flags, vec_func, vec_flags,
              categories, aliases, flags, examples,
              module, platform, version, source,
              stdin_accepts, stdout_shape, pipe_into, pipe_from,
              see_also, scraped_at
            ) VALUES (
              'pwsh', %s, %s::jsonb, %s, %s, %s,
              %s, %s, %s::vector, %s::vector,
              %s, %s, %s::jsonb, %s::jsonb,
              %s, 'pwsh7', '7.4', 'powershell-docs-7.4',
              %s, %s, %s, %s,
              %s, now()
            )
            ON CONFLICT (ns, key) DO UPDATE SET
              content       = EXCLUDED.content,
              synopsis      = EXCLUDED.synopsis,
              signature     = EXCLUDED.signature,
              description   = EXCLUDED.description,
              embed_func    = EXCLUDED.embed_func,
              embed_flags   = EXCLUDED.embed_flags,
              vec_func      = EXCLUDED.vec_func,
              vec_flags     = EXCLUDED.vec_flags,
              categories    = EXCLUDED.categories,
              aliases       = EXCLUDED.aliases,
              flags         = EXCLUDED.flags,
              examples      = EXCLUDED.examples,
              module        = EXCLUDED.module,
              stdin_accepts = EXCLUDED.stdin_accepts,
              stdout_shape  = EXCLUDED.stdout_shape,
              pipe_into     = EXCLUDED.pipe_into,
              pipe_from     = EXCLUDED.pipe_from,
              see_also      = EXCLUDED.see_also,
              scraped_at    = now()
        """, (
            cmdlet, json.dumps(rec), synopsis, sig, desc,
            ef, el, vf_str, vl_str,
            cats, aliases, flags_j, examples_j,
            module,
            stdin_acc, stdout_sh, pipe_into, pipe_from,
            see_also,
        ))
        inserted += 1

    conn.commit()
    cur.close()
    conn.close()
    print(f"🟢 upserted {inserted} rows into docs (ns=pwsh)")

if __name__ == "__main__":
    main()

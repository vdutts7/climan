#!/usr/bin/env python3
"""
parse_pwsh_md.py — extract parameter descriptions from PowerShell-Docs vendor markdown
usage: python3 parse_pwsh_md.py <path-to-cmdlet.md>
"""

import re, sys, yaml
from pathlib import Path


def parse_cmdlet_md(md_path) -> dict:
    """
    Parse a PowerShell-Docs markdown file and return structured data.
    Returns:
      description: str  — DESCRIPTION section prose
      parameters: list  — [{name, description, type, required, position, default,
                             pipeline_input, wildcard, aliases}]
      examples: list    — [{title, code, description}]
      links: list       — related link strings
    """
    text = Path(md_path).read_text(encoding="utf-8")
    return {
        "description": _extract_description(text),
        "parameters":  _extract_parameters(text),
        "examples":    _extract_examples(text),
        "links":       _extract_links(text),
    }


def _extract_description(text: str) -> str:
    """Extract prose from ## DESCRIPTION section."""
    m = re.search(r"## DESCRIPTION\n+(.*?)(?=\n## |\Z)", text, re.DOTALL)
    if not m:
        return ""
    raw = m.group(1).strip()
    # strip markdown: backticks, bold, links, HTML
    raw = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", raw)  # [text](url) → text
    raw = re.sub(r"`([^`]+)`", r"\1", raw)               # `code` → code
    raw = re.sub(r"\*\*([^*]+)\*\*", r"\1", raw)         # **bold** → bold
    raw = re.sub(r"<[^>]+>", "", raw)                    # <tags>
    raw = re.sub(r"\n{3,}", "\n\n", raw)
    return raw.strip()[:800]


def _extract_parameters(text: str) -> list:
    """
    Extract each ### -{Name} parameter block.
    Structure:
      ### -ParamName
      
      Prose description paragraph
      
      ```yaml
      Type: ...
      Required: ...
      Position: ...
      Default value: ...
      Accept pipeline input: ...
      Accept wildcard characters: ...
      ```
    """
    # skip common params that add noise to embed_flags
    SKIP = {
        "Verbose", "Debug", "ErrorAction", "WarningAction", "InformationAction",
        "ErrorVariable", "WarningVariable", "InformationVariable", "OutVariable",
        "OutBuffer", "PipelineVariable", "WhatIf", "Confirm", "ProgressAction",
    }

    params = []
    # split on ### - headings
    blocks = re.split(r"\n### -", text)

    for block in blocks[1:]:  # skip everything before first param
        lines = block.split("\n")
        name = lines[0].strip()
        if name in SKIP:
            continue

        rest = "\n".join(lines[1:])

        # prose description: text before the yaml block
        yaml_match = re.search(r"```yaml\n(.*?)```", rest, re.DOTALL)
        if yaml_match:
            desc_raw = rest[:yaml_match.start()].strip()
            yaml_raw = yaml_match.group(1)
        else:
            desc_raw = rest.strip()
            yaml_raw = ""

        # clean description
        desc = re.sub(r"> \[!NOTE\][^\n]*\n", "", desc_raw)   # strip NOTE callouts
        desc = re.sub(r"> ", "", desc)                          # strip blockquote markers
        desc = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", desc)
        desc = re.sub(r"`([^`]+)`", r"\1", desc)
        desc = re.sub(r"\*\*([^*]+)\*\*", r"\1", desc)
        desc = re.sub(r"<[^>]+>", "", desc)
        desc = " ".join(desc.split())[:300]

        # parse yaml block
        meta = {}
        if yaml_raw:
            try:
                meta = yaml.safe_load(yaml_raw) or {}
            except Exception:
                # fallback: manual parse
                for line in yaml_raw.splitlines():
                    if ":" in line:
                        k, _, v = line.partition(":")
                        meta[k.strip()] = v.strip()

        # normalize type — strip generic brackets and take last segment
        raw_type = str(meta.get("Type", ""))
        raw_type = re.sub(r"`\d+\[.*?\]", "", raw_type)         # strip `1[...] generics
        type_simple = raw_type.split(".")[-1].strip("[]") if raw_type else ""

        # normalize required
        req_raw = str(meta.get("Required", "false")).lower()
        required = req_raw in ("true", "yes", "1")

        # normalize pipeline input
        pip_raw = str(meta.get("Accept pipeline input", "false")).lower()
        pipeline_input = "true" in pip_raw or "byvalue" in pip_raw or "bypropertyname" in pip_raw

        params.append({
            "name":           name,
            "description":    desc,
            "type":           type_simple,
            "type_full":      raw_type,
            "required":       required,
            "position":       str(meta.get("Position", "Named")).strip(),
            "default":        str(meta.get("Default value", "")).strip(),
            "pipeline_input": pipeline_input,
            "wildcard":       str(meta.get("Accept wildcard characters", "false")).lower() in ("true", "yes"),
            "aliases":        [a.strip() for a in str(meta.get("Aliases", "")).split(",") if a.strip() and a.strip() != "None"],
        })

    return params


def _extract_examples(text: str) -> list:
    """Extract ## EXAMPLES blocks."""
    examples = []
    section = re.search(r"## EXAMPLES\n+(.*?)(?=\n## |\Z)", text, re.DOTALL)
    if not section:
        return examples

    ex_blocks = re.split(r"\n### Example \d+", section.group(1))
    for block in ex_blocks[1:]:
        lines = block.strip().split("\n")
        title = lines[0].strip(" -:") if lines else ""
        code_m = re.search(r"```(?:powershell|ps1|)?\n(.*?)```", block, re.DOTALL)
        code = code_m.group(1).strip() if code_m else ""
        # description: text outside code blocks
        desc_raw = re.sub(r"```.*?```", "", block, flags=re.DOTALL).strip()
        desc_raw = re.sub(r"\*\*([^*]+)\*\*", r"\1", desc_raw)
        desc = " ".join(desc_raw.split())[:300]
        if title or code:
            examples.append({"title": title[:100], "code": code[:500], "description": desc})

    return examples[:8]


def _extract_links(text: str) -> list:
    """Extract RELATED LINKS section."""
    m = re.search(r"## RELATED LINKS\n+(.*?)(?=\n## |\Z)", text, re.DOTALL)
    if not m:
        return []
    links = re.findall(r"\[([^\]]+)\]", m.group(1))
    return [l for l in links if l and not l.startswith("http")][:10]


# ── CLI ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import json
    if len(sys.argv) < 2:
        print("usage: python3 parse_pwsh_md.py <path/to/Cmdlet.md>")
        sys.exit(1)
    result = parse_cmdlet_md(sys.argv[1])
    print(json.dumps(result, indent=2))

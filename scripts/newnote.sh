#!/usr/bin/env bash
# Build reading notes + review + index, and auto-sync citation_key from refs/library.bib
set -euo pipefail
umask 022
shopt -s nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"

mkdir -p notes-html
[[ -d filters ]] || mkdir -p filters
[[ -d assets  ]] || mkdir -p assets
[[ -d notes   ]] || mkdir -p notes
[[ -d refs    ]] || mkdir -p refs

if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc not found on PATH." >&2; exit 1
fi
if [[ ! -f "$BIB_PATH" ]]; then
  echo "Error: bibliography not found: $BIB_PATH" >&2; exit 1
fi

TEMPLATE_ARG=()
[[ -f assets/note.html   ]] && TEMPLATE_ARG=(--template assets/note.html)

REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)

[[ -f assets/notes.css   ]] && cp -f assets/notes.css notes-html/notes.css

FILTER_ARGS=()
[[ -f filters/strip-leading-citation.lua ]] && FILTER_ARGS+=(--lua-filter=filters/strip-leading-citation.lua)
[[ -f filters/citations-in-lists.lua     ]] && FILTER_ARGS+=(--lua-filter=filters/citations-in-lists.lua)
[[ -f filters/sentence-case-title.lua    ]] && FILTER_ARGS+=(--lua-filter=filters/sentence-case-title.lua)

EXTRA_FLAGS=()
if [[ -n "${PANDOC_EXTRA_FLAGS:-}" ]]; then EXTRA_FLAGS=(${PANDOC_EXTRA_FLAGS}); fi
[[ " ${EXTRA_FLAGS[*]-} " != *" --citeproc "* ]] && EXTRA_FLAGS+=(--citeproc)
[[ " ${EXTRA_FLAGS[*]-} " != *" --metadata link-citations=true "* ]] && EXTRA_FLAGS+=(--metadata link-citations=true)

note_files=(notes/reading-notes/*.md)

# ------------------------------------------------------------------------------
# 0) Auto-sync citation_key in YAML from refs/library.bib (by DOI/URL/title/author+year)
# ------------------------------------------------------------------------------
/usr/bin/env python3 - "$BIB_PATH" "${note_files[@]}" <<'PY'
import re, sys, json, pathlib

def load_bib(path):
    txt = pathlib.Path(path).read_text(encoding='utf-8',errors='ignore')
    chunks = re.split(r'(?m)^(?=@)', txt)
    entries=[]
    for ch in chunks:
        m = re.match(r'@\s*([^{(]+)\s*[\{\(]\s*([^,\s]+)', ch)
        if not m: continue
        key = m.group(2)
        fields={}
        for fm in re.finditer(r'([a-zA-Z]+)\s*=\s*({([^{}]*|{[^}]*})*}|"([^"]*)")\s*,?', ch, re.S):
            name=fm.group(1).lower()
            val = fm.group(3) if fm.group(3) is not None else (fm.group(4) or "")
            fields[name]=val.strip()
        entries.append((key,fields))
    return entries

def norm(s): return re.sub(r'[^a-z0-9]+','', s.lower())

def surname_first(author_field):
    # take first "Surname" token
    if not author_field: return ""
    first = author_field.split(' and ')[0]
    # handle "Surname, Given"
    if ',' in first:
        return first.split(',',1)[0].strip()
    return first.split()[-1].strip()

bib = sys.argv[1]
notes = sys.argv[2:]

entries = load_bib(bib)
by_key = {k:k for k,_ in entries}
by_doi = {norm(f.get('doi','')): k for k,f in entries if f.get('doi')}
by_url = {}
for k,f in entries:
    u=f.get('url','')
    if u: by_url[norm(u)] = k
by_title_year = {}
by_author_year = {}
for k,f in entries:
    t = norm(f.get('title',''))
    y = re.sub(r'\D+','', f.get('year',''))
    if t and y: by_title_year[(t,y)] = k
    ay = (norm(surname_first(f.get('author',''))), y)
    if ay[0] and ay[1]: by_author_year[ay] = k

def read_yaml_head(p):
    s = pathlib.Path(p).read_text(encoding='utf-8')
    m = re.match(r'^---\n(.*?)\n---\n', s, re.S)
    return (m.group(1), s[m.end():]) if m else ("", s)

def parse_yaml_block(y):
    out={}
    for line in y.splitlines():
        if not line.strip() or line.strip().startswith('#'): continue
        m=re.match(r'^([A-Za-z0-9_-]+)\s*:\s*"(.*)"\s*$', line)
        if not m: m=re.match(r'^([A-Za-z0-9_-]+)\s*:\s*(.*)$', line)
        if m: out[m.group(1)] = m.group(2).strip()
    return out

def write_yaml(p, meta, body):
    # keep existing order where possible
    keys = ["title","authors","year","journal","citation_key","doi","url",
            "bibliography","csl","link-citations"]
    lines=["---"]
    for k in keys:
        if k in meta:
            v=str(meta[k])
            if re.search(r'[:#"]|\s', v): lines.append(f'{k}: "{v}"')
            else: lines.append(f'{k}: {v}')
    # include any extra keys
    for k,v in meta.items():
        if k in keys: continue
        if re.search(r'[:#"]|\s', v): lines.append(f'{k}: "{v}"')
        else: lines.append(f'{k}: {v}')
    lines.append('---')
    pathlib.Path(p).write_text('\n'.join(lines)+ '\n' + body, encoding='utf-8')

changed = False
for n in notes:
    path = pathlib.Path(n)
    if not path.exists(): continue
    yml, body = read_yaml_head(path)
    if not yml: continue
    meta = parse_yaml_block(yml)

    cite = meta.get("citation_key","").strip()
    if cite and cite in by_key:
        continue  # already correct

    # Try to discover the correct key
    found = None
    if not found and meta.get("doi"):
        found = by_doi.get(norm(meta["doi"]))
    if not found and meta.get("url"):
        found = by_url.get(norm(meta["url"]))
    if not found and meta.get("title") and meta.get("year"):
        found = by_title_year.get((norm(meta["title"]), re.sub(r'\D+','',meta["year"])))
    if not found and meta.get("authors") and meta.get("year"):
        first = meta["authors"].split(' and ')[0].split(',')[0].strip() if ',' in meta["authors"] else meta["authors"].split()[ -1]
        found = by_author_year.get((norm(first), re.sub(r'\D+','',meta["year"])))

    if found:
        # fill/overwrite with trusted bib data for accuracy
        k, f = next((kk,ff) for kk,ff in entries if kk==found)
        meta["citation_key"] = k
        meta["title"]   = meta.get("title")   or f.get("title","")
        meta["authors"] = meta.get("authors") or f.get("author","")
        meta["year"]    = meta.get("year")    or f.get("year","")
        meta["journal"] = meta.get("journal") or f.get("journal","") or f.get("booktitle","") or f.get("publisher","")
        meta["doi"]     = meta.get("doi")     or f.get("doi","")
        meta["url"]     = meta.get("url")     or f.get("url","")
        write_yaml(path, meta, body)
        changed = True

if changed:
    print("Synchronized citation_key from bibliography for some notes.")
PY
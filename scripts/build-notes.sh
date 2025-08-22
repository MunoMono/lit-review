#!/usr/bin/env bash
# Build reading notes + literature review + index.
# Auto-syncs citation_key in each note from refs/library.bib (by DOI/URL/title/author+year).

set -euo pipefail
umask 022
shopt -s nullglob

# ── Repo root & config ─────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"

mkdir -p notes-html
[[ -d filters ]] || mkdir -p filters
[[ -d assets  ]] || mkdir -p assets
[[ -d notes   ]] || mkdir -p notes
[[ -d refs    ]] || mkdir -p refs

command -v pandoc >/dev/null 2>&1 || { echo "Error: pandoc not found on PATH." >&2; exit 1; }
[[ -f "$BIB_PATH" ]] || { echo "Error: bibliography not found: $BIB_PATH" >&2; exit 1; }

# Optional assets/templates
TEMPLATE_ARG=()
[[ -f assets/note.html   ]] && TEMPLATE_ARG=(--template assets/note.html)
REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)
[[ -f assets/notes.css   ]] && cp -f assets/notes.css notes-html/notes.css

# Optional Lua filters
FILTER_ARGS=()
[[ -f filters/strip-leading-citation.lua ]] && FILTER_ARGS+=(--lua-filter=filters/strip-leading-citation.lua)
[[ -f filters/citations-in-lists.lua     ]] && FILTER_ARGS+=(--lua-filter=filters/citations-in-lists.lua)
[[ -f filters/keep-refs.lua              ]] && FILTER_ARGS+=(--lua-filter=filters/keep-refs.lua)
[[ -f filters/sentence-case-title.lua    ]] && FILTER_ARGS+=(--lua-filter=filters/sentence-case-title.lua)
[[ -f filters/hide-citekey.lua ]] && FILTER_ARGS+=(--lua-filter=filters/hide-citekey.lua)

# Pandoc flags (citeproc + link-citations by default)
EXTRA_FLAGS=()
if [[ -n "${PANDOC_EXTRA_FLAGS:-}" ]]; then EXTRA_FLAGS=(${PANDOC_EXTRA_FLAGS}); fi
[[ " ${EXTRA_FLAGS[*]-} " != *" --citeproc "* ]] && EXTRA_FLAGS+=(--citeproc)
[[ " ${EXTRA_FLAGS[*]-} " != *" --metadata link-citations=true "* ]] && EXTRA_FLAGS+=(--metadata link-citations=true)

# Source notes
note_files=(notes/reading-notes/*.md)

# ------------------------------------------------------------------------------
# 0) Auto-sync citation_key in YAML from refs/library.bib (by DOI/URL/title/author+year)
# ------------------------------------------------------------------------------
/usr/bin/env python3 - "$BIB_PATH" "${note_files[@]}" <<'PY'
import re, sys, pathlib

def load_bib(path):
    txt = pathlib.Path(path).read_text(encoding='utf-8', errors='ignore')
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

def norm(s): return re.sub(r'[^a-z0-9]+','', (s or '').lower())

def surname_first(author_field):
    if not author_field: return ""
    first = author_field.split(' and ')[0]
    if ',' in first:
        return first.split(',',1)[0].strip()
    parts = first.split()
    return parts[-1].strip() if parts else ""

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
    keys = ["title","authors","year","journal","citation_key","doi","url",
            "bibliography","csl","link-citations"]
    lines=["---"]
    seen=set()
    for k in keys:
        if k in meta:
            v=str(meta[k]); seen.add(k)
            lines.append(f'{k}: "{v}"' if re.search(r'[:#"]|\s', v) else f'{k}: {v}')
    for k,v in meta.items():
        if k in seen: continue
        vv=str(v)
        lines.append(f'{k}: "{vv}"' if re.search(r'[:#"]|\s', vv) else f'{k}: {vv}')
    lines.append('---')
    pathlib.Path(p).write_text('\n'.join(lines)+ '\n' + body, encoding='utf-8')

bib_path = sys.argv[1]
notes = sys.argv[2:]
entries = load_bib(bib_path)

# lookups
by_key = {k:k for k,_ in entries}
by_doi = {norm(f.get('doi')): k for k,f in entries if f.get('doi')}
by_url = {norm(f.get('url')): k for k,f in entries if f.get('url')}
by_title_year = {}
by_author_year = {}
for k,f in entries:
    t = norm(f.get('title'))
    y = re.sub(r'\D+','', f.get('year',''))
    if t and y: by_title_year[(t,y)] = k
    ay = (norm(surname_first(f.get('author'))), y)
    if ay[0] and ay[1]: by_author_year[ay] = k

changed = False
for n in notes:
    p = pathlib.Path(n)
    if not p.exists(): continue
    yml, body = read_yaml_head(p)
    if not yml: continue
    meta = parse_yaml_block(yml)

    cite = (meta.get("citation_key") or "").strip()
    if cite and cite in by_key:
        # normalize header (avoid dupes) and keep going
        write_yaml(p, meta, body)
        continue

    found = None
    if not found and meta.get("doi"):   found = by_doi.get(norm(meta["doi"]))
    if not found and meta.get("url"):   found = by_url.get(norm(meta["url"]))
    if not found and meta.get("title") and meta.get("year"):
        found = by_title_year.get((norm(meta["title"]), re.sub(r'\D+','',meta["year"])))
    if not found and meta.get("authors") and meta.get("year"):
        first = surname_first(meta["authors"])
        found = by_author_year.get((norm(first), re.sub(r'\D+','',meta["year"])))

    if found:
        k, f = next((kk,ff) for kk,ff in entries if kk==found)
        meta["citation_key"] = k
        meta.setdefault("title",   f.get("title",""))
        meta.setdefault("authors", f.get("author",""))
        meta.setdefault("year",    f.get("year",""))
        meta.setdefault("journal", f.get("journal","") or f.get("booktitle","") or f.get("publisher",""))
        meta.setdefault("doi",     f.get("doi",""))
        meta.setdefault("url",     f.get("url",""))
        write_yaml(p, meta, body)
        changed = True

print("No notes needed citation_key updates." if not changed else "Synchronized citation_key from bibliography for some notes.")
PY

# ── Helper to run pandoc (optional quiet citeproc warnings) ────────────────────
run_pandoc() {
  if [[ "${QUIET_CITEPROC_WARN:-0}" == "1" ]]; then
    pandoc "$@" "${FILTER_ARGS[@]}" "${EXTRA_FLAGS[@]}" --csl "$CSL_STYLE" --bibliography "$BIB_PATH" 2>/dev/null
  else
    pandoc "$@" "${FILTER_ARGS[@]}" "${EXTRA_FLAGS[@]}" --csl "$CSL_STYLE" --bibliography "$BIB_PATH"
  fi
}

# ── 1) Optional: heuristic placeholder-fix ─────────────────────────────────────
python3 - <<'PY'
import re
from pathlib import Path
ROOT = Path(".")
NOTES = ROOT / "notes" / "reading-notes"
heuristic_map = {
    "Wilkinson2016": "wilkinsonCommentFAIRGuiding2016",
    "Lissack2024":   "lissackResponsibleUseLarge2024",
    "Buchanan1992":  "buchananDesignNewRhetoric2001",
}
for p in sorted(NOTES.glob("*.md")):
    txt = p.read_text(encoding="utf-8")
    orig = txt
    for left, right in heuristic_map.items():
        txt = re.sub(rf'\[@{re.escape(left)}\]', f'[@{right}]', txt)
    if txt != orig:
        p.write_text(txt, encoding="utf-8")
PY

# ── 2) Build each reading‑note page ────────────────────────────────────────────
for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  run_pandoc "$f" --standalone "${TEMPLATE_ARG[@]}" -o "notes-html/${base}.html"
done

# ── 3) Build Literature Review (inject only reading‑notes references) ─────────
if [[ -f notes/review.md ]]; then
  run_pandoc notes/review.md --standalone "${REVIEW_TEMPLATE_ARG[@]}" \
    -M suppress-bibliography=true -o notes-html/review.html

  tmp_refs_md="$(mktemp -t refs.XXXXXX.md)"
  {
    echo '---'
    echo "bibliography: $BIB_PATH"
    echo "csl: $CSL_STYLE"
    echo 'nocite: |'
    for f in "${note_files[@]}"; do
      key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
      [[ -z "${key_line:-}" ]] && continue
      key="${key_line#*:}"; key="${key//\"/}"; key="${key//\'/}"
      key="$(echo "$key" | xargs)"
      [[ -n "$key" ]] && echo "  @$key"
    done
    echo '---'
    echo; echo '::: {#refs}'; echo ':::'
  } > "$tmp_refs_md"

  refs_fragment="$(mktemp -t refsfrag.XXXXXX.html)"
  run_pandoc "$tmp_refs_md" -f markdown -t html > "$refs_fragment"

  python3 - "$refs_fragment" notes-html/review.html <<'PY'
import re, sys, pathlib
frag = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
html_path = pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")
new_html, n = re.subn(r'<div id="refs"[^>]*>.*?</div>', frag, html, flags=re.DOTALL|re.IGNORECASE)
if n == 0:
    new_html, n = re.subn(r'</body>', frag + '\n</body>', html, count=1, flags=re.IGNORECASE)
    if n == 0: new_html = html + '\n' + frag
html_path.write_text(new_html, encoding="utf-8")
PY

  rm -f "$tmp_refs_md" "$refs_fragment"
fi

# ── 4) Build Reading Notes index (case‑preserving links) ───────────────────────
python3 - <<'PY'
import os, re, unicodedata
from pathlib import Path
from bs4 import BeautifulSoup

ROOT = Path(".")
NOTES_DIR = ROOT / "notes-html"
NOTES_SRC = ROOT / "notes" / "reading-notes"
REVIEW = NOTES_DIR / "review.html"
OUT = NOTES_DIR / "index.html"

def strip_diacritics(s): return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
def norm_basic(s): return re.sub(r"[^0-9a-z]", "", strip_diacritics((s or "").lower()))
def norm_consonants(s): return re.sub(r"[aeiou]", "", norm_basic(s))

def first_author_year_title(html_fragment):
    soup = BeautifulSoup(html_fragment, "html.parser")
    text = " ".join(soup.stripped_strings)
    m_surname = re.match(r"\s*([A-Za-zÀ-ÖØ-öø-ÿ'’\-]+)", text)
    m_year = re.search(r"\((\d{4})\)", text)
    m_title = re.search(r"[‘“\"']([^’”\"']+)[’”\"']", text)
    title = m_title.group(1).strip() if m_title else None
    if not (m_surname and m_year): return None, None, title
    surname = strip_diacritics(re.sub(r"[^A-Za-z]", "", m_surname.group(1)))
    return surname, m_year.group(1), title

def compact_title(title, max_words=6):
    if not title: return ""
    words = [strip_diacritics(w) for w in re.findall(r"[A-Za-zÀ-ÖØ-öø-ÿ]+", title)][:max_words]
    return "".join(w.capitalize() for w in words)

if not REVIEW.exists():
    raise SystemExit("review.html not found; build review first.")

# Map HTML note basenames (case preserved)
note_stems = []
for fn in os.listdir(NOTES_DIR):
    if fn.endswith(".html") and fn[:-5] not in {"index","review","template"}:
        note_stems.append(fn[:-5])

# Build stem maps for fuzzy matching (value keeps original case)
stem_map = {}
for stem in note_stems:
    for form in {norm_basic(stem), norm_consonants(stem), stem.lower()}:
        if form and form not in stem_map:
            stem_map[form] = stem

# NEW: map citation_key (from note YAML) -> note stem (case preserved)
key_to_stem = {}
for md in NOTES_SRC.glob("*.md"):
    txt = md.read_text(encoding="utf-8", errors="ignore")
    m = re.match(r"^---\n(.*?)\n---\n", txt, re.S)
    yml = m.group(1) if m else ""
    km = re.search(r'(?i)^\s*citation_key\s*:\s*"?([^"\n]+)"?', yml, re.M)
    if not km: 
        continue
    key = km.group(1).strip()
    if key:
        key_to_stem[norm_basic(key)] = md.stem  # case-preserved stem

soup = BeautifulSoup(REVIEW.read_text(encoding="utf-8"), "html.parser")
refs_div = soup.find(id="refs")
entries = list(refs_div.select("div.csl-entry[id^=ref-]")) if refs_div else []

out = BeautifulSoup(
    "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>"
    "<meta name='viewport' content='width=device-width, initial-scale=1.0'/>"
    "<title>Reading notes list</title><link rel='stylesheet' href='notes.css'/></head><body></body></html>",
    "html.parser"
)
body = out.body
nav = out.new_tag("nav", **{"class": "top-nav"})
back = out.new_tag("a", href="review.html"); back.string = "← Back to Literature Review"
nav.append(back); body.append(nav)
header = out.new_tag("header", **{"class": "page-header"})
h1 = out.new_tag("h1", **{"class": "title"}); h1.string = "Reading notes list"
header.append(h1); body.append(header)
ul = out.new_tag("ul"); body.append(ul)

for e in entries:
    li = out.new_tag("li"); frag_html = e.decode_contents()
    li.append(BeautifulSoup(frag_html, "html.parser"))

    # Candidate keys
    candidates = []
    eid = e.get("id","")
    csl_key = eid[4:] if eid.lower().startswith("ref-") else eid
    if csl_key:
        # 1) direct citation_key → filename mapping (preserves case)
        kb = norm_basic(csl_key)
        if kb in key_to_stem:
            target = key_to_stem[kb] + ".html"
        else:
            # 2) fallback fuzzy matching on the filename
            candidates += [norm_basic(csl_key), norm_consonants(csl_key), csl_key.lower()]
            target = None
    else:
        target = None

    # 3) further fallback: AuthorYear and AuthorCompactTitleYear
    if target is None:
        from bs4 import BeautifulSoup as BS
        surname, year, title = first_author_year_title(frag_html)
        if surname and year:
            ay = f"{surname}{year}"
            candidates += [norm_basic(ay), norm_consonants(ay), ay.lower()]
            stem = compact_title(title)
            if stem:
                ayt = f"{surname}{stem}{year}"
                candidates += [norm_basic(ayt), norm_consonants(ayt), ayt.lower()]
        for c in candidates:
            if c in stem_map:
                target = stem_map[c] + ".html"; break

    if target and (NOTES_DIR / target).exists():
        li.append(out.new_tag("br"))
        a = out.new_tag("a", href=target); a.string = "See notes →"
        li.append(a)

    ul.append(li)

OUT.write_text(str(out), encoding="utf-8")
PY

# ── 5) Verify that every cited key in notes exists in the .bib ─────────────────
python3 - <<'PY'
import re
from pathlib import Path
BIB = Path("refs/library.bib")
NOTES = Path("notes/reading-notes")
cited=set()
for p in NOTES.glob("*.md"):
    cited.update(re.findall(r'\[@([A-Za-z0-9:_-]+)\]', p.read_text(encoding="utf-8", errors="ignore")))
bib=set()
for line in BIB.read_text(encoding="utf-8", errors="ignore").splitlines():
    m = re.match(r'^@[^{(]+\{\s*([^,\s]+)', line)
    if m: bib.add(m.group(1))
missing = sorted(k for k in cited if k not in bib)
print("Citations OK: all note citations resolve in refs/library.bib ✅" if not missing else
      "⚠︎ Missing citation keys:\n  - " + "\n  - ".join(missing))
PY
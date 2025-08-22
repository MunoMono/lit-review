#!/usr/bin/env bash
# Build reading notes, literature review, and an index with Harvard CTR + your .bib
# Adds an auto-fix step for placeholder citation keys like [@SurnameYYYY].
#
# ENV (optional):
#   CSL_STYLE                 : path/URL to CSL (default: Harvard Cite Them Right)
#   BIB / BIBLIOGRAPHY        : path to .bib (default: refs/library.bib)
#   PANDOC_EXTRA_FLAGS        : extra flags (e.g., --citeproc --metadata link-citations=true)
#   AUTO_FIX_PLACEHOLDER_KEYS : 1 to enable (default 1), 0 to disable

set -euo pipefail
umask 022
shopt -s nullglob

# ------------------------------------------------------------------------------
# Repo root & basic dirs
# ------------------------------------------------------------------------------
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p notes-html
[[ -d filters ]] || mkdir -p filters
[[ -d assets  ]] || mkdir -p assets
[[ -d notes   ]] || mkdir -p notes
[[ -d refs    ]] || mkdir -p refs

# ------------------------------------------------------------------------------
# Configuration (env‑overridable)
# ------------------------------------------------------------------------------
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"

# Optional pandoc flags
EXTRA_FLAGS=()
if [[ -n "${PANDOC_EXTRA_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_FLAGS=(${PANDOC_EXTRA_FLAGS})
fi
if [[ " ${EXTRA_FLAGS[*]-} " != *" --citeproc "* ]]; then
  EXTRA_FLAGS+=(--citeproc)
fi
if [[ " ${EXTRA_FLAGS[*]-} " != *" --metadata link-citations=true "* ]]; then
  EXTRA_FLAGS+=(--metadata link-citations=true)
fi

AUTO_FIX_PLACEHOLDER_KEYS="${AUTO_FIX_PLACEHOLDER_KEYS:-1}"

# ------------------------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------------------------
if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc not found on PATH." >&2
  exit 1
fi
if [[ ! -f "$BIB_PATH" ]]; then
  echo "Error: bibliography not found: $BIB_PATH" >&2
  echo "Tip: keep your Better BibTeX export at refs/library.bib or set BIB=/path/to.bib" >&2
  exit 1
fi

# ------------------------------------------------------------------------------
# Optional assets & templates
# ------------------------------------------------------------------------------
TEMPLATE_ARG=()
[[ -f assets/note.html   ]] && TEMPLATE_ARG=(--template assets/note.html)

REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)

[[ -f assets/notes.css   ]] && cp -f assets/notes.css notes-html/notes.css

# Optional Lua filters
[[ -f filters/strip-leading-citation.lua ]] && FILTER_ARGS+=(--lua-filter=filters/strip-leading-citation.lua)
[[ -f filters/citations-in-lists.lua     ]] && FILTER_ARGS+=(--lua-filter=filters/citations-in-lists.lua)
[[ -f filters/keep-refs.lua              ]] && FILTER_ARGS+=(--lua-filter=filters/keep-refs.lua)
# NEW: sentence-case the YAML title (only)
[[ -f filters/sentence-case-title.lua    ]] && FILTER_ARGS+=(--lua-filter=filters/sentence-case-title.lua)

# ------------------------------------------------------------------------------
# Source notes
# ------------------------------------------------------------------------------
note_files=(notes/reading-notes/*.md)

# ------------------------------------------------------------------------------
# 0) Auto-fix placeholder citations [@SurnameYYYY] -> real BBT keys (unique matches)
# ------------------------------------------------------------------------------
if (( AUTO_FIX_PLACEHOLDER_KEYS )); then
  if (( ${#note_files[@]} > 0 )); then
python3 - "$BIB_PATH" "${note_files[@]}" <<'PY'
import sys, re, unicodedata, pathlib

def nfd_strip(s):
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

def norm_name(s):
    s = nfd_strip(s).lower()
    s = re.sub(r"[^a-z]", "", s)  # letters only
    return s

bib_path = pathlib.Path(sys.argv[1])
note_paths = [pathlib.Path(p) for p in sys.argv[2:]]

# --- Very lightweight BibTeX entry parser (first author surname + year) ---
entries = []
entry = None
with bib_path.open("r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if line.strip().startswith('@'):
            if entry: entries.append(entry)
            entry = {"raw": line.rstrip(), "fields": {}}
            # key extraction for @type{key, ...} or @type(key, ...)
            m = re.match(r'^@[^({]+\{\s*([^,\s]+)', line)
            if not m:
                m = re.match(r'^@[^({]+\(\s*([^,\s]+)', line)
            entry["key"] = m.group(1) if m else None
        elif entry is not None:
            entry.setdefault("body", []).append(line.rstrip())
if entry: entries.append(entry)

def get_field(body_lines, name):
    pat = re.compile(r'(?i)\b'+re.escape(name)+r'\s*=\s*[{"]([^"}]+)')
    for ln in body_lines:
        m = pat.search(ln)
        if m:
            return m.group(1).strip()
    return ""

index = {}  # (surname_norm, year) -> [keys]
for e in entries:
    body = e.get("body", [])
    au = get_field(body, "author")
    yr = get_field(body, "year")
    key = e.get("key")
    if not key or not yr or not au:
        continue
    # first author surname: token before comma, else last token
    au1 = au.split(" and ")[0]
    if "," in au1:
        surn = au1.split(",")[0]
    else:
        parts = au1.strip().split()
        if not parts: 
            continue
        surn = parts[-1]
    surn_norm = norm_name(surn)
    yr4 = re.search(r'(\d{4})', yr)
    if not yr4:
        continue
    tup = (surn_norm, yr4.group(1))
    index.setdefault(tup, []).append(key)

# --- Scan notes and replace placeholder citations if unique match ---
# pattern: [@SurnameYYYY] or [@SurnameYYYYa]
pat = re.compile(r'\[@([A-Za-zÀ-ÖØ-öø-ÿ\'’\-]+)(\d{4}[a-z]?)\]')

changed_any = False
for path in note_paths:
    txt = path.read_text(encoding="utf-8")
    replacements = []
    def repl(m):
        surname = m.group(1)
        yya     = m.group(2)           # may include letter suffix, ignore it for lookup
        yy_m    = re.match(r'(\d{4})', yya)
        if not yy_m:
            return m.group(0)
        yy      = yy_m.group(1)
        surn_norm = norm_name(surname)
        candidates = index.get((surn_norm, yy), [])
        if len(candidates) == 1:
            new_key = candidates[0]
            old = m.group(0)
            new = f"[@{new_key}]"
            replacements.append((old, new))
            return new
        else:
            return m.group(0)  # leave as-is

    new_txt = pat.sub(repl, txt)
    if replacements and new_txt != txt:
        path.write_text(new_txt, encoding="utf-8")
        changed_any = True
        uniq = []
        seen = set()
        for o,n in replacements:
            if (o,n) not in seen:
                uniq.append((o,n)); seen.add((o,n))
        print(f"Auto-fixed {path}:")
        for o,n in uniq:
            print(f"  - {o}  →  {n}")

if not changed_any:
    print("No placeholder citations to fix (or no unique matches).")
PY
  fi
fi

# ------------------------------------------------------------------------------
# Helper to run pandoc
# ------------------------------------------------------------------------------
run_pandoc() {
  pandoc "$@" \
    "${FILTER_ARGS[@]}" \
    "${EXTRA_FLAGS[@]}" \
    --csl "$CSL_STYLE" \
    --bibliography "$BIB_PATH"
}

# ------------------------------------------------------------------------------
# 1) Build each reading‑note page
# ------------------------------------------------------------------------------
if (( ${#note_files[@]} == 0 )); then
  echo "No reading notes found in notes/reading-notes/ (skipping note pages)"
else
  for f in "${note_files[@]}"; do
    base="$(basename "$f" .md)"
    run_pandoc "$f" \
      --standalone \
      "${TEMPLATE_ARG[@]}" \
      -o "notes-html/${base}.html"
    echo "Built notes-html/${base}.html"
  done
fi

# ------------------------------------------------------------------------------
# 2) Build Literature Review (suppress bib, then inject refs from notes)
# ------------------------------------------------------------------------------
if [[ -f notes/review.md ]]; then
  run_pandoc notes/review.md \
    --standalone \
    "${REVIEW_TEMPLATE_ARG[@]}" \
    -M suppress-bibliography=true \
    -o notes-html/review.html
  echo "Built notes-html/review.html (bibliography suppressed)"

  # Gather citation keys from notes' YAML: citation_key: SomeKey2024
  tmp_refs_md="$(mktemp -t refs.XXXXXX.md)"
  {
    echo '---'
    echo "bibliography: $BIB_PATH"
    echo "csl: $CSL_STYLE"
    echo 'nocite: |'
    for f in "${note_files[@]}"; do
      key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
      [[ -z "${key_line:-}" ]] && continue
      key="${key_line#*:}"
      key="${key//\"/}"; key="${key//\'/}"
      key="$(echo "$key" | xargs)"
      [[ -n "$key" ]] && echo "  @$key"
    done
    echo '---'
    echo
    echo '::: {#refs}'
    echo ':::'
  } > "$tmp_refs_md"

  refs_fragment="$(mktemp -t refsfrag.XXXXXX.html)"
  run_pandoc "$tmp_refs_md" -f markdown -t html > "$refs_fragment"

  # Splice #refs into review.html
  python3 - "$refs_fragment" notes-html/review.html <<'PY'
import re, sys, pathlib
frag = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
html_path = pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")

new_html, n = re.subn(r'<div id="refs"[^>]*>.*?</div>', frag, html, flags=re.DOTALL|re.IGNORECASE)
if n == 0:
    new_html, n = re.subn(r'</body>', frag + '\n</body>', html, count=1, flags=re.IGNORECASE)
    if n == 0:
        new_html = html + '\n' + frag

html_path.write_text(new_html, encoding="utf-8")
PY

  rm -f "$tmp_refs_md" "$refs_fragment"
  echo "Injected references from reading-notes only ✅"
else
  echo "Skipping lit review: notes/review.md not found."
fi

# ------------------------------------------------------------------------------
# 3) Build Reading Notes index from review’s reference list
# ------------------------------------------------------------------------------
python3 - <<'PY'
import os, re, unicodedata
from pathlib import Path
try:
    from bs4 import BeautifulSoup
except Exception as e:
    raise SystemExit("BeautifulSoup (bs4) is required to build index.html") from e

ROOT = Path(".")
NOTES_DIR = ROOT / "notes-html"
REVIEW = NOTES_DIR / "review.html"
OUT = NOTES_DIR / "index.html"

def strip_diacritics(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

def norm_basic(s: str) -> str:
    s = strip_diacritics(s.lower())
    return re.sub(r"[^0-9a-z]", "", s)

def norm_consonants(s: str) -> str:
    s = norm_basic(s)
    return re.sub(r"[aeiou]", "", s)

def surname_and_year_from_citation(html_fragment: str):
    text = " ".join(BeautifulSoup(html_fragment, "html.parser").stripped_strings)
    m_surname = re.match(r"\s*([A-Za-zÀ-ÖØ-öø-ÿ'’\-]+)", text)
    m_year = re.search(r"\((\d{4})\)", text)
    if not m_surname or not m_year:
        return None, None
    surname = m_surname.group(1)
    year = m_year.group(1)
    surname_clean = strip_diacritics(re.sub(r"[^A-Za-z]", "", surname))
    return surname_clean, year

if not REVIEW.exists():
    raise SystemExit("review.html not found; build review first.")

# Map note stems for fuzzy matching
stem_map = {}
note_stems = []
for fn in os.listdir(NOTES_DIR):
    if not fn.endswith(".html"):
        continue
    stem = fn[:-5]
    if stem in {"index", "review", "template"}:
        continue
    note_stems.append(stem)

for stem in note_stems:
    for form in {norm_basic(stem), norm_consonants(stem), stem.lower()}:
        if form and form not in stem_map:
            stem_map[form] = stem

soup = BeautifulSoup(REVIEW.read_text(encoding="utf-8"), "html.parser")
refs_div = soup.find(id="refs")
entries = list(refs_div.select("div.csl-entry[id^=ref-]")) if refs_div else []

out = BeautifulSoup(
    "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>"
    "<meta name='viewport' content='width=device-width, initial-scale=1.0'/>"
    "<title>Reading Notes</title><link rel='stylesheet' href='notes.css'/></head><body></body></html>",
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
    li = out.new_tag("li")
    frag_html = e.decode_contents()
    li.append(BeautifulSoup(frag_html, "html.parser"))

    # 1) key from CSL id
    eid = e.get("id","")
    key = eid[4:] if eid.lower().startswith("ref-") else eid
    candidates = [norm_basic(key), norm_consonants(key), key.lower()]

    # 2) fallback: AuthorYear
    surname, year = surname_and_year_from_citation(frag_html)
    if surname and year:
        ay = f"{surname}{year}"
        candidates.extend([norm_basic(ay), norm_consonants(ay), ay.lower()])

    target = None
    for cand in candidates:
        if cand in stem_map:
            target = stem_map[cand] + ".html"
            break

    if target and (NOTES_DIR / target).exists():
        li.append(out.new_tag("br"))
        a = out.new_tag("a", href=target); a.string = "See notes →"
        li.append(a)

    ul.append(li)

OUT.write_text(str(out), encoding="utf-8")
print("Built notes-html/index.html ✅ (with See notes links when matched)")
PY

# ------------------------------------------------------------------------------
# 4) Missing-citation report (notes vs bib)
# ------------------------------------------------------------------------------
tmp_notes_keys="$(mktemp -t noteskeys.XXXX)"
tmp_bib_keys="$(mktemp -t bibkeys.XXXX)"

grep -Rho '\[@[A-Za-z0-9:_-]\+' notes/reading-notes \
| sed 's/.*\[@//' | sort -u > "$tmp_notes_keys" || true

python3 - <<'PY' > "$tmp_bib_keys"
import re
keys=set()
with open("refs/library.bib","r",encoding="utf-8",errors="ignore") as f:
    for line in f:
        m=re.match(r'^@[^{(]+\{\s*([^,\s]+)', line)
        if m: keys.add(m.group(1)); continue
        m=re.match(r'^@[^(]+\(\s*([^,\s]+)', line)
        if m: keys.add(m.group(1)); continue
print("\n".join(sorted(keys)))
PY

missing="$(comm -23 "$tmp_notes_keys" "$tmp_bib_keys" || true)"
if [[ -n "$missing" ]]; then
  echo "⚠︎ Missing citation keys (not found in $BIB_PATH):"
  echo "$missing" | sed 's/^/   - /'
else
  echo "Citations OK: all note citations resolve in $BIB_PATH ✅"
fi
rm -f "$tmp_notes_keys" "$tmp_bib_keys"

echo "All done."
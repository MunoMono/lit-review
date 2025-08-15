#!/usr/bin/env bash
set -euo pipefail
umask 022

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Safe globs on macOS/Linux
shopt -s nullglob

# ------------------------------------------------------------------------------
# Folders & assets
# ------------------------------------------------------------------------------
mkdir -p notes-html
[[ -d filters ]] || mkdir -p filters
[[ -d assets  ]] || mkdir -p assets

# CSL default (override with env var if needed)
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"

# Copy CSS for consistent styling
[[ -f assets/notes.css ]] && cp -f assets/notes.css notes-html/notes.css

# Optional templates
TEMPLATE_ARG=()
[[ -f assets/note.html   ]] && TEMPLATE_ARG=(--template assets/note.html)

REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)

# All reading-note sources
note_files=(notes/reading-notes/*.md)

# ------------------------------------------------------------------------------
# 1) Build each reading‑note page
# ------------------------------------------------------------------------------

for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone \
    "${TEMPLATE_ARG[@]}" \
    --lua-filter=filters/strip-leading-citation.lua \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# ------------------------------------------------------------------------------
# 2) Build Literature Review (with references ONLY from reading notes)
#    - First, render review.html WITHOUT an auto-bibliography
#    - Then, inject a refs block built from the citation_key of each note
# ------------------------------------------------------------------------------

if [[ -f notes/review.md ]]; then
  pandoc notes/review.md \
    --standalone \
    "${REVIEW_TEMPLATE_ARG[@]}" \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -M suppress-bibliography=true \
    -o notes-html/review.html
  echo "Built notes-html/review.html (bibliography suppressed)"

  # Build a tiny MD with a nocite list of all note keys
  # (use mktemp portable form for macOS/Linux)
  tmp_refs_md="$(mktemp -t refs.XXXXXX.md)"
  {
    echo '---'
    echo 'bibliography: refs/library.bib'
    echo "csl: $CSL_STYLE"
    echo 'nocite: |'
    for f in "${note_files[@]}"; do
      key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
      [[ -z "${key_line:-}" ]] && continue
      key="${key_line#*:}"; key="${key//\"/}"; key="${key//\'/}"; key="${key// /}"
      [[ -n "$key" ]] && echo "  @$key"
    done
    echo '---'
    echo
    echo '::: {#refs}'
    echo ':::'
  } > "$tmp_refs_md"

  # Render just the #refs fragment
  refs_fragment="$(mktemp -t refsfrag.XXXXXX.html)"
  pandoc "$tmp_refs_md" \
    -f markdown \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -t html \
    > "$refs_fragment"

  # Splice it into review.html (replace existing refs or append before </body>)
  python3 - "$refs_fragment" notes-html/review.html <<'PY'
import re, sys, pathlib
frag = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
html_path = pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")

new_html, n = re.subn(r'<div id="refs"[^>]*>.*?</div>', frag, html, flags=re.DOTALL)
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
# 3) Build Reading Notes index by cloning the review’s reference list.
#    For each ref, show full formatted citation + a “See notes” link if the
#    corresponding notes HTML exists. No more key-matching headaches.
# ------------------------------------------------------------------------------

python3 - <<'PY'
import os, re, unicodedata
from pathlib import Path
from bs4 import BeautifulSoup

ROOT = Path(".")
NOTES_DIR = ROOT / "notes-html"
REVIEW = NOTES_DIR / "review.html"
OUT = NOTES_DIR / "index.html"

def strip_diacritics(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

def norm_basic(s: str) -> str:
    # lowercase, remove diacritics, drop non-alphanumerics
    s = strip_diacritics(s.lower())
    return re.sub(r"[^0-9a-z]", "", s)

def norm_consonants(s: str) -> str:
    s = norm_basic(s)
    return re.sub(r"[aeiou]", "", s)

# 1) Build a robust map from *note file stems* -> multiple normalised keys
#    (so we can match weird ref IDs like 'Hernndez-Ramrez2024' to 'HernandezRamirez2024.html')
stem_map = {}  # normalized_key -> actual_stem
note_stems = []
for fn in os.listdir(NOTES_DIR):
    if not fn.endswith(".html"):
        continue
    stem = fn[:-5]
    if stem in {"index", "review", "template"}:
        continue
    note_stems.append(stem)

for stem in note_stems:
    forms = { norm_basic(stem), norm_consonants(stem), stem.lower() }
    for form in forms:
        if form and form not in stem_map:
            stem_map[form] = stem

# 2) Parse the refs from review.html (must exist already)
soup = BeautifulSoup(REVIEW.read_text(encoding="utf-8"), "html.parser")
refs_div = soup.find(id="refs")
entries = []
if refs_div:
    # Each entry is <div class="csl-entry" id="ref-KEY">…</div> (or identical structure).
    for entry in refs_div.select("div.csl-entry[id^=ref-]"):
        entries.append(entry)

# 3) Build index HTML: full Harvard citation, + exact "See notes" link if we can map it
out = BeautifulSoup(
    "<!DOCTYPE html><html lang=''><head><meta charset='utf-8'/>"
    "<meta name='viewport' content='width=device-width, initial-scale=1.0'/>"
    "<title>Reading Notes</title><link rel='stylesheet' href='notes.css'/></head><body></body></html>",
    "html.parser"
)
body = out.body

# Breadcrumb
nav = out.new_tag("nav", **{"class": "top-nav"})
back = out.new_tag("a", href="review.html"); back.string = "← Back to Literature Review"
nav.append(back)
body.append(nav)

header = out.new_tag("header", **{"class": "page-header"})
h1 = out.new_tag("h1", **{"class": "title"}); h1.string = "Reading Notes"
header.append(h1)
body.append(header)

ul = out.new_tag("ul")
body.append(ul)

for e in entries:
    li = out.new_tag("li")

    # Keep the formatted citation (italics, small caps, links) intact
    li.append(BeautifulSoup(e.decode_contents(), "html.parser"))

    # Determine the correct note file by KEY normalisation
    eid = e.get("id","")
    key = eid[4:] if eid.startswith("ref-") else eid

    candidates = [
        norm_basic(key),
        norm_consonants(key),
        key.lower()
    ]

    target = None
    for cand in candidates:
        if cand in stem_map:
            target = stem_map[cand] + ".html"
            break

    if target and (NOTES_DIR / target).exists():
        li.append(out.new_tag("br"))
        a = out.new_tag("a", href=target); a.string = "See notes"
        li.append(a)

    ul.append(li)

OUT.write_text(str(out), encoding="utf-8")
print("Built notes-html/index.html ✅")
PY
#!/usr/bin/env bash
# Build reading notes, literature review and an index with Harvard CTR + your .bib
# Portable, CI-friendly. Control via env:
#   CSL_STYLE   : path or URL to CSL (default: Harvard Cite Them Right)
#   BIB / BIBLIOGRAPHY : path to .bib (default: refs/library.bib)
#   PANDOC_EXTRA_FLAGS : extra flags (e.g., --citeproc --metadata link-citations=true)

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

# Optional pandoc flags (space-separated), e.g.:
# PANDOC_EXTRA_FLAGS="--citeproc --metadata link-citations=true"
EXTRA_FLAGS=()
if [[ -n "${PANDOC_EXTRA_FLAGS:-}" ]]; then
  # shellcheck disable=SC2206 # intentional word-splitting
  EXTRA_FLAGS=(${PANDOC_EXTRA_FLAGS})
fi

# Default to citeproc + link-citations if not explicitly supplied
if [[ " ${EXTRA_FLAGS[*]-} " != *" --citeproc "* ]]; then
  EXTRA_FLAGS+=(--citeproc)
fi
if [[ " ${EXTRA_FLAGS[*]-} " != *" --metadata link-citations=true "* ]]; then
  EXTRA_FLAGS+=(--metadata link-citations=true)
fi

# ------------------------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------------------------
if ! command -v pandoc >/dev/null 2>&1; then
  echo "Error: pandoc not found on PATH." >&2
  exit 1
fi

if [[ ! -f "$BIB_PATH" ]]; then
  echo "Error: bibliography not found: $BIB_PATH" >&2
  echo "Tip: commit your cleaned Zotero export to refs/library.bib or set BIB=/path/to.bib" >&2
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

# Optional Lua filters: if missing, skip quietly
FILTER_ARGS=()
[[ -f filters/strip-leading-citation.lua ]] && FILTER_ARGS+=(--lua-filter=filters/strip-leading-citation.lua)
[[ -f filters/citations-in-lists.lua     ]] && FILTER_ARGS+=(--lua-filter=filters/citations-in-lists.lua)

# ------------------------------------------------------------------------------
# Source notes
# ------------------------------------------------------------------------------
note_files=(notes/reading-notes/*.md)

# ------------------------------------------------------------------------------
# Helper: run pandoc with consistent flags
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
# 2) Build Literature Review (suppress bib, then inject note‑derived references)
# ------------------------------------------------------------------------------
if [[ -f notes/review.md ]]; then
  run_pandoc notes/review.md \
    --standalone \
    "${REVIEW_TEMPLATE_ARG[@]}" \
    -M suppress-bibliography=true \
    -o notes-html/review.html
  echo "Built notes-html/review.html (bibliography suppressed)"

  # Collect citation keys from front‑matter of each note:
  # expects a line like: citation_key: SomeKey2024
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
    echo
    echo '::: {#refs}'
    echo ':::'
  } > "$tmp_refs_md"

  refs_fragment="$(mktemp -t refsfrag.XXXXXX.html)"
  run_pandoc "$tmp_refs_md" \
    -f markdown \
    -t html \
    > "$refs_fragment"

  # Splice #refs fragment into review.html (replace if exists; else append before </body>)
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
    """
    Try to extract the first author surname and year from the rendered CSL entry.
    Works for patterns like: “Hernández-Ramírez, R. and Ferreira, J.B. (2024) …”
    Returns (surname, year) or (None, None)
    """
    text = " ".join(BeautifulSoup(html_fragment, "html.parser").stripped_strings)
    # first author surname = the token(s) before the first comma
    # year = first (YYYY) in parentheses
    m_surname = re.match(r"\s*([A-Za-zÀ-ÖØ-öø-ÿ'’\-]+)", text)
    m_year = re.search(r"\((\d{4})\)", text)
    if not m_surname or not m_year:
        return None, None
    surname = m_surname.group(1)
    year = m_year.group(1)
    # collapse hyphenated / compound surnames (e.g., Hernández-Ramírez -> HernandezRamirez)
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
h1 = out.new_tag("h1", **{"class": "title"}); h1.string = "Reading Notes"
header.append(h1); body.append(header)

ul = out.new_tag("ul"); body.append(ul)

for e in entries:
    li = out.new_tag("li")
    # keep the formatted Harvard citation intact
    frag_html = e.decode_contents()
    li.append(BeautifulSoup(frag_html, "html.parser"))

    # 1) key from CSL id
    eid = e.get("id","")
    key = eid[4:] if eid.lower().startswith("ref-") else eid
    candidates = [norm_basic(key), norm_consonants(key), key.lower()]

    # 2) fallback: AuthorYear (e.g., Lissack2024), also consonant/normalized
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
        a = out.new_tag("a", href=target); a.string = "See notes"
        li.append(a)

    ul.append(li)

OUT.write_text(str(out), encoding="utf-8")
print("Built notes-html/index.html ✅ (with See notes links when matched)")
PY
echo "All done."
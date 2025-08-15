#!/usr/bin/env bash
set -euo pipefail
umask 022

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
shopt -s nullglob

mkdir -p notes-html
test -d filters || mkdir -p filters
test -d assets  || mkdir -p assets

# Default CSL (override with $CSL_STYLE if needed)
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"

# Shared CSS for all pages
[[ -f assets/notes.css ]] && cp -f assets/notes.css notes-html/notes.css

# Templates
TEMPLATE_ARG=()
[[ -f assets/note.html   ]] && TEMPLATE_ARG=(--template assets/note.html)
REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)

# Optional Lua strip filter (only if present)
STRIP_FILTER_ARG=()
[[ -f filters/strip-leading-citation.lua ]] && STRIP_FILTER_ARG=(--lua-filter=filters/strip-leading-citation.lua)

# Collect reading-note files
note_files=(notes/reading-notes/*.md)

# ---------- 1) Build each note page ----------
for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone \
    "${TEMPLATE_ARG[@]}" \
    "${STRIP_FILTER_ARG[@]}" \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# ---------- 2) Build index: FULL Harvard refs linking to notes ----------
# a) Build nocite list from citation_key in each note
tmp_map="$(mktemp --suffix=.tsv)"
tmp_refs_md="$(mktemp --suffix=.md)"
{
  echo '---'
  echo 'bibliography: refs/library.bib'
  echo "csl: $CSL_STYLE"
  echo 'nocite: |'
  for f in "${note_files[@]}"; do
    base="$(basename "$f" .md)"
    key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
    [[ -z "${key_line:-}" ]] && continue
    key="${key_line#*:}"; key="${key//\"/}"; key="${key//\'/}"; key="$(echo "$key" | tr -d '[:space:]')"
    [[ -z "$key" ]] && continue
    printf '%s\t%s\n' "$key" "$base" >> "$tmp_map"
    echo "  @$key"
  done
  echo '---'
  echo
  echo '::: {#refs}'
  echo ':::'
} > "$tmp_refs_md"

# b) Ask Pandoc to render the full references once
refs_fragment="$(mktemp --suffix=.html)"
pandoc "$tmp_refs_md" \
  -f markdown \
  --citeproc \
  --csl "$CSL_STYLE" \
  --bibliography refs/library.bib \
  -t html \
  > "$refs_fragment"

# c) Post-process: wrap each reference in a link to its note.
#    If the key→basename mapping fails, fall back to ./KEY.html (and keep only those that exist).
python3 - "$refs_fragment" "$tmp_map" notes-html/index.html <<'PY'
import re, sys, pathlib, html

frag_path = pathlib.Path(sys.argv[1])
map_path  = pathlib.Path(sys.argv[2])
out_path  = pathlib.Path(sys.argv[3])
site_dir  = out_path.parent  # notes-html

frag = frag_path.read_text(encoding="utf-8")

# Load key->basename (from note filenames)
key_to_base = {}
if map_path.exists():
    for line in map_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        key, base = line.split("\t", 1)
        key_to_base[key.strip()] = base.strip()

# Pull the refs block
m_refs = re.search(r'(<div id="refs"[^>]*>.*?</div>)', frag, flags=re.DOTALL)
refs_html = m_refs.group(1) if m_refs else ""

# Build list items in CSL order
items = []
for m in re.finditer(r'<div id="ref-([^"]+)"[^>]*>(.*?)</div>', refs_html, flags=re.DOTALL):
    key = m.group(1)
    inner = m.group(2).strip()

    # Resolve link target: map key→base; else fallback base = key
    base = key_to_base.get(key, key)
    target = site_dir / f"{base}.html"
    if not target.exists():
        # skip entries that don't have a note page
        continue

    items.append(f'<li><a href="./{html.escape(base)}.html">{inner}</a></li>')

page = f"""<!DOCTYPE html>
<html lang="">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Reading Notes</title>
  <link rel="stylesheet" href="notes.css" />
</head>
<body>
  <nav class="top-nav">
    <a href="./review.html">&larr; Back to Literature Review</a>
  </nav>
  <header class="page-header">
    <h1 class="title">Reading Notes</h1>
  </header>
  <main id="content">
    <ul>
      {'\\n      '.join(items)}
    </ul>
  </main>
</body>
</html>
"""
out_path.write_text(page, encoding="utf-8")
PY

rm -f "$tmp_refs_md" "$refs_fragment" "$tmp_map"
echo "Built notes-html/index.html ✅"

# ---------- 3) Literature review with refs ONLY from reading-notes ----------
if [[ -f notes/review.md ]]; then
  # 3a) Build review without auto bibliography
  pandoc notes/review.md \
    --standalone \
    "${REVIEW_TEMPLATE_ARG[@]}" \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -M suppress-bibliography=true \
    -o notes-html/review.html
  echo "Built notes-html/review.html (bibliography suppressed)"

  # 3b) Generate refs fragment from note keys
  tmp_refs_md2="$(mktemp --suffix=.md)"
  {
    echo '---'
    echo 'bibliography: refs/library.bib'
    echo "csl: $CSL_STYLE"
    echo 'nocite: |'
    for f in "${note_files[@]}"; do
      key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
      [[ -z "${key_line:-}" ]] && continue
      key="${key_line#*:}"; key="${key//\"/}"; key="${key//\'/}"; key="$(echo "$key" | tr -d '[:space:]')"
      [[ -n "$key" ]] && echo "  @$key"
    done
    echo '---'
    echo
    echo '::: {#refs}'
    echo ':::'
  } > "$tmp_refs_md2"

  refs_fragment2="$(mktemp --suffix=.html)"
  pandoc "$tmp_refs_md2" \
    -f markdown \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -t html \
    > "$refs_fragment2"

  # 3c) Splice refs into review.html
  python3 - "$refs_fragment2" notes-html/review.html <<'PY'
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

  rm -f "$tmp_refs_md2" "$refs_fragment2"
  echo "Injected references from reading-notes only ✅"
else
  echo "Skipping lit review: notes/review.md not found."
fi
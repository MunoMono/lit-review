#!/usr/bin/env bash
set -euo pipefail

# ---------- setup
mkdir -p notes-html
test -d filters || mkdir -p filters

# Default CSL = Harvard (Cite Them Right). Allow override via env.
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"

# Copy CSS (if present) so all pages pick up consistent styling.
if [[ -f assets/notes.css ]]; then
  cp -f assets/notes.css notes-html/notes.css
fi

# ---------- 1) Build each reading-note page
for f in notes/reading-notes/*.md; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# ---------- 2) Build the aggregated Reading Notes index
pandoc notes/reading-notes/*.md \
  --standalone \
  --lua-filter=filters/citations-in-lists.lua \
  --citeproc \
  --csl "$CSL_STYLE" \
  --bibliography refs/library.bib \
  -M title="Reading Notes" --toc \
  -o notes-html/index.html
echo "Built notes-html/index.html ✅"

# ---------- 3) Build the Literature Review with auto-populated References
# Collect citation_key from each reading note and inject via a temporary nocite block.
tmp_nocite="$(mktemp)"
{
  echo 'nocite: |'
  # Extract the first "citation_key:" line from each file, trim quotes/spaces, and list as @keys
  for f in notes/reading-notes/*.md; do
    key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
    if [[ -n "${key_line:-}" ]]; then
      key="$(sed -E 's/^[[:space:]]*citation_key[[:space:]]*:[[:space:]]*//' <<<"$key_line")"
      key="${key//\"/}"; key="${key//\'/}"; key="${key// /}"
      if [[ -n "$key" ]]; then
        echo "  @$key"
      fi
    fi
  done
} > "$tmp_nocite"

if [[ -f notes/review.md ]]; then
  pandoc notes/review.md \
    --standalone \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    --metadata-file "$tmp_nocite" \
    -o notes-html/review.html
  echo "Built notes-html/review.html ✅"
else
  echo "Skipping lit review: notes/review.md not found."
fi

rm -f "$tmp_nocite"
#!/usr/bin/env bash
set -euo pipefail

mkdir -p notes-html
# ensure filter dir exists (in case it’s not under version control yet)
test -d filters || mkdir -p filters

# 1) Build each note page with citations resolved (bullets included)
for f in notes/reading-notes/*.md; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl refs/apa.csl \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# 2) Build the aggregated index page (also resolve citations inside bullets)
pandoc notes/reading-notes/*.md \
  --standalone \
  --lua-filter=filters/citations-in-lists.lua \
  --citeproc \
  --csl refs/apa.csl \
  --bibliography refs/library.bib \
  -M title="Reading Notes" --toc \
  -o notes-html/index.html

echo "Built notes-html/index.html ✅"
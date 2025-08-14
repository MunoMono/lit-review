#!/usr/bin/env bash
set -euo pipefail

mkdir -p notes-html

# 1) Build each note page with citations resolved
for f in notes/reading-notes/*.md; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone --citeproc \
    --csl refs/apa.csl \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# 2) Build the aggregated index page
pandoc notes/reading-notes/*.md \
  --standalone --citeproc \
  --csl refs/apa.csl \
  --bibliography refs/library.bib \
  -M title="Reading Notes" --toc \
  -o notes-html/index.html

echo "Built notes-html/index.html ✅"
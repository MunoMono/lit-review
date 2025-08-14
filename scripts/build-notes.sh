#!/usr/bin/env bash
set -euo pipefail
mkdir -p notes-html
pandoc notes/reading-notes/*.md \
  --standalone --citeproc \
  --csl refs/apa.csl \
  --bibliography refs/library.bib \
  -M title="Reading Notes" --toc \
  -o notes-html/index.html
echo "Built notes-html/index.html ✅"
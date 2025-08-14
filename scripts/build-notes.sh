#!/usr/bin/env bash
set -euo pipefail

OUTDIR="notes-html"
mkdir -p "$OUTDIR"

# Ensure there are notes to build
shopt -s nullglob
files=(notes/reading-notes/*.md)
if (( ${#files[@]} == 0 )); then
  echo "No notes found in notes/reading-notes/*.md"; exit 1
fi

# 1) Build each note page with citations resolved
for f in $(printf '%s\n' "${files[@]}" | sort); do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone --citeproc \
    --csl refs/apa.csl \
    --bibliography refs/library.bib \
    -M link-citations=true \
    -o "$OUTDIR/${base}.html"
  echo "Built $OUTDIR/${base}.html"
done

# 2) Build the aggregated index page
pandoc "${files[@]}" \
  --standalone --citeproc \
  --csl refs/apa.csl \
  --bibliography refs/library.bib \
  -M title="Reading Notes" \
  -M link-citations=true \
  --toc \
  -o "$OUTDIR/index.html"

echo "Built $OUTDIR/index.html ✅"
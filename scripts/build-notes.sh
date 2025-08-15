#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root (works no matter where you call the script)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Safer globs: if no matches, expand to nothing (not the literal pattern)
shopt -s nullglob

mkdir -p notes-html
test -d filters || mkdir -p filters

# Default CSL = Harvard (Cite Them Right). Allow override via env.
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"

# Copy CSS if present
[[ -f assets/notes.css ]] && cp -f assets/notes.css notes-html/notes.css

# Optional HTML template (for timestamp-above-title + authors-as-H3)
TEMPLATE_ARG=()
[[ -f assets/note.html ]] && TEMPLATE_ARG=(--template assets/note.html)

# ---------- 1) Build each reading-note page
note_files=(notes/reading-notes/*.md)
for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  pandoc "$f" \
    --standalone \
    "${TEMPLATE_ARG[@]}" \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -o "notes-html/${base}.html"
  echo "Built notes-html/${base}.html"
done

# ---------- 2) Build the aggregated Reading Notes index
if ((${#note_files[@]})); then
  pandoc "${note_files[@]}" \
    --standalone \
    --lua-filter=filters/citations-in-lists.lua \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -M title="Reading Notes" --toc \
    -o notes-html/index.html
  echo "Built notes-html/index.html ✅"
else
  echo "No reading notes found; skipping index."
fi

# ---------- 3) Build the Literature Review with refs ONLY from reading notes
tmp_meta="$(mktemp)"

{
  echo 'nocite: |'        # include note keys even if not cited in the body
  # collect citation_key from each reading note
  for f in "${note_files[@]}"; do
    key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
    [[ -z "${key_line:-}" ]] && continue
    key="$(sed -E 's/^[[:space:]]*citation_key[[:space:]]*:[[:space:]]*//' <<<"$key_line")"
    key="${key//\"/}"; key="${key//\'/}"; key="${key// /}"
    [[ -n "$key" ]] && echo "  @$key"
  done

  echo 'keep_refs:'
  for f in "${note_files[@]}"; do
    key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
    [[ -z "${key_line:-}" ]] && continue
    key="$(sed -E 's/^[[:space:]]*citation_key[[:space:]]*:[[:space:]]*//' <<<"$key_line")"
    key="${key//\"/}"; key="${key//\'/}"; key="${key// /}"
    [[ -n "$key" ]] && echo "  - $key"
  done
} > "$tmp_meta"

if [[ -f notes/review.md ]]; then
  pandoc notes/review.md \
    --standalone \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    --metadata-file "$tmp_meta" \
    --lua-filter=filters/keep-refs.lua \
    -o notes-html/review.html
  echo "Built notes-html/review.html ✅ (refs from reading-notes only)"
else
  echo "Skipping lit review: notes/review.md not found."
fi

rm -f "$tmp_meta"
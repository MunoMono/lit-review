#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root (works no matter where you call the script)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Safer globs: if no matches, expand to nothing (not the literal pattern)
shopt -s nullglob

mkdir -p notes-html
test -d filters || mkdir -p filters
test -d assets  || mkdir -p assets

# Default CSL = Harvard (Cite Them Right). Allow override via env.
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"

# Copy CSS (if present) so all pages pick up consistent styling.
[[ -f assets/notes.css ]] && cp -f assets/notes.css notes-html/notes.css

# Optional HTML template (for note pages: timestamp-above-title + authors-as-H3)
TEMPLATE_ARG=()
[[ -f assets/note.html ]] && TEMPLATE_ARG=(--template assets/note.html)

# Optional review template (adds top nav + same header layout to review.html)
REVIEW_TEMPLATE_ARG=()
[[ -f assets/review.html ]] && REVIEW_TEMPLATE_ARG=(--template assets/review.html)

# ---------- 1) Build each reading-note page ----------
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

# ---------- 2) Build the aggregated Reading Notes index ----------
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

# ---------- 3) Build the Literature Review with refs ONLY from reading-notes ----------
# 3a) Build review.html WITHOUT any auto bibliography (use review template if present)
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

  # 3b) Create a temp markdown whose refs = ONLY the reading-note keys
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

  # Produce an HTML fragment containing just the #refs block
  refs_fragment="$(mktemp -t refsfrag.XXXXXX.html)"
  pandoc "$tmp_refs_md" \
    -f markdown \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -t html \
    > "$refs_fragment"

  # 3c) Splice the fragment into review.html (replace or insert before </body>)
  python3 - "$refs_fragment" notes-html/review.html <<'PY'
import re, sys, pathlib
frag = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
html_path = pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")

# Replace existing refs block if present
new_html, n = re.subn(r'<div id="refs"[^>]*>.*?</div>', frag, html, flags=re.DOTALL)

if n == 0:
    # Try to insert before </body>
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
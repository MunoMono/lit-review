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
[[ -f assets/note.html ]] && TEMPLATE_ARG=(--template assets/note.html)

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

# ---------- 2) Build index: Harvard‑style alphabetical list ----------
# We generate a tiny markdown file with ONLY a list of "Surname and Surname (Year)" → link to each note.
# No citeproc, no concat of note contents, so headings/refs won't leak in.

tmp_idx_md="$(mktemp --suffix=.md)"
{
  echo '---'
  echo 'title: "Reading Notes"'
  echo '---'
  echo

  # Build an in-memory array of "sortkey|markdown-line" and then sort case-insensitively.
  mapfile -t rows < <(
    for f in "${note_files[@]}"; do
      base="$(basename "$f" .md)"
      authors="$(grep -m1 -E '^[[:space:]]*authors[[:space:]]*:' "$f" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//')"
      year="$(grep -m1 -E '^[[:space:]]*year[[:space:]]*:' "$f"    | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//')"

      IFS=';' read -r -a arr <<<"${authors:-}"
      surnames=()
      for a in "${arr[@]}"; do
        a="$(echo "$a" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [[ -z "$a" ]] && continue
        s="$(echo "$a" | awk '{print $NF}')"
        [[ -n "$s" ]] && surnames+=("$s")
      done

      label=""
      if ((${#surnames[@]}==1)); then
        label="${surnames[0]}"
      elif ((${#surnames[@]}==2)); then
        label="${surnames[0]} and ${surnames[1]}"
      elif ((${#surnames[@]}>2)); then
        label="${surnames[0]} et al."
      fi
      [[ -z "$label" ]] && label="${authors:-Unknown}"
      [[ -z "$year"  ]] && year="n.d."

      # emit "sortkey|line"
      printf '%s|%s\n' "$(echo "$label" | tr '[:upper:]' '[:lower:]')" "- [${label} (${year})](./${base}.html)"
    done | sort -f
  )

  for r in "${rows[@]}"; do
    echo "${r#*|}"
  done
  echo
} > "$tmp_idx_md"

pandoc "$tmp_idx_md" \
  --standalone \
  -o notes-html/index.html
rm -f "$tmp_idx_md"
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
  tmp_refs_md="$(mktemp --suffix=.md)"
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

  refs_fragment="$(mktemp --suffix=.html)"
  pandoc "$tmp_refs_md" \
    -f markdown \
    --citeproc \
    --csl "$CSL_STYLE" \
    --bibliography refs/library.bib \
    -t html \
    > "$refs_fragment"

  # 3c) Splice refs into review.html
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
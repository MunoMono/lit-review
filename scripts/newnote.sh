#!/usr/bin/env bash
# newnote.sh — create a reading-note skeleton with correct Harvard CSL + bibliography.
# Usage: ./scripts/newnote.sh <citation-key> [--title "Title"] [--authors "Surname, I.; ..."] [--year 2024]
#
# Env you can set:
#   CSL_STYLE           : path/URL to CSL (default: Harvard Cite Them Right)
#   BIB / BIBLIOGRAPHY  : path to .bib used by the build (default: refs/library.bib)

set -euo pipefail

# Repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Args
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <citation-key> [--title \"Title\"] [--authors \"Surname, I.; ...\"] [--year 2024]" >&2
  exit 1
fi

CITEKEY="$1"; shift

# Optional flags
TITLE=""
AUTHORS=""
YEAR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   shift; TITLE="${1:-}";;
    --authors) shift; AUTHORS="${1:-}";;
    --year)    shift; YEAR="${1:-}";;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift || true
done

# Validate citekey (simple, Pandoc/CSL-friendly)
if [[ ! "$CITEKEY" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "✖ citation-key must be alphanumerics/._:- only (got: '$CITEKEY')" >&2
  exit 1
fi

# Paths
NOTES_DIR="notes/reading-notes"
mkdir -p "$NOTES_DIR"
FILE="${NOTES_DIR}/${CITEKEY}.md"
if [[ -e "$FILE" ]]; then
  echo "✖ $FILE already exists" >&2
  exit 1
fi

# CSL & bibliography (write stable relative paths by default)
CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"

# From notes/reading-notes/*.md to refs/* the relative is ../../
REL_CSL="$CSL_STYLE"
REL_BIB="../../${BIB_PATH#./}"     # normalise leading ./ if present
REL_BIB="${REL_BIB#../}"           # guard double-dot if user already gave relative
# If BIB_PATH is absolute, fall back to default relative location
if [[ "$BIB_PATH" = /* ]]; then
  REL_BIB="../../refs/library.bib"
fi

# If CSL is a local file, prefer a stable relative path to avoid machine-specific absolute paths
if [[ -f "$CSL_STYLE" ]]; then
  REL_CSL="../../${CSL_STYLE#./}"
fi

# Sensible defaults
TITLE_YAML="${TITLE}"
AUTHORS_YAML="${AUTHORS}"
YEAR_YAML="${YEAR}"

# Write file
cat > "$FILE" <<EOF
---
title: "${TITLE_YAML}"
citation_key: "${CITEKEY}"
authors: "${AUTHORS_YAML}"
year: "${YEAR_YAML}"
bibliography: ${REL_BIB}
csl: ${REL_CSL}
link-citations: true
tags:
  - reading-note
  - to-file
---

## Summary
- **What is the author arguing?**  
- **What is claimed as new?**  
- **What evidence or method underpins it?**  

## Relevance
- **Why this matters to my research question / hypotheses:**  

## Critical appraisal
**Strengths**
- 

**Weaknesses / gaps**
- 

## Key quotes
- ""

## Notes
- 

## Related works
- [@]
EOF

echo "✓ Created: $FILE"

# Try to open in a sensible editor
open_in_editor() {
  local path="$1"
  if [[ -n "${EDITOR:-}" ]]; then
    "$EDITOR" "$path" || true
  elif command -v code >/dev/null 2>&1; then
    code "$path" || true
  elif command -v subl >/dev/null 2>&1; then
    subl "$path" || true
  elif command -v open >/dev/null 2>&1; then      # macOS
    open -t "$path" || open "$path" || true
  elif command -v xdg-open >/dev/null 2>&1; then   # Linux
    xdg-open "$path" || true
  else
    nano "$path" || true
  fi
}

open_in_editor "$FILE"
#!/usr/bin/env bash
# newnote.sh — create a reading-note skeleton with correct Harvard CSL + bibliography.
# Usage:
#   ./scripts/newnote.sh <citation-key> [--title "Title"] [--authors "Surname, I.; ..."] [--year 2024] [--journal "Journal"] [--tag "foo"] [--dry-run]
#
# Env:
#   CSL_STYLE           : path/URL to CSL (default: Harvard Cite Them Right)
#   BIB / BIBLIOGRAPHY  : path to .bib used by the build (default: refs/library.bib)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# -------- args --------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <citation-key> [--title \"Title\"] [--authors \"Surname, I.; ...\"] [--year 2024] [--journal \"Journal\"] [--tag tag] [--dry-run]" >&2
  exit 1
fi

CITEKEY="$1"; shift || true
TITLE=""; AUTHORS=""; YEAR=""; JOURNAL=""; TAG=""; DOI=""; URL=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   shift; TITLE="${1:-}";;
    --authors) shift; AUTHORS="${1:-}";;
    --year)    shift; YEAR="${1:-}";;
    --journal) shift; JOURNAL="${1:-}";;
    --tag)     shift; TAG="${1:-}";;
    --dry-run) DRY_RUN=1;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift || true
done

# validate citekey
if [[ ! "$CITEKEY" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "✖ citation-key must be alphanumerics/._:- only (got: '$CITEKEY')" >&2
  exit 1
fi

# paths
NOTES_DIR="notes/reading-notes"
mkdir -p "$NOTES_DIR"
FILE="${NOTES_DIR}/${CITEKEY}.md"
if [[ $DRY_RUN -eq 0 && -e "$FILE" ]]; then
  echo "✖ $FILE already exists" >&2
  exit 1
fi

CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"

# relative paths for YAML (from notes/reading-notes/*.md)
REL_CSL="$CSL_STYLE"
if [[ -f "$CSL_STYLE" ]]; then
  REL_CSL="../../${CSL_STYLE#./}"
fi
REL_BIB="../../${BIB_PATH#./}"
if [[ "$BIB_PATH" = /* ]]; then
  REL_BIB="../../refs/library.bib"
fi

# ------- metadata via embedded Python (TSV output) -------
META_OUT="$(
/usr/bin/env python3 - "$CITEKEY" "$BIB_PATH" <<'PY'
import re, sys, pathlib

key = sys.argv[1]
bib = pathlib.Path(sys.argv[2])

def squash(s: str) -> str:
    if not s: return ""
    s = s.replace('\n', ' ').replace('\r', ' ').replace('\t', ' ')
    s = re.sub(r'\s+', ' ', s).strip()
    if len(s) >= 2 and ((s[0] == '{' and s[-1] == '}') or (s[0] == '"' and s[-1] == '"')):
        s = s[1:-1].strip()
    s = s.replace('{','').replace('}','').replace('\\&','&').replace('~',' ')
    return re.sub(r'\s+', ' ', s).strip()

def parse_entries(text: str):
    parts = re.split(r'(?=@[A-Za-z]+[ \t]*[({])', text)
    for p in parts:
        if not p.strip().startswith('@'):
            continue
        m = re.match(r'@([A-Za-z]+)\s*[\({]\s*([^,\s]+)\s*,', p)
        if not m: continue
        yield m.group(2), p

def field(entry: str, name: str) -> str:
    pat = re.compile(rf'{name}\s*=\s*(\{{(?:[^{{}}]|\{{[^{{}}]*\}})*\}}|"(?:[^"\\]|\\.)*")',
                     re.IGNORECASE | re.DOTALL)
    m = pat.search(entry)
    return squash(m.group(1)) if m else ""

title=authors=year=journal=doi=url=""
if bib.exists():
    text = bib.read_text(encoding='utf-8', errors='ignore')
    entries = dict(parse_entries(text))
    ent = entries.get(key)
    if ent is None:
        kl = key.lower()
        for k,p in entries.items():
            if k.lower() == kl:
                ent = p
                break
    if ent:
        title   = field(ent, 'title')
        authors = field(ent, 'author')
        year    = field(ent, 'year')
        journal = field(ent, 'journal') or field(ent, 'booktitle')
        doi     = field(ent, 'doi')
        url     = field(ent, 'url')
        if (not url) and doi:
            url = f'https://doi.org/{doi}'

def safe(s: str) -> str:
    return (s or "").replace('\t',' ').replace('\n',' ').replace('\r',' ').strip()

print('\t'.join(map(safe, [title, authors, year, journal, doi, url])))
PY
)"

META_TITLE=""; META_AUTHORS=""; META_YEAR=""; META_JOURNAL=""; META_DOI=""; META_URL=""
IFS=$'\t' read -r META_TITLE META_AUTHORS META_YEAR META_JOURNAL META_DOI META_URL <<< "$META_OUT"
unset IFS

# ------- DRY RUN -------
if [[ $DRY_RUN -eq 1 ]]; then
  if [[ -z "$META_TITLE$META_AUTHORS$META_YEAR$META_JOURNAL$META_DOI$META_URL" ]]; then
    echo "⚠︎ Could not find BibTeX entry for key '${CITEKEY}' in ${BIB_PATH}" >&2
  endmsg="— DRY RUN —"
  else
    endmsg="— DRY RUN —"
  fi
  echo "$endmsg"
  printf "title:    %s\n"   "${TITLE:-$META_TITLE}"
  printf "authors:  %s\n"   "${AUTHORS:-$META_AUTHORS}"
  printf "year:     %s\n"   "${YEAR:-$META_YEAR}"
  printf "journal:  %s\n"   "${JOURNAL:-$META_JOURNAL}"
  printf "doi:      %s\n"   "${DOI:-$META_DOI}"
  printf "url:      %s\n"   "${URL:-$META_URL}"
  printf "tag:      %s\n"   "$TAG"
  printf "bib:      %s\n"   "$REL_BIB"
  printf "csl:      %s\n"   "$REL_CSL"
  exit 0
fi

# final values prefer CLI overrides
VAL_TITLE="${TITLE:-$META_TITLE}"
VAL_AUTHORS="${AUTHORS:-$META_AUTHORS}"
VAL_YEAR="${YEAR:-$META_YEAR}"
VAL_JOURNAL="${JOURNAL:-$META_JOURNAL}"
VAL_DOI="${DOI:-$META_DOI}"
VAL_URL="${URL:-$META_URL}"

# ------- write file -------
cat > "$FILE" <<EOF
---
title: "${VAL_TITLE}"
authors: "${VAL_AUTHORS}"
year: "${VAL_YEAR}"
journal: "${VAL_JOURNAL}"
citation_key: "${CITEKEY}"
doi: "${VAL_DOI}"
url: "${VAL_URL}"

bibliography: ${REL_BIB}
csl: ${REL_CSL}
link-citations: true
---

## Purpose/aim
- **What research question or objective is being addressed?**

## Methodology
- **Research design, methods, and sample size.**

## Key findings and arguments
- **Main results and conclusions.**

## Relevance
- **How does it link to your own research questions or framework?**

## Critical evaluation
- **Strengths**
  - What is robust here?
  - Any novel contributions?
- **Weaknesses / limitations**
  - Flaws, gaps, or biases?
  - Anything the study overlooks?
- **Author's credibility**
  - Credentials, affiliations, track record?
- **Contextual validity**
  - Does it generalise beyond the sample/context studied?
- **Comparisons**
  - How does it align or conflict with other studies?

## Interpretation
- **Your own insights**
  - Alternative explanations?
  - Implications for practice, policy, or theory?
  - How does it shape your thinking?

## Key quotes
- "<Quote>" (p. X)

## Related works
- **Directly cited or conceptually linked papers.**

## Questions for further research
- **What unanswered questions remain?**
- **What should you follow up next?**
EOF

echo "✓ Created: $FILE"
fi
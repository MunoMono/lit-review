#!/usr/bin/env bash
# Create a new reading note from a citekey, DOI or URL using the project template.
set -euo pipefail
umask 022

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <citekey|doi|url> [--build]" >&2
  exit 1
fi

IDENT="$1"; shift || true
DO_BUILD=0
[[ "${1:-}" == "--build" ]] && DO_BUILD=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CSL_STYLE="${CSL_STYLE:-https://www.zotero.org/styles/harvard-cite-them-right}"
BIB_PATH="${BIB:-${BIBLIOGRAPHY:-refs/library.bib}}"
NOTES_DIR="notes/reading-notes"
mkdir -p "$NOTES_DIR"

command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 1; }
[[ -f "$BIB_PATH" ]] || { echo "Error: bibliography not found: $BIB_PATH" >&2; exit 1; }

python3 - "$BIB_PATH" "$NOTES_DIR" "$IDENT" "$CSL_STYLE" <<'PY'
import re, sys, pathlib, textwrap

bib_path = pathlib.Path(sys.argv[1])
notes_dir = pathlib.Path(sys.argv[2])
ident     = sys.argv[3]
csl_style = sys.argv[4]

def norm(s): return re.sub(r'[^a-z0-9]+','', (s or '').lower())

def load_bib_entries(path):
    txt = path.read_text(encoding='utf-8', errors='ignore')
    chunks = re.split(r'(?m)^(?=@)', txt)
    entries=[]
    for ch in chunks:
        m = re.match(r'@\s*([^{(]+)\s*[\{\(]\s*([^,\s]+)', ch)
        if not m: continue
        key = m.group(2).strip()
        fields={}
        for fm in re.finditer(r'([a-zA-Z]+)\s*=\s*({([^{}]*|{[^}]*})*}|"([^"]*)")\s*,?', ch, re.S):
            name=fm.group(1).lower()
            val = fm.group(3) if fm.group(3) is not None else (fm.group(4) or "")
            fields[name]=val.strip()
        entries.append((key, fields))
    return entries

entries = load_bib_entries(bib_path)
by_key = {k:(k,f) for k,f in entries}
by_doi = {norm(f.get('doi','')):(k,f) for k,f in entries if f.get('doi')}
by_url = {norm(f.get('url','')):(k,f) for k,f in entries if f.get('url')}

# try to resolve identifier
key_like = ident.lstrip('@')
found = by_key.get(key_like)
if not found:
    idn = norm(ident)
    if '/' in ident or ident.startswith('10.'):
        found = by_doi.get(idn) or by_url.get(idn)

if found:
    citekey, f = found
    title   = f.get('title','').strip()
    authors = f.get('author','').strip()
    year    = re.sub(r'\D+','', f.get('year','')).strip() or ""
    journal = f.get('journal','') or f.get('booktitle','') or f.get('publisher','')
    doi     = f.get('doi','')
    url     = f.get('url','')
else:
    citekey = key_like if key_like else norm(ident)[:32] or "unknown"
    title   = "<Paper title here>"
    authors = "<Authors here>"
    year    = "<Year>"
    journal = "<Journal name>"
    doi     = ident if ident.startswith('10.') else ""
    url     = ident if ident.startswith('http') else ""

# safe filename from citekey
fname = re.sub(r'[^A-Za-z0-9._-]+', '-', citekey) + ".md"
out = notes_dir / fname
if out.exists():
    print(str(out))  # idempotent: print path and exit 0
    sys.exit(0)

tpl = textwrap.dedent(f"""\
    ---
    title: "{title}"
    authors: "{authors}"
    year: "{year}"
    journal: "{journal}"
    citation_key: {citekey}
    doi: {doi if doi else ''}
    url: "{url}"
    bibliography: ../../refs/library.bib
    csl: {csl_style}
    link-citations: true
    ---

    ## Purpose and aim
    - State the research question or objective.

    ## Methodology
    - Describe the research design, methods and sample size.

    ## Key findings and arguments
    - Summarise the main results and conclusions.

    ## Relevance
    - Explain how it links to the research questions or framework.

    ## Project integration
    - **Why it helps the project (evidence-linked)**  
      - What concrete evidence from the paper strengthens the project? Cite inline (for example, ``[@{citekey}]``) and add page references for specifics.  
    - **Hooks into the project**  
      - Which workstream, deliverable, decision or stakeholder does this inform?  
    - **Use across the methods spine**  
      - Tick where this source is most useful:  
        - `[ ]` Framing and theory  
        - `[ ]` Study design  
        - `[ ]` Data collection and instruments  
        - `[ ]` Analysis and models  
        - `[ ]` Synthesis and interpretation  
        - `[ ]` Reporting and communications

    ## Critical evaluation
    - **Strengths**  
      - What is robust here?  
      - Any novel contributions?  
    - **Weaknesses and limitations**  
      - Flaws, gaps or biases?  
      - Anything the study overlooks?  
    - **Author’s credibility**  
      - Credentials, affiliations, track record?  
    - **Contextual validity**  
      - Does it generalise beyond the sample or context studied?  
    - **Comparisons**  
      - How does it align or conflict with other studies?

    ## Interpretation
    - **Your own insights**  
      - Alternative explanations?  
      - Implications for practice, policy or theory?  
      - How does it shape your thinking?

    ## Evidence to quote or paraphrase
    - ‘<Quote>’ (page X)

    ## Related works
    - List directly cited or conceptually linked papers.

    ## Questions for further research
    - What unanswered questions remain?  
    - What should you follow up next?
    """)

out.write_text(tpl, encoding="utf-8")
print(str(out))
PY

# Build immediately if requested
if [[ $DO_BUILD -eq 1 ]]; then
  ./scripts/build-notes.sh
fi
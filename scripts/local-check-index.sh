#!/usr/bin/env bash
# local-check-index.sh — rebuild, then verify references ↔ notes mapping.
# ENV you may set:
#   CSL_STYLE : path/URL to CSL (propagated to build)
#   BIB / BIBLIOGRAPHY : .bib path (propagated to build)

set -euo pipefail

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# --------------------------------------------------------------------
# 0) Sanity: BeautifulSoup is required for robust HTML parsing
# --------------------------------------------------------------------
python3 - <<'PY' >/dev/null || {
  echo "✖ BeautifulSoup4 not installed. Install with:  python3 -m pip install --user beautifulsoup4" >&2
  exit 1
}
from bs4 import BeautifulSoup
PY
echo "✓ bs4 OK"

# --------------------------------------------------------------------
# 1) Rebuild (propagate CSL/BIB env if present)
# --------------------------------------------------------------------
chmod +x scripts/build-notes.sh
echo "▶ Rebuilding site…"
CSL_STYLE="${CSL_STYLE:-${CSL:-}}"
BIBLIO="${BIBLIOGRAPHY:-${BIB:-}}"

# Pass through only if set; otherwise let build script defaults apply
if [[ -n "${CSL_STYLE}" && -n "${BIBLIO}" ]]; then
  CSL_STYLE="$CSL_STYLE" BIB="$BIBLIO" ./scripts/build-notes.sh >/dev/null
elif [[ -n "${CSL_STYLE}" ]]; then
  CSL_STYLE="$CSL_STYLE" ./scripts/build-notes.sh >/dev/null
elif [[ -n "${BIBLIO}" ]]; then
  BIB="$BIBLIO" ./scripts/build-notes.sh >/dev/null
else
  ./scripts/build-notes.sh >/dev/null
fi

test -f notes-html/review.html || { echo "✖ notes-html/review.html missing"; exit 1; }

# --------------------------------------------------------------------
# 2) Build key→page map from notes/reading-notes/*.md
# --------------------------------------------------------------------
tmp_map="$(mktemp -t notes-map.XXXXXX)"
: > "$tmp_map"

shopt -s nullglob
note_md=(notes/reading-notes/*.md)
if (( ${#note_md[@]} == 0 )); then
  echo "✖ No markdown notes found in notes/reading-notes/" >&2
  exit 1
fi

added=0
for f in "${note_md[@]}"; do
  stem="$(basename "$f" .md)"
  [[ "$stem" == "template" ]] && continue
  # Strict YAML key at line start; tolerate spaces around colon
  line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
  [[ -z "$line" ]] && continue
  key="${line#*:}"
  # Strip quotes and whitespace
  key="${key//\"/}"; key="${key//\'/}"
  key="$(echo "$key" | xargs)"
  if [[ -n "$key" ]]; then
    printf '%s=%s.html\n' "$key" "$stem" >> "$tmp_map"
    ((added++))
  fi
done

if (( added == 0 )); then
  echo "✖ Found no usable citation_key entries in notes." >&2
  exit 2
fi

# --------------------------------------------------------------------
# 3) Extract #refs from review.html and print + save mapping
# --------------------------------------------------------------------
python3 - "notes-html/review.html" "$tmp_map" <<'PY'
import sys, csv, pathlib
from bs4 import BeautifulSoup

review_path = pathlib.Path(sys.argv[1])
map_path    = pathlib.Path(sys.argv[2])

# Read key→page mapping (from notes)
key_to_page = {}
for line in map_path.read_text(encoding="utf-8").splitlines():
    if '=' in line:
        k, v = line.split('=', 1)
        key_to_page[k.strip()] = v.strip()

html = review_path.read_text(encoding="utf-8")
soup = BeautifulSoup(html, "html.parser")
refs = soup.find("div", id="refs")
if refs is None:
    print("✖ No <div id='refs'> found in review.html", file=sys.stderr)
    sys.exit(3)

rows = []
for div in refs.find_all("div", id=True):
    eid = div.get("id", "")
    if not eid.lower().startswith("ref-"):
        continue
    key = eid[4:]
    page = key_to_page.get(key)
    text_plain = " ".join(div.stripped_strings)
    text_html  = "".join(str(c) for c in div.contents).strip()
    rows.append((key, page, text_plain, text_html))

# Terminal report (grep-friendly)
for key, page, text_plain, _ in rows:
    suffix = f" -> {page}" if page else ""
    print(f"{text_plain}{suffix}")

# CSV artifact for CI / local debugging
out_csv = pathlib.Path("notes-html") / "reference-map.csv"
with out_csv.open("w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["citation_key", "note_page", "citation_plain", "citation_html"])
    for r in rows:
        w.writerow(r)

print(f"\n✓ Wrote mapping CSV: {out_csv}")
PY

echo "✓ Reference mapping complete."
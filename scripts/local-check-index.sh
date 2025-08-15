#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 0) Sanity: need BeautifulSoup for safe HTML parsing
python3 - <<'PY' || { echo "✖ BeautifulSoup4 not installed. Run:  python3 -m pip install --user beautifulsoup4"; exit 1; }
from bs4 import BeautifulSoup
print("✓ bs4 OK")
PY

# 1) Build the site so we have fresh review.html + notes
chmod +x scripts/build-notes.sh
./scripts/build-notes.sh >/dev/null

test -f notes-html/review.html || { echo "✖ notes-html/review.html missing"; exit 1; }

# 2) Build a key→page map from the note files
map_file="$(mktemp -t map)"
: > "$map_file"
for f in notes/reading-notes/*.md; do
  b="$(basename "$f" .md)"
  [[ "$b" == "template" ]] && continue
  line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
  [[ -z "$line" ]] && continue
  key="${line#*:}"
  key="${key//\"/}"; key="${key//\'/}"
  key="$(echo "$key" | tr -d '[:space:]')"
  [[ -n "$key" ]] && printf '%s=%s.html\n' "$key" "$b" >> "$map_file"
done

# 3) Extract refs from review.html and append “ — see notes” links (no nested <a>!)
python3 - "notes-html/review.html" "$map_file" <<'PY'
import sys, pathlib
from bs4 import BeautifulSoup

review_path = pathlib.Path(sys.argv[1])
map_path    = pathlib.Path(sys.argv[2])

key_to_page = {}
for line in map_path.read_text(encoding="utf-8").splitlines():
    if '=' in line:
        k,v = line.split('=',1); key_to_page[k.strip()] = v.strip()

s = BeautifulSoup(review_path.read_text(encoding="utf-8"), "html.parser")
refs = s.find("div", id="refs")
if not refs:
    print("✖ No <div id='refs'> found in review.html", file=sys.stderr)
    sys.exit(2)

# Collect entries in order; each is a div with id="ref-KEY"
rows = []
for div in refs.find_all("div", id=True):
    eid = div.get("id","")
    if not eid.startswith("ref-"):
        continue
    key = eid[4:]
    page = key_to_page.get(key)
    # Get the FULL Harvard text exactly as rendered
    text_html = "".join(str(c) for c in div.contents).strip()
    # also a TEXT-ONLY version for quick terminal grep
    text_plain = " ".join(div.stripped_strings)
    rows.append((key, page, text_plain, text_html))

# Print a clean, testable list to the terminal
for key, page, text_plain, _ in rows:
    tail = f" -> {page}" if page else ""
    print(f"{text_plain}{tail}")
PY
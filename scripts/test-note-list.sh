#!/usr/bin/env bash
# test-note-list.sh — list reading notes in a compact, human/grep-friendly form
# Adds basic validation and optional CSV export for audits.
#
# Usage:
#   ./scripts/test-note-list.sh            # pretty terminal list
#   ./scripts/test-note-list.sh --csv      # also writes notes-html/note-list.csv

set -euo pipefail
shopt -s nullglob

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Options
WRITE_CSV=0
if [[ "${1:-}" == "--csv" ]]; then
  WRITE_CSV=1
fi

NOTES_DIR="notes/reading-notes"
OUT_DIR="notes-html"
mkdir -p "$OUT_DIR"

note_files=("${NOTES_DIR}"/*.md)
if (( ${#note_files[@]} == 0 )); then
  echo "No reading notes found in ${NOTES_DIR}/"
  exit 1
fi

# Utility: extract a YAML scalar field (first match), strip quotes and trim
get_field() {
  local field="$1" file="$2" line val
  line="$(grep -m1 -E "^[[:space:]]*${field}[[:space:]]*:" "$file" || true)"
  [[ -z "$line" ]] && { echo ""; return; }
  val="${line#*:}"
  val="${val//\"/}"; val="${val//\'/}"
  # trim
  val="$(echo "$val" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  echo "$val"
}

# CSV header (optional)
CSV_PATH="${OUT_DIR}/note-list.csv"
if (( WRITE_CSV )); then
  printf "file,citation_key,authors,year,title,short_auth\n" > "$CSV_PATH"
fi

# Render
for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  [[ "$base" == "template" ]] && continue

  key="$(get_field citation_key "$f")"
  title="$(get_field title "$f")"
  authors_line="$(get_field authors "$f")"
  year="$(get_field year "$f")"

  # Derive short author string from semicolon-separated "Surname, I.; Surname2, I."
  # Fallbacks if authors missing
  short_auth=""
  if [[ -n "$authors_line" ]]; then
    IFS=';' read -r -a arr <<<"$authors_line"
    # Extract last token of each name as surname
    surnames=()
    for a in "${arr[@]}"; do
      a="$(echo "$a" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -z "$a" ]] && continue
      # handle forms like "Buchanan, R." or "Richard Buchanan"
      if [[ "$a" == *","* ]]; then
        surn="$(echo "$a" | cut -d',' -f1 | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      else
        surn="$(echo "$a" | awk '{print $NF}')"
      fi
      [[ -n "$surn" ]] && surnames+=("$surn")
    done
    if (( ${#surnames[@]} == 1 )); then
      short_auth="${surnames[0]}"
    elif (( ${#surnames[@]} == 2 )); then
      short_auth="${surnames[0]} and ${surnames[1]}"
    elif (( ${#surnames[@]} > 2 )); then
      short_auth="${surnames[0]} et al."
    fi
  fi
  [[ -z "$short_auth" ]] && short_auth="${authors_line:-Unknown}"
  [[ -z "${year:-}"  ]] && year="n.d."
  [[ -z "${title:-}" ]] && title="(untitled)"
  [[ -z "${key:-}"   ]] && key="(no-citekey)"

  # Pretty terminal line
  printf "%s (%s) — %s  [%s] -> %s.html\n" "$short_auth" "$year" "$title" "$key" "$base"

  # CSV row (optional)
  if (( WRITE_CSV )); then
    # Escape any embedded quotes by doubling them
    esc() { echo "$1" | sed 's/"/""/g'; }
    printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n" \
      "$(esc "$base")" "$(esc "$key")" "$(esc "$authors_line")" "$(esc "$year")" "$(esc "$title")" "$(esc "$short_auth")" \
      >> "$CSV_PATH"
  fi
done

if (( WRITE_CSV )); then
  echo "✓ Wrote ${CSV_PATH}"
fi
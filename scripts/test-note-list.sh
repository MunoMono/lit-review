#!/usr/bin/env bash
set -euo pipefail

# Always run from repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
shopt -s nullglob

note_files=(notes/reading-notes/*.md)

if [ ${#note_files[@]} -eq 0 ]; then
  echo "No reading notes found in notes/reading-notes/"
  exit 1
fi

for f in "${note_files[@]}"; do
  base="$(basename "$f" .md)"
  key_line="$(grep -m1 -E '^[[:space:]]*citation_key[[:space:]]*:' "$f" || true)"
  [[ -z "${key_line:-}" ]] && continue
  key="${key_line#*:}"; key="${key//\"/}"; key="${key//\'/}"; key="$(echo "$key" | tr -d '[:space:]')"

  title="$(  grep -m1 -E '^[[:space:]]*title[[:space:]]*:'   "$f" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//' )"
  authors="$(grep -m1 -E '^[[:space:]]*authors[[:space:]]*:' "$f" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//' )"
  year="$(   grep -m1 -E '^[[:space:]]*year[[:space:]]*:'    "$f" | sed -E 's/^[^:]*:[[:space:]]*//; s/^"//; s/"$//' )"

  IFS=';' read -r -a arr <<<"${authors:-}"
  surnames=()
  for a in "${arr[@]}"; do
    a="$(echo "$a" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$a" ]] && continue
    s="$(echo "$a" | awk '{print $NF}')"
    [[ -n "$s" ]] && surnames+=("$s")
  done

  short_auth=""
  if ((${#surnames[@]}==1)); then
    short_auth="${surnames[0]}"
  elif ((${#surnames[@]}==2)); then
    short_auth="${surnames[0]} and ${surnames[1]}"
  elif ((${#surnames[@]}>2)); then
    short_auth="${surnames[0]} et al."
  fi
  [[ -z "$short_auth" ]] && short_auth="${authors:-Unknown}"
  [[ -z "${year:-}"  ]] && year="n.d."

  echo "${short_auth} (${year}) — ${title}  [${key}] -> ${base}.html"
done
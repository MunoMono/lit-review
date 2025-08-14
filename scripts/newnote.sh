#!/usr/bin/env bash
set -e

key="$1"
if [ -z "$key" ]; then
  echo "Usage: $0 <citation-key>"
  exit 1
fi

file="notes/reading-notes/${key}.md"

if [ -e "$file" ]; then
  echo "Error: $file already exists"
  exit 1
fi

cat > "$file" <<EOF
---
title: ""
citation_key: "$key"
authors: ""
year: ""
bibliography: ../../refs/library.bib
csl: ../../refs/apa.csl
link-citations: true
---

## Summary
- **What is the author saying?**  

## Relevance
- **How is it relevant to your research?**  

## Critical appraisal
- **Strengths**  
  - 
- **Weaknesses / Gaps**  
  - 

## Key quotes
- ""

## Related works
- [@]
EOF

echo "Created: $file"

# Automatically open in default editor or fallback
if [ -n "$EDITOR" ]; then
  "$EDITOR" "$file"
else
  open "$file" 2>/dev/null || nano "$file"
fi
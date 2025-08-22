# Literature review toolkit

A lightweight, scalable workflow for managing a literature review with **Markdown**, **Pandoc**, and **GitHub Pages**.

---

## ✨ Features

- **Markdown-based** — write your lit review in plain text, easy to edit anywhere.
- **Bibliography support** — integrates with `.bib` files exported from Zotero for citations.
- **Citation formatting** — powered by CSL styles (APA, Harvard, etc.).
- **Reading notes system** — quick-create structured notes for each paper.
- **Auto-publishing** — every push to `main` rebuilds the review and publishes it to GitHub Pages.
- **Last updated stamp** — automatically updated in the HTML output.
- **Fully version-controlled** — never lose changes.

Live version: [https://munomono.github.io/literature-review/review.html](https://munomono.github.io/literature-review/review.html)

---

## 📂 Project structure

```
lit-review/
├── notes/                # Main review + reading notes
│   ├── review.md          # Your literature review
│   └── reading-notes/     # Individual reading note files
├── refs/                  # Bibliography + citation style
│   ├── library.bib
│   └── apa.csl
├── scripts/               # Helper scripts
│   ├── newnote.sh         # Create new reading note from template
│   └── build-notes.sh     # Build all notes locally
└── .github/workflows/     # GitHub Actions build config
```

---

## 🖋 Writing workflow

### 1. Create a new reading note

Run:

```bash
scripts/newnote.sh CitationKey
```

- **`CitationKey`** should match the BibTeX key in `refs/library.bib` (e.g., `Smith2020`).
- This creates a new Markdown file in `notes/reading-notes/` using the template.
- To auto-open the new file in VS Code (or your preferred editor), set:

```bash
export EDITOR='code -w'
```

---

### 2. Write your note

Fill in the sections in the generated file:

```markdown
---
title: "<Paper title here>"
citation_key: "Smith2020"
authors: "John Smith"
year: "2020"

bibliography: ../../refs/library.bib
csl: ../../refs/apa.csl
link-citations: true
---

## Summary
...

## Relevance
...

## Critical appraisal
...

## Key quotes
...

## Related works
...
```

---

### 3. Preview locally

Run:

```bash
scripts/build-notes.sh
```

This will:
- Generate individual HTML pages for each note in `notes-html/`
- Create an `index.html` listing all notes  
Open `notes-html/index.html` in your browser to preview.

---

### 4. Publish

Push your changes to `main`:

```bash
git add notes/reading-notes/YourNote.md
git commit -m "Add reading note: Smith2020"
git push
```

GitHub Actions will:
- Rebuild the literature review and all notes
- Deploy the updated site to GitHub Pages

✅ Your changes will be live at:  
[https://munomono.github.io/literature-review/](https://munomono.github.io/literature-review/)

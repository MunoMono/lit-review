# Literature Review Toolkit

A lightweight, scalable workflow for managing a literature review with **Markdown**, **Pandoc**, and **GitHub Pages**.

---

## ✨ Features

- **Markdown-based** — write your lit review in plain text, easy to edit anywhere.
- **Bibliography support** — integrates with `.bib` files exported from Mendeley/Zotero for citations.
- **Citation formatting** — powered by CSL styles (APA, Harvard, etc.).
- **Reading notes system** — quick-create structured notes for each paper.
- **Auto-publishing** — every push to `main` rebuilds the review and publishes it to GitHub Pages.
- **Last updated stamp** — automatically updated in the HTML output.
- **Fully version-controlled** — never lose changes.

Live version: [https://munomono.github.io/lit-review/review.html](https://munomono.github.io/lit-review/review.html)

---

## 📂 Project Structure
lit-review/
├── notes/                # Main review + reading notes
│   ├── review.md          # Your literature review
│   └── reading-notes/     # Individual reading note files
├── refs/                 # Bibliography + citation style
│   ├── library.bib
│   └── apa.csl
└── .github/workflows/    # GitHub Actions build config


## 🖋 Writing Workflow

1. **Edit your review** in `notes/review.md`.
2. **Add new notes** for a paper:
   ```bash
   newnote Smith2020
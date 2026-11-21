# KOReader Heading Normaliser

A KOReader plugin that finds chapter headings which are not real `<h1>`–`<h6>` elements — the `<p class="calibre7">Chapter One</p>` kind — and gives them the same typography as the rest of your library.

It does **not** rewrite the book. It generates a small per-book stylesheet, injects it through KOReader's style-tweak pipeline before the first render, and caches the result in the book's sidecar. Progress, highlights, bookmarks and reading settings stay attached to the original file.

## Why not rewrite the EPUB?

KOReader keys per-book state by `util.partialMD5(file)`. A rewritten file — cached or in-place — has a different identity, so the `.sdr` sidecar no longer follows it. You would have to migrate progress and annotations, and handle switching back. The plugin avoids that entire class of bugs by changing presentation only.

The TOC benefit that tag-renaming would give you is covered by crengine's `-cr-hint: toc-levelN`, which makes arbitrary elements usable in KOReader's alternative table of contents.

## How detection works

1. **Table of contents first.** EPUB 2 NCX and EPUB 3 nav entries point at the chapter titles; the plugin resolves `file#fragment` to the actual element (or its first block child).
2. **EPUB semantics second.** `epub:type="chapter"`, `role="doc-chapter"`, `aria-level` and friends.
3. **Layout heuristics last.** `page-break-before`, font size, bold, centring, first block in the file, class used once per file. Several independent signals must agree; a single class name is never enough.

Negative filters reject navigation, footnotes, tables, figures, captions, drop caps, poetry, epigraphs, bylines and front matter.

## Install

Copy `plugin/heading-normalizer.koplugin` to `koreader/plugins/`, restart KOReader, then open a book and enable it under **Document → Heading normaliser → Enable for all books**.

It is off by default. The first open of each book scans it once; later opens use the cached stylesheet.

## Menu

- **Enable for all books**
- **Disable for this book**
- **Status and detected headings** — what was found, with level, selector and confidence
- **View generated CSS**
- **Copy generated CSS**
- **Re-scan this book on next open**

## Limits

- EPUB only (reflowable crengine documents).
- A class shared by two heading levels cannot be split by CSS; the plugin picks the dominant level and reports the conflict.
- A class reused for both titles and body text cannot be distinguished by selector alone.
- No literal `<h2>` tags for other tools that scan markup; this is a reading/typography plugin, not an EPUB editor.
- The scan is capped by document count and byte size; overly large or encrypted books are skipped cleanly.

## Development

```powershell
.\tools\Setup-Toolchain.ps1   # pinned KOReader source and Windows LuaJIT
.\tools\Test.ps1              # lint, unit tests, handoff and mock-device checks
.\tools\Device.ps1 Status     # read-only hardware check
```

Design notes and the timing constraint are in [docs/design.md](docs/design.md). Device acceptance cases are in [docs/acceptance.md](docs/acceptance.md).

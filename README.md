# Book Theme

A KOReader plugin that gives a book one house style: body text, quotes, and chapter headings — including the ones that are not real `<h1>`–`<h6>` elements, the `<p class="calibre7">Chapter One</p>` kind. The detection engine is inherited from the earlier Heading Normaliser plugin; it is now the `hn_*` engine namespace inside Book Theme.

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

Copy `plugin/book-theme.koplugin` to `koreader/plugins/`, restart KOReader, then open a book and enable it under **Tools → Book Theme → Enable for all books**.

It is off by default. The first open of each book scans it once; later opens use the cached stylesheet.

Upgrading from Heading Normaliser: deploy with `tools/Device.ps1 Deploy`, which archives the old `heading-normalizer.koplugin` outside the plugin directory, or delete that folder yourself. The old `heading_normalizer*` settings and per-book caches are read as a fallback, so the enabled state and already-scanned books carry over; saves always write the new `book_theme*` keys, and the old values are left in place.

## Menu

- **Body font** — pick the reading face. Quotes and epigraphs follow it.
- **Heading font** — one face for every heading level.
- **Restore default theme**
- **Enable for all books**
- **Disable for this book**
- **Diagnostics** — Status and detected headings, View/Copy/Export generated CSS, Prepare KOReader settings, Re-scan this book on next open.

Everything except the two face choices is a fixed default: heading sizes 1.75/1.50/1.25/1.05 rem, bold headings, the chapter opening block centred and section/minor headings left aligned, lining figures on headings, uppercase minor headings, extra space below part/chapter titles, italic quotes. There is no per-level editor, so no combination of menu choices can produce a stylesheet the renderer cannot use.

Changing either face restyles the book you are reading straight away, keeping your place; other books pick the change up when they are next opened.

A chapter number is kept with its title whether the book glues it inline (`19Philosophy`) or sets it as a separate heading above the title: inline gets a word space in the heading's own face, standalone gets a small gap above the title. A publisher's negative margin that pulls the opening paragraph up under the title is cancelled, so the title keeps its breathing room.

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

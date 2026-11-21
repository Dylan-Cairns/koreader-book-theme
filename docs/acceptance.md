# Device acceptance cases

Run these on the configured Boox after a deploy. Record observed results in `STATUS.md`; do not mark a case passed from expectation alone.

## 1. Clean book is left alone

Open an EPUB whose chapter titles are real `<h1>`/`<h2>` elements.

- Page appearance before and after enabling the plugin is the same.
- **Status and detected headings** reports `no-pseudo-headings`.
- No generated CSS rule targets body paragraphs.

## 2. Calibre pseudo-headings are normalised

Open an EPUB whose ToC points at `<p class="calibre…">` chapter titles.

- Chapter openings use the sans heading stack and the level sizes.
- Body text remains EB Garamond / the configured body font.
- Chapter titles no longer inherit weird publisher sizes, centring or indentation.
- **Status** lists the selectors and the ToC reason.

## 3. No-ToC book falls back to layout

Open an EPUB without a usable NCX/nav, where chapters are a `page-break-before` wrapper plus a bold/centred title paragraph.

- The title paragraph is detected.
- Ordinary paragraphs and the first paragraph of a chapter are not restyled.

## 4. Negative fixtures stay untouched

In a book containing poetry, an epigraph, a drop cap and a footnote block, none of those elements take the heading typography.

## 5. Per-book switch

- Disable the plugin for one book, reopen it: the book returns to publisher styling.
- Re-enable it, reopen: generated styling returns.
- Other books are unaffected.

## 6. Reading state survives

Before enabling, set a reading position and add one highlight. After enabling and reopening:

- The position is unchanged.
- The highlight is still present and still points at the same text.
- No `.sdr` migration or duplicate sidecar appears.

This is the primary reason the plugin does not rewrite the EPUB.

## 7. Malformed and encrypted books fail safely

- A malformed XHTML book still opens; the plugin either skips it or styles what it could.
- A DRM/encrypted book is skipped with `encrypted`; the book opens normally.
- A very large archive is skipped by the size cap without freezing the reader.

## 8. Alternative ToC

For a book with pseudo-headings and generated `-cr-hint: toc-levelN`:

- Toggle **Table of contents → Settings → Build alternative ToC** twice (off, then on).
- The alternative ToC lists the pseudo-headings at the expected levels.

## 9. Restart persistence

Restart KOReader. Reopen a previously scanned book.

- The cached stylesheet is applied on first render; there is no visible reflow after the page appears.
- The menu still shows the cached report.

## 10. Upgrade check

After a KOReader upgrade, re-run cases 2 and 8. The plugin depends on `ReaderStyleTweak:getCssText`, `PreRenderDocument` and `Archiver.Reader`; if any moved, the plugin must log an error and leave the book unmodified rather than half-apply.

# Design

> **Milestone-1 note.** This document describes the original heading-normaliser design, now shipped as **Book Theme**. The product contract extends it: the theme owns body font family/weight and all document type, real headings are themed too, and KOReader keeps the reading environment. Where this document conflicts, `NEXT_AGENT.md` and `STATUS.md` win. The no-rewrite and `PreRenderDocument` timing decisions still stand. The engine modules keep their `hn_*` filenames as a legacy namespace; the plugin directory, menu and settings keys are Book Theme.

## The problem

Publishers mark chapter titles in wildly different ways. Some use `<h1>`–`<h6>`; many Calibre conversions use `<p class="calibre7">`, `<div class="chapter-title">`, or a bold paragraph inside a wrapper. KOReader's global typography settings only reach real heading tags, so those books ignore it.

The plugin's job is to identify the pseudo-headings and give them the same visual hierarchy as real ones, without changing the book.

## Why presentation, not content

Per-book state is keyed by the file's partial MD5 (`frontend/docsettings.lua`). Rewriting the EPUB — producing a cached copy or replacing it in place — changes that identity. The `.sdr` sidecar no longer follows the book, so progress, highlights, bookmarks and reading settings are orphaned or split.

A cached copy also changes the open path, which affects recent history, cover caches, statistics and sync. A destructive rewrite adds zip writing, backups, atomic replacement and validation to the maintenance burden.

The plugin therefore leaves the archive alone and generates CSS. The one semantic benefit of real tags — an alternative ToC — is available through crengine's `-cr-hint: toc-levelN` on any element.

## Timing

The stylesheet must be in place before the first render:

- `ReadSettings` → `ReaderTypeset:onReadSettings` builds and applies the first stylesheet (`readerui.lua:484`).
- `loadDocument()` runs in a post-init callback (`:331`).
- `PreRenderDocument` fires (`:340`), with the document loaded but not rendered.
- `render()` (`:343`).

Applying a new stylesheet after render changes the rendering hash and can start `ReaderRolling`'s rerender/reload machinery. `omer-faruq/readingstyle.koplugin` documents this failure mode.

The plugin therefore:

1. Wraps `ReaderStyleTweak:getCssText` in `init()` so generated CSS is appended to every stylesheet application, not just the first.
2. Scans and applies at `PreRenderDocument`, the last free moment.
3. Never applies for the first time from `onReaderReady`.
4. Treats menu toggles as “next open” changes; a mid-session stylesheet change would be a reload.

## Reading the archive

`base/ffi/archiver.lua` wraps libarchive and is shipped with KOReader; `wikipedia.lua` already uses the writer to build EPUBs. The plugin uses `Archiver.Reader` to list entries and extract text, with `document:getDocumentFileContent` as a fallback. The reader interface is tiny:

```lua
book:list()        -- { {path=..., size=...}, ... }
book:read(path)    -- bytes or nil
```

Tests use an in-memory implementation, so the whole scan path runs under host LuaJIT without Android or libarchive.

## Detection

### Tier 1: navigation

Parse `META-INF/container.xml` → OPF → NCX or EPUB 3 nav. For each ToC entry, resolve `file#fragment` to the element with that `id` (or the first block in that file). If the target is a wrapper, use its first block child with short text. Level comes from title semantics and depth, not raw depth alone: a flat ToC of forty chapters is forty chapters, not forty part titles.

Front matter (cover, title page, copyright, contents) is skipped.

### Tier 2: EPUB semantics

`epub:type`, `role`, `aria-level`. A wrapper such as `<section epub:type="chapter">` is reduced to its first short block.

### Tier 3: layout

Only when at least two independent signals agree:

- `page-break-before` on the element or an ancestor
- font size clearly above body size
- bold and/or centred
- first block in the file
- class or id name containing chapter/part/title/section
- class used once in the file
- uppercase, large top margin, bold child

Negative filters reject navigation, footnotes, tables, figures, captions, drop caps, poetry, epigraphs, bylines, front matter and long text. A missed pseudo-heading is acceptable; restyling body text is not.

## Theme

Book Theme owns the document type through a small theme table: the body face and weight, one style per heading role (Part, Chapter, Section, Minor heading) and a quote role. Real `h1`–`h6` and detected pseudo-headings share the same role scale, so a book with clean markup and a Calibre-converted book look the same.

The theme is merged over built-in defaults and validated field by field before it reaches CSS. The font family pattern excludes quotes, semicolons, braces and newlines, sizes are restricted to a `rem` range and unknown roles or fields are rejected. Invalid stored values fall back to their default and are reported, so a corrupt settings table can never inject CSS or stop a book from opening.

`Theme.canonical` serialises the effective theme into sorted `key=value;` lines and `Theme.hash` runs FNV-1a over it. The hash is the per-book cache key: changing one role font invalidates that book's cached CSS on the next open.

## Output

The generated stylesheet has a fixed shape: a banner with the theme hash, the body family and weight, a universal `font-family: inherit` reset, a monospace exception for `pre`/`code`/`kbd`/`samp`/`tt`, paragraph family/weight/line-height inheritance, quote type on `blockquote`, and real heading rules for `h1`–`h6`. Detected pseudo-headings add rules at their detected level, keep the publisher span reset, and are the only rules with a `-cr-hint: toc-levelN` hint. Detected quotes get the quote role and no hint.

The base stylesheet is emitted even when no pseudo-heading is found, so `css` is never empty for a readable book. The scan still reports `no-pseudo-headings`.

Selectors use the element's existing tag and classes (`p.calibre7`, `div.chapter-title`), never a guessed class. All declarations use `!important` because publisher CSS is arbitrary, except `-cr-hint`, which is not a style declaration.

The generated CSS is deterministic: sorted, deduplicated selectors, a fixed declaration order, no timestamps and no book text. The same book, theme and candidate set produce byte-identical CSS, so the rendering hash does not churn.

Body **size** is deliberately not set. Levels use `rem`, which crengine resolves against KOReader's font size, so headings scale with the reader's setting while footnote and small-print sizes stay untouched.

## Cache

The generated CSS and a compact report live in the book's sidecar:

```lua
book_theme = {
    version = 2,
    theme_hash = "74cfd6d8",
    css = "...",
    report = { ... },
    scanned_at = 1234567890,
}
```

A cache is reused only when its version, `css` and theme hash match the current build. A mismatch triggers one lazy rescan on the next open. The Heading Normaliser cache (version 1, no hash) therefore rebuilds once per book. Changing a role font changes the theme hash and rebuilds exactly the affected books.

`css = ""` is a completed scan that produced no stylesheet (for example a skipped book); `css = nil` is not a completed scan. Re-scan deletes the setting; the next open rebuilds it. Saves always write `book_theme`; the legacy `heading_normalizer` key is read as a fallback and left untouched.

## Failure containment

- Every scan is wrapped in `pcall`; a plugin error never blocks opening a book.
- Encrypted books, missing OPF, no content documents and oversized archives are skipped with a reason.
- Document count, HTML size and CSS size are capped.
- Malformed XHTML is tolerated; the scanner closes unclosed blocks and ignores broken tags.

## Deliberate non-goals

- Rewriting EPUBs, cached or in place.
- PDFs and fixed-layout documents.
- Literal tag semantics for other plugins.
- Per-element font weight or contrast controls; those remain KOReader-global.

## Prior art

- [readingstyle.koplugin](https://github.com/omer-faruq/readingstyle.koplugin) — stylesheet through the tweak pipeline; documents the `init()`/`PreRenderDocument` timing trap and the “only real headings” limitation this plugin addresses.
- [htmlreplacer.koplugin](https://github.com/onatbas/htmlreplacer.koplugin) — on-device EPUB rewriting with preview and backup; useful for the archive mechanics, and a reminder of the progress/settings cost.
- KOReader `frontend/ui/data/css_tweaks.lua` — alternative ToC hints and the built-in style-tweak vocabulary.

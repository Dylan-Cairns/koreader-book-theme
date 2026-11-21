# Design

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

## Output

Selectors use the element's existing tag and classes (`p.calibre7`, `div.chapter-title`), never a guessed class. All declarations use `!important` because publisher CSS is arbitrary.

The generated CSS is deterministic: sorted selectors, fixed level table, no timestamps. The same book and plugin version produce byte-identical CSS, so the rendering hash does not churn.

Levels use `rem`, which crengine resolves against KOReader's font size, so headings scale with the reader's setting and ignore publisher base sizes.

## Cache

The generated CSS and a compact report live in the book's sidecar:

```lua
heading_normalizer = {
    version = 1,
    css = "...",          -- "" means "scanned, nothing to do"
    report = { ... },
    scanned_at = 1234567890,
}
```

A version bump invalidates the cache. Re-scan deletes the setting; the next open rebuilds it.

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

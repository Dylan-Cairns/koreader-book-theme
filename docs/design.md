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

Applying a new stylesheet after render changes the rendering hash and can start `ReaderRolling`'s rerender/reload machinery. `omer-faruq/readingstyle.koplugin` documents this failure mode. That is why the first application happens before the first render; a later change goes through the path KOReader itself uses for a style tweak, not through a bare stylesheet swap.

The plugin therefore:

1. Wraps `ReaderStyleTweak:getCssText` in `init()` so generated CSS is appended to every stylesheet application, not just the first.
2. Scans and applies at `PreRenderDocument`, the last free moment.
3. Never applies for the first time from `onReaderReady`.
4. Applies a later face change with `ReaderTypeset`'s `ApplyStyleSheet` event, rebuilding the CSS from the cached generator inputs. That is the same live re-render a style-tweak toggle uses: it keeps the reading position and does not reload the document. A book whose cache predates the stored inputs is rescanned once.

## Reading the archive

`base/ffi/archiver.lua` wraps libarchive and is shipped with KOReader; `wikipedia.lua` already uses the writer to build EPUBs. The plugin uses `Archiver.Reader` to list entries and extract text, with `document:getDocumentFileContent` as a fallback. The reader interface is tiny:

```lua
book:list()        -- { {path=..., size=...}, ... }
book:read(path)    -- bytes or nil
```

Tests use an in-memory implementation, so the whole scan path runs under host LuaJIT without Android or libarchive.

## Detection

Detection is precision-first: a missed pseudo-heading is acceptable, restyling body text is not. Three tiers feed one merge step; quotes are detected separately.

### Front matter

Cover, title page, half title, copyright, contents, dedication, imprint, colophon and epigraph documents are furniture. Pseudo-heading and quote detection is skipped for the whole document; real `h1`–`h6` still get the theme. Paths come from three sources, merged:

- the EPUB 2 OPF `<guide>` (`title-page`, `copyright-page`, `toc`, …),
- EPUB 3 landmarks (`<nav epub:type="landmarks">` with `epub:type` on each link),
- a filename fallback (`title`, `contents`, `copyright`, `cover`, `nav`, and unambiguous stems such as `titlepage`/`halftitle` anywhere in the name, so `s003-BookTitlePage-01.xhtml` is recognised).

A heading inside a `titlepage`, `halftitlepage`, `cover`, `copyright`, `imprint`, `colophon`, `dedication` or `epigraph` container is furniture even when the containing document was not recognised as front matter; embedded title pages inside a chapter file are common.

### Tier 1: navigation

Parse `META-INF/container.xml` → OPF → NCX or EPUB 3 nav. For each ToC entry, resolve `file#fragment` to the element with that `id`, or the first block in that file. `body`/`html` may be the starting point (ids on `<body>` are common) but never the final target. A wrapper target is descended to its first short block; a target that is a real heading, has no visible text, is longer than 140 characters, contains a URL, is a long sentence ending in a full stop (over 60 characters), or holds two or more long block children is rejected. Level comes from title semantics and depth, not raw depth alone: a flat ToC of forty chapters is forty chapters, not forty part titles.

### Tier 2: EPUB semantics

Only an explicit allow-list of `epub:type`/`role` kinds counts (`chapter`, `part`, `title`, `subtitle`, `introduction`, `preface`, …). A deny token wins even if another token is allowed (`biblioentry`, `index-entry`, `endnote`, `footnote`, `noteref`, `backlink`, `pagebreak`, `caption`, `cover`, `titlepage`, `toc`, `rearnote`, `poem`, `verse`, …). A wrapper is reduced to its first short block, to a depth of three. A real `h1`–`h6` ends the walk, and a wrapper that contains a real heading is not a candidate: the global heading rule already covers it. Semantic candidates score 80.

### Tier 3: layout

Only when at least two independent signals agree, the score reaches `min_layout_score` (38), **and** one shape signal is present:

- `page-break-before` on the element or an ancestor (score, but never shape on its own)
- font size clearly above body size (ratio ≥ 1.12)
- bold and/or centred
- first block in the file
- class or id name containing chapter/part/title/section
- class used once in the file
- uppercase, large top margin, bold child

The shape gate (`name_hint`, ratio ≥ 1.12, or bold + centred) stops a page break plus first-block from turning an ordinary opening paragraph into a heading.

Negative filters reject navigation, footnotes, tables, figures, captions, drop caps, poetry, epigraphs, bylines, front matter, denied semantic kinds and long text.

### Quotes

Epigraphs, verse and poems are styled with the separate quote role, never as headings: a short `epigraph`/`verse`/`poem` block, or any blockquote outside a heading. Quotes are skipped in ToC/nav/footnote containers, notes documents (note, endnote, footnote, bibliography, index, glossary), front matter, the first block of a document, and any selector already used as a heading. A quote rule carries no `-cr-hint`: it must not enter the alternative ToC.

### Merge

Per-document candidates are merged by selector. A selector may not restyle many more visible blocks than were judged heading-like (`occurrences >= 3 and count * 2 < occurrences` is rejected); this bounds `div#thework` and `li.Biblio`-style blast radii. A ToC target that hits such a shared selector is kept when it carries its own id: the entry's fragment names one element, so `tag#id` replaces the class selector and restyles exactly that element. Id fallback applies to the ToC tier only. A layout-only selector whose text repeats verbatim in three or more documents is a running head and is dropped; ToC and semantic candidates are kept. The rule budget of 60 applies to inferred layout and semantic rules (score, then selector, deterministically); ToC rules are always kept and are not counted against it.

## Theme

Book Theme exposes exactly two choices: the body face and the heading face. The body face also types quotes and epigraphs; the heading face is shared by every heading role. Everything else is a fixed default in `Theme.defaults()` — part/chapter/section/minor at 1.75/1.50/1.15/1.00 rem, bold, the chapter opening block (part title, chapter title and its number) centred, section and minor headings left aligned, sentence-case minor headings with no tracking, lining figures on headings, italic quotes, and fixed vertical metrics per role (part `2.8rem 0 1.8rem`, chapter `2.4rem 0 1.5rem`, section `1.9rem 0 0.8rem`, minor `1.5rem 0 0.5rem`). Chapter-number rules set regular weight so the title stays visually dominant. Real `h1`–`h6` and detected pseudo-headings share those roles, so a book with clean markup and a Calibre-converted book look the same.

Alignment follows the book convention: the opening block of a chapter is a display unit and is centred, while section and minor headings sit inside prose and stay at the left margin, where a centred line would read as a divider. Part and chapter are display levels at 1.75/1.50 rem. The in-text levels follow book practice instead of a display scale: section is 1.15 rem and minor is body size at 1.00 rem, sentence case and bold, told apart by weight and space rather than size. A book-design reference the owner supplied makes the same point about chapter numbers: the title must be the most prominent element and the number secondary, so the number is 1.05 rem in regular weight against a 1.50 rem bold chapter title. Old-style (text) figures are the default in both Garamond faces, which looked wrong on chapter numbers; crengine cannot read `font-feature-settings`, but it maps `font-variant-numeric: lining-nums` to HarfBuzz `+lnum`, so every heading and number rule carries that declaration. The space below a chapter or part title is deliberately larger than the space above it: on device, the earlier `0.65rem` bottom margin left the opening paragraph looking glued to the title.

`Theme.load` reads the stored `{body_font, heading_font}` table. A settings table from a build before the simplification is still accepted: it keeps the body face and any heading face that differs from the default, and drops the derived sizes and weights. Families are validated (length, character set) before they reach CSS, and an invalid one falls back to its default with a logged problem, so a corrupt settings table can never inject CSS or stop a book from opening.

A face change applies to the book that is open, not only to the next one opened. The scan stores compact generator inputs in the cache (`generation`: candidate selectors and levels, marker selectors, number pairs, title followers), so `Generate.from_generation` rebuilds the stylesheet without reading the EPUB again. The adapter writes the new cache entry and fires ReaderTypeset's `ApplyStyleSheet`, the same live re-render path KOReader uses when a style tweak changes; the page restyles in place and keeps its position. A pre-11 cache has no inputs, so the first font change after the upgrade runs one scan instead. The rebuild must be byte-identical to a scan under the same theme, and a unit test asserts exactly that.

`Theme.canonical` serialises the resolved theme into sorted `key=value;` lines and `Theme.hash` runs FNV-1a over it. The hash is the per-book cache key: changing either face rebuilds the open book immediately and leaves other books' caches stale until they are opened. The default theme hash is `b575eae4` since the chapter opening block became centred-only, section and minor returned to the left, minor moved just above body size and headings switched to lining figures (2026-11-23). Earlier defaults were `23cb147d` (every level centred, 1.00 rem minor), `655593d8` (part/chapter centred) and `74cfd6d8` (all left).

## Output

The generated stylesheet has a fixed shape: a banner with the theme hash, the body family and weight, a universal `font-family: inherit` reset, a monospace exception for `pre`/`code`/`kbd`/`samp`/`tt`, paragraph family/weight/line-height inheritance, `sup`/`sub` sizing (publisher CSS normally carries it, and with publisher CSS off a note reference would render at body size on the baseline), quote type on `blockquote`, and real heading rules for `h1`–`h6`. Detected pseudo-headings add rules at their detected level, keep the publisher span reset, and are the only rules with a `-cr-hint: toc-levelN` hint. Detected quotes get the quote role and no hint.

A heading that opens with a bare, glued number - `<h1><span class="chapter-number">19</span>Philosophy</h1>` - relies on the publisher's stylesheet for whatever separates the number from the title. The scan records those markers (a real heading whose first non-empty child is a 1-3 digit marker, no whitespace before the title, and whose class does not contain `page`, `note`, `ref`, `bullet`, `marker`, `toc` or `index`) and the generator gives that class `display: block`, `font-size: 1.05rem`, `font-weight: normal`, `line-height: 1.15`, `margin: 0 0 0.3rem 0`, `font-family: inherit` and lining figures. The number therefore becomes a secondary line above the title, in the heading's own face, regular weight and smaller than it - the same treatment as a standalone number heading. `font-family: inherit` also overrides a reader's style tweak that forces every `span` to the body face. The exclusion list matters: page numbers, footnote markers, list bullets and ToC numbers share the markup but must stay inline untouched. This is scoped to the marker class inside a heading, so body text can never match.

Some publishers set the number as its own heading and the title as the next heading (`<h2 class="ch_title1">8</h2><h2 class="ch_title2">Title</h2>`). The scan pairs them when the first heading's text is only a 1-3 digit number, the next *block* element is another heading with title text, and the marker exclusions still pass; both headings need a class or id selector, because a bare tag would restyle every heading of that level. The generator keeps the number's role top margin, sets the number to `1.05rem` in `font-weight: normal` with `line-height: 1.15` and lining figures, gives it `0.3rem` below, and removes the title's top margin so the title keeps its full role size and bold weight. Both pair rules spell out the full `margin` shorthand so a later override cannot leave one side at its default.

Publisher CSS often pulls the opening block up under a chapter title with a negative top margin — Oxford's own stylesheet uses `div.top { margin: -1em 2em 2em 2em }` — which silently cancels the title's bottom margin. For each document the scan records the block after the first heading and after a number-pair title, and the generator sets `margin-top: 0` on those selectors. The title's own bottom margin then survives, and unrelated blocks keep their spacing. Section headings mid-document are deliberately not followed this way.

The base stylesheet is emitted even when no pseudo-heading is found, so `css` is never empty for a readable book. The scan still reports `no-pseudo-headings`.

Selectors use the element's existing tag and classes (`p.calibre7`, `div.chapter-title`), never a guessed class. All declarations use `!important` because publisher CSS is arbitrary, except `-cr-hint`, which is not a style declaration.

The generated CSS is deterministic: sorted, deduplicated selectors, a fixed declaration order, no timestamps and no book text. The same book, theme and candidate set produce byte-identical CSS, so the rendering hash does not churn.

Body **size** is deliberately not set. Levels use `rem`, which crengine resolves against KOReader's font size, so headings scale with the reader's setting while footnote and small-print sizes stay untouched.

## Cache

The generated CSS and a compact report live in the book's sidecar:

```lua
book_theme = {
    version = 11,
    theme_hash = "b575eae4",
    css = "...",
    report = { ... },
    generation = { candidates = {...}, markers = {...},
        number_headings = {...}, number_titles = {...},
        title_followers = {...} },
    scanned_at = 1234567890,
}
```

A cache is reused only when its version, `css` and theme hash match the current build. A mismatch triggers one lazy rescan on the next open. The Heading Normaliser cache (version 1, no hash) therefore rebuilds once per book. Version 4 added the chapter-marker rule; version 6 centred part and chapter titles, widened their spacing and added the number/title pair; version 9 added the pull-up cancellation; version 10 widened the size ladder; version 11 stores the generator inputs so a font change rebuilds the open book without a reopen; version 12 moved section/minor to the book scale and put chapter numbers in regular weight. The 2026-11-23 defaults change the theme hash as well, so affected books rebuild on their next open. Changing either face changes the theme hash and rebuilds exactly the affected books.

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

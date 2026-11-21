# Status

## Current work

Milestone 1 of the Heading Normaliser plugin: ToC-driven detection, EPUB semantic fallback, conservative layout heuristics, deterministic CSS generation, per-book cache and menu.

## Decisions

- The plugin does **not** rewrite EPUBs. KOReader sidecars are keyed by the file's partial MD5, so a rewritten file loses progress/highlights/bookmarks. Presentation is changed through a generated stylesheet instead.
- Generated CSS is injected by wrapping `ReaderStyleTweak:getCssText` and applying at `PreRenderDocument`, before the first render. Applying after render can trigger `ReaderRolling`'s reload machinery.
- Detection is ToC-first. Layout heuristics require multiple signals and are heavily filtered. A missed heading is preferable to restyling body text.
- `-cr-hint: toc-levelN` is emitted so pseudo-headings work in KOReader's alternative ToC.
- The plugin is off by default; enabling takes effect on the next open.
- Layout candidates require at least two signals, a score of 38, and at least one of: a semantic class/name hint, font size >= 1.12x body, or a page break. This keeps bold first paragraphs and similar body-text patterns out.

## Tests run

Run on 2026-11-20 in this repository:

- `.\tools\Setup-Toolchain.ps1` — pinned KOReader v2026.07.1 checkout and base submodule verified; LuaJIT 2.1.1783773675 ready.
- `.\tools\Test.ps1` — Luacheck: 20 files, 0 warnings, 0 errors. LuaUnit: 36 tests, 36 successes. Handoff checks: 44 project files, local exclusions, doc links and model-free config passed. Mock device checks: identity, deploy/backup/rollback (existing and first install), activation recovery, settings preservation, successful/failed/empty captures passed. No physical device operations.
- `local/toolchain/LuaJIT/src/luajit.exe` preview scan of a synthetic Calibre-style chapter confirmed `p.calibre7` level 2 from the ToC, `p.section-title` level 3 from layout, and rejection of a bold first paragraph and an epigraph.

Not run: real-device deploy, Android rendering, acceptance cases. Those are historical/untested until performed.

## Next action

Deploy to the Boox with `tools/Device.ps1 Deploy`, then execute `docs/acceptance.md` cases 1–3 and record exact observations. After that, validate against two or three real books from the owner's library (one clean EPUB, one Calibre pseudo-heading book, one div-wrapped/no-ToC book).

## Open work

- Device verification and screenshots.
- Real-book classifier tuning, especially books whose titles are split across inline spans.
- Optional settings for heading font and scale (currently hardcoded to match the companion stylesheet).
- Optional opt-in EPUB exporter with sidecar migration; not part of the default path.

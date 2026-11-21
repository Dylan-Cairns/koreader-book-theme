# Next agent: Book Theme orchestrator

You are the primary agent for the **Book Theme** project. Work only in:

`C:\Users\dylan\Documents\development\koreader-heading-normalizer`

The repository directory keeps its current name for now. The product, plugin directory, menu and documentation become **Book Theme**. Do not rename the repository directory during a live session.

Read, in this order:

1. `AGENTS.md`
2. `STATUS.md`
3. `docs/design.md` (milestone-1 design; this prompt's product contract supersedes it where they conflict)
4. `docs/harness.md`
5. this file

Then inspect `git log --oneline -5` and `git status`.

The owner has authorized subagents for this project. Use them. Do not ask the owner to manage sessions, copy context, or relay messages between subagents. Keep your own context small: delegate data-heavy work, require short reports, and keep `STATUS.md` current.

## Product contract

Book Theme owns the document's **type**:

- body font family and weight
- `p`, `li`, `dd`, `dt`, `blockquote` family/weight/line-height inheritance
- quote and epigraph type
- heading families, weights, sizes, case and alignment
- **both** real `h1`–`h6` and detected pseudo-headings
- publisher font-family/weight overrides

KOReader owns the **reading environment**:

- base font size
- line spacing
- margins
- contrast/gamma
- hyphenation
- UI chrome

Rules:

- The theme is authoritative for body and heading type. Write the body face through to KOReader's font setting so the Aa menu agrees, but the theme CSS still enforces it.
- KOReader Font Weight must be 0; the theme owns weight. Provide a “Prepare KOReader settings” action that sets weight to 0 and leaves size, spacing, margins and contrast alone.
- Contrast stays in KOReader. CSS cannot scope gamma; say so in the UI once.
- Body **size** normalisation is out of v1. Do not force `font-size: 1rem` on every `p`; it would enlarge footnotes and small print. Leave body size to KOReader.
- Do not rewrite EPUBs, cached or in place. Preserve sidecars, progress, highlights and bookmarks.
- Keep `pre`/`code` monospace. Footnotes inherit family/weight but keep their smaller size and KOReader handling.
- Cache generated CSS per book with a **theme hash**, so changing a theme font invalidates the cache lazily on the next open.

## Current state

- Milestone 1 heading-normaliser engine is implemented and committed (`81dcd89`).
- `tools/Test.ps1` passes: Luacheck 20 files, 36 LuaUnit tests, handoff and mock-device checks.
- Device: Go6, KOReader **v2026.07.2** (tag resolves to the same commit as v2026.07.1), plugin deployed at `/sdcard/koreader/plugins/heading-normalizer.koplugin`, enabled for all books.
- Real-book scan observed: 26 documents, 1 stylesheet, 88 ToC entries, 2 pseudo-headings (`p.bibliography` score 100, `p.other` score 39) in *Rethinking meditation.epub*. Generated CSS and the report were viewed on-device.
- `p.other` is a possible false positive. The corpus audit must check it and similar patterns.
- Menu must use `sorting_hint = "tools"`; nesting under `document_settings` did not attach.
- CSS is injected at `PreRenderDocument`; `ReaderStyleTweak:getCssText` is wrapped so later style changes do not drop it.
- The plugin is instantiated by the file manager too; guard `init`/`addToMainMenu` on `self.ui.document`.
- Settings flush on graceful KOReader exit. `am force-stop` loses a just-toggled setting. Use the Exit menu or wait for a save before force-stopping.
- Device acceptance has **not** been completed. Do not claim it has.

## Orchestration protocol

1. Write a short plan in `STATUS.md` before delegating.
2. Launch **one read-only corpus research subagent**. Wait for its report.
3. Then run implementation subagents **sequentially**. Never run two implementation subagents at once; they share the working tree.
4. For each subagent, provide a narrow brief: scope, files, acceptance tests, constraints, and the exact report you want back.
5. After each subagent: inspect `git diff`, run `tools/Test.ps1`, fix or re-brief if needed, commit, update `STATUS.md`.
6. Keep subagent reports short. Do not ask them to paste whole files or logs.
7. If a subagent fails the same task twice, stop and report to the owner.

Use the built-in `general` subagent for research and implementation, and `explore` for read-only discovery when it is sufficient. Delegation is authorized; the old “do not delegate” instruction no longer applies to this project.

## Research brief (first subagent)

Scope: read-only audit of the owner's EPUB library in:

`C:\Users\dylan\Documents\development\meaning-and-meditation`

Locate the library; do not modify that project or its books. Do not copy book text into this repository. Hash paths in reports.

Use Python 3 stdlib (`python -B`) with `zipfile` and XML parsing. Write outputs under this repo's ignored `local/corpus-audit/`:

- `report.md` — readable summary
- `report.json` — per-book structural data
- `patterns.md` — recurring tag/class patterns and frequencies

Analyse:

- ToC quality and coverage (EPUB2 NCX, EPUB3 nav, missing ToC)
- real `h1`–`h6` versus pseudo-headings
- chapter titles in wrappers, `p.calibreN`, class-based titles, inline spans/links
- no-ToC books and `page-break-before` titles
- false positives: drop caps, epigraphs, poetry, bibliographies, footnotes, tables, captions, bylines, front matter
- generator fingerprints (Calibre, Sigil, Pandoc, InDesign, unknown)

Where practical, run the **actual Lua classifier** from this repo against extracted EPUBs rather than reimplementing it: extract to a temp directory, feed a directory reader through `hn_scan`, and record candidates/scores. Include the current `p.other` pattern from *Rethinking meditation*.

Deliverable: taxonomy, frequencies, the strongest false-positive and false-negative cases, and 5–10 **synthetic fixture specs** (small anonymised EPUB structures, no book text) for permanent tests.

Do not edit the plugin. Do not touch the device.

## Work units (sequential)

### A. Rename to Book Theme

- Product, plugin directory (`plugin/book-theme.koplugin`), menu text, docs and harness paths.
- Keep the `hn_*` engine module names or rename consistently; update `tests/run.lua`, `tools/Device.ps1`, mock-device checks and `opencode.jsonc` watcher if needed.
- Migrate old settings/cache keys (`heading_normalizer*`) with a fallback; do not lose the owner's current enabled state.
- Update `README.md`, `AGENTS.md`, `docs/design.md`, `docs/harness.md`.
- Tests and a commit.

### B. Theme model and CSS generator

- Role model: Body, Part, Chapter, Section, Minor heading, Quote/epigraph.
- Deterministic CSS:
  - explicit body family and weight
  - `*, *::before, *::after { font-family: inherit !important; }`
  - `pre, code, kbd, samp, tt { font-family: monospace !important; }`
  - `p, li, dd, dt, blockquote { font-weight: inherit !important; line-height: inherit !important; }`
  - heading rules for **all** levels, real and pseudo
  - quote role
  - `-cr-hint: toc-levelN` only on pseudo-headings
- Theme hash in the per-book cache; deterministic output, no timestamps.
- Tests for body inheritance, real headings, pseudo-headings, quotes, cache invalidation and determinism.
- Commit.

### C. Theme UI

- Font chooser for each role (installed fonts), weight, relative size, case, alignment.
- Body face write-through to KOReader's font setting; theme remains authoritative.
- “Prepare KOReader settings” sets Font Weight to 0; do not touch contrast/size/spacing/margins.
- Menu under Tools, with status, role editor, per-book use toggle, detected headings, view/copy CSS, export as style tweak.
- Pure settings-model tests; device smoke test for menu rendering.
- Commit.

### D. Detection tuning

- Consume the corpus report.
- Add the quote/epigraph role detector.
- Fix false positives/negatives with fixtures, especially the `p.other` case.
- Add a confidence threshold test matrix.
- Commit.

### E. Device acceptance

- `tools/Device.ps1 Backup` then `Deploy`.
- Run `docs/acceptance.md` plus: clean `h1`/`h2` book (real headings themed), Calibre pseudo-heading book, no-ToC book, negatives, progress/highlight preservation, per-book disable, restart persistence, alternative ToC.
- Exit KOReader gracefully so settings flush.
- Update `STATUS.md` with exact observations and screenshots under `local/captures/`.

### F. Only with owner approval

Body-size normalisation, per-book theme overrides, cached EPUB exporter. Do not start these unprompted.

## Subagent brief template

Give each implementation subagent:

- one work unit only
- exact files/areas it owns
- what it must not touch
- the acceptance tests and commands
- the report format: summary, files changed, tests run, remaining risks
- instruction to update `STATUS.md` only within its work unit

The parent, not the subagent, commits and decides the next unit.

## Hard constraints

- Do not modify `koreader-vault-reader` or `meaning-and-meditation`.
- Do not push.
- Do not factory-reset, uninstall FreeKiosk, change Device Owner, change the launcher, or reconfigure kiosk settings.
- No secrets in tracked files or reports; keep local data under ignored `local/`.
- Use `python -B` and the project's pinned LuaJIT.
- Distinguish observed results, hypotheses and untested plans. Never claim a device test or deployment that did not happen.

## Final report

When the work units are done, report:

- commits created
- exact tests run and results
- device observations, with paths to captures
- remaining known limitations
- whether the owner needs to make any decision

If the device or corpus is unavailable, stop at the last verified point and say exactly what is blocked.

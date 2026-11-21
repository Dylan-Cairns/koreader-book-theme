# Status

## Current work

Milestone 1 heading-normaliser engine is committed and verified offline. The product is pivoting to **Book Theme**: a role-based document typography plugin that owns body and heading type, detects pseudo-headings, and leaves the reading environment to KOReader.

The repository directory was renamed from `koreader-heading-normalizer` to **`C:\Users\dylan\Documents\development\koreader-book-theme`** on 2026-11-21 (commit `83f4e2c` before the move; history preserved). The plugin directory, menu text and `heading_normalizer` settings keys are unchanged until work unit A.

The next session must read `NEXT_AGENT.md` and execute its orchestration protocol. That file is the authoritative product contract where it supersedes the milestone-1 design.

## Decisions

- Book Theme owns body font family/weight, `p`/`li`/`blockquote` family and weight, quote/epigraph type, and all heading roles — real `h1`–`h6` as well as detected pseudo-headings.
- KOReader owns base font size, line spacing, margins, contrast/gamma, hyphenation and UI chrome.
- The theme is authoritative for body type but writes the body face through to KOReader's font setting so the Aa menu agrees. KOReader Font Weight must be 0; the theme owns weight.
- Body size normalisation is out of v1; forcing `1rem` on every `p` would enlarge footnotes and small print.
- No EPUB rewriting. The plugin changes presentation only, preserving sidecars, progress, highlights and bookmarks.
- Per-book CSS cache must include a theme hash, so changing a theme font invalidates that book's cached CSS on the next open.
- The auto-compaction buffer is global at 80% of the model window with a 40K retained tail; subagents are enabled globally.

## Tests run

Run on 2026-11-20/21 in this repository:

- `.\tools\Setup-Toolchain.ps1` — pinned KOReader v2026.07.1 source plus base verified; LuaJIT 2.1.1783773675 ready.
- `.\tools\Test.ps1` — Luacheck: 20 files, 0 warnings, 0 errors. LuaUnit: 36 tests, 36 successes. Handoff checks passed. Mock device checks passed: identity, deploy/backup/rollback, activation recovery, settings preservation, capture handling. No physical device operations in the mock test.
- Device (Go6, KOReader v2026.07.2, same commit as v2026.07.1): deployed `heading-normalizer.koplugin`, enabled for all books, menu under Tools. Real-book scan of *Rethinking meditation.epub*: 26 documents, 1 stylesheet, 88 ToC entries, 2 pseudo-headings (`p.bibliography` 100, `p.other` 39). Generated CSS viewed on-device.
- Device acceptance is **not** complete. Clean-EPUB behavior, pseudo-heading visual effect, progress/highlight preservation, per-book disable and restart persistence still need explicit checks.

## Device notes

- On 2026-11-21 the cleaned build (diagnostic markers removed, file-manager guard added) was redeployed to `/sdcard/koreader/plugins/heading-normalizer.koplugin` and the debug file removed. The Tools → Heading normaliser entry still attaches; no debug file was recreated. The plugin setting remained enabled.
- Settings flush on graceful exit. `am force-stop` after toggling a setting loses it.
- `sorting_hint = "tools"` works; nesting under `document_settings` did not attach.
- The plugin is also instantiated by the file manager; guard `init` and `addToMainMenu` on `self.ui.document`.
- `p.other` may be a false positive; the corpus audit must check it.
- Plugin path currently `/sdcard/koreader/plugins/heading-normalizer.koplugin`. Book Theme rename must update the device harness and backup prefixes.

## Next action

Start a new session in `C:\Users\dylan\Documents\development\koreader-book-theme` (the global compaction and subagent settings are active) and run `/orchestrate`, or say: “Read `NEXT_AGENT.md` and execute it.” The first step is the read-only EPUB corpus audit; implementation follows sequentially.

## Open work

- Rename product/plugin/menu to Book Theme.
- Theme model, CSS generator, theme-hash cache.
- Role-based font UI, body write-through, KOReader weight preparation.
- Corpus-driven detection tuning and quote role.
- Device acceptance.
- Optional later: body-size normalisation, per-book overrides, EPUB exporter (owner approval required).

# Status

## Current work

Milestone 1 heading-normaliser engine is committed and verified offline. The product is pivoting to **Book Theme**: a role-based document typography plugin that owns body and heading type, detects pseudo-headings, and leaves the reading environment to KOReader.

Work units A and B are complete. A (`f034e28`): plugin directory `plugin/book-theme.koplugin`, menu **Book Theme**, `book_theme*` settings with `heading_normalizer*` read fallback, device path `.../plugins/book-theme.koplugin`, legacy device install archived on deploy. B (`hn_theme.lua`, `hn_cache.lua`): role theme with defaults from the owner's tweak (body EB Garamond, headings Alegreya Sans), deterministic CSS (body, universal inherit, monospace exception, real `h1`–`h6`, pseudo levels, quote role), FNV-1a theme hash in a version-3 per-book cache. C: role editor under **Tools → Book Theme → Theme**, body write-through to `cre_font`/`font_face`, Prepare KOReader settings, export as style tweak (commit `60c4b32`). D (detection tuning) and its follow-up D1 are complete and committed: semantic allow-list with a deny-wins gate, ToC target shape check with wrapper descent, guide/landmarks/filename front-matter skip, separate quote role, selector sharing guard, running-head drop, confidence gate, ToC-exempt rule budget and an id fallback for ToC targets whose class selector is shared with body text. Corpus measurement is under **Tests run**. Unit E (device acceptance) is next; the acceptance matrix is in ignored `local/plan/device-acceptance.md`.

The repository directory was renamed from `koreader-heading-normalizer` to **`C:\Users\dylan\Documents\development\koreader-book-theme`** on 2026-11-21 (commit `83f4e2c` before the move; history preserved).

The next session must read `NEXT_AGENT.md` and execute its orchestration protocol. That file is the authoritative product contract where it supersedes the milestone-1 design.

## Plan — Book Theme session 2026-11-21

Owner approved end-to-end execution: corpus audit, work units A–E, device available and reserved; deployed `heading-normalizer.koplugin` may be deleted (no archive required).

1. Read-only corpus audit (49 EPUBs in `meaning-and-meditation`) via one research subagent, using the real Lua classifier; outputs in `local/corpus-audit/`, reusable scripts in `tools/`.
2. Unit A rename → Book Theme (plugin dir, menu, docs, harness, settings/cache migration with fallback).
3. Unit B theme model + deterministic CSS + theme-hash cache.
4. Unit C theme UI, body write-through, "Prepare KOReader settings".
5. Unit D detection tuning from the audit, quote/epigraph role, `p.other` fix, fixtures.
6. Unit E device backup/deploy/acceptance; graceful KOReader exit; record observations.
7. Default theme comes from the owner's current user tweak: body **EB Garamond**, headings **Alegreya Sans** (both installed on device); `cre_font` already "EB Garamond", `copt_font_base_weight` is currently 1 (Prepare action should set 0).

Session decisions (durable):

- Engine modules keep the `hn_*` names (allowed by the contract) to avoid churn; the plugin directory, product strings, settings keys and device paths become `book-theme`.
- New settings: global `book_theme_enabled`, theme table `book_theme_settings`; per-book `book_theme` cache (version + theme hash), `book_theme_disabled`. Old `heading_normalizer*` keys are read as a fallback and never destroyed.
- Role scale: body = EB Garamond normal; Part/Chapter/Section/Minor = Alegreya Sans bold at 1.45/1.3/1.15/0.95 rem; Minor uppercase; quotes = EB Garamond italic. Real `h1`∈Part … `h4`–`h6`∈Minor; detected levels map the same way.
- Theme hash: pure-Lua deterministic hash (FNV-1a over canonical serialisation), included in the per-book cache key; no timestamps in CSS.
- Watch out: `copt_font_base_weight` is 1 on the device; the Prepare action sets it to 0 and touches nothing else.

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
- Unit A (2026-11-21, commit `f034e28`): `.\tools\Test.ps1` — Luacheck 23 files, 0 warnings; LuaUnit 41/41; handoff checks 47 files; mock device checks include legacy plugin archival on deploy and old-manifest restore into the new path.
- Unit B (2026-11-21): `.\tools\Test.ps1` — Luacheck 27 files, 0 warnings; LuaUnit 81/81 (theme 21, cache 8, generate 14, scan 7, prior suites unchanged); handoff checks 51 files; mock device checks unchanged and passing. Default theme hash `74cfd6d8`. No device or ADB activity.
- Unit C (2026-11-21): `.\tools\Test.ps1` - Luacheck 27 files, 0 warnings; LuaUnit 88/88 (7 new theme helpers tests: body `set_role`, every role/field, `ROLE_ORDER`, `ROLE_LABELS`, `describe`); handoff checks 51 files; mock device checks unchanged and passing. Menu, lazy font list, write-through and export are not covered offline; no device or ADB activity.
- Unit D (2026-11-21): `.\tools\Test.ps1` - Luacheck 28 files, 0 warnings; LuaUnit 108/108 (20 new: F1-F10 detection fixtures, semantic deny-list, guide/landmarks/filename front-matter skips, quote role, six-case confidence matrix, front-matter path unit test); handoff checks 52 files; mock device checks unchanged and passing. No device or ADB activity.
- Unit D corpus measurement (2026-11-21, 49 books, reviewed verdict table unchanged): candidates TP 83 -> 73, FP 334 -> 17, unreviewed 0 -> 5; candidate precision 0.199 -> 0.8111, occurrence precision 0.2315 -> 0.9699; books with candidates 39 -> 31, books without a TP 16 -> 9. ToC-shaped recall 621/654 (94.95%) -> 392/654 (59.94%). The drop is the required rejection of `edefee52` `p.calibreN` (223 empty-text targets); excluding that pattern 392/431 = 90.95%, and the other uncovered entries are front-matter/notes furniture (`p.FM-HT`, `p.book-title`, `p.copy-txtN`, `p.crtf`, `header#headerindexN`), so genuine heading recall is unchanged. The 17 remaining FPs are title-page, copyright, byline and running-head furniture. The five unreviewed candidates are four quote rules and `390a89b9 p#p1` (a Praise-section line).
- Unit D follow-up D1 (2026-11-21, working tree): ToC id fallback plus a rule budget that never drops ToC rules. `.\tools\Test.ps1` - Luacheck 28 files, 0 warnings; LuaUnit 111/111 (3 new: 100-block/3-id fallback, shared class without id still dropped, 70-layout/5-ToC budget keeps 65); handoff 52 files; mock device checks unchanged. Corpus re-measured into `local/corpus-audit-after-d1/`, earlier outputs kept in `local/corpus-audit/`; only `0f571cb8` changed, gaining `p#sub2_6` and `p#sub2_13` (real sub-headings previously dropped as a shared class). Candidates TP 73 / FP 17 / PARTIAL 1 / unreviewed 7: precision is unchanged and the two new rules are unreviewed. The ToC recall estimate stays 392/654 (59.94%) because those ids land in a pattern group already credited through `p.subhead1`. `edefee52` still emits nothing: its 223 ToC fragments point at empty inline `<a id>` anchors inside `p.calibre1`, not at id-addressable blocks, and 94 of those entries sit on repeated running-head paragraphs and 20 on images. `bd1083b1` unchanged (`div.calibre_8` plus two quote rules). `9beffdc5`/`112f2ccd`/`6029b25d` still emit nothing; `390a89b9` keeps its three ToC rules; `f840350d p.other` still emitted. `tools/corpus_audit.py` now records `id_keys` per ToC target pattern so the recall estimate can credit exact id rules. No device or ADB activity.
- Device acceptance is **not** complete. Clean-EPUB behavior, pseudo-heading visual effect, progress/highlight preservation, per-book disable and restart persistence still need explicit checks.

## Device notes

- On 2026-11-21 the cleaned build (diagnostic markers removed, file-manager guard added) was redeployed to `/sdcard/koreader/plugins/heading-normalizer.koplugin` and the debug file removed. The Tools → Heading normaliser entry still attaches; no debug file was recreated. The plugin setting remained enabled.
- Settings flush on graceful exit. `am force-stop` after toggling a setting loses it.
- `sorting_hint = "tools"` works; nesting under `document_settings` did not attach.
- The plugin is also instantiated by the file manager; guard `init` and `addToMainMenu` on `self.ui.document`.
- `p.other` is a **true positive**: a one-line list caption with no heading markup (corpus audit 2026-11-21). Its neighbour `p.para-ul` is a figure caption and a false positive, now rejected.
- Plugin path before unit E: `/sdcard/koreader/plugins/heading-normalizer.koplugin`. Deploy moves it to `/sdcard/Documents/BooxSetupBackup/heading-normalizer-legacy-<stamp>` and installs `/sdcard/koreader/plugins/book-theme.koplugin`.

## Next action

Run unit E: `.\tools\Device.ps1 Backup` → `Deploy` → verify the legacy plugin was archived to `/sdcard/Documents/BooxSetupBackup/` and only `book-theme.koplugin` is active → work through `docs/acceptance.md` with the books listed in `local/plan/device-acceptance.md` → capture screenshots → quit KOReader gracefully → record observed results here. Then report to the owner.

## Open work

- Device acceptance (unit E) is the remaining milestone work. It needs the following observed on the Go6, not inferred: legacy-plugin archival, menu rendering and role editing, a clean book reporting `no-pseudo-headings` with the theme hash, `Rethinking Meditation` styling `p.bibliography`/`p.other`, the pseudo-only book, progress/highlight survival, the CSS export path, and restart persistence.
- Case 3 of `docs/acceptance.md` (no-ToC book, layout fallback) has no matching book in the owner's library — every corpus EPUB has a ToC. It is covered offline by the confidence-matrix tests only and must not be reported as device-verified.
- Optional later: body-size normalisation, per-book overrides, EPUB exporter (owner approval required).

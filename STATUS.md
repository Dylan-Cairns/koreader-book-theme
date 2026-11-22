# Status

## Current work

Milestone 1 heading-normaliser engine is committed and verified offline. The product is pivoting to **Book Theme**: a role-based document typography plugin that owns body and heading type, detects pseudo-headings, and leaves the reading environment to KOReader.

Work units A and B are complete. A (`f034e28`): plugin directory `plugin/book-theme.koplugin`, menu **Book Theme**, `book_theme*` settings with `heading_normalizer*` read fallback, device path `.../plugins/book-theme.koplugin`, legacy device install archived on deploy. B (`hn_theme.lua`, `hn_cache.lua`): role theme with defaults from the owner's tweak (body EB Garamond, headings Alegreya Sans), deterministic CSS (body, universal inherit, monospace exception, real `h1`–`h6`, pseudo levels, quote role), FNV-1a theme hash in a version-3 per-book cache. C: role editor under **Tools → Book Theme → Theme**, body write-through to `cre_font`/`font_face`, Prepare KOReader settings, export as style tweak (commit `60c4b32`). D (detection tuning) and its follow-up D1 are complete and committed: semantic allow-list with a deny-wins gate, ToC target shape check with wrapper descent, guide/landmarks/filename front-matter skip, separate quote role, selector sharing guard, running-head drop, confidence gate, ToC-exempt rule budget and an id fallback for ToC targets whose class selector is shared with body text. Corpus measurement is under **Tests run**. Unit E (device acceptance) ran on 2026-11-21; the observed results are in **Unit E device acceptance** below, and the working matrix is in ignored `local/plan/device-acceptance.md`.

Follow-up after unit E (owner feedback, 2026-11-21): per-role typography controls were rejected as tinkering, and the owner reported that *Buddhism* chapter titles render as "19Philosophy". Both are addressed. The menu is now two quick switches — **Body font** and **Heading font** — plus restore and the diagnostics; sizes, weights, case, alignment and spacing are fixed defaults. Settings store only `{body_font, heading_font}`. The Lopez defect was ours: the publisher separates `<h1><span class="chapter-number">19</span>Philosophy</h1>` only in its own stylesheet, the owner has publisher CSS disabled (`copt_embedded_css = 0`), and the heading descendant reset also flattened the number to full size. The scan now detects a glued leading chapter number inside a real heading and the generator gives that one class a block line at 0.75em; `sup`/`sub` sizing was added for the same reason (footnote markers). Cache version 4 rebuilds every book once. The default theme hash is still `74cfd6d8`.

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
- New settings: global `book_theme_enabled`, theme table `book_theme_settings` (after the follow-up it holds only `{body_font, heading_font}`); per-book `book_theme` cache (version + theme hash), `book_theme_disabled`. Old `heading_normalizer*` keys are read as a fallback and never destroyed.
- Role scale is fixed, non-editable default: body = EB Garamond normal; Part/Chapter/Section/Minor = Alegreya Sans bold at 1.45/1.3/1.15/0.95 rem; Minor uppercase; quotes = EB Garamond italic. Real `h1`∈Part … `h4`–`h6`∈Minor; detected levels map the same way. The UI changes only the body face and the heading face.
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
- Device acceptance is now covered by the section below.
- Follow-up: two-font theme and glued chapter numbers (2026-11-21). `.\tools\Test.ps1` - Luacheck 29 files, 0 warnings; LuaUnit 121/121 (13 new: `Theme.from_fonts`/`settings`/legacy migration, marker positive and negative fixtures, generator marker and `sup`/`sub` rules); handoff checks 53 files; mock device checks unchanged and passing. Corpus re-run with the real classifier into `local/tmp/classifier-new.json` against `local/corpus-audit-after-d1/`: candidates and totals byte-identical for all 49 books; the only change is the new `heading_markers` counter, which is 1 for `6ac1f97c` (Lopez) and 1 for `f339bd11`, and 0 everywhere else. A direct scan of those two books emits `h1 .chapter-number { display: block ... }`; the pagebreak book `390a89b9` emits no marker rule.

## Unit E device acceptance (2026-11-21, observed)

Device Go6 `6C7AE6EA`, KOReader v2026.07.2, 1072×1448. Everything in this section was seen on the device in this session; screenshots are in disposable `local/captures/`.

- `.\tools\Device.ps1 Backup` wrote `local/backups/20261121-160218-040` (manifest kind `book-theme-device-backup-v1`, `legacyPluginPresent = true`). `Deploy` installed `/sdcard/koreader/plugins/book-theme.koplugin` and moved the old plugin to `/sdcard/Documents/BooxSetupBackup/heading-normalizer-legacy-20261121160229330`. The plugins directory now holds `book-theme.koplugin` plus the unrelated `cleanlibrary`, `vault-reader` and `vos` plugins.
- **Tools → Book Theme** rendered, at the time of unit E, in order: Enable for all books ✔, Disable for this book ☐, Theme, Prepare KOReader settings, Status and detected headings, View generated CSS, Copy generated CSS, Export generated CSS as style tweak, Re-scan this book on next open. (The follow-up section below replaces this layout.)
- Case 1 (clean book): *Buddhism: A Journey through History* reports `Skipped: no-pseudo-headings`, 71 documents, 1 stylesheet, 36 ToC entries, 0 pseudo-headings, theme `74cfd6d8`. Body text is EB Garamond; the chapter opening "19 Philosophy" is Alegreya Sans bold. At the time of unit E the publisher's number and title ran together ("19Philosophy"); the follow-up below fixes that.
- Case 2 (pseudo-headings): *Rethinking Meditation* reports 26 documents, 1 stylesheet, 88 ToC entries and exactly the offline rules — L2 `p.bibliography` (100) "Works Cited" and L2 `p.other` (39) "The Seventy-Five Dharmas According to the Sarvāstivāda Abhidharma". On the page "Works Cited" is Alegreya Sans bold at heading size, left aligned, with the bibliography body still EB Garamond. That element is a *detected* selector, so this also shows the plugin's CSS outranks the enabled user tweak `dylan_style.css`.
- Case 5 (per-book switch): disabling for *Rethinking Meditation*, closing and reopening returned "Works Cited" to the publisher's serif heading; re-enabling and reopening restored the sans heading. *Buddhism* kept its styling throughout.
- Case 6 (reading state): the book holds 52 annotations (Bookmarks dialog) and a highlight still renders on page 800 with its original text; the saved position survived the deploy and every reopen; the `.sdr` keeps one metadata file, with no migration or duplicate sidecar.
- Case 8 (alternative ToC): after the confirmation dialog, the ToC was rebuilt from document headings and listed "Works Cited" at its level; reverting restored the publisher ToC and left `handmade_toc_enabled = false` with no stray global key.
- Case 9 (restart persistence): after a graceful quit and relaunch the book opened at the saved page with the generated stylesheet already applied (no visible reflow) and the cached report available.
- CSS export: the toast confirms `/storage/emulated/0/koreader/styletweaks/book-theme.css`; the file is 3451 bytes and starts `/* book-theme v2: per-book typography; theme 74cfd6d8. */`.
- Role editing round trip (old per-role UI, since removed): setting Section heading font to FreeSans took effect on the next open (heading rendered in FreeSans, cache `theme_hash cc3ae712`). **Restore default theme** showed its toast; after reopening, the heading rendered identically to the earlier default and the cache was rewritten to `theme_hash 74cfd6d8`, version 3, with no FreeSans left. `settings.reader.lua` has no `book_theme_settings` afterwards, and `FreeSans` remains only in KOReader's own font list.
- Logs: `.\tools\Device.ps1 Logs` captured a logcat with no `book-theme:` errors or warnings; the only book-theme matches are media-scanner lines for the capture temporaries.
- Final device state: Book Theme enabled for all books, no per-book override, default theme, alternative ToC off, KOReader closed gracefully from its menu (never force-stopped).

Not observed on device — do not report these as passed:

- Case 3: no book in the library lacks a usable ToC, so the layout fallback is covered by offline tests only.
- Case 4 beyond front matter: the *Relationality* title page still styles `p.fm-title`/`p.title`/`p.subtitle` as headings (known cosmetic furniture false positive, never body text); the poetry/drop-cap/footnote checks were not repeated on device.
- Case 7: no malformed, encrypted or oversized book was tried.
- `Prepare KOReader settings` was not run in this session.

## Follow-up device check (2026-11-21, observed)

Same device and session as unit E, after redeploying the follow-up build (`.\tools\Device.ps1 Deploy`, backup `local/backups/20261121-171247-705`). Everything here was seen on the device; screenshots are in disposable `local/captures/`.

- **Tools → Book Theme** now renders: **Body font**, **Heading font**, **Restore default theme**, **Enable for all books** ✔, **Disable for this book** ☐, **Diagnostics** (Status and detected headings, View/Copy/Export generated CSS, Prepare KOReader settings, Re-scan this book on next open). There is no per-role editor left in the menu.
- **Chapter number fixed** (*Buddhism*, chapter 19): "19" now sits on its own line above "Philosophy", smaller than the title and letter-spaced, instead of reading "19Philosophy". The rule is `h1 .chapter-number`, so the title line itself keeps the heading face and size. The same page's footnote marker (`<sup>1</sup>`) now renders small and raised rather than at body size on the baseline.
- **Status and detected headings** reports `Body font: EB Garamond`, `Heading font: Alegreya Sans`, `Theme: 74cfd6d8`, and the new `Glued chapter numbers: 1` line.
- **Heading font switch**: choosing FreeSans under **Heading font** took effect on the next open (headings sans, body unchanged); **Restore default theme** and reopening returned headings to Alegreya Sans. The book's cache was rewritten each time.
- **Disk state** after the round trip: the book cache is `version 4`, `theme_hash "74cfd6d8"`, report includes `heading_markers`, and its banner is `book-theme v2: per-book typography; theme 74cfd6d8.` `settings.reader.lua` has no `book_theme_settings` at the default theme, and the legacy `heading_normalizer_enabled` key is still present and untouched.
- **User tweak note**: the enabled `dylan_style.css` still sets `span` to EB Garamond, which is why the chapter-number rule sets only `display`, size, spacing and margin (never a family) — the number keeps following the reader's tweak. `book-theme.css` is not enabled, so no stylesheet is duplicated.
- KOReader was closed from its File manager exit row afterwards; `Status` then showed the Onyx launcher, not a force-stop.
- Not exercised in this check: cases 3, 4 (poetry/drop cap beyond front matter) and 7, exactly as listed below.

## Device notes

- On 2026-11-21 the cleaned build (diagnostic markers removed, file-manager guard added) was redeployed to `/sdcard/koreader/plugins/heading-normalizer.koplugin` and the debug file removed. The Tools → Heading normaliser entry still attaches; no debug file was recreated. The plugin setting remained enabled.
- Settings flush on graceful exit. `am force-stop` after toggling a setting loses it.
- `sorting_hint = "tools"` works; nesting under `document_settings` did not attach.
- The plugin is also instantiated by the file manager; guard `init` and `addToMainMenu` on `self.ui.document`.
- `p.other` is a **true positive**: a one-line list caption with no heading markup (corpus audit 2026-11-21). Its neighbour `p.para-ul` is a figure caption and a false positive, now rejected.
- Plugin path before unit E: `/sdcard/koreader/plugins/heading-normalizer.koplugin`. Deploy moves it to `/sdcard/Documents/BooxSetupBackup/heading-normalizer-legacy-<stamp>` and installs `/sdcard/koreader/plugins/book-theme.koplugin`.
- Settings shape on disk: `book_theme_enabled` is absent when the default (enabled) applies, `book_theme_settings` is absent at the default theme, and `book_theme_disabled` exists only while a book is opted out. The legacy `heading_normalizer_enabled` key is still present by design.
- Deterministic book opening: `adb shell am start -a android.intent.action.VIEW -d 'file:///sdcard/Books/...epub' -t application/epub+zip -n org.koreader.launcher/.MainActivity` opens that exact book. This is the reliable way in; the file manager's history/cover view is not.
- Menu panes remember their last submenu, so "open menu, tap tab, tap offset" chains land on the wrong rows. Capture between the tab tap and the item tap.
- `adb shell input text 'a%sb'` inserts a space; `%20` is inserted literally. On-screen keyboard taps work for deletes.
- Theme hashes seen on device: default `74cfd6d8`, Section heading = FreeSans variant `cc3ae712` (old per-role UI). A theme change invalidates the per-book cache, and the next open re-scans and rewrites it (verified both directions). The cache version is now 4; a version-3 cache is rebuilt once.
- The owner has publisher CSS disabled on device (`copt_embedded_css = 0`, `copt_embedded_fonts = 1`). Anything an EPUB gets only from its own stylesheet — chapter-number breaks, `sup` sizing — must therefore be handled by our generated CSS.
- Verified on device: crengine honours `display: block` on a `<span>` inside an `h1`, so the marker rule works without changing markup. The probe was a temporary append to `dylan_style.css`, restored byte-for-byte afterwards.

## Next action

Unit E and its follow-up (two-font theme, glued chapter numbers, `sup`/`sub`) are complete and verified on device for the cases listed above. The next session should start from **Open work**, not from a redeploy. Anything that changes detection or the CSS needs `.\tools\Test.ps1` plus a fresh corpus measurement, and a device deploy only when the change is meant to ship.

## Open work

- Unverified acceptance items: case 3 (no-ToC book), the rest of case 4 (poetry, epigraph, drop cap, footnote), and case 7 (malformed, encrypted, oversized books). Case 3 needs a real no-ToC EPUB before it can be signed off; the owner's library has none.
- The chapter-number marker rule trusts the heading shape, not the publisher's class: it fires on any 1–3 digit first child with no whitespace and no `page`/`note`/`ref`/`bullet`/`marker`/`toc`/`index` class token. Corpus-wide that is 2 of 49 books and 0 paragraph false positives, but a book that deliberately puts the number inline with a margin gap (the corpus had one, `f339bd11`) gets a block line instead of a gap. Worth a look if the owner ever prefers the inline form.
- Known cosmetic false positive: title-page furniture rules (`p.fm-title`, `p.title`, `p.subtitle` in *Relationality*) make a title page look like headings. They never touch body text; tightening them is optional.
- `edefee52` ToC recall is accepted as a miss: its 223 fragments point at empty inline `<a id>` anchors inside `p.calibre1`, so CSS cannot select their parent and crengine has no `:has()`.
- Optional later: body-size normalisation, per-book overrides, EPUB exporter (owner approval required).

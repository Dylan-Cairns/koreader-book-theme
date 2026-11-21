# Agent instructions

This repository is the independent **KOReader Heading Normaliser** plugin. It is not part of `koreader-vault-reader` and must not modify that project.

Read `STATUS.md`, `docs/harness.md` and `docs/design.md` at session start. Run `tools/Test.ps1` for offline checks; `tools/Device.ps1 Status` checks hardware state read-only. Update `STATUS.md` after milestones, deployments or device-state changes, including the exact tests run and the remaining work.

## Product rule

The plugin must **not rewrite the EPUB**. It finds pseudo-headings in EPUB markup, generates a per-book stylesheet, and injects it into KOReader's existing style-tweak pipeline before the first render. This preserves progress, highlights, bookmarks and per-book settings, which are keyed by the file's partial MD5.

Do not add a cached or destructive EPUB rewriter as the default path. A future opt-in exporter is possible, but it needs explicit sidecar migration and backup design.

## KOReader reference

- Pinned source: `local/upstream/koreader` at v2026.07.1, including the `base` submodule. Revisions are in `toolchain.lock.json`.
- Development runtime: pinned LuaJIT under `local/toolchain`.
- Search the installed release's source before current master. The plugin uses semi-internal hooks (`ReaderStyleTweak:getCssText`, `PreRenderDocument`, `Archiver.Reader`); re-check them on every KOReader upgrade.
- Style injection must happen at `PreRenderDocument`. Applying a new stylesheet after the first render changes the rendering hash and can trigger `ReaderRolling`'s reload machinery.

## Device rules

- Read `docs/device-runbook.md` and `local/device-access.md` before using ADB.
- Target the configured serial/model explicitly. Treat recorded device state as historical until checked.
- Back up affected device files before deployment. `tools/Device.ps1 Deploy` backs up KOReader settings and this plugin, stages the replacement, and attempts rollback on activation failure.
- Never factory-reset, uninstall FreeKiosk, change Device Owner, change the default launcher, or reconfigure kiosk settings. FreeKiosk is owner-managed outside this project.
- Preserve KOReader preferences, fonts, gestures, progress and other plugins. This plugin must not write into book files.

## Engineering rules

- Keep parser/classifier/generator modules pure Lua with no KOReader dependencies. `main.lua` is the only adapter.
- Every detection change needs a positive and a negative fixture test. A false positive that restyles body text is worse than a missed pseudo-heading.
- Keep generated CSS deterministic: sorted selectors, no timestamps, no random ordering. Unstable CSS invalidates the rendering cache on every open.
- Use `python -B` if Python is needed; keep generated outputs ignored.
- Do not delegate unless the user asks. Do not publish, push, or message anyone without instruction.
- Distinguish observed behaviour, hypotheses and untested plans. Never claim a device test happened without doing it.

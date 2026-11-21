# Development harness

## Baseline

Windows PowerShell host. KOReader reference is pinned at **v2026.07.1** in `local/upstream/koreader`, including its `base` submodule; revisions are in `toolchain.lock.json`. The test runtime is a pinned LuaJIT built locally from the same source revision, not host Lua 5.3.

This is source inspection plus a host LuaJIT test environment, not a full KOReader emulator or Android build environment.

## Commands

```powershell
.\tools\Setup-Toolchain.ps1       # verify/setup pinned sources and Windows LuaJIT
.\tools\Test.ps1                  # offline lint, unit tests, handoff and mock-device checks
.\tools\Test.ps1 -Device          # same plus read-only real device status
.\tools\Device.ps1 Status
```

Setup needs Git/network and MSVC x64 Build Tools. Third-party sources and binaries stay under Git-ignored `local/`. Luacheck's library API runs directly under LuaJIT; LuaUnit 3.5 runs under the same runtime with KOReader's `table.pack`/`table.unpack` patch.

`Test.ps1`:

1. Parses PowerShell under `tools/` and `tests/`.
2. Lints Lua under `tools/`, `tests/` and `plugin/`.
3. Discovers `tests/unit/*_test.lua` and runs them under LuaJIT; each file returns a LuaUnit table, and the runner rejects zero executed tests.
4. Runs `tests/handoff-check.cjs`: no tracked `local/` assets, no broken documentation links, model-free OpenCode config.
5. Runs `tests/device-harness-check.cjs`: deploy/backup/rollback/capture against a fake ADB transport under `KVR_RUN_ROOT`.
6. Fails if `plugin/` exists but `STATUS.md` has no `## Tests run` section.

The plugin's parser, classifier and generator are pure Lua, so most coverage is host tests. The device harness proves the deploy/restore plumbing, not the Android rendering.

## Layout

```
plugin/heading-normalizer.koplugin/
  main.lua            KOReader adapter: hooks, menu, archive reader
  hn_util.lua         paths, attributes, entities
  hn_html.lua         tolerant HTML scanner
  hn_css.lua          simple-selector CSS parser and computed styles
  hn_epub.lua         container/OPF/NCX/nav parsing
  hn_classify.lua     ToC, semantic and layout classification
  hn_generate.lua     deterministic stylesheet generation
  hn_scan.lua         orchestration and failure containment
tests/unit/           LuaUnit suites, one per pure module
tests/helpers.lua     in-memory archive reader and fixture helpers
```

## Device commands

Device identity is in ignored `local/device.json`; serial and model are verified before every operation. `KVR_DEVICE_CONFIG` is an advanced override used only by fake-device tests.

```powershell
.\tools\Device.ps1 Capture
.\tools\Device.ps1 Logs
.\tools\Device.ps1 Backup
.\tools\Device.ps1 Launch
.\tools\Device.ps1 Deploy
.\tools\Device.ps1 Restore -Backup C:\path\to\harness-backup
```

Deploy requires `main.lua` and `_meta.lua`, stops KOReader, backs up settings and this plugin, stages the replacement, archives the prior plugin, and attempts rollback if activation fails. Restore replaces only this plugin; it does not overwrite settings or book sidecars. Remote replacement is restricted to `/sdcard/koreader/plugins/heading-normalizer.koplugin`.

Capture writes a binary-safe PNG under `local/captures/` and removes its device-side temporaries. Empty or non-PNG images fail explicitly.

## Device safety

FreeKiosk is owner-managed outside this project. Do not re-enable it, change Device Owner, uninstall it, change the default launcher, or reconfigure kiosk settings. `Status` reports `lockTask` read-only.

Do not run raw `uiautomator dump` or `screencap` into `/sdcard`; use `Device.ps1 Capture`.

## Session budget and delegation

Global OpenCode config (applies to every project) sets automatic compaction to keep a 40K tail with an 80% buffer, so a 1M-context model compacts around 200K rather than near its advertised ceiling. DeepSeek's reliable working range is roughly 128K–200K; compaction earlier than the window is deliberate.

Subagents are enabled globally and the project-level denial has been removed. This project authorises delegation: use one read-only corpus research subagent first, then implementation subagents strictly sequentially. `NEXT_AGENT.md` is the orchestration contract.

## Working state

Maintain `STATUS.md` after milestones, deployment or device-state changes: current work, decisions, exact tests run, deployed version, device state and next action. Keep credentials and raw logs under `local/`. `local/captures/`, `local/logs/` and `local/backups/` are disposable evidence and are pruned by `Device.ps1`.

# Device runbook

## Target

The device is the owner's Boox. Identity and paths are in Git-ignored `local/device.json`; `tools/Device.ps1` verifies the serial and model before every operation. Do not target a device that fails that check.

KOReader root: `/sdcard/koreader`. Plugin directory: `/sdcard/koreader/plugins/book-theme.koplugin`. Setup backups: `/sdcard/Documents/BooxSetupBackup/`.

The pre-rename install lived at `/sdcard/koreader/plugins/heading-normalizer.koplugin`. It must not stay active beside Book Theme — both would append a stylesheet. `Deploy` moves it to `/sdcard/Documents/BooxSetupBackup/heading-normalizer-legacy-<stamp>`; only one such archive is kept.

## Before deploying

1. `.\tools\Device.ps1 Status` — confirm the expected device, KOReader version and foreground app.
2. `.\tools\Test.ps1` — offline tests must pass.
3. `.\tools\Device.ps1 Backup` — current settings and plugin state.
4. `.\tools\Device.ps1 Deploy` — stages the plugin, archives the previous one, and rolls back if activation fails.

## After deploying

1. Open one clean EPUB and one pseudo-heading EPUB.
2. Enable the plugin and confirm the report.
3. Check progress and a highlight survive.
4. Record exact results in `STATUS.md`.

## Do not

- Factory reset, uninstall or reconfigure FreeKiosk, change Device Owner, or change the default launcher.
- Change KOReader's fonts, gestures or other plugins as part of this task.
- Write into book files; this plugin only adds a per-book stylesheet setting.
- Leave raw captures or UI dumps on `/sdcard`.

## Recovery

`tools/Device.ps1 Restore -Backup <dir>` replaces only this plugin from a harness backup. It backs up the current state first. Book progress and KOReader preferences are not overwritten.

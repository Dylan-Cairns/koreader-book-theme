[CmdletBinding()]
param(
    [ValidateSet('Status', 'Capture', 'Logs', 'Backup', 'Deploy', 'Restore', 'Launch')]
    [string]$Action = 'Status',
    [string]$Source,
    [string]$Backup
)
. "$PSScriptRoot/Common.ps1"
Assert-ReaderConnected
$configTask = Get-DeviceConfig
$pluginTask = '/sdcard/koreader/plugins/book-theme.koplugin'
# Pre-rename install. It must never stay active next to the Book Theme plugin.
$legacyPluginTask = '/sdcard/koreader/plugins/heading-normalizer.koplugin'
$backupRootTask = '/sdcard/Documents/BooxSetupBackup'

function Remove-OldRunDirectories {
    param([string]$Category, [int]$Keep)
    $rootTask = if ($env:KVR_RUN_ROOT) { [IO.Path]::GetFullPath($env:KVR_RUN_ROOT) } else { $script:ProjectRoot }
    $directoryTask = Join-Path $rootTask "local/$Category"
    if (-not (Test-Path -LiteralPath $directoryTask)) { return }
    Get-ChildItem -LiteralPath $directoryTask -Directory |
        Sort-Object Name -Descending |
        Select-Object -Skip $Keep |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}

function Remove-OldDevicePluginBackups {
    param([int]$Keep = 1)
    $listingTask = Invoke-Adb -AdbArgs @('shell', "ls -1 $backupRootTask") -AllowFailure
    if ($listingTask.ExitCode -ne 0) { return }
    $namesTask = @($listingTask.Output -split "`n")
    # heading-normalizer-legacy- is the archived pre-rename install, kept only
    # long enough to recover from a bad deploy.
    foreach ($prefixTask in @('book-theme-previous-', 'heading-normalizer-legacy-')) {
        $matchesTask = @($namesTask |
            Where-Object { $_ -match ('^' + [regex]::Escape($prefixTask)) } |
            Sort-Object -Descending)
        foreach ($nameTask in ($matchesTask | Select-Object -Skip $Keep)) {
            $null = Invoke-Adb -AdbArgs @('shell', "rm -rf '$backupRootTask/$nameTask'") -AllowFailure
        }
    }
}

function Get-ManifestFlag {
    param($Manifest, [string]$Name)
    $propertyTask = $Manifest.PSObject.Properties[$Name]
    return [bool]($propertyTask -and $propertyTask.Value)
}

function Backup-Reader {
    $destinationTask = New-RunDirectory 'backups'
    $statusTask = Get-ReaderStatus
    $presentTask = Test-DevicePath $pluginTask
    $legacyPresentTask = Test-DevicePath $legacyPluginTask
    $relativePathsTask = @('settings.reader.lua', 'history.lua', 'defaults.custom.lua', 'settings')
    if ($presentTask) { $relativePathsTask += 'plugins/book-theme.koplugin' }
    if ($legacyPresentTask) { $relativePathsTask += 'plugins/heading-normalizer.koplugin' }
    foreach ($relativeTask in $relativePathsTask) {
        $remoteTask = '/sdcard/koreader/' + $relativeTask
        if (Test-DevicePath $remoteTask) {
            $targetTask = Join-Path $destinationTask $relativeTask
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetTask) | Out-Null
            $null = Invoke-Adb -AdbArgs @('pull', $remoteTask, $targetTask)
        }
    }
    Write-JsonFile (Join-Path $destinationTask 'manifest.json') ([ordered]@{
        kind = 'book-theme-device-backup-v1'; serial = $configTask.serial
        pluginPath = $pluginTask; pluginPresent = $presentTask
        legacyPluginPath = $legacyPluginTask; legacyPluginPresent = $legacyPresentTask
        status = $statusTask
        note = 'Settings are backed up for recovery context. Restore action replaces only this plugin, not user preferences or book sidecars.'
    })
    return $destinationTask
}

# Resolves the plugin folder to install from a backup. An old
# heading-normalizer-device-backup-v1 manifest stores it under the legacy name,
# and it is installed at the Book Theme path.
function Get-BackupPluginSource {
    param([string]$BackupPath, [bool]$PluginPresent, [bool]$LegacyPluginPresent)
    $currentTask = Join-Path $BackupPath 'plugins/book-theme.koplugin'
    $legacyTask = Join-Path $BackupPath 'plugins/heading-normalizer.koplugin'
    if ($PluginPresent) {
        if (-not (Test-Path -LiteralPath (Join-Path $currentTask 'main.lua'))) { throw 'Backup reports the plugin present but plugins/book-theme.koplugin is missing' }
        return $currentTask
    }
    if ($LegacyPluginPresent) {
        if (-not (Test-Path -LiteralPath (Join-Path $legacyTask 'main.lua'))) { throw 'Backup reports the legacy plugin present but plugins/heading-normalizer.koplugin is missing' }
        return $legacyTask
    }
    return $null
}

# The pre-rename plugin must not load beside Book Theme: both would wrap
# ReaderStyleTweak:getCssText and append two stylesheets.
function Archive-LegacyPlugin {
    param([string]$Suffix)
    if (-not (Test-DevicePath $legacyPluginTask)) { return }
    $archiveTask = "$backupRootTask/heading-normalizer-legacy-$Suffix"
    $null = Invoke-Adb -AdbArgs @('shell', "mkdir -p $backupRootTask")
    $moveTask = Invoke-Adb -AdbArgs @('shell', "mv '$legacyPluginTask' '$archiveTask'") -AllowFailure
    if ($moveTask.ExitCode -ne 0) {
        throw "Could not archive the legacy plugin at $legacyPluginTask. Move or remove it before using Book Theme."
    }
}

function Install-PluginDirectory {
    param([string]$Directory)
    foreach ($requiredTask in @('main.lua', '_meta.lua')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $requiredTask))) { throw "Plugin missing $requiredTask" }
    }
    # Only fixed project-specific destinations may be replaced. No recursive deletion.
    $suffixTask = Get-Date -Format 'yyyyMMddHHmmssfff'
    $stageTask = "/sdcard/koreader/plugins/book-theme.stage-$suffixTask"
    $archiveTask = "$backupRootTask/book-theme-previous-$suffixTask"
    $null = Invoke-Adb -AdbArgs @('push', $Directory, $stageTask)
    $null = Invoke-Adb -AdbArgs @('shell', "test -f '$stageTask/main.lua' && test -f '$stageTask/_meta.lua'")
    $null = Invoke-Adb -AdbArgs @('shell', "mkdir -p $backupRootTask")
    if (Test-DevicePath $pluginTask) {
        $null = Invoke-Adb -AdbArgs @('shell', "mv '$pluginTask' '$archiveTask'")
    }
    $resultTask = Invoke-Adb -AdbArgs @('shell', "mv '$stageTask' '$pluginTask'") -AllowFailure
    if ($resultTask.ExitCode -ne 0) {
        if (Test-DevicePath $archiveTask) { $null = Invoke-Adb -AdbArgs @('shell', "mv '$archiveTask' '$pluginTask'") }
        throw 'Plugin activation failed; previous plugin restored if available.'
    }
    Archive-LegacyPlugin -Suffix $suffixTask
}

switch ($Action) {
    'Status' { Get-ReaderStatus | ConvertTo-Json }
    'Capture' {
        $destinationTask = New-RunDirectory 'captures'
        $remoteTask = "$backupRootTask/book-theme-capture-" + [guid]::NewGuid().ToString('N')
        $null = Invoke-Adb -AdbArgs @('shell', "mkdir -p $backupRootTask")
        $captureTask = Invoke-Adb -AdbArgs @('shell', "screencap -p $remoteTask.png") -AllowFailure
        $pullTask = Invoke-Adb -AdbArgs @('pull', "$remoteTask.png", (Join-Path $destinationTask 'screen.png')) -AllowFailure
        $dumpTask = Invoke-Adb -AdbArgs @('shell', "uiautomator dump $remoteTask.xml") -AllowFailure
        if ($dumpTask.ExitCode -eq 0) { $null = Invoke-Adb -AdbArgs @('pull', "$remoteTask.xml", (Join-Path $destinationTask 'ui.xml')) -AllowFailure }
        # Captures are pulled locally; do not leave the device-side temporary files.
        $null = Invoke-Adb -AdbArgs @('shell', "rm -f '$remoteTask.png' '$remoteTask.xml'") -AllowFailure
        $statusTask = Get-ReaderStatus
        $statusTask['captureCommandExit'] = $captureTask.ExitCode
        Write-JsonFile (Join-Path $destinationTask 'status.json') $statusTask
        $imageTask = Join-Path $destinationTask 'screen.png'
        $bytesTask = if (Test-Path -LiteralPath $imageTask) { [IO.File]::ReadAllBytes($imageTask) } else { [byte[]]@() }
        $validTask = $captureTask.ExitCode -eq 0 -and $pullTask.ExitCode -eq 0 -and @($bytesTask).Length -ge 8 -and [BitConverter]::ToString($bytesTask[0..7]) -eq '89-50-4E-47-0D-0A-1A-0A'
        if (-not $validTask) { throw "No valid PNG captured. Check that the device screen is on and unlocked. UI/status saved in $destinationTask. Do not infer screen appearance from an empty image." }
        Remove-OldRunDirectories -Category 'captures' -Keep 20
        [pscustomobject]@{ directory = $destinationTask; screenshot = $imageTask } | ConvertTo-Json
    }
    'Logs' {
        $destinationTask = New-RunDirectory 'logs'
        $logTask = Invoke-Adb -AdbArgs @('logcat', '-d', '-v', 'threadtime', '-t', '2000')
        [IO.File]::WriteAllText((Join-Path $destinationTask 'logcat.txt'), $logTask.Output)
        foreach ($remoteTask in @('/sdcard/koreader/crash.log', '/sdcard/Android/data/org.koreader.launcher/files/crash.log')) {
            if (Test-DevicePath $remoteTask) { $null = Invoke-Adb -AdbArgs @('pull', $remoteTask, (Join-Path $destinationTask ((Split-Path $remoteTask -Leaf) + '-' + [guid]::NewGuid().ToString('N') + '.txt'))) }
        }
        Write-JsonFile (Join-Path $destinationTask 'status.json') (Get-ReaderStatus)
        Remove-OldRunDirectories -Category 'logs' -Keep 3
        Write-Output "Logs saved locally: $destinationTask"
    }
    'Backup' {
        Stop-Reader
        try {
            $backupTask = Backup-Reader
            Remove-OldRunDirectories -Category 'backups' -Keep 3
            Write-Output $backupTask
        }
        finally { $null = Invoke-Adb -AdbArgs @('shell', 'am start -n org.koreader.launcher/.MainActivity') }
    }
    'Deploy' {
        if (-not $Source) { $Source = Join-Path $script:ProjectRoot 'plugin/book-theme.koplugin' }
        $Source = (Resolve-Path -LiteralPath $Source).Path
        # Check before stopping the reader or making any device changes.
        foreach ($requiredTask in @('main.lua', '_meta.lua')) {
            if (-not (Test-Path -LiteralPath (Join-Path $Source $requiredTask))) { throw "Plugin missing $requiredTask" }
        }
        Stop-Reader
        try {
            $backupTask = Backup-Reader
            Install-PluginDirectory $Source
            Remove-OldDevicePluginBackups -Keep 1
            Remove-OldRunDirectories -Category 'backups' -Keep 3
            Write-Output "Installed plugin. Backup: $backupTask"
        } finally { $null = Invoke-Adb -AdbArgs @('shell', 'am start -n org.koreader.launcher/.MainActivity') }
    }
    'Restore' {
        if (-not $Backup) { throw 'Specify -Backup pointing to a harness backup directory.' }
        $backupPathTask = (Resolve-Path -LiteralPath $Backup).Path
        $manifestTask = Get-Content -Raw -LiteralPath (Join-Path $backupPathTask 'manifest.json') | ConvertFrom-Json
        # Backups written before the rename are still accepted; their plugin
        # folder is installed at the Book Theme path.
        $isLegacyManifestTask = $manifestTask.kind -eq 'heading-normalizer-device-backup-v1'
        if (-not $isLegacyManifestTask -and $manifestTask.kind -ne 'book-theme-device-backup-v1') { throw 'Backup does not match this harness/device' }
        if ($manifestTask.serial -ne $configTask.serial) { throw 'Backup does not match this harness/device' }
        $expectedPathTask = if ($isLegacyManifestTask) { $legacyPluginTask } else { $pluginTask }
        if ($manifestTask.pluginPath -ne $expectedPathTask) { throw 'Backup does not match this harness/device' }
        $pluginPresentTask = Get-ManifestFlag $manifestTask 'pluginPresent'
        $legacyPresentTask = Get-ManifestFlag $manifestTask 'legacyPluginPresent'
        if ($isLegacyManifestTask) {
            # In an old manifest pluginPresent describes the heading-normalizer folder.
            $legacyPresentTask = $pluginPresentTask
            $pluginPresentTask = $false
        }
        $sourceTask = Get-BackupPluginSource -BackupPath $backupPathTask -PluginPresent $pluginPresentTask -LegacyPluginPresent $legacyPresentTask
        Stop-Reader
        try {
            $currentBackupTask = Backup-Reader
            if ($sourceTask) { Install-PluginDirectory $sourceTask }
            else {
                $stampTask = Get-Date -Format 'yyyyMMddHHmmssfff'
                if (Test-DevicePath $pluginTask) {
                    $archiveTask = "$backupRootTask/book-theme-removed-$stampTask"
                    $null = Invoke-Adb -AdbArgs @('shell', "mkdir -p $backupRootTask")
                    $null = Invoke-Adb -AdbArgs @('shell', "mv '$pluginTask' '$archiveTask'")
                }
                Archive-LegacyPlugin -Suffix $stampTask
            }
            Remove-OldDevicePluginBackups -Keep 1
            Remove-OldRunDirectories -Category 'backups' -Keep 3
            Write-Output "Restored plugin state. Replaced state backed up in $currentBackupTask"
        } finally { $null = Invoke-Adb -AdbArgs @('shell', 'am start -n org.koreader.launcher/.MainActivity') }
    }
    'Launch' { (Invoke-Adb -AdbArgs @('shell', 'am start -n org.koreader.launcher/.MainActivity')).Output }
}

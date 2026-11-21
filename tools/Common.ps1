Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Write-JsonFile {
    param([string]$Path, $Value)
    $parentTask = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parentTask)) {
        New-Item -ItemType Directory -Force -Path $parentTask | Out-Null
    }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
}

function Get-DeviceConfig {
    $pathTask = if ($env:KVR_DEVICE_CONFIG) { $env:KVR_DEVICE_CONFIG } else { Join-Path $script:ProjectRoot 'local/device.json' }
    if (-not (Test-Path -LiteralPath $pathTask)) { throw 'Missing local/device.json. Copy tools/device.example.json and set the device values.' }
    $configTask = Get-Content -Raw -LiteralPath $pathTask | ConvertFrom-Json
    if ($configTask.serial -notmatch '^[A-Za-z0-9._:-]+$') { throw 'Invalid device serial' }
    if ($configTask.readerRoot -ne '/sdcard/koreader') { throw 'This harness only supports the verified /sdcard/koreader root.' }
    if (-not (Test-Path -LiteralPath $configTask.adb)) { throw 'Configured adb executable not found' }
    return $configTask
}

function Invoke-Adb {
    param([string[]]$AdbArgs, [switch]$AllowFailure)
    $configTask = Get-DeviceConfig
    $savedTask = $ErrorActionPreference
    try {
        # Native stderr is diagnostic output; exit status determines success.
        $ErrorActionPreference = 'Continue'
        $outputTask = @(& $configTask.adb -s $configTask.serial @AdbArgs 2>&1 | ForEach-Object { "$_" })
        $exitTask = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedTask }
    if ($exitTask -ne 0 -and -not $AllowFailure) {
        # Print output but never reconstructed arguments: they can carry local secrets.
        throw "ADB failed (exit $exitTask). Output: $($outputTask -join "`n")"
    }
    return [pscustomobject]@{ ExitCode = $exitTask; Output = ($outputTask -join "`n") }
}

function Assert-ReaderConnected {
    $stateTask = Invoke-Adb -AdbArgs @('get-state')
    if ($stateTask.Output.Trim() -ne 'device') { throw 'Expected configured device to be connected and authorized' }
    $modelTask = Invoke-Adb -AdbArgs @('shell', 'getprop ro.product.model')
    $configTask = Get-DeviceConfig
    if ($modelTask.Output.Trim() -ne $configTask.expectedModel) { throw 'Connected device model differs from local/device.json' }
}

function New-RunDirectory {
    param([string]$Category)
    $stampTask = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $rootTask = if ($env:KVR_RUN_ROOT) { [IO.Path]::GetFullPath($env:KVR_RUN_ROOT) } else { $script:ProjectRoot }
    $pathTask = Join-Path $rootTask "local/$Category/$stampTask"
    New-Item -ItemType Directory -Path $pathTask -Force | Out-Null
    return $pathTask
}

function Test-DevicePath {
    param([string]$Path)
    if ($Path -notmatch '^/[A-Za-z0-9_./-]+$') { throw 'Unsafe remote path' }
    $resultTask = Invoke-Adb -AdbArgs @('shell', "test -e '$Path'") -AllowFailure
    return $resultTask.ExitCode -eq 0
}

function Get-ReaderStatus {
    Assert-ReaderConnected
    $configTask = Get-DeviceConfig
    $packageTask = (Invoke-Adb -AdbArgs @('shell', 'dumpsys package org.koreader.launcher')).Output
    $activityTask = (Invoke-Adb -AdbArgs @('shell', 'dumpsys activity activities')).Output
    $kioskTask = (Invoke-Adb -AdbArgs @('shell', 'dumpsys package com.freekiosk')).Output
    return [ordered]@{
        checkedAt = (Get-Date).ToString('o')
        serial = $configTask.serial
        model = $configTask.expectedModel
        koreaderVersion = [regex]::Match($packageTask, 'versionName=([^\s]+)').Groups[1].Value
        koreaderVersionCode = [regex]::Match($packageTask, 'versionCode=(\d+)').Groups[1].Value
        freekioskVersion = [regex]::Match($kioskTask, 'versionName=([^\s]+)').Groups[1].Value
        lockTask = [regex]::Match($activityTask, 'mLockTaskModeState=([^\s]+)').Groups[1].Value
        foreground = [regex]::Match($activityTask, 'mResumedActivity:[^\r\n]+').Value
    }
}

function Get-LuaJitPath {
    $pathTask = Join-Path $script:ProjectRoot 'local/toolchain/LuaJIT/src/luajit.exe'
    if (-not (Test-Path -LiteralPath $pathTask)) { throw 'LuaJIT missing. Run tools/Setup-Toolchain.ps1.' }
    return $pathTask
}

function Stop-Reader {
    $null = Invoke-Adb -AdbArgs @('shell', 'am force-stop org.koreader.launcher')
    Start-Sleep -Milliseconds 500
    $processTask = Invoke-Adb -AdbArgs @('shell', 'pidof org.koreader.launcher') -AllowFailure
    if ($processTask.Output.Trim()) { throw 'KOReader restarted after force-stop. Disable automatic launch/relaunch before changing files.' }
}

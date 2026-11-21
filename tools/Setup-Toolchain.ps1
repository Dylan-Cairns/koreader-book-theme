[CmdletBinding()]
param([switch]$Rebuild)
. "$PSScriptRoot/Common.ps1"
$lock = Get-Content -Raw (Join-Path $script:ProjectRoot 'toolchain.lock.json') | ConvertFrom-Json

function Invoke-GitChecked {
    param([string[]]$GitArgs)
    & git @GitArgs
    if ($LASTEXITCODE -ne 0) { throw 'Git source setup failed' }
}

function Ensure-Source {
    param([string]$Relative, $Pin)
    $directoryTask = Join-Path $script:ProjectRoot $Relative
    if (-not (Test-Path -LiteralPath (Join-Path $directoryTask '.git'))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $directoryTask -Parent) | Out-Null
        Invoke-GitChecked -GitArgs @('clone', '--filter=blob:none', '--no-checkout', $Pin.url, $directoryTask)
        Invoke-GitChecked -GitArgs @('-C', $directoryTask, 'fetch', '--depth', '1', 'origin', $Pin.commit)
        Invoke-GitChecked -GitArgs @('-C', $directoryTask, 'checkout', '--detach', $Pin.commit)
    }
    $actualTask = (& git -C $directoryTask rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualTask -ne $Pin.commit) { throw "Source pin mismatch in $Relative; review local changes before changing revisions." }
    return $directoryTask
}

# Suppress git progress as function return values; paths are the only returned values.
$sourceTask = Ensure-Source 'local/upstream/koreader' $lock.koreader
$sourceTask = @($sourceTask)[-1]
Invoke-GitChecked -GitArgs @('-C', $sourceTask, 'submodule', 'update', '--init', '--depth', '1', 'base')
$baseTask = (& git -C (Join-Path $sourceTask 'base') rev-parse HEAD).Trim()
if ($baseTask -ne $lock.koreader.baseCommit) { throw 'KOReader base submodule pin mismatch' }
$jitTask = @(Ensure-Source 'local/toolchain/LuaJIT' $lock.luajit)[-1]
$null = Ensure-Source 'local/toolchain/luacheck' $lock.luacheck
$null = Ensure-Source 'local/toolchain/luaunit' $lock.luaunit
$patchTask = Join-Path $sourceTask $lock.luajit.patch
$savedPreferenceTask = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & git -C $jitTask apply --check $patchTask 2>$null
    $canApplyTask = $LASTEXITCODE -eq 0
    & git -C $jitTask apply --reverse --check $patchTask 2>$null
    $alreadyAppliedTask = $LASTEXITCODE -eq 0
} finally { $ErrorActionPreference = $savedPreferenceTask }
if ($canApplyTask) {
    Invoke-GitChecked -GitArgs @('-C', $jitTask, 'apply', $patchTask)
} elseif (-not $alreadyAppliedTask) {
    throw 'LuaJIT patch does not match; inspect the source rather than resetting it.'
}

$exeTask = Join-Path $jitTask 'src/luajit.exe'
if ($Rebuild -or -not (Test-Path -LiteralPath $exeTask)) {
    $vswhereTask = 'C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhereTask)) { throw 'MSVC Build Tools required for the local Windows LuaJIT build.' }
    $vsTask = (& $vswhereTask -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if (-not $vsTask) { throw 'No MSVC x64 toolchain found' }
    $varsTask = Join-Path $vsTask 'VC/Auxiliary/Build/vcvars64.bat'
    $srcTask = Join-Path $jitTask 'src'
    if ($varsTask -match '[%\r\n]' -or $srcTask -match '[%\r\n]') { throw 'Unsupported batch-path characters' }
    $batchTask = Join-Path $script:ProjectRoot 'local/toolchain/build-luajit.cmd'
    $batchTextTask = "@echo off`r`ncall `"$varsTask`" >nul`r`nif errorlevel 1 exit /b 1`r`npushd `"$srcTask`"`r`ncall msvcbuild.bat`r`nexit /b %errorlevel%`r`n"
    [IO.File]::WriteAllText($batchTask, $batchTextTask, [Text.Encoding]::ASCII)
    # Relative backslash path avoids native cmd quoting/forward-slash ambiguity.
    Push-Location $script:ProjectRoot
    try {
        & $env:ComSpec /d /c 'local\toolchain\build-luajit.cmd'
        if ($LASTEXITCODE -ne 0) { throw 'LuaJIT build failed' }
    } finally { Pop-Location }
}
& $exeTask -v
if ($LASTEXITCODE -ne 0) { throw 'Built LuaJIT did not start' }
Write-Output 'Pinned KOReader source and local LuaJIT/Luacheck/LuaUnit toolchain ready.'

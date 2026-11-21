[CmdletBinding()]
param([switch]$Device)
. "$PSScriptRoot/Common.ps1"
Push-Location $script:ProjectRoot
try {
    $syntaxErrorsTask = @()
    foreach ($fileTask in (Get-ChildItem tools,tests -Recurse -File -Filter '*.ps1')) {
        $tokensTask = $null; $errorsTask = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($fileTask.FullName, [ref]$tokensTask, [ref]$errorsTask)
        $syntaxErrorsTask += @($errorsTask)
    }
    if ($syntaxErrorsTask.Count) { throw ($syntaxErrorsTask -join "`n") }
    $jitTask = Get-LuaJitPath
    $extensionTask = Test-Path plugin
    $luaFilesTask = @(Get-ChildItem tools,tests -Recurse -File -Filter '*.lua' | Select-Object -ExpandProperty FullName)
    if ($extensionTask) { $luaFilesTask += @(Get-ChildItem plugin -Recurse -File -Filter '*.lua' | Select-Object -ExpandProperty FullName) }
    & $jitTask tools/lint.lua @luaFilesTask
    if ($LASTEXITCODE -ne 0) { throw 'Lua lint failed' }
    $testFilesTask = @(Get-ChildItem tests/unit -Recurse -File -Filter '*_test.lua' | Select-Object -ExpandProperty FullName)
    if (-not $testFilesTask.Count) { throw 'No unit tests discovered' }
    & $jitTask tests/run.lua @testFilesTask
    if ($LASTEXITCODE -ne 0) { throw 'Lua unit tests failed' }
    & node tests/handoff-check.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Handoff/config checks failed' }
    & node tests/device-harness-check.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Mock device integration checks failed' }
    & git diff --check
    if ($LASTEXITCODE -ne 0) { throw 'Git whitespace check failed' }
    if ($Device) { & "$PSScriptRoot/Device.ps1" Status }
    if ($extensionTask) {
        $statusTextTask = Get-Content -Raw -LiteralPath (Join-Path $script:ProjectRoot 'STATUS.md')
        if ($statusTextTask -notmatch '(?m)^## Tests run') { throw 'plugin/ exists but STATUS.md has no "## Tests run" section. Record the tests actually run before claiming progress.' }
        Write-Output 'Harness and extension checks passed. Mode: extension present; tests run are listed in STATUS.md.'
    } else {
        Write-Output 'Harness checks passed. Mode: harness-only (no plugin/ directory); this run does not validate an extension.'
    }
} finally { Pop-Location }

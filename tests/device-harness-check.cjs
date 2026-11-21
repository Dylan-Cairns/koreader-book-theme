const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const sandbox = fs.mkdtempSync(path.join(root, 'local', 'mock-device-'));
// Remove the sandbox after a passing run; retain it (and say where) after a failure.
const keepSandbox = process.env.KVR_KEEP_MOCK_SANDBOX === '1';
process.on('exit', code => {
  if (code === 0 && !keepSandbox) fs.rmSync(sandbox, {recursive: true, force: true});
  else if (code !== 0) console.error(`Mock device sandbox retained for inspection: ${sandbox}`);
});
const remote = p => path.join(sandbox, 'remote', p.replace(/^\//, ''));
const plugin = '/sdcard/koreader/plugins/heading-normalizer.koplugin';
const source = path.join(sandbox, 'candidate.koplugin');
fs.mkdirSync(source);
fs.writeFileSync(path.join(source, 'main.lua'), 'return { version = "candidate" }\n');
fs.writeFileSync(path.join(source, '_meta.lua'), 'return { name = "mock" }\n');
fs.mkdirSync(remote('/sdcard/koreader/settings'), {recursive: true});
fs.mkdirSync(remote(plugin), {recursive: true});
fs.writeFileSync(remote(plugin + '/main.lua'), 'return { version = "original" }\n');
fs.writeFileSync(remote(plugin + '/_meta.lua'), 'return { name = "mock" }\n');
fs.writeFileSync(remote('/sdcard/koreader/settings.reader.lua'), 'return { preserve = true }\n');
const fakeAdb = path.join(sandbox, 'mock-adb.cmd');
fs.writeFileSync(fakeAdb, `@echo off\r\n"${process.execPath}" "${path.join(root, 'tests/mock-adb.cjs')}" %*\r\n`);
const config = path.join(sandbox, 'device.json');
fs.writeFileSync(config, JSON.stringify({adb:fakeAdb,serial:'mock-reader',expectedModel:'MockGo6',readerRoot:'/sdcard/koreader'}));
const env = {...process.env, KVR_DEVICE_CONFIG: config, KVR_MOCK_ROOT: sandbox, KVR_RUN_ROOT: sandbox};
const powershell = path.join(process.env.SystemRoot, 'System32/WindowsPowerShell/v1.0/powershell.exe');
function run(args, expectedSuccess = true) {
  const result = cp.spawnSync(powershell, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'tools/Device.ps1', ...args], {cwd:root, env, encoding:'utf8', timeout:45000});
  assert(!result.error, result.error?.message);
  assert.equal(result.status === 0, expectedSuccess, result.stdout + result.stderr);
  return result;
}
const status = JSON.parse(run(['Status']).stdout);
assert.equal(status.serial, 'mock-reader');
assert.equal(status.koreaderVersion, 'v2026.07.1');
const deployment = run(['Deploy', '-Source', source]);
assert(fs.readFileSync(remote(plugin + '/main.lua'), 'utf8').includes('candidate'));
const backup = deployment.stdout.match(/Backup: ([^\r\n]+)/)?.[1];
assert(backup && fs.existsSync(path.join(backup, 'manifest.json')), 'Original plugin backup missing');
run(['Restore', '-Backup', backup]);
assert(fs.readFileSync(remote(plugin + '/main.lua'), 'utf8').includes('original'));
fs.writeFileSync(path.join(sandbox, 'fail-activation'), '1');
run(['Deploy', '-Source', source], false);
assert(fs.readFileSync(remote(plugin + '/main.lua'), 'utf8').includes('original'), 'Activation failure did not restore old plugin');
assert(fs.readFileSync(remote('/sdcard/koreader/settings.reader.lua'), 'utf8').includes('preserve = true'));
const capture = run(['Capture'], false);
assert((capture.stdout + capture.stderr).includes('No valid PNG captured'));
fs.writeFileSync(path.join(sandbox, 'fail-capture'), '1');
const failedCapture = run(['Capture'], false);
assert((failedCapture.stdout + failedCapture.stderr).includes('No valid PNG captured'));
fs.unlinkSync(path.join(sandbox, 'fail-capture'));
fs.writeFileSync(path.join(sandbox, 'valid-capture'), '1');
const validCapture = JSON.parse(run(['Capture']).stdout);
assert(fs.readFileSync(validCapture.screenshot).subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')));
const remoteBackupDir = path.join(sandbox, 'remote/sdcard/Documents/BooxSetupBackup');
const remoteCaptures = fs.existsSync(remoteBackupDir)
  ? fs.readdirSync(remoteBackupDir).filter(name => name.startsWith('heading-normalizer-capture-')) : [];
assert.equal(remoteCaptures.length, 0, 'Capture left device-side temporary files');
// First deployment must also roll back to a state with no plugin at all.
fs.unlinkSync(path.join(sandbox, 'fail-activation'));
fs.renameSync(remote(plugin), path.join(sandbox, 'original-plugin-saved'));
const emptyBackup = run(['Backup']).stdout.trim();
assert.equal(JSON.parse(fs.readFileSync(path.join(emptyBackup, 'manifest.json'))).pluginPresent, false);
run(['Deploy', '-Source', source]);
run(['Restore', '-Backup', emptyBackup]);
assert(!fs.existsSync(remote(plugin)), 'Restore should remove a first-time plugin without deleting other state');
const previousBackups = fs.existsSync(remoteBackupDir)
  ? fs.readdirSync(remoteBackupDir).filter(name => name.startsWith('heading-normalizer-previous-')) : [];
assert(previousBackups.length <= 1, `Device plugin backups accumulated: ${previousBackups.join(', ')}`);
const localBackupDirs = fs.readdirSync(path.join(sandbox, 'local/backups'), {withFileTypes: true})
  .filter(entry => entry.isDirectory()).map(entry => entry.name);
assert(localBackupDirs.length <= 3, `Local deploy backups accumulated: ${localBackupDirs.join(', ')}`);
const missingConfig = path.join(sandbox, 'wrong-device.json');
fs.writeFileSync(missingConfig, JSON.stringify({adb:fakeAdb,serial:'mock-reader',expectedModel:'WrongModel',readerRoot:'/sdcard/koreader'}));
const oldConfig = env.KVR_DEVICE_CONFIG; env.KVR_DEVICE_CONFIG = missingConfig;
run(['Status'], false); env.KVR_DEVICE_CONFIG = oldConfig;
console.log('Mock device checks passed: identity, deploy/backup/rollback (existing and first install), activation recovery, settings preservation, successful/failed/empty captures. No physical device operations.');

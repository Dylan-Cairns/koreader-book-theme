// A local filesystem model of the small ADB surface used by Device.ps1.
// It never connects to Android and is only selected with KVR_DEVICE_CONFIG.
const fs = require('node:fs');
const path = require('node:path');
const args = process.argv.slice(2);
if (args.shift() !== '-s' || args.shift() !== 'mock-reader') process.exit(2);
const root = process.env.KVR_MOCK_ROOT;
if (!root) process.exit(2);
const remote = p => path.join(root, 'remote', p.replace(/^\//, ''));
const readerRoot = '/sdcard/koreader';
function mkdirFor(p) { fs.mkdirSync(path.dirname(p), {recursive: true}); }
function exists(p) { return fs.existsSync(remote(p)); }
function copy(src, dst) { mkdirFor(dst); fs.cpSync(src, dst, {recursive: true}); }
if (args[0] === 'get-state') console.log('device');
else if (args[0] === 'pull') {
  if (!exists(args[1])) process.exit(1);
  copy(remote(args[1]), args[2]);
} else if (args[0] === 'push') copy(args[1], remote(args[2]));
else if (args[0] === 'logcat') console.log('mock KOReader log');
else if (args[0] === 'shell') {
  const command = args.slice(1).join(' ');
  if (command === 'getprop ro.product.model') console.log('MockGo6');
  else if (command === 'dumpsys package org.koreader.launcher') console.log('versionName=v2026.07.1 versionCode=119462');
  else if (command === 'dumpsys package com.freekiosk') console.log('versionName=2.0.0');
  else if (command === 'dumpsys activity activities') console.log(`mLockTaskModeState=NONE\nmResumedActivity: org.koreader.launcher/.MainActivity`);
  else if (command === 'pidof org.koreader.launcher') process.exit(1);
  else if (command.startsWith('am force-stop ') || command.startsWith('am start ')) console.log('OK');
  else if (command.startsWith('mkdir -p ')) fs.mkdirSync(remote(command.slice(9)), {recursive: true});
  else if (command.startsWith('test ')) {
    for (const match of command.matchAll(/test -[ef] '([^']+)'/g)) if (!exists(match[1])) process.exit(1);
  } else if (command.startsWith('ls -1 ')) {
    const target = command.slice(6).trim().replace(/^'|'$/g, '');
    const dir = remote(target);
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) process.exit(1);
    for (const name of fs.readdirSync(dir)) console.log(name);
  } else if (command.startsWith('rm -f ') || command.startsWith('rm -rf ')) {
    const recursive = command.startsWith('rm -rf ');
    const rest = command.slice(recursive ? 8 : 6);
    for (const match of rest.matchAll(/'([^']+)'|([^\s']+)/g)) {
      fs.rmSync(remote(match[1] || match[2]), {recursive, force: true});
    }
  } else if (command.startsWith('mv ')) {
    const [, src, dst] = command.match(/^mv '([^']+)' '([^']+)'$/) || [];
    if (!src || !dst) process.exit(2);
    // Simulated failure specifically exercises rollback after prior-plugin archival.
    if (fs.existsSync(path.join(root, 'fail-activation')) && src.includes('book-theme.stage-')) process.exit(1);
    mkdirFor(remote(dst)); fs.renameSync(remote(src), remote(dst));
  } else if (command.startsWith('screencap -p ')) {
    if (fs.existsSync(path.join(root, 'fail-capture'))) process.exit(1);
    const dst = remote(command.slice(13)); mkdirFor(dst);
    // An empty result models a blocked or failed capture; a marker enables the success path.
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlWQAAAAASUVORK5CYII=';
    fs.writeFileSync(dst, fs.existsSync(path.join(root, 'valid-capture')) ? Buffer.from(png, 'base64') : '');
  } else if (command.startsWith('uiautomator dump ')) {
    const dst = remote(command.slice(17)); mkdirFor(dst); fs.writeFileSync(dst, '<hierarchy/>');
  } else { console.error(`Unsupported mock operation: ${command}`); process.exit(2); }
} else { console.error('Unsupported mock ADB call'); process.exit(2); }
// Keep the readerRoot declaration useful to flag accidental changes in mock layout.
if (!readerRoot.startsWith('/sdcard/')) process.exit(2);

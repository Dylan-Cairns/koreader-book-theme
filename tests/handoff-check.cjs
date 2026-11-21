const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const tracked = cp.execFileSync('git', ['ls-files', '-z'], {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean);
const untracked = cp.execFileSync('git', ['ls-files', '--others', '--exclude-standard', '-z'], {cwd: root, encoding: 'utf8'}).split('\0').filter(Boolean);
const candidates = [...new Set([...tracked, ...untracked])];

for (const name of candidates) {
  assert(!name.startsWith('local/'), 'Private local asset is tracked');
}

for (const name of candidates) {
  if (!name.endsWith('.md') || name.startsWith('tests/fixtures/')) continue;
  const text = fs.readFileSync(path.join(root, name), 'utf8')
    .replace(/^(```|~~~)[\s\S]*?^\1/gm, '')
    .replace(/`[^`\n]*`/g, '');
  for (const match of text.matchAll(/\]\(([^)]+)\)/g)) {
    const target = match[1].split('#')[0];
    if (!target || target.includes('://')) continue;
    if (target.startsWith('local/') && !fs.existsSync(path.join(root, 'local'))) continue;
    assert(fs.existsSync(path.resolve(root, path.dirname(name), decodeURIComponent(target))),
      `Broken doc link: ${name} -> ${target}`);
  }
}

const configText = fs.readFileSync(path.join(root, 'opencode.jsonc'), 'utf8');
const config = JSON.parse(configText.replace(/^\s*\/\/.*$/gm, ''));
assert(!('model' in config) && !('small_model' in config) && !('providers' in config),
  'Model/provider must remain session-selected');
assert(config.compaction.auto);
assert(config.instructions.includes('docs/harness.md'));
assert.equal(config.share, 'disabled');

const accessPath = path.join(root, 'local/device-access.md');
if (fs.existsSync(accessPath)) {
  cp.execFileSync('git', ['check-ignore', 'local/device-access.md'], {cwd: root});
}

console.log(`Handoff checks: ${candidates.length} project files; local exclusions, doc links and model-free config passed.`);

import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

function fixture(t, exitCode = 0) {
  const directory = mkdtempSync(join(tmpdir(), 'runtime-pack-json-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  writeFileSync(join(directory, 'package.json'), JSON.stringify({
    name: 'actql-pack-json-hook-fixture', version: '0.0.0', private: true,
    files: ['hook-ran.txt'], scripts: {prepack: 'node hook.cjs'},
  }));
  writeFileSync(join(directory, 'hook.cjs'), `
const {writeFileSync} = require('node:fs');
writeFileSync('hook-ran.txt', 'original-hook-ran\\n');
console.log('Original lifecycle diagnostic, not package metadata');
if (${exitCode}) { console.error('Original lifecycle hook refused'); process.exitCode = ${exitCode}; }
`);
  const result = spawnSync('npm', ['pack', '--json', '--pack-destination', directory,
    '--foreground-scripts=false'], {cwd: directory, encoding: 'utf8', timeout: 30000,
    maxBuffer: 4 * 1024 * 1024, env: {...process.env,
      npm_config_ignore_scripts: 'false', npm_config_update_notifier: 'false',
      npm_config_cache: join(directory, 'cache')}});
  assert.ifError(result.error);
  assert.equal(readFileSync(join(directory, 'hook-ran.txt'), 'utf8'), 'original-hook-ran\n');
  return {directory, result};
}

test('real npm pack keeps lifecycle execution while isolating JSON stdout', t => {
  const {directory, result} = fixture(t);
  assert.equal(result.status, 0, result.stderr);
  // Parse the complete output: diagnostic prefixes and suffixes stay invalid.
  const metadata = JSON.parse(result.stdout);
  assert.equal(metadata.length, 1);
  assert.equal(metadata[0].name, 'actql-pack-json-hook-fixture');
  assert.equal(metadata[0].filename, 'actql-pack-json-hook-fixture-0.0.0.tgz');
  assert(metadata[0].files.some(file => file.path === 'hook-ran.txt' && file.size === 18));
  assert(readdirSync(directory).includes(metadata[0].filename));
});

test('real npm pack preserves the original lifecycle failure without an archive', t => {
  const {directory, result} = fixture(t, 7);
  assert.equal(result.status, 7);
  assert.match(result.stderr, /Original lifecycle hook refused/u);
  assert(!readdirSync(directory).some(name => name.endsWith('.tgz')));
});

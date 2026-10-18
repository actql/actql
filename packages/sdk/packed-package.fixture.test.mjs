import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync,
  symlinkSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {packSdkFixture} from './packed-package.fixture.mjs';

function fixture(t, mode = 'normal') {
  const root = mkdtempSync(join(tmpdir(), 'sdk-packed-package-'));
  t.after(() => rmSync(root, {recursive: true}));
  const directory = join(root, 'source');
  const destination = join(root, 'destination');
  const packageRoot = join(root, 'archive', 'package');
  for (const path of [directory, destination, packageRoot]) mkdirSync(path, {recursive: true});
  const original = '{"name":"@actql/sdk","version":"0.0.0-development"}\n';
  writeFileSync(join(directory, 'package.json'), original);
  writeFileSync(join(packageRoot, 'package.json'), mode === 'foreign'
    ? '{"name":"@actql/client-wire","version":"0.0.0-development"}\n' : original);
  if (mode === 'member-link') symlinkSync('package.json', join(packageRoot, 'index.mjs'));
  else writeFileSync(join(packageRoot, 'index.mjs'), 'export const value = 1;\n');
  const template = join(root, 'template.tgz');
  execFileSync('tar', ['-czf', template, '-C', join(root, 'archive'), 'package']);
  const filename = 'actql-sdk-0.0.0-development.tgz';
  const target = join(destination, filename);
  const calls = [];
  const run = (command, args, cwd) => {
    calls.push({command, args, cwd});
    if (command === 'npm') {
      assert.deepEqual(args, ['pack', '--json', '--cache', destination,
        '--pack-destination', destination]);
      assert.equal(cwd, directory);
      if (mode === 'exit') throw new Error('OriginalPrepackFailed');
      if (mode === 'linked') symlinkSync(template, target);
      else if (mode === 'empty') writeFileSync(target, '');
      else if (mode !== 'missing') copyFileSync(template, target);
      return '{"lifecycle":"diagnostic"}\nnot a JSON package report\n';
    }
    return execFileSync(command, args, {encoding: 'utf8', timeout: 30000});
  };
  return {directory, destination, target, filename, calls, run};
}

test('normal prepack diagnostics do not replace actual package bytes or digests', t => {
  const f = fixture(t);
  const report = packSdkFixture({name: 'sdk', ...f});
  assert.equal(report.name, '@actql/sdk');
  assert.equal(report.filename, f.filename);
  assert.equal(report.shasum, createHash('sha1').update(readFileSync(f.target)).digest('hex'));
  assert.equal(report.integrity, 'sha512-' + createHash('sha512').update(readFileSync(f.target)).digest('base64'));
  assert.deepEqual(report.files.map(row => row.path).sort(), ['index.mjs', 'package.json']);
  assert.equal(f.calls.filter(call => call.command === 'npm').length, 1);
});

for (const mode of ['missing', 'empty', 'linked', 'foreign', 'member-link', 'exit']) {
  test(`normal prepack refuses ${mode} artifact or original failure`, t => {
    const f = fixture(t, mode);
    assert.throws(() => packSdkFixture({name: 'sdk', ...f}));
    assert.equal(f.calls.filter(call => call.command === 'npm').length, 1);
  });
}

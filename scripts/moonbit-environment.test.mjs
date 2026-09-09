import assert from 'node:assert/strict';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { checkInterfaces } from './check-moonbit-api.mjs';
import { installationFiles, verifyInstallation } from './moonbit-installation.mjs';

test('installation health rejects missing core, bundles, tools and mismatched marker', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-install-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  writeFileSync(join(root, 'installed.json'), 'pinned');
  for (const file of installationFiles) {
    mkdirSync(dirname(join(root, file)), { recursive: true });
    writeFileSync(join(root, file), 'fixture', { mode: 0o755 });
  }
  verifyInstallation(root, 'pinned');
  for (const file of installationFiles) {
    rmSync(join(root, file));
    assert.throws(() => verifyInstallation(root, 'pinned'), /Move only this directory aside/);
    writeFileSync(join(root, file), 'fixture', { mode: 0o755 });
  }
  assert.throws(() => verifyInstallation(root, 'other'), /marker differs/);
});

test('live tool rejects backend API drift, tracked changes and untracked interfaces', t => {
  const root = mkdtempSync(join(tmpdir(), 'actql-api-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const run = (command, args) => execFileSync(command, args, { cwd: root, stdio: 'pipe' });
  mkdirSync(join(root, 'src'));
  writeFileSync(join(root, 'moon.mod'), 'name = "test/api"\nsource = "src"\npreferred_target = "js"\nsupported_targets = "+js+wasm+native"\n');
  writeFileSync(join(root, 'src/moon.pkg'), '');
  const source = join(root, 'src/api.mbt');
  writeFileSync(source, 'pub fn f(x : Int) -> Int { x }\n');
  run('git', ['init', '-q']);
  run('moon', ['info']);
  assert.throws(() => checkInterfaces(root), /Untracked public interfaces/);
  run('git', ['add', 'src/pkg.generated.mbti']);
  checkInterfaces(root);
  writeFileSync(source, '#cfg(not(target="native"))\npub fn f(x : Int) -> Int { x }\n#cfg(target="native")\npub fn f(x : Int) -> String { x.to_string() }\n');
  for (const target of ['js', 'wasm', 'native']) run('moon', ['check', '--target', target]);
  assert.throws(() => checkInterfaces(root), /Common-core interfaces differ/);
  writeFileSync(source, 'pub fn f(x : Int) -> String { x.to_string() }\n');
  assert.throws(() => checkInterfaces(root));
  assert.match(readFileSync(join(root, 'src/pkg.generated.mbti'), 'utf8'), /String/);
});

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { parse } from 'yaml';
import { checkInterfaces } from './check-moonbit-api.mjs';
import { installationFiles, verifyInstallation } from './moonbit-installation.mjs';

test('CI installs and exposes the pinned formatter before specification checks', () => {
  const workflow = parse(readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8'));
  const steps = workflow.jobs.spec.steps;
  const installation = steps.findIndex(step => /node scripts\/setup-moonbit\.mjs/.test(step.run ?? ''));
  const specification = steps.findIndex(step => /npm run check:spec/.test(step.run ?? ''));
  assert.ok(installation >= 0 && specification >= 0, 'CI must install MoonBit and run specification checks');
  assert.ok(installation < specification, 'check:spec invokes moonfmt and must follow pinned MoonBit setup');
  assert.match(steps[installation].run, /MOON_HOME=.*GITHUB_ENV/);
  assert.match(steps[installation].run, /bin.*GITHUB_PATH/);
});

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
  mkdirSync(join(root, 'src/native_test'));
  writeFileSync(
    join(root, 'src/native_test/moon.pkg'),
    'supported_targets = "native"\n',
  );
  writeFileSync(
    join(root, 'src/native_test/native.mbt'),
    'pub fn native_value() -> Int { 1 }\n',
  );
  writeFileSync(
    join(root, 'src/native_test/pkg.generated.mbti'),
    '// native-only fixture interface\npub fn native_value() -> Int\n',
  );
  run('git', ['add', 'src/native_test/pkg.generated.mbti']);
  checkInterfaces(root);
  writeFileSync(source, '#cfg(not(target="native"))\npub fn f(x : Int) -> Int { x }\n#cfg(target="native")\npub fn f(x : Int) -> String { x.to_string() }\n');
  for (const target of ['js', 'wasm', 'native']) run('moon', ['check', '--target', target]);
  assert.throws(() => checkInterfaces(root), /Common-core interfaces differ/);
  writeFileSync(source, 'pub fn f(x : Int) -> String { x.to_string() }\n');
  assert.throws(() => checkInterfaces(root));
  assert.match(readFileSync(join(root, 'src/pkg.generated.mbti'), 'utf8'), /String/);
});

// Exercise the real entrypoints with tiny child fixtures; the real isolation
// checks separately exercise the unchanged product dependency assertions.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync,
  readdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

const scripts = ['check-node-without-duckdb.mjs',
  'check-core-without-connectors.mjs'];

function fixture(t, script, mode = 'passed') {
  const root = mkdtempSync(join(tmpdir(), 'actql-isolation-lifecycle-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const checkout = join(root, 'checkout');
  const scratch = join(root, 'scratch');
  const bin = join(root, 'bin');
  for (const directory of [join(checkout, 'scripts'),
    join(checkout, 'adapters/connectors/duckdb/node'), scratch, bin]) {
    mkdirSync(directory, {recursive: true});
  }
  for (const name of [script, 'owned-scratch.mjs']) {
    copyFileSync(new URL(name, import.meta.url), join(checkout, 'scripts', name));
  }
  writeFileSync(join(checkout, 'package.json'), '{"type":"module"}');
  writeFileSync(join(checkout, 'scripts/node-host-fixtures.mjs'), '');
  writeFileSync(join(checkout, 'scripts/portable-core.mjs'), `
import {writeFileSync} from 'node:fs';
import {join} from 'node:path';
export function copyProductionCore(root, isolated) {
  writeFileSync(join(isolated, 'diagnostic'), 'core evidence');
  return {roots: [], packages: []};
}`);
  writeFileSync(join(checkout, 'scripts/node-host-subset-fixture.mjs'), `
import {writeFileSync} from 'node:fs';
writeFileSync('diagnostic', 'node evidence');
${mode === 'failed' ? "throw new Error('original isolation child failure');" : ''}`);
  for (const name of ['scripts/connector-node-bundles.test.mjs',
    'adapters/host-node/strategy.test.mjs',
    'adapters/host-common/managed-failure.test.mjs']) {
    mkdirSync(join(checkout, name, '..'), {recursive: true});
    writeFileSync(join(checkout, name), `import test from 'node:test';
test('isolated child', () => {
  ${mode === 'last-child-failed' ? "throw new Error('last isolation child failure');" : ''}
});`);
  }
  const moon = join(bin, 'moon');
  writeFileSync(moon, `#!${process.execPath}
const {mkdirSync, writeFileSync} = require('node:fs');
const {join, basename} = require('node:path');
if (process.argv[2] === 'build') {
  const name = basename(process.argv.at(-1));
  const directory = join('_build/js/release/build', name);
  mkdirSync(directory, {recursive: true});
  writeFileSync(join(directory, name + '.js'), '// compiled fixture');
} else {
  ${mode === 'failed' ? "console.error('original isolation child failure'); process.exit(7);" : ''}
}
`);
  chmodSync(moon, 0o755);
  if (mode === 'spawn-failed') rmSync(moon);
  const env = {...process.env, PATH: bin, TMPDIR: scratch,
    ACTQL_TEST_PRESERVE_SCRATCH: mode === 'preserve' ? '1' : ''};
  // The entrypoint starts its own Node test runner, outside this runner.
  delete env.NODE_TEST_CONTEXT;
  const result = spawnSync(process.execPath, [join(checkout, 'scripts', script)], {
    encoding: 'utf8', env,
  });
  return {...result, scratch};
}

for (const script of scripts) {
  test(`${script}: success removes its new scratch`, t => {
    const result = fixture(t, script);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(readdirSync(result.scratch), []);
    assert.match(result.stdout, /removed .*actql-(node-no-duckdb|common-closure)-/u);
  });
  test(`${script}: failure keeps the original failure and diagnostic path`, t => {
    const result = fixture(t, script, 'failed');
    assert.equal(result.status, script === scripts[1] ? 7 : 1);
    assert.match(result.stderr, /original isolation child failure/u);
    const path = /scratch kept: (.*)/u.exec(result.stderr)?.[1];
    assert.ok(path, result.stderr);
    assert.ok(existsSync(join(path, 'diagnostic')));
    assert.doesNotMatch(result.stderr, /cleanup failed/u);
  });
  test(`${script}: explicit preservation retains successful evidence`, t => {
    const result = fixture(t, script, 'preserve');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /preservation requested; scratch kept:/u);
    assert.equal(readdirSync(result.scratch).length, 1);
  });
}

test('core isolation retains its new tree when moon cannot spawn', t => {
  const result = fixture(t, scripts[1], 'spawn-failed');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /spawnSync moon ENOENT/u);
  const path = /scratch kept: (.*)/u.exec(result.stderr)?.[1];
  assert.ok(path, result.stderr);
  assert.equal(readFileSync(join(path, 'diagnostic'), 'utf8'), 'core evidence');
});


test('Node isolation cannot pass before its last child has succeeded', t => {
  const result = fixture(t, scripts[0], 'last-child-failed');
  assert.equal(result.status, 1);
  assert.match(result.stderr + result.stdout, /last isolation child failure/u);
  const path = /scratch kept: (.*)/u.exec(result.stderr)?.[1];
  assert.ok(path, result.stderr);
  assert.ok(existsSync(join(path, 'diagnostic')));
});

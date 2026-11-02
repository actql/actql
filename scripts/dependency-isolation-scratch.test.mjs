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
    join(checkout, 'adapters/connectors/duckdb/node'),
    join(checkout, 'packages/client-wire'), scratch, bin]) {
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
  writeFileSync(join(checkout, 'packages/client-wire/index.mjs'), 'export const originalWire = true;');
  writeFileSync(join(checkout, 'scripts/node-host-subset-fixture.mjs'), `
import {originalWire} from '../packages/client-wire/index.mjs';
if (!originalWire) throw new Error('missing original Client wire closure');
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

// Exercise the original generators with tiny authored preparation DATA. No
// compiler, runtime, result oracle or replacement projection engine is used.
function nodeFixtureInputs(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-node-fixture-input-'));
  t.diagnostic(`source-only generator fixture retained: ${root}`);
  const put = (path, text) => {
    mkdirSync(join(root, path, '..'), {recursive: true});
    writeFileSync(join(root, path), text);
  };
  for (const name of ['workers-fixtures.mjs', 'node-host-fixtures.mjs', 'portable-core.mjs']) {
    mkdirSync(join(root, 'scripts'), {recursive: true});
    copyFileSync(new URL(name, import.meta.url), join(root, 'scripts', name));
  }
  put('src/query_integration/helper.mbt',
    'fn captured_graph_fixture() -> Int { 1 }\n///|\nfn dispatch_test_generated() -> Int { 2 }\n');
  put('src/query_integration/moon.pkg', `supported_targets = "+js+wasm+native"

options(
  targets: { "strategy_cleanup_current_js_wbtest.mbt": [ "js" ] },
  link: {
    "native": {
      "cc": "./scripts/native-cxx-link-driver.sh",
      "stub-cc": "c++",
      "cc-link-flags": "-lssl -lcrypto",
    },
  },
)
`);
  put('src/query_integration/strategy_cleanup_current_js_wbtest.mbt', '// JS-only metadata fixture.\n');
  put('src/connectors_workers_bridge/moon.pkg',
    'import { "actql/actql/connectors/local/driver" @local }');
  put('src/connectors_workers_async_bridge/moon.pkg',
    'import { "actql/actql/connectors/reference_compute/driver" @driver, "actql/actql/connectors/reference_compute" @compute }');
  for (const file of ['bridge.generated.mbt', 'finite.mbt', 'authorization_bridge.mbt']) {
    put(`src/connectors_workers_bridge/${file}`, '');
  }
  put('src/connectors_workers_async_bridge/bridge.generated.mbt', '');
  const env = {...process.env};
  delete env.NODE_TEST_CONTEXT;
  const run = (script, ...args) => spawnSync(process.execPath,
    [`scripts/${script}.mjs`, ...args], {cwd: root, encoding: 'utf8', env});
  for (const script of ['workers-fixtures', 'node-host-fixtures']) {
    const result = run(script, '--write');
    assert.equal(result.status, 0, result.stdout + result.stderr);
  }
  return {root, put, run};
}

test('Node fixture input refuses stale Workers projection before an explicit write', t => {
  const f = nodeFixtureInputs(t);
  const path = join(f.root, 'src/node_host_conformance/fixture.generated.mbt');
  const before = readFileSync(path, 'utf8');
  f.put('src/workers_conformance/fixture.generated.mbt', '// stale upstream original\n');
  const result = f.run('node-host-fixtures', '--write');
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /Stale Workers fixture: fixture.generated.mbt/);
  assert.equal(readFileSync(path, 'utf8'), before);
});

test('Node fixture input keeps default refusal and writes only exact owned source', t => {
  const f = nodeFixtureInputs(t);
  const path = join(f.root, 'src/node_host_conformance/fixture.generated.mbt');
  f.put('src/node_host_conformance/fixture.generated.mbt', '// stale Node original\n');
  const refused = f.run('node-host-fixtures');
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /Stale Node Host fixture: fixture.generated.mbt/);
  assert.equal(readFileSync(path, 'utf8'), '// stale Node original\n');
  const written = f.run('node-host-fixtures', '--write');
  assert.equal(written.status, 0, written.stdout + written.stderr);
  assert.equal(readFileSync(path, 'utf8'), readFileSync(
    join(f.root, 'src/workers_conformance/fixture.generated.mbt'), 'utf8'));
  const checked = f.run('node-host-fixtures');
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
});

test('Node fixture input retains the exact native-option refusal before writes', t => {
  const f = nodeFixtureInputs(t);
  const manifest = join(f.root, 'src/query_integration/moon.pkg');
  const path = join(f.root, 'src/node_host_conformance/fixture.generated.mbt');
  const before = readFileSync(path, 'utf8');
  writeFileSync(manifest, readFileSync(manifest, 'utf8').replace('"-lssl -lcrypto"', '"-lother"'));
  const result = f.run('node-host-fixtures', '--write');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /UnexpectedQueryIntegrationOptions/);
  assert.equal(readFileSync(path, 'utf8'), before);
});


test('Node fixture input refuses unreviewed target metadata before writes', t => {
  const f = nodeFixtureInputs(t);
  const manifest = join(f.root, 'src/query_integration/moon.pkg');
  const path = join(f.root, 'src/node_host_conformance/fixture.generated.mbt');
  const original = readFileSync(manifest, 'utf8');
  const before = readFileSync(path, 'utf8');
  for (const altered of [
    original.replace('strategy_cleanup_current_js_wbtest.mbt', 'unreviewed_wbtest.mbt'),
    original.replace('[ "js" ]', '[ "native" ]'),
    original.replace('[ "js" ]', 'selected_targets'),
  ]) {
    writeFileSync(manifest, altered);
    const result = f.run('node-host-fixtures', '--write');
    assert.notEqual(result.status, 0, result.stdout + result.stderr);
    assert.match(result.stderr, /UnexpectedQueryIntegrationOptions/);
    assert.equal(readFileSync(path, 'utf8'), before);
  }
});

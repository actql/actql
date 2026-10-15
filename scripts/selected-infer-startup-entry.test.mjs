import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('../', import.meta.url));
// Source-copied package layouts, not a packed product or numerical profile.
// Nested Local installation deliberately does not rely on npm hoisting.
function installation(t) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-selected-startup-entry-'));
  t.after(() => rmSync(directory, {recursive: true, force: true}));
  const node = join(directory, 'node_modules/@actql/node');
  const local = join(node, 'node_modules/@actql/local-node');
  const put = (path, bytes) => {
    mkdirSync(dirname(path), {recursive: true});
    writeFileSync(path, bytes);
  };
  for (const [name, destination] of [['node', node], ['local-node', local]]) {
    const manifest = JSON.parse(readFileSync(join(root, 'packages', name, 'package.json')));
    assert.equal(manifest.exports['./selected-infer-startup'], './selected-infer-startup.cjs');
    assert.ok(manifest.files.includes('selected-infer-startup.cjs'));
    put(join(destination, 'package.json'), JSON.stringify(manifest));
    put(join(destination, 'selected-infer-startup.cjs'),
      readFileSync(join(root, 'packages', name, 'selected-infer-startup.cjs')));
  }
  for (const name of ['infer-trusted-node-preload.cjs', 'infer-trusted-runtime-view.mjs']) {
    put(join(local, 'adapters/host-node', name), readFileSync(join(root, 'adapters/host-node', name)));
  }
  const entry = join(directory, 'entry.mjs');
  put(entry, `import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const path = require.resolve('@actql/node/selected-infer-startup');
const local = createRequire(path).resolve('@actql/local-node/selected-infer-startup');
const mode = process.argv[2];
const entry = require('@actql/node/selected-infer-startup');
assert.deepEqual(Reflect.ownKeys(entry), []);
assert.ok(Object.isFrozen(entry));
const viewModule = await import(new URL('./adapters/host-node/infer-trusted-runtime-view.mjs',
  'file://' + local));
const {issueInferTrustedRuntimeView: issue, associateInferTrustedStartupView: associate,
  requireInferTrustedStartupView: check, borrowInferTrustedStartupView: borrow,
  forgetInferTrustedStartupView: retire, forgetInferTrustedRuntimeView: forget} = viewModule;
// Nominal Host/Scope reference doubles; no Core Scope, permission or ACK.
const original = {host: {}, supplier() {}, installation: {}, generation: {},
  runtime: process, moduleLifetime: viewModule, transport() {}, target: 'selected-node'};
const view = issue(original);
if (mode === 'absent') {
  assert.equal(associate(view, original), undefined);
  assert.throws(() => check(view, original), {code: 'InferTrustedStartupUnavailable'});
} else {
  assert.equal(associate(view, original), view);
  check(view, original);
  const scoped = {...original, installation: {}, transport() {}};
  const scopedView = issue(scoped);
  borrow(view, scopedView, original, scoped);
  check(scopedView, scoped);
  assert.throws(() => check(scopedView, {...scoped, generation: {}}),
    {code: 'InferTrustedRuntimeOriginalChanged'});
  if (mode === 'changed-loader') {
    const loader = require.cache[local];
    const filename = loader.filename;
    loader.filename = filename + '.foreign';
    assert.throws(() => check(view, original), {code: 'InferTrustedStartupChanged'});
    loader.filename = filename;
    assert.throws(() => check(view, original), {code: 'InferTrustedStartupChanged'});
  }
  retire(scopedView, original.host, original.generation);
  forget(scopedView, original.host, original.generation);
  retire(view, original.host, original.generation);
  forget(view, original.host, original.generation);
}
console.log(JSON.stringify({checked: true, physicalAcks: 0, providerCalls: 0,
  coreScopes: 0, normalNumericProfile: null, publicE2E: 0}));
`);
  return {directory, node, local, entry, put};
}

function child(fixture, args, mode = 'selected', extra = {}) {
  const result = spawnSync(process.execPath, [...args, fixture.entry, mode], {
    cwd: fixture.directory, env: {PATH: process.env.PATH, ...extra},
    encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout.trim()), {checked: true, physicalAcks: 0,
    providerCalls: 0, coreScopes: 0, normalNumericProfile: null, publicE2E: 0});
}

for (const flags of [[], ['--no-lazy']]) {
  test(`public Node selected startup reaches its same nested Local owner (${flags.length})`, t =>
    child(installation(t), [...flags, '--require', '@actql/node/selected-infer-startup']));
}
test('public Local selected startup uses its same package without the standard wrapper', t => {
  const fixture = installation(t);
  // Resolve the selected Local package from this consumer, not a Node sibling.
  fixture.put(join(fixture.directory, 'node_modules/@actql/local-node/package.json'),
    readFileSync(join(fixture.local, 'package.json')));
  // A direct consumer has the same full source-copied package, not a symlink to
  // another installation. Its entry imports that SAME Local private fixture.
  for (const name of ['selected-infer-startup.cjs', 'adapters/host-node/infer-trusted-node-preload.cjs',
    'adapters/host-node/infer-trusted-runtime-view.mjs']) {
    fixture.put(join(fixture.directory, 'node_modules/@actql/local-node', name),
      readFileSync(join(fixture.local, name)));
  }
  fixture.put(fixture.entry, readFileSync(fixture.entry, 'utf8')
    .replace("const local = createRequire(path).resolve('@actql/local-node/selected-infer-startup');",
      "const local = require.resolve('@actql/local-node/selected-infer-startup');"));
  child(fixture, ['--require', '@actql/local-node/selected-infer-startup']);
});
test('application-time public import cannot reconstruct an early startup', t =>
  child(installation(t), [], 'absent'));
test('another prior preload cannot supply the public selected startup', t => {
  const fixture = installation(t);
  const prior = join(fixture.directory, 'prior.cjs');
  fixture.put(prior, "'use strict';\n");
  child(fixture, ['--require', prior, '--require', '@actql/node/selected-infer-startup'], 'absent');
});
test('public startup rejects NODE_OPTIONS even without another preload', t =>
  child(installation(t), ['--require', '@actql/node/selected-infer-startup'],
    'absent', {NODE_OPTIONS: ''}));
test('public startup retains its actual wrapper identity and sticky invalidation', t =>
  child(installation(t), ['--require', '@actql/node/selected-infer-startup'], 'changed-loader'));

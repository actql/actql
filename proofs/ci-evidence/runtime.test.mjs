import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, chmodSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {inventoryDistribution, observeRuntime, runtimeResiduals, checkRuntimeObservation} from './runtime.mjs';
import {hash} from './inputs.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'actql-runtime-inputs-'));
  t.after(() => rmSync(root, {recursive: true, force: true}));
  const put = (path, value) => { mkdirSync(join(root, path, '..'), {recursive: true}); writeFileSync(join(root, path), value); };
  return {root, put};
}
const identity = value => hash(encode(value));

test('distribution captures actual regular bytes, mode and directory membership', t => {
  const {root, put} = fixture(t);
  put('lib/core/prelude.mi', 'independent core'); put('bin/moon', 'compiler');
  const before = inventoryDistribution(root);
  assert.deepEqual(before.unresolved, []);
  assert.equal(before.observedBytes, 24);
  assert.equal(before.entries.find(e => e.path === 'lib/core/prelude.mi').digest, hash('independent core'));
  put('lib/core/prelude.mi', 'different core');
  assert.notEqual(identity(inventoryDistribution(root)), identity(before));
  put('lib/core/new.mi', 'another dependency');
  assert(inventoryDistribution(root).entries.find(e => e.path === 'lib/core').members.includes('new.mi'));
  const member = inventoryDistribution(root);
  chmodSync(join(root, 'bin/moon'), 0o755);
  assert.notEqual(identity(inventoryDistribution(root)), identity(member));
  rmSync(join(root, 'lib/core/new.mi'));
  assert.notEqual(identity(inventoryDistribution(root)), identity(member));
});

test('physical root relocation is separate from relative installation identity', t => {
  const a = fixture(t), b = fixture(t);
  a.put('lib/core/value.mi', 'same core'); b.put('lib/core/value.mi', 'same core');
  assert.deepEqual(inventoryDistribution(a.root), inventoryDistribution(b.root));
});

test('symlinks including a root symlink stay open and never traverse the target', t => {
  const a = fixture(t), outside = fixture(t);
  outside.put('private/input', 'must not inventory this');
  symlinkSync(outside.root, join(a.root, 'external'));
  let observation = inventoryDistribution(a.root);
  assert.deepEqual(observation.unresolved, ['untraversed symlink: external']);
  assert(!observation.entries.some(e => e.path.includes('private')));
  assert(!encode(observation).includes(outside.root));
  observation = inventoryDistribution(join(a.root, 'external'));
  assert.deepEqual(observation.unresolved, ['untraversed symlink: .']);
  assert.equal(observation.entries.length, 1);
});

test('byte and entry limits, missing inputs cannot masquerade as complete coverage', t => {
  const {root, put} = fixture(t); put('a', '1234'); put('b', '5678');
  const bytes = inventoryDistribution(root, {maxBytes: 3});
  assert(bytes.unresolved.some(value => value.startsWith('byte limit')));
  assert.equal(bytes.observedBytes, 0);
  const entries = inventoryDistribution(root, {maxEntries: 1});
  assert.deepEqual(entries.unresolved, ['entry limit']);
  assert.equal(entries.entries.length, 1);
  const missing = inventoryDistribution(join(root, 'not-installed'));
  assert.deepEqual(missing.unresolved, ['missing input: .']);
  assert.throws(() => inventoryDistribution(root, {maxEntries: 0}));
});

function installation(t) {
  const f = fixture(t);
  f.put('toolchain.json', JSON.stringify({version: 'test-pin'}));
  f.put('proofs/bounded-session/lean-toolchain', 'leanprover/lean4:v4.30.0-rc1');
  for (const name of ['moon', 'moonc', 'moonrun']) f.put(`.toolchains/moonbit-test-pin/bin/${name}`, name);
  f.put('.toolchains/moonbit-test-pin/lib/core/prelude.mi', 'core dependency');
  f.put('.toolchains/moonbit-test-pin/installed.json', 'installation marker');
  f.put('.toolchains/lean-4.30.0-rc1-linux/bin/lean', 'lean');
  f.put('.toolchains/lean-4.30.0-rc1-linux/lib/lean/Init.olean', 'Lean dependency');
  f.put('node', 'node executable');
  const observe = env => observeRuntime({root: f.root, executable: join(f.root, 'node'), env});
  return {...f, observe};
}

test('actual MoonBit core and Lean imports are bound, rather than executable hashes alone', t => {
  const f = installation(t), a = f.observe({}).runtime;
  f.put('.toolchains/moonbit-test-pin/lib/core/prelude.mi', 'changed core');
  const b = f.observe({}).runtime;
  assert.deepEqual(a.executables, b.executables);
  assert.notEqual(identity(a), identity(b));
  f.put('.toolchains/lean-4.30.0-rc1-linux/lib/lean/Init.olean', 'changed Lean import');
  assert.notEqual(identity(b), identity(f.observe({}).runtime));
  f.put('.toolchains/moonbit-test-pin/installed.json', 'changed installation');
  assert.notEqual(identity(b), identity(f.observe({}).runtime));
});

test('matching distribution bytes do not close loaders, inherited environment or execution-time mutation', t => {
  const f = installation(t), observed = f.observe({});
  assert(runtimeResiduals.every(reason => observed.runtime.unresolved.includes(reason)));
  assert(observed.distributionInputs.lean.entries.some(e => e.path === 'lib/lean/Init.olean'));
  assert.equal(checkRuntimeObservation(observed.runtime, observed.distributionInputs), true);
  assert(observed.measurement.entries > 0 && observed.measurement.bytes > 0);
  assert.equal(observed.measurement.inputDigest, identity(observed.runtime));
  assert(Number.isSafeInteger(observed.measurement.milliseconds));
});

test('only curated configuration is bound, without arbitrary secret-derived hashes', t => {
  const f = installation(t), secret = 'unique-secret-not-an-execution-option';
  const a = f.observe({TZ: 'UTC', ACTIONS_READ_TOKEN: secret}).runtime;
  const b = f.observe({TZ: 'UTC', ACTIONS_READ_TOKEN: 'different-secret'}).runtime;
  assert.equal(identity(a), identity(b));
  assert(!encode(a).includes(secret) && !encode(a).includes(hash(secret)) && !encode(a).includes('ACTIONS_READ_TOKEN'));
  assert.notEqual(identity(a), identity(f.observe({TZ: 'Europe/Paris'}).runtime));
});


test('archive consumer independently rejects missing inventory, changed bytes and erased coverage', t => {
  const f = installation(t), observed = f.observe({});
  assert.equal(checkRuntimeObservation(observed.runtime, observed.distributionInputs), true);
  const missing = structuredClone(observed.distributionInputs); delete missing.lean;
  assert.throws(() => checkRuntimeObservation(observed.runtime, missing));
  const changed = structuredClone(observed.distributionInputs);
  changed.lean.entries.find(e => e.kind === 'file').digest = '1'.repeat(64);
  assert.throws(() => checkRuntimeObservation(observed.runtime, changed), /inventory bytes/u);
  assert.throws(() => checkRuntimeObservation({...observed.runtime, unresolved: []}, observed.distributionInputs), /unclosed execution/u);
  const open = structuredClone(observed.distributionInputs); open.lean.unresolved.push('missing loader');
  const labeled = f.observe({}).runtime;
  labeled.distributions.lean.unresolved.push('missing loader');
  // Even a self-consistent inventory digest must retain the coverage reason.
  labeled.distributions.lean.digest = identity(open.lean);
  assert.throws(() => checkRuntimeObservation(labeled, open), /coverage gap/u);
});

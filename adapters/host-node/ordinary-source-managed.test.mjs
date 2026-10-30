import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareOrdinarySourceManagedInstallation,
  prepareOrdinaryProjectSourceManagedInstallation} from './ordinary-source-managed.mjs';
import runtime from './ordinary-node-resource-runtime.cjs';

async function fixture(source = true, project = false) {
  const root = await mkdtemp(join(tmpdir(), 'actql-ordinary-source-'));
  const dataPath = join(root, 'data.json');
  await writeFile(dataPath, '{"original":1}');
  const originals = {}, prepared = {}, request = {}, body = {}, declarations = [{}, {}], selected = {};
  const bundle = Object.freeze({dataPath, sources: declarations.map(declaration => ({declaration}))});
  let current = true;
  const quotes = {pure: 0, effect: 0};
  const callbacks = {validator(value) {
    assert.strictEqual(value, originals);
    if (!current) throw new Error('original-current');
  }, async prepare() {}, read: () => bundle, request(value, p) {
    assert.strictEqual(p, prepared); return request;
  }, intent: () => 'sha256:' + 'a'.repeat(64), requirements: () => {quotes.pure++; return {planningWork: 100,
    attempts: 10, holdings: 10, transferBytes: 10000n, retainedBytes: 10000n, executionBytes: 10000n};},
    effectRequirements: () => {quotes.effect++; return {planningWork: 100,
      attempts: 10, holdings: 10, transferBytes: 10000n, retainedBytes: 10000n, executionBytes: 10000n};},
    mockRequirements: () => ({planningWork: 100, attempts: 10, holdings: 10,
      transferBytes: 10000n, retainedBytes: 10000n, executionBytes: 10000n}),
    contentRequirements(value, actualPrepared, actualSelected) {
      assert.strictEqual(value, originals); assert.strictEqual(actualPrepared, prepared);
      assert.strictEqual(actualSelected, selected);
      return {planningWork: 100, attempts: 2, holdings: 10,
        transferBytes: 10000n, retainedBytes: 10000n, executionBytes: 10000n};
    }};
  const view = project ? await prepareOrdinaryProjectSourceManagedInstallation(originals, callbacks)
    : await prepareOrdinarySourceManagedInstallation(originals, callbacks, source);
  const receipt = view.beforeSourceSnapshot('aql', 'text', {});
  view.bindSourceSnapshot(receipt, body);
  view.bindSourceRequest(receipt, body, request);
  return {view, prepared, selected, declarations, dataPath, receipt, quotes, setCurrent(value) {current = value;}};
}

test('ordinary Content owns one purpose and retains the same keyed physical close through current refusal', async () => {
  const f = await fixture(true, true);
  const original = f.view.prepareContentRun(f.prepared, f.selected);
  assert.strictEqual(f.view.prepareContentRun(f.prepared, f.selected), original);
  assert.throws(() => f.view.prepareRun(f.prepared), {code: 'ForeignInstalledModelPreparation'});
  assert.throws(() => f.view.prepareContentRun(f.prepared, {}), {code: 'ForeignInstalledModelPreparation'});
  const ports = runtime.prepareOriginalLocalContentRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  const request = {}, child = f.view.prepareKeyedRead(f.prepared, f.declarations[0], original, request);
  assert.throws(() => f.view.prepareKeyedRead(f.prepared, {}, original, {}), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => f.view.prepareKeyedRead(f.prepared, f.declarations[0], {}, {}), {code: 'InstalledSourcePreparationMismatch'});
  assert.throws(() => f.view.prepareKeyedRead(f.prepared, f.declarations[0], original, request), {code: 'InstalledSourcePreparationMismatch'});
  let pending = true, calls = 0;
  const physical = {close() {assert.strictEqual(this, physical); calls++; return {pending};}, status() {return {pending};}};
  child.retainChild(physical);
  physical.close = () => assert.fail('replacement close must not be adopted');
  f.view.finishSourceProducer(f.receipt, 'returned');
  f.setCurrent(false);
  assert.throws(() => f.view.assertCurrent(), /original-current/);
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);
  assert.equal(ports.status(2), -42);
  assert.equal((await child.close()).pending, true);
  pending = false;
  assert.equal((await child.close()).pending, false);
  assert.equal(calls, 2);
  assert.equal(ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary keyed physical child history is not refilled by close', async () => {
  const f = await fixture(true, true);
  const original = f.view.prepareContentRun(f.prepared, f.selected);
  for (let index = 0; index < 2; index++) {
    const child = f.view.prepareKeyedRead(f.prepared, f.declarations[0], original, {});
    assert.equal((await child.close()).pending, false);
  }
  assert.throws(() => f.view.prepareKeyedRead(f.prepared, f.declarations[0], original, {}),
    {code: 'InstalledSourcePreparationMismatch'});
  f.view.finishSourceProducer(f.receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary two-Source acquisition uses distinct actual readers and one managed Run', async () => {
  const f = await fixture(), original = f.view.prepareRun(f.prepared);
  const ports = runtime.prepareOriginalManagedRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  const children = f.declarations.map(declaration => f.view.prepareRead(f.prepared, declaration, original));
  assert.notStrictEqual(children[0].originalSource, children[1].originalSource);
  assert.throws(() => f.view.prepareRead(f.prepared, f.declarations[0], original));
  const bytes = await Promise.all(children.map(child => child.readOriginalBytes()));
  assert.equal(bytes[0].toString(), '{"original":1}');
  assert.deepEqual(bytes[1], bytes[0]);
  assert.notStrictEqual(bytes[0], bytes[1]);
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);
  assert.equal(ports.status(2), -42);
  for (const child of children) assert.equal((await child.close()).pending, false);
  assert.equal(ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary Source refuses a changed same-Run file and preserves cleanup after current refusal', async () => {
  const f = await fixture(), original = f.view.prepareRun(f.prepared);
  const children = f.declarations.map(declaration => f.view.prepareRead(f.prepared, declaration, original));
  await children[0].readOriginalBytes();
  await writeFile(f.dataPath, '{"original":2}');
  await assert.rejects(children[1].readOriginalBytes(), {code: 'InstalledMockSourceChanged'});
  f.setCurrent(false);
  assert.throws(() => f.view.assertCurrent(), /original-current/);
  f.view.finishSourceProducer(f.receipt, 'failed');
  for (const child of children) assert.equal((await child.close()).pending, false);
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary Compute refuses a foreign request and retains a real in-flight producer until finished', async () => {
  const f = await fixture(false);
  assert.throws(() => f.view.prepareRun({}));
  assert.equal((await f.view.close()).pending, true);
  f.view.finishSourceProducer(f.receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary Mock purpose retains one request original and both real Source children without conversion', async () => {
  const f = await fixture(), model = Object.freeze({});
  const original = f.view.prepareLocalMockModelRun(f.prepared, model);
  assert.strictEqual(f.view.prepareLocalMockModelRun(f.prepared, model), original);
  assert.equal(runtime.prepareOriginalManagedRunPorts(original, f.prepared), null);
  assert.throws(() => f.view.prepareRun(f.prepared), {code: 'ForeignInstalledModelPreparation'});
  assert.throws(() => f.view.prepareLocalMockModelRun(f.prepared, {}), {code: 'ForeignInstalledModelPreparation'});
  const ports = runtime.prepareOriginalLocalMockModelRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  assert.equal(runtime.prepareOriginalLocalMockModelRunPorts(original, f.prepared), null);
  const children = f.declarations.map(declaration => f.view.prepareRead(f.prepared, declaration, original));
  const bytes = await Promise.all(children.map(child => child.readOriginalBytes()));
  assert.deepEqual(bytes[0], bytes[1]);
  assert.notStrictEqual(bytes[0], bytes[1]);
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);
  assert.equal(ports.status(2), -42);
  await children[0].close();
  assert.equal(ports.status(2), -42);
  await children[1].close();
  assert.equal(ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary Source original cannot later acquire the separate Mock purpose', async () => {
  const f = await fixture();
  f.view.prepareRun(f.prepared);
  assert.throws(() => f.view.prepareLocalMockModelRun(f.prepared, {}), {code: 'ForeignInstalledModelPreparation'});
  f.view.finishSourceProducer(f.receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

test('ordinary Effect preparation uses its original typed quote and cannot switch to Pure', async () => {
  const f = await fixture(), original = f.view.prepareEffectRun(f.prepared);
  assert.strictEqual(f.view.prepareEffectRun(f.prepared), original);
  assert.deepEqual(f.quotes, {pure: 0, effect: 1});
  assert.throws(() => f.view.prepareRun(f.prepared), {code: 'ForeignInstalledModelPreparation'});
  const ports = runtime.prepareOriginalManagedRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  const children = f.declarations.map(declaration => f.view.prepareRead(f.prepared, declaration, original));
  const bytes = await Promise.all(children.map(child => child.readOriginalBytes()));
  assert.deepEqual(bytes[0], bytes[1]); assert.notStrictEqual(bytes[0], bytes[1]);
  f.view.finishSourceProducer(f.receipt, 'returned');
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n), 0);
  assert.equal(ports.status(2), -42);
  for (const child of children) await child.close();
  assert.equal(ports.status(2), 0);
  assert.equal((await f.view.close()).pending, false);
});

test('Effect Model Plan has no standalone manager Root constructor after Request adoption', async () => {
  const f = await fixture();
  assert.equal(f.view.prepareEffectModelPlanRun, undefined);
  assert.equal(typeof f.view.adoptEffectModelPreparation, 'function');
  assert.deepEqual(f.quotes, {pure: 0, effect: 0});
  f.view.finishSourceProducer(f.receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

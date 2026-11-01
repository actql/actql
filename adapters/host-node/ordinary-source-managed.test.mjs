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

test('ordinary Project Content exposes only its original Request constructor, not another Root', async () => {
  const f = await fixture(true, true);
  assert.equal(f.view.prepareContentRun, undefined);
  assert.equal(typeof f.view.prepareKeyedContentRun, 'function');
  assert.throws(() => f.view.prepareKeyedContentRun(f.prepared, {}, {}, {}, () => {}, () => {}),
    {code: 'ForeignInstalledSourceProducer'});
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
  assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
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

test('ordinary manager exposes no retired raw Effect entry or replacement Root', async () => {
  const f = await fixture();
  assert.equal(Object.hasOwn(f.view, 'prepareEffectRun'), false);
  assert.equal(f.view.prepareEffectRun, undefined);
  assert.deepEqual(f.quotes, {pure: 0, effect: 0});
  f.view.finishSourceProducer(f.receipt, 'failed');
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

test('retired Mock Effect manager entry cannot acquire another Model Root', async () => {
  const f = await fixture();
  assert.equal(f.view.prepareEffectLocalMockModelRun, undefined);
  assert.deepEqual(f.quotes, {pure: 0, effect: 0});
  await f.view.close();
});

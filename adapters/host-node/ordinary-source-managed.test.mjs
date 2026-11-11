import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, writeFile} from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareOrdinarySourceManagedInstallation,
  prepareOrdinaryProjectSourceManagedInstallation} from './ordinary-source-managed.mjs';
import runtime from './ordinary-node-resource-runtime.cjs';
import {mockProjectFiles} from '../../scripts/fixtures/hubspot-approval/three-source-mock-project.mjs';

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

test('ordinary Mock published Source occurrences keep three children of the same declaration distinct', async () => {
  const files = mockProjectFiles({recordId: 'original', previousName: 'before', nextName: 'after'});
  const aliases = JSON.parse(files['mock/catalog.json']).connections.hubspot.query_aliases;
  assert.deepEqual(aliases.map(alias => alias.name),
    ['hubspot.companies', 'hubspot.companies_middle', 'hubspot.companies_right']);
  assert.equal(new Set(aliases.map(alias => alias.resource)).size, 1);
  const f = await fixture(), original = f.view.prepareRun(f.prepared);
  const ports = runtime.prepareOriginalManagedRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  const children = [];
  try {
    for (const [task] of aliases.entries()) {
      children.push(f.view.prepareRead(f.prepared, f.declarations[0], original,
        Object.freeze({stage: task, input: 0, task})));
    }
    assert.equal(new Set(children.map(child => child.originalSource)).size, 3);
    assert.throws(() => f.view.prepareRead(f.prepared, f.declarations[0], original,
      {stage: 1, input: 0, task: 1}), {code: 'InstalledSourcePreparationMismatch'});
    const bytes = await Promise.all(children.map(child => child.readOriginalBytes()));
    assert.equal(bytes.length, 3);
    assert(bytes.every(value => value.toString() === '{"original":1}'));
    assert.equal(new Set(bytes).size, 3);
  } finally {
    f.view.finishSourceProducer(f.receipt, 'returned');
    assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
    for (const child of children) assert.equal((await child.close()).pending, false);
    assert.equal(ports.status(2), 0);
    assert.equal((await f.view.close()).pending, false);
  }
});

test('ordinary Mock occurrence selection keeps foreign Run, declaration and malformed coordinates refused', async () => {
  const f = await fixture(), original = f.view.prepareRun(f.prepared);
  const ports = runtime.prepareOriginalManagedRunPorts(original, f.prepared);
  assert.equal(ports.status(0), 0);
  const occurrence = {stage: 0, input: 0, task: 0};
  try {
    assert.throws(() => f.view.prepareRead(f.prepared, {}, original, occurrence),
      {code: 'InstalledSourcePreparationMismatch'});
    assert.throws(() => f.view.prepareRead(f.prepared, f.declarations[0], {}, occurrence),
      {code: 'InstalledSourcePreparationMismatch'});
    for (const malformed of [{stage: -1, input: 0, task: 0},
      {stage: 0, input: -1, task: 0}, {stage: 0, input: 0, task: 0.5}, {}, null]) {
      assert.throws(() => f.view.prepareRead(f.prepared, f.declarations[0], original, malformed),
        {code: 'InstalledSourcePreparationMismatch'});
    }
  } finally {
    f.view.finishSourceProducer(f.receipt, 'returned');
    assert.equal(ports.report(0, 0, 0, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0, 0, 0), 0);
    assert.equal(ports.status(2), 0);
    assert.equal((await f.view.close()).pending, false);
  }
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

// Actual lookup body with explicit weak/live/receipt ports. This is a local
// work counter, not a Run, Resource admission or latency measurement.
test('producer Request lookup stays linear for N and twice N without scanning other live originals', () => {
  const source = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
  const start = source.indexOf('  const producerForRequest = request => {');
  const end = source.indexOf('  const current = () => {', start);
  assert(start >= 0 && end > start);
  const body = source.slice(start, end);
  for (const count of [64, 128]) {
    let visits = 0, gets = 0, memberships = 0;
    const weak = new WeakMap(), receipts = new WeakMap(), values = [];
    const producers = new Set();
    const originalValues = producers.values;
    producers[Symbol.iterator] = function* () {
      for (const value of Reflect.apply(originalValues, this, [])) {visits++; yield value;}
    };
    const originalHas = producers.has;
    producers.has = function(value) {memberships++; return Reflect.apply(originalHas, this, [value]);};
    const index = {get(request) {gets++; return weak.get(request);}};
    for (let i = 0; i < count; i++) {
      const request = {}, receipt = {}, producer = {request, receipt, finished:false};
      weak.set(request, producer); receipts.set(receipt, producer); producers.add(producer); values.push(producer);
    }
    const lookup = new Function('requestProducers', 'producers', 'receipts', body + ';return producerForRequest;')(index, producers, receipts);
    for (const producer of values) assert.equal(lookup(producer.request), producer);
    assert.equal(visits, 0, 'unrelated live producer visits');
    assert.equal(gets, count, 'one original weak lookup per Request');
    assert.equal(memberships, count, 'one actual live membership check per Request');
    const original = values[0], request = original.request;
    producers.delete(original); assert.equal(lookup(request), undefined);
    producers.add(original); original.finished = true; assert.equal(lookup(request), undefined);
    original.finished = false; receipts.delete(original.receipt); assert.equal(lookup(request), undefined);
    receipts.set(original.receipt, original); original.request = {}; assert.equal(lookup(request), undefined);
    assert.equal(lookup({}), undefined);
  }
});

test('ordinary producer binding rejects a second original for the same Request and stale or foreign Host lookups', async () => {
  const f = await fixture(false), g = await fixture(false);
  const request = {};
  const first = f.view.beforeSourceSnapshot('aql', 'one', {}), body = {};
  f.view.bindSourceSnapshot(first, body); f.view.bindSourceRequest(first, body, request);
  assert.equal(f.view.submittedIntentOriginal(request), undefined);
  assert.throws(() => g.view.submittedIntentOriginal(request), {code:'ForeignInstalledSourceProducer'});
  assert.throws(() => f.view.submittedIntentOriginal({...request}), {code:'ForeignInstalledSourceProducer'});
  const second = f.view.beforeSourceSnapshot('aql', 'two', {}), otherBody = {};
  f.view.bindSourceSnapshot(second, otherBody);
  assert.throws(() => f.view.bindSourceRequest(second, otherBody, request), {code:'ForeignInstalledSourceProducer'});
  f.view.finishSourceProducer(first, 'returned');
  assert.throws(() => f.view.submittedIntentOriginal(request), {code:'ForeignInstalledSourceProducer'});
  assert.throws(() => f.view.bindSourceRequest(second, otherBody, request), {code:'ForeignInstalledSourceProducer'});
  f.view.finishSourceProducer(second, 'failed'); f.view.finishSourceProducer(f.receipt, 'returned');
  g.view.finishSourceProducer(g.receipt, 'returned');
  assert.equal((await f.view.close()).pending, false); assert.equal((await g.view.close()).pending, false);
});


test('failed original Source initialization cannot leave a Request lookup or bypass the existing current refusal', async () => {
  const originals = {}, failure = {}, request = {};
  const view = await prepareOrdinarySourceManagedInstallation(originals, {
    validator(value) {assert.equal(value, originals);},
    borrowSourceInitializationMaterial() {throw failure;},
  }, false);
  assert.throws(() => view.beforeSourceSnapshot('aql', 'one', {}), cause => cause === failure);
  assert.throws(() => view.submittedIntentOriginal(request), {code:'ForeignInstalledSourceProducer'});
  assert.equal((await view.close()).pending, false);
  const f = await fixture(false);
  f.setCurrent(false);
  assert.throws(() => f.view.submittedIntentOriginal(request), /original-current/);
  f.setCurrent(true); f.view.finishSourceProducer(f.receipt, 'failed');
  assert.equal((await f.view.close()).pending, false);
});

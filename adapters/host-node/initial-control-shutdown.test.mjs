import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledHostShutdown, retainInstalledHostInitializationFailure}
  from './installed-host-cleanup.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';

// These explicit control-port doubles exercise existing Host custody only.
// They do not issue a startup admission, physical lease or business capacity.
function shutdown(initialControl, overrides = {}) {
  const calls = [];
  const actions = Object.fromEntries(['stop', 'drain', 'retire', 'checkpoint',
    'journal', 'source', 'effect', 'store', 'diagnostic', 'observation',
    'ownerViews', 'finalize'].map(name => [name, () => calls.push(name)]));
  return {calls, owner: createInstalledHostShutdown({...actions,
    ...overrides, initialControl})};
}

test('initial control holding follows every child and precedes final reference retirement', async () => {
  let f;
  const control = {close() {
    assert.equal(this, control); f.calls.push('initialControl');
    return {pending: false};
  }};
  f = shutdown(control);
  await f.owner.close(); await f.owner.close();
  assert.deepEqual(f.calls, ['stop', 'drain', 'retire', 'checkpoint', 'journal',
    'source', 'effect', 'store', 'ownerViews', 'diagnostic', 'observation',
    'initialControl', 'finalize']);
  assert.deepEqual(f.owner.status().pending, []);
});

test('failed child close retains initial control until the same child ACK', async () => {
  let pending = true, controlCloses = 0, journalCloses = 0;
  const control = {close() {controlCloses++; return {pending: false};}};
  const f = shutdown(control, {journal() {
    journalCloses++; if (pending) throw new Error('OriginalJournalPending');
  }});
  await assert.rejects(f.owner.close(), {code: 'InstalledHostCleanupPending'});
  assert.equal(controlCloses, 0); assert.equal(f.calls.includes('finalize'), false);
  pending = false; await f.owner.close();
  assert.equal(journalCloses, 2); assert.equal(controlCloses, 1);
  assert.equal(f.calls.filter(name => name === 'store').length, 1);
});

test('control Promise completion and malformed observations cannot retire the holding', async () => {
  let observation, closes = 0;
  const control = {async close() {closes++; return observation;}};
  const f = shutdown(control);
  for (observation of [undefined, {}, {pending: true}, {pending: null}, {pending: 0}]) {
    await assert.rejects(f.owner.close(), {message: 'InstalledHostInitialControlCleanupPending'});
    assert.deepEqual(f.owner.status().pending, ['initialControl', 'finalize']);
    assert.equal(f.calls.includes('finalize'), false);
  }
  observation = {pending: false}; await f.owner.close();
  assert.equal(closes, 6); assert.equal(f.calls.filter(name => name === 'finalize').length, 1);
});

test('original close receiver and callback survive pending retries without replacement', async () => {
  let reads = 0, calls = 0, pending = true;
  const control = {get close() {
    reads++; return function () {assert.equal(this, control); calls++; return {pending};};
  }};
  const f = shutdown(control);
  await assert.rejects(f.owner.close());
  Object.defineProperty(control, 'close', {value() {throw new Error('Replacement');}});
  pending = false; await f.owner.close(); await f.owner.close();
  assert.equal(reads, 1); assert.equal(calls, 2);
});

test('shutdown captures original control close before a preceding child await', async () => {
  let enter, release, pending = true, originals = 0, replacements = 0;
  const entered = new Promise(resolve => {enter = resolve;});
  const child = new Promise(resolve => {release = resolve;});
  const control = {close() {assert.equal(this, control); originals++; return {pending};}};
  const f = shutdown(control, {async drain() {enter(); await child;}});
  const closing = f.owner.close();
  await entered;
  assert.equal(originals, 0);
  control.close = () => {replacements++; return {pending: false};};
  release();
  await assert.rejects(closing, {message: 'InstalledHostInitialControlCleanupPending'});
  assert.equal(originals, 1); assert.equal(replacements, 0);
  assert.equal(f.calls.includes('finalize'), false);
  assert.deepEqual(f.owner.status().pending, ['initialControl', 'finalize']);
  pending = false; await f.owner.close();
  assert.equal(originals, 2); assert.equal(replacements, 0);
  assert.equal(f.calls.filter(name => name === 'finalize').length, 1);
});

test('shutdown captures original control close before its first close request', async () => {
  let originals = 0, replacements = 0;
  const control = {close() {assert.equal(this, control); originals++; return {pending: false};}};
  const f = shutdown(control);
  control.close = () => {replacements++; return {pending: false};};
  await f.owner.close();
  assert.equal(originals, 1); assert.equal(replacements, 0);
});

test('initialization captures original control close before a preceding child await', async () => {
  let enter, release, pending = true, originals = 0, replacements = 0;
  const entered = new Promise(resolve => {enter = resolve;});
  const child = new Promise(resolve => {release = resolve;});
  const primary = Object.freeze(new Error('OriginalPreparationFailed'));
  const control = {close() {assert.equal(this, control); originals++; return {pending};}};
  const retaining = retainInstalledHostInitializationFailure(primary,
    {store: {async close() {enter(); await child;}}, initialControl: control});
  await entered;
  assert.equal(originals, 0);
  control.close = () => {replacements++; return {pending: false};};
  release();
  const failure = await retaining;
  assert.equal(failure.primaryFailure, primary);
  assert.equal(originals, 1); assert.equal(replacements, 0);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(failure.cleanupHandle.status().owners, ['initial-control']);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(originals, 2); assert.equal(replacements, 0);
  assert.equal(failure.cleanupHandle.status().pending, false);
});

for (const initialization of [false, true]) {
  test(`${initialization ? 'initialization' : 'shutdown'} retains an unobserved throwing control getter for retry`, async () => {
    let readable = false, reads = 0, closes = 0;
    const originalError = new Error('OriginalControlGetterPending');
    const control = {get close() {
      reads++;
      if (!readable) throw originalError;
      return function () {assert.equal(this, control); closes++; return {pending: false};};
    }};
    if (initialization) {
      const primary = Object.freeze(new Error('OriginalPreparationFailed'));
      const failure = await retainInstalledHostInitializationFailure(primary, {initialControl: control});
      assert.equal(failure.primaryFailure, primary);
      assert.equal(failure.cleanupHandle.status().pending, true);
      assert.equal(failure.cleanupHandle.status().errors.at(-1).error, originalError);
      readable = true; await failure.cleanupHandle.retry();
      assert.equal(failure.cleanupHandle.status().pending, false);
    } else {
      const f = shutdown(control);
      await assert.rejects(f.owner.close(), error => error === originalError);
      assert.deepEqual(f.owner.status().pending, ['initialControl', 'finalize']);
      assert.equal(f.calls.includes('finalize'), false);
      readable = true; await f.owner.close();
      assert.equal(f.calls.filter(name => name === 'finalize').length, 1);
    }
    assert.equal(closes, 1); assert.ok(reads >= 2);
  });
}

test('throwing initialization cleanup getters retain the already acquired control holding', async () => {
  let readable = false, pending = true, retries = 0, closes = 0;
  const child = {status: () => ({pending, errors: []}), retry() {retries++;}};
  const original = Object.freeze({get cleanupHandle() {
    if (!readable) throw new Error('OriginalCleanupGetterPending');
    return child;
  }, get primaryFailure() {throw new Error('OriginalDiagnosticGetter');}});
  const control = {close() {closes++; return {pending: false};}};
  const failure = await retainInstalledHostInitializationFailure(original, {initialControl: control});
  assert.equal(failure.primaryFailure, original);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(closes, 0);
  readable = true; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(retries, 1); assert.equal(closes, 0);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(retries, 2); assert.equal(closes, 1);
});

test('a successfully absent original cleanup cannot be replaced to acknowledge its pending duty', async () => {
  let closes = 0;
  const original = {cleanupHandle: undefined, cleanupPending: true};
  const control = {close() {closes++; return {pending: false};}};
  const failure = await retainInstalledHostInitializationFailure(original, {initialControl: control});
  original.cleanupHandle = {status: () => ({pending: false}), retry() {
    assert.fail('Do not use a replacement cleanup owner');
  }};
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(closes, 0);
});

test('initialization preserves child-first control custody through the same retry', async () => {
  let pending = true, childRetries = 0, controlCloses = 0, storeCloses = 0;
  const child = {status: () => ({pending}), retry() {childRetries++;}};
  const primary = Object.freeze(Object.assign(new Error('OriginalPreparationFailed'),
    {cleanupHandle: child, cleanupPending: true}));
  const control = {close() {controlCloses++; return {pending: false};}};
  const failure = await retainInstalledHostInitializationFailure(primary,
    {store: {close() {storeCloses++;}}, initialControl: control});
  assert.equal(failure.primaryFailure, primary); assert.equal(controlCloses, 0);
  assert.equal(storeCloses, 0); assert.equal(failure.cleanupHandle.status().pending, true);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(controlCloses, 1); assert.equal(storeCloses, 1); assert.equal(childRetries, 2);
  assert.equal(failure.cleanupHandle.status().pending, false);
  await failure.cleanupHandle.retry(); assert.equal(controlCloses, 1);
});

test('initialization does not retire control while an independent Store close remains Unknown', async () => {
  let pending = true, closes = 0, observation;
  const control = {close() {closes++; return observation;}};
  const failure = await retainInstalledHostInitializationFailure(new Error('OriginalFailure'),
    {store: {close() {if (pending) throw new Error('StoreUnknown');}}, initialControl: control});
  assert.equal(closes, 0);
  pending = false; observation = {pending: true};
  await failure.cleanupHandle.retry();
  assert.equal(closes, 1); assert.equal(failure.cleanupHandle.status().pending, true);
  observation = {pending: false}; await failure.cleanupHandle.retry();
  assert.equal(closes, 2); assert.equal(failure.cleanupHandle.status().pending, false);
});

test('existing installed Host shutdown retains and closes the same initial control', async () => {
  let pending = true, closes = 0, finalized = 0;
  const control = {close() {assert.equal(this, control); closes++; return {pending};}};
  const noOp = () => {};
  const host = {initialControl: control, dispatchOwner: {drain: noOp},
    retireTerminalEffects: noOp, journal: {close: noOp}, store: {close: noOp},
    retireModelRuntime() {finalized++;}};
  const owner = installedHostShutdown(host);
  await assert.rejects(owner.close());
  host.initialControl = {close() {throw new Error('ForeignControl');}};
  assert.equal(finalized, 0);
  pending = false; await owner.close(); await owner.close();
  assert.equal(closes, 2); assert.equal(finalized, 1);
});

test('pending initialization keeps bounded first and latest original phase diagnostics', async () => {
  let sequence = 0, pending = true;
  const failures = [];
  const control = {close() {
    if (!pending) return {pending: false};
    const failure = new Error(`OriginalControlClose${++sequence}`);
    failures.push(failure); throw failure;
  }};
  const primary = Object.freeze(new Error('OriginalPreparationFailure'));
  const failure = await retainInstalledHostInitializationFailure(primary, {initialControl: control});
  for (let retry = 0; retry < 8; retry++) await failure.cleanupHandle.retry();
  assert.equal(failure.primaryFailure, primary);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(failure.cleanupHandle.status().errors.map(item => item.error),
    [failures[0], failures.at(-1)]);
  pending = false; await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(failure.cleanupHandle.status().errors.map(item => item.error),
    [failures[0], failures.at(-1)]);
});

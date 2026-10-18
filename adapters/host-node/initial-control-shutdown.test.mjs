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

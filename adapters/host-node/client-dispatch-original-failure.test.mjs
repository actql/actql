import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {CapturedRunPublicationError} from './entry.mjs';
import {beginManagedFailureProgress, settleFailedManagedOperations} from '../host-common/managed-failure.mjs';

// The selected immutable runtime supplies only the existing pure progress
// planner. Physical cleanup and the actual imported dispatch Owner stay here.
const runtime = await import(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME
  ? pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME).href
  : new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href);

async function managedFailure(primary) {
  let pending = true, closes = 0, settlements = 0;
  primary.cleanupPending = true;
  primary.cleanupHandle = {status: () => ({pending, errors: []}),
    async retry() {pending = false;}};
  const progress = beginManagedFailureProgress(runtime, true, false);
  const wrapper = settleFailedManagedOperations({close() {closes++;},
    settle() {settlements++;}, cleanup_refresh: () => true}, () => {}, primary, progress);
  assert.notEqual(wrapper, primary);
  assert.equal(wrapper.primaryFailure, primary);
  assert.equal(wrapper.cause, primary);
  assert.equal(wrapper.cleanupPending, true);
  assert.equal((await wrapper.cleanupHandle.retry()).pending, false);
  assert.equal(closes, 1);
  assert.equal(settlements, 1);
  return wrapper;
}

async function observe(failure) {
  const records = [], stopped = [];
  let closes = 0, cleanups = 0;
  const owner = installNodeClientDispatchOwner({observed(name, detail) {
    if (name === 'dispatch_failed') records.push(detail);
  }});
  const ref = {runDefinitionCid: 'original-failure-site'};
  const physical = {async close() {closes++;}, cleanup() {cleanups++; return true;},
    cleanupPending: () => false};
  await assert.rejects(owner.track(ref, {run({beginPhysicalWork, retainExecution}) {
    beginPhysicalWork(); retainExecution(physical); throw failure;
  }, observeStopped: outcome => stopped.push(outcome)}), actual => actual === failure);
  await owner.drain();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(closes, 1); assert.equal(cleanups, 1);
  assert.deepEqual(stopped, [null]);
  assert.equal(owner.operation(ref), undefined);
  assert.equal(records.length, 1);
  return records[0];
}

const failure = () => Object.assign(new Error('OriginalManagedFailure'), {code: 'OriginalManagedFailure'});

test('original failure site survives actual managed and publication wrappers', async () => {
  const primary = failure();
  const managed = await managedFailure(primary);
  const publication = new CapturedRunPublicationError(managed, undefined);
  const detail = await observe(publication);
  assert.equal(publication.primaryFailure, managed);
  assert.equal(managed.primaryFailure, primary);
  assert.equal(detail.primaryCode, primary.code);
  assert.equal(detail.primaryDiagnostic.kind, 'code_site');
  assert.match(detail.primaryDiagnostic.message,
    /^adapters\/host-node\/client-dispatch-original-failure\.test\.mjs:\d+:\d+/u);
  assert.equal(detail.primaryDiagnostic.message.includes('managed-failure.mjs'), false);
  assert.equal(detail.primaryDiagnostic.message.includes(process.cwd()), false);
  assert.equal(detail.primaryDiagnostic.message.includes(primary.message), false);
  assert.equal(Object.isFrozen(detail.primaryDiagnostic), true);
  assert.ok(detail.primaryDiagnostic.message.length <= 2048);
  assert.deepEqual(Object.keys(detail.primaryDiagnostic).sort(), ['kind', 'message', 'phase']);
});

test('original typed diagnostic stays ahead of optional original code site', async () => {
  const primary = Object.assign(failure(), {primaryDiagnostic: Object.freeze({
    code: 'MoonBitHostFailure', phase: 'local_managed_advance', kind: 'control_work',
    task: 3, controlWorkLimit: 17})});
  const managed = await managedFailure(primary);
  const detail = await observe(new CapturedRunPublicationError(managed, undefined));
  assert.deepEqual(detail.primaryDiagnostic, primary.primaryDiagnostic);
});

test('original failure site reads one inert association without invoking or traversing foreign data', async () => {
  let reads = 0;
  const accessor = failure();
  Object.defineProperty(accessor, 'primaryFailure', {get() {reads++; throw new Error('PrivateGetter');}});
  const self = failure(); self.primaryFailure = self;
  const proxy = new Proxy(failure(), {getPrototypeOf() {reads++; throw new Error('PrivateProxy');}});
  for (const primary of [accessor, self, Object.assign(failure(), {primaryFailure: proxy}),
    Object.assign(failure(), {primaryFailure: Object.assign({}, {primaryFailure: failure()})})]) {
    assert.equal((await observe(primary)).primaryDiagnostic, undefined);
  }
  assert.equal(reads, 0);
});

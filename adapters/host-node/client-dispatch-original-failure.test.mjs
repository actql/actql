import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {CapturedRunPublicationError, CapturedRunExecutionError} from './entry.mjs';
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


test('original failure site reaches the ordinary start catch with the same execution owner', async () => {
  const primary = failure(), managed = await managedFailure(primary);
  const records = [], stopped = [];
  const prepared = {}, request = {}, setup = {};
  const ref = {runDefinitionCid: 'ordinary-start-original-failure'};
  const definition = {wire: 'same-original-definition'};
  const row = {cancellationRequested: false, revision: 1, runDefinition: definition};
  let closes = 0, cleanups = 0, starts = 0, finished = 0;
  const execution = {failure: managed, async close() {closes++;},
    cleanup() {cleanups++; return true;}, cleanupPending: () => false};
  const publication = new CapturedRunExecutionError(execution);
  const owner = installNodeClientDispatchOwner({
    moon: {clientProgramRequiresAcquisitionResultPublication: value => {
      assert.equal(value, prepared); return false;
    }, clientProgramOpenSourceFreeLocalHost: value => {
      assert.equal(value, prepared); return setup;
    }},
    observed(name, detail) {if (name === 'dispatch_failed') records.push(detail);},
    control: {runDefinitionRunId: () => 'original-run', runCancellationConfirmed: () => false},
    journal: {reservePhysicalStart: value => {assert.equal(value, request); return true;},
      lookupRunDefinition: value => {assert.equal(value, ref); return row;},
      lookupReconciliationState: () => undefined,
      markPhysicalClose(value, outcome, original) {
        assert.equal(value, ref); assert.equal(original, row); stopped.push(outcome);
      }},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async ({identity}) => {
      assert.equal(identity, request); starts++; return {kind: 'reserved', ref};
    },
    hostConnection: () => true, planFor: () => ({kind: 'pure'}),
    // Explicit physical execution port, not another compiler or Run issuer.
    async runPublished(originalSetup, _publication, _options, _signal, _observer, retain) {
      assert.equal(originalSetup, setup); retain(execution); throw publication;
    },
  });
  assert.equal(await owner.start({preparedProgram: prepared, principalId: 'owner',
    connection: {}, requestId: 'original-request'}, request, {ref, runDefinition: definition,
    dispatchReserved: false, cancellationRequested: false}, {}, () => {finished++;}), 'started');
  await owner.drain();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(starts, 1); assert.equal(finished, 1);
  assert.equal(closes, 1); assert.equal(cleanups, 1);
  assert.deepEqual(stopped, ['failed']);
  assert.equal(owner.operation(ref), undefined);
  assert.equal(records.length, 1);
  assert.equal(records[0].code, 'CapturedRunExecutionFailed');
  assert.equal(records[0].primaryCode, primary.code);
  assert.equal(publication.execution, execution);
  assert.equal(publication.primaryFailure, managed);
  assert.equal(managed.primaryFailure, primary);
  assert.match(records[0].primaryDiagnostic.message,
    /^adapters\/host-node\/client-dispatch-original-failure\.test\.mjs:\d+:\d+/u);
  assert.equal(records[0].primaryDiagnostic.message.includes('managed-failure.mjs'), false);
});

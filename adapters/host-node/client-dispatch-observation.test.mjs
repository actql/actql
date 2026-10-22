import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {createHostObservationConnection, installHostObservation} from '../host-common/observation.mjs';

// Execute the original declarations with explicit ports. No runtime, Model
// permission, Store commit or physical capacity is issued by these fixtures.
const source = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = ast.body.flatMap(node => {
  const value = node.type === 'ExportNamedDeclaration' ? node.declaration : node;
  return value?.type === 'FunctionDeclaration' ? [source.slice(value.start, value.end)] : [];
});
const installNodeClientDispatchOwner = compileFunction(
  declarations.join('\n') + '\nreturn installNodeClientDispatchOwner;',
  ['diagnosticObserver', 'CapturedRunPublicationError', 'runtimeTag', 'runPublishedCapturedStrategy'])(
  diagnosticObserver, class ExplicitPublicationError extends Error {}, () => undefined,
  () => assert.fail('No fixture Relation execution'));
const observation = retained => ({emit() {}, retainOperation(promise) {retained.push(promise);}});

test('dispatch observation retains the original operation beyond its start barrier', async () => {
  let finish, committed = false;
  const pending = new Promise(resolve => {finish = resolve;});
  const retained = [], stopped = [], ref = {runDefinitionCid: 'observed-dispatch'};
  const definition = {wire: 'explicit-definition'};
  const row = {cancellationRequested: false, revision: 1, runDefinition: definition};
  const owner = installNodeClientDispatchOwner({observation: observation(retained),
    moon: {}, control: {runDefinitionRunId: () => 'explicit-run', runCancellationConfirmed: () => false},
    journal: {reservePhysicalStart: () => true,
      lookupRunDefinition: () => row,
      lookupReconciliationState: () => undefined,
      markPhysicalClose: (...args) => stopped.push(args)},
    store: {confirmCommittedIndex: async () => committed ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref}), hostConnection: () => true,
    planFor: () => ({kind: 'infer', runDefinition: definition}),
    runInfer: async ({retainExecution}) => {
      retainExecution({async close() {}, cleanup: () => true, cleanupPending: () => false});
      await pending; committed = true;
    }});
  const started = owner.start({preparedProgram: {}, principalId: 'owner', connection: {},
    requestId: 'explicit-request'}, {}, {ref, runDefinition: definition,
    dispatchReserved: false, cancellationRequested: false}, {});
  const original = owner.operation(ref);
  try {
    assert.equal(await started, 'started');
    assert.deepEqual(retained, [original]);
    assert.equal(owner.live(ref), true);
    assert.deepEqual(stopped, []);
  } finally {finish(); await owner.drain();}
  assert.deepEqual(stopped, [[ref, null, row]]);
});

test('tracked observation settlement cannot retire unresolved physical cleanup', async () => {
  const retained = [], ref = {runDefinitionCid: 'observed-pending-cleanup'};
  let ready = false, runs = 0;
  const owner = installNodeClientDispatchOwner({observation: observation(retained)});
  const run = ({beginPhysicalWork, retainExecution}) => {
    runs++; beginPhysicalWork();
    retainExecution({async close() {}, cleanup: () => ready, cleanupPending: () => !ready});
  };
  const original = owner.track(ref, {run, observeStopped() {}});
  await assert.rejects(original, {message: 'ClientDispatchCleanupPending'});
  try {
    assert.deepEqual(retained, [original]);
    assert.equal(owner.operation(ref), original);
    assert.equal(owner.track(ref, {run, observeStopped() {}}), original);
    assert.deepEqual(retained, [original]);
    await assert.rejects(owner.drain(), {code: 'ClientDispatchCleanupPending'});
  } finally {ready = true; await owner.drain();}
  assert.equal(owner.operation(ref), undefined);
  assert.equal(runs, 1);
});

test('optional dispatch observation cannot change execution or create another invocation', async () => {
  for (const selected of [undefined, {emit() {}, retainOperation() {throw new Error('OptionalObserverFailed');}}]) {
    let runs = 0;
    const result = {}, ref = {runDefinitionCid: 'explicit-optional-observation'};
    const owner = installNodeClientDispatchOwner({observation: selected});
    assert.equal(await owner.track(ref, {run() {runs++; return result;},
      observeStopped() {assert.fail('No physical operation to acknowledge');}}), result);
    assert.equal(runs, 1);
    assert.equal(owner.operation(ref), undefined);
    await owner.drain();
  }
});

test('installed observation follows the actual tracked work after ingress returns', async () => {
  const records = [], ref = {namespaceId: 'explicit-namespace', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
    runDefinitionCid: `sha256:${'b'.repeat(64)}`};
  const trace = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
  const projection = installHostObservation(createHostObservationConnection({
    deliver: record => records.push(record), include: ['run'],
    measurements: {include: ['rows']}, events: {level: 'diagnostic'},
  }), {journal: {observationStorage: () => ({consume: () => ({accepted: true})})}});
  let release, flight;
  const gate = new Promise(resolve => {release = resolve;});
  const owner = installNodeClientDispatchOwner({observation: projection});
  const accepted = {};
  try {
    assert.equal(await projection.run('submit', trace, () => {
      flight = owner.track(ref, {run: async () => {
        await gate;
        projection.diagnostic('selected_rows_observed', {ref, rowOwner: 'request-journal',
          selection: 'run-definition', rowKind: 'run', returnedRows: 1, unrelatedRows: 0,
          coverage: 'selected-returned'});
      }, observeStopped() {assert.fail('No physical operation in this port fixture');}});
      return accepted;
    }), accepted);
    assert.equal(projection.status().activeSegments, 1);
    release(); await flight;
    assert.equal(projection.status().activeSegments, 0);
    await projection.close();
    const rows = records.filter(record => record.event === 'selected_rows_observed');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].attributes['actql.rows.returned'], 1);
    assert.deepEqual(rows[0].parent, trace);
    assert.deepEqual(projection.status().loss, {});
  } finally {release(); if (flight) await flight; await owner.drain(); await projection.close();}
});

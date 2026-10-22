import assert from 'node:assert/strict';
import test from 'node:test';
import {createInstalledRowSource} from './installed-row-source.mjs';
import {AcquisitionOpenError} from '../host-common/acquisition-outcome.mjs';

// Explicit Core/physical ports exercise the actual installed adapter. They do
// not supply a nominal Common admission or qualify an installed filesystem Run.
const ok = value => ({$tag: 1, _0: value});
async function fixture({failCurrent = false, failReader = false, transport} = {}) {
  const preparedProgram = {}, keyedAcquisition = {}, request = {}, declaration = {}, ledger = {};
  const original = {}, acquisition = {}, run = {}, capture = {}, calls = [];
  const expectedTransfer = Object.getOwnPropertyDescriptor(transport ?? {}, 'transferBytes')?.value ?? 2048n;
  const expectedExecution = Object.getOwnPropertyDescriptor(transport ?? {}, 'executionBytes')?.value ?? 1024n;
  const currentFailure = new Error('original-current'), readerFailure = new Error('original-reader');
  let pendingTicket, cleanupConfirmed, physicalAcknowledged = !failReader, finished = false;
  const physicalRecovery = Object.freeze({close() {calls.push('physical-stop');},
    cleanup() {calls.push('physical-cleanup'); return physicalAcknowledged;},
    cleanupPending: () => !physicalAcknowledged});
  const facts = ['local:contents', 'source', 'schema', 'policy', 'classification', 'view'];
  const moon = {
    clientProgramMatchesRequestIdentity: () => true,
    clientProgramKeyedAcquisitionMatchesProgram: () => true,
    clientProgramKeyedRowPrepareCapacity: () => ok({}),
    clientProgramKeyedAcquisitionSourceEvidenceFacts: () => ok(facts),
    clientProgramKeyedAcquisitionInputCoordinates: () => ok([0, 0, 0, 1]),
    clientProgramKeyedAcquisitionCoordinates: () => [0, 0, 1],
    clientProgramKeyedRowCapacityTarget: () => ok(['contents', 'content']),
    clientRequestProgramCid: () => 'sha256:' + 'a'.repeat(64),
    clientRequestParametersCid: () => 'sha256:' + 'b'.repeat(64),
    clientProgramInstalledKeyedSourceReadCheckCurrent(value) {
      assert.strictEqual(value, original); calls.push('current');
      return failCurrent ? {$tag: 0, _0: currentFailure} : ok(undefined);
    },
    clientProgramInstalledKeyedSourceReadAcquisition(value) {assert.strictEqual(value, original); return ok(acquisition);},
    clientProgramInstalledKeyedSourceReadCheckLedger(value, actual) {
      assert.strictEqual(value, original); assert.strictEqual(actual, ledger); return ok(undefined);
    },
    clientProgramInstalledKeyedSourceReadStartRows(value, selected, nonce, stopped, transfer, execution, confirmed) {
      assert.strictEqual(value, original); assert.strictEqual(selected, acquisition);
      assert.equal(transfer, expectedTransfer);
      assert.equal(execution, expectedExecution);
      cleanupConfirmed = confirmed; calls.push('start'); return ok(run);
    },
    clientProgramInstalledKeyedSourceReadRetire(value) {assert.strictEqual(value, original); calls.push('retire'); return ok(undefined);},
    clientProgramKeyedRowTarget: () => ok(['contents', 'content']),
    clientProgramKeyedRequestWire: () => ok('{}'),
    clientProgramKeyedRowBegin: () => ok(undefined),
    clientProgramKeyedRequestObserveAttempt: () => ok(undefined),
    clientProgramKeyedRequestRemainingMs: () => ok(10000n),
    clientProgramRowSourceChargePage(value, bytes) {
      assert.strictEqual(value, run); assert.ok(bytes instanceof Uint8Array);
      assert.equal(pendingTicket, undefined, 'consume the prior actual byte ticket before another charge');
      pendingTicket = {}; calls.push('charge'); return ok(pendingTicket);
    },
    clientProgramRowSourceConsumeObservationCharge(value, ticket) {
      assert.strictEqual(value, run); assert.strictEqual(ticket, pendingTicket);
      pendingTicket = undefined; calls.push('consume-original-bytes'); return ok(undefined);
    },
    clientProgramKeyedResponseObserve: () => ok(undefined),
    clientProgramKeyedRowBeginChargedPage(value, ticket) {
      assert.strictEqual(value, run); assert.strictEqual(ticket, pendingTicket);
      pendingTicket = undefined; return ok(undefined);
    },
    clientProgramKeyedRowAdvancePage: () => ok([1, 1]),
    clientProgramRowSourceFinish() {finished = true; return ok(undefined);},
    clientProgramRowSourceAttempt: () => 'attempt',
    clientProgramKeyedRowRetain: () => ok(capture),
    clientProgramKeyedRequestFinishIO: () => ok(undefined),
    clientProgramKeyedRequestFailIO() {calls.push('fail-io');},
    clientProgramRowSourceCloseAccounted() {
      if (!cleanupConfirmed()) return {$tag: 0, _0: new Error('physical-pending')};
      calls.push('row-close'); return ok(undefined);
    },
    clientProgramRowSourceCaptureCleanup: () => ok(true),
    clientProgramRowSourceCaptureCleanupAdvance: () => ok(true),
  };
  const adapter = await createInstalledRowSource({moon, declaration,
    declared: {views: [{source_ref: facts[0], resource: 'contents'}]},
    environmentWire: '{}', connectorId: 'local', connectorRegistration: 'local', connectorRevision: 'local/0.1',
    bindingCid: 'sha256:' + 'c'.repeat(64), readOperation: 'read',
    site: {connection: 'local', issueReadGrant() {calls.push('grant'); return {};}, close() {}},
    authorization: {authorize: async () => ({action: 'dispatch'}), context: {contextCid: 'context'}},
    physicalTarget: () => ({root: 'original'}),
    limits: {maxPages: 2, maxPageBytes: 1024, maxPageRows: 4, maxCaptureRows: 4},
    originalKeyedTransport: transport,
    prepareKeyedSourceRead(args) {
      assert.strictEqual(args.checkedOwner, preparedProgram); assert.strictEqual(args.keyedAcquisition, keyedAcquisition);
      assert.strictEqual(args.request, request); assert.strictEqual(args.declaration, declaration);
      calls.push('prepare-original'); return original;
    },
    async closeKeyedSourceRead(value) {
      assert.strictEqual(value, original); calls.push('close-original');
      return {pending: !physicalAcknowledged};
    },
    async readPages(options) {
      assert.strictEqual(options.rowRun.originalKeyedRead, original);
      assert.strictEqual(options.rowRun.run, run);
      await options.beginRequest(new Uint8Array([1]));
      if (failReader) throw new AcquisitionOpenError(readerFailure, 'unknown', physicalRecovery);
      const rawCharge = options.chargePage(new Uint8Array([2, 3]));
      options.consumeObservation(rawCharge);
      await options.consumePage([{content: 'original'}]);
    }});
  const selected = await adapter.prepareKeyed({preparedProgram, keyedAcquisition, requestIdentity: {}});
  return {calls, currentFailure, readerFailure, get finished() {return finished;},
    acknowledgePhysical() {physicalAcknowledged = true;},
    capacity: () => adapter.keyedLedgerCapacity(keyedAcquisition),
    open: () => adapter.openKeyed({preparedProgram, keyedAcquisition, request, ledger, preparedKeyed: selected.prepared})};
}

test('installed keyed native transport keeps its full captured workspace beside page limits', async () => {
  const transport = {transferBytes: 65536n, executionBytes: 131072n};
  const f = await fixture({transport});
  assert.equal(f.capacity().transferBytes, 65536n);
  assert.equal(f.capacity().executionBytes, 131072n);
  transport.transferBytes = 1n; transport.executionBytes = 1n;
  const acquired = await f.open(); await acquired.close();
  assert.equal(f.capacity().executionBytes, 131072n);
});

test('installed keyed transport rejects accessor or out-of-range limits before acquisition', async () => {
  let getters = 0;
  await assert.rejects(fixture({transport: {get transferBytes() {getters++; return 1n;}, executionBytes: 1n}}),
    {code: 'InvalidInstalledKeyedTransportLimits'});
  await assert.rejects(fixture({transport: {transferBytes: 1n, executionBytes: 9223372036854775808n}}),
    {code: 'InvalidInstalledKeyedTransportLimits'});
  assert.equal(getters, 0);
});

test('installed keyed original drives its same RowRun and consumes native bytes before encoded rows', async () => {
  const f = await fixture(), acquired = await f.open();
  assert.equal(f.finished, true);
  assert.ok(f.calls.indexOf('consume-original-bytes') < f.calls.lastIndexOf('charge'));
  await acquired.close(); await acquired.close();
  assert.equal(f.calls.filter(name => name === 'prepare-original').length, 1);
  assert.equal(f.calls.filter(name => name === 'close-original').length, 1);
});

test('installed keyed current refusal closes its original before any grant or physical start', async () => {
  const f = await fixture({failCurrent: true});
  await assert.rejects(f.open(), error => error.cause?.cause === f.currentFailure && error.outcome === 'not_started');
  assert.equal(f.calls.includes('grant'), false);
  assert.equal(f.calls.includes('start'), false);
  assert.equal(f.calls.filter(name => name === 'close-original').length, 1);
});

test('installed keyed failure retains the same physical recovery before Core and parent retirement', async () => {
  const f = await fixture({failReader: true});
  let originalFailure;
  try {await f.open();} catch (error) {originalFailure = error;}
  assert.strictEqual(originalFailure.cause.cause, f.readerFailure);
  assert.equal(originalFailure.outcome, 'unknown');
  assert.equal(originalFailure.recovery.cleanupPending(), true);
  assert.equal(f.calls.includes('close-original'), false);
  assert.equal(await originalFailure.recovery.cleanup(), false);
  f.acknowledgePhysical();
  assert.equal(await originalFailure.recovery.cleanup(), true);
  assert.equal(originalFailure.recovery.cleanupPending(), false);
  assert.equal(f.calls.filter(name => name === 'prepare-original').length, 1);
  assert.ok(f.calls.indexOf('physical-cleanup') < f.calls.indexOf('retire'));
  assert.ok(f.calls.indexOf('retire') < f.calls.indexOf('close-original'));
});

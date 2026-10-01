import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeQuery } from '../native-query.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {acquisitionOutcome} from '../../../../host-common/acquisition-outcome.mjs';
import {installNodeClientDispatchOwner} from '../../../../host-node/client-dispatch-owner.mjs';
import {createInstalledHostShutdown} from '../../../../host-node/installed-host-cleanup.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 100, maxTransportBytes: 10000,
  maxSqlBytes: 1000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };

// A trusted bridge lifecycle double, not an ActQL verifier or an evidence
// constructor. Real MoonBit admission/issuer conformance is tested separately.
function factory(events, mode, cancellation) {
  return verify => {
    const attempt = Object.freeze({});
    const observation = Object.freeze({});
    let readView;
    const owns = view => {
      if (readView === undefined) readView = view;
      assert.equal(view, readView);
      assert.equal(verify(attempt), false);
    };
    return {
      attempt,
      port: {
        metadataSql: () => 'SELECT table_type FROM information_schema.tables WHERE table_schema = ? AND table_name = ?',
        metadataParameters: () => ['main', 'records'].map(value => ({ type: { id: 'VARCHAR' }, value })),
        acceptMetadata(chunk, view) { owns(view); assert.deepEqual(chunk.columns, [['BASE TABLE']]); },
        finishMetadata(_fields, view) { owns(view); },
        validationSql: () => 'SELECT amount, id FROM main.records',
        nativeSql: () => 'SELECT id FROM main.records WHERE id > 1',
        nativeParameters: () => [],
        beginReceipt(role, fields, view) {
          owns(view); events.push(`${role}-begin`);
          assert.deepEqual(fields.map(field => field.name), role === 'validation_scan' ? ['amount', 'id'] : ['id']);
        },
        acceptChunk(role, chunk, view) {
          owns(view);
          assert.equal(chunk.rowCount, role === 'validation_scan' ? 3 : 2);
        },
        finishReceipt(role, view) {
          owns(view); events.push(`${role}-finished`);
          if (mode === `cancel-${role}`) cancellation.abort();
          return mode === `foreign-${role}` ? Object.freeze({ ...attempt }) : attempt;
        },
        abort() { events.push('port-abort'); },
      },
      complete() {
        assert.equal(verify(attempt), true);
        assert.equal(verify({ ...attempt }), false);
        events.push('complete');
        if (mode === 'completion-failure' || mode === 'completion-close-failure') throw new Error('capture rejected');
        if (mode === 'async-completion') return Promise.resolve(observation);
        return observation;
      },
      bindInput(value, fail) {
        assert.equal(value, observation);
        assert.equal(verify(attempt), true);
        if (fail) throw new Error('consumer rejected');
        return observation;
      },
      abort() { events.push('attempt-abort'); },
      close() {
        events.push('close');
        assert.equal(verify(attempt), false);
        if (mode === 'completion-close-failure' &&
            events.filter(event => event === 'close').length === 1) {
          throw new Error('issuer close failed');
        }
      },
    };
  };
}

test('native coordinator requires both exact settled receipts and revokes failed or released ownership', async t => {
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'native-query-'));
  try {
    const path = join(directory, 'source.duckdb');
    const database = await DuckDBInstance.create(path);
    const connection = await database.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE); INSERT INTO records VALUES (3, 30), (1, NULL), (2, 20)');
    } finally { connection.closeSync(); database.closeSync(); }
    const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
    const events = [];
    let transferred = 0;
    const captured = await runNativeQuery(grant, factory(events, 'success'), limits, undefined, {
      started() { assert.deepEqual(events, []); },
      chargeTransfer(bytes) { transferred += bytes; assert(!events.includes('complete')); },
      settled(confirmed) {
        assert.equal(confirmed, true);
        assert(events.includes('native_result-finished'));
        assert(!events.includes('complete'));
      },
    });
    assert(transferred > 0);
    assert.deepEqual(events, ['validation_scan-begin', 'validation_scan-finished',
      'native_result-begin', 'native_result-finished', 'complete']);
    assert.throws(() => captured.bindInput(true), /consumer rejected/);
    assert.equal(captured.bindInput(false), captured.observation);
    captured.close(); captured.close();
    assert.throws(() => captured.bindInput(false), { code: 'IssuerClosed' });
    assert.equal(events.filter(event => event === 'close').length, 1);
    for (const mode of ['foreign-validation_scan', 'foreign-native_result',
      'cancel-validation_scan', 'cancel-native_result', 'completion-failure', 'async-completion']) {
      const failed = [];
      const controller = new AbortController();
      await assert.rejects(runNativeQuery(grant, factory(failed, mode, controller), limits, controller.signal), error => {
        assert.equal(acquisitionOutcome(error).outcome, 'stopped',
          'a physically settled session must transfer its confirmed end');
        if (mode.startsWith('foreign-')) return error.code === 'ForeignAcceptedAttempt';
        if (mode === 'async-completion') return error.code === 'InvalidCaptureCompletion';
        if (mode === 'completion-failure') return /capture rejected/.test(error.message);
        return error.code === 'Cancelled' || error.name === 'AbortError';
      });
      assert.deepEqual(failed.slice(-2), ['attempt-abort', 'close']);
      if (mode.startsWith('foreign-') || mode.startsWith('cancel-')) assert(!failed.includes('complete'));
      if (mode === 'cancel-validation_scan') assert(!failed.includes('native_result-begin'));
    }
    const failed = [];
    let failure;
    await assert.rejects(runNativeQuery(grant,
      factory(failed, 'completion-close-failure'), limits), error => {
      failure = error;
      return true;
    });
    const ended = acquisitionOutcome(failure);
    assert.equal(ended.outcome, 'unknown');
    assert.equal(ended.recovery.cleanupPending(), true);
    assert.match(failure.cause.primaryFailure.message, /capture rejected/);
    await ended.recovery.close();
    assert.equal(await ended.recovery.cleanup(), true);
    assert.equal(ended.recovery.cleanupPending(), false);
    assert.equal(failed.filter(event => event === 'close').length, 2);
    await ended.recovery.cleanup();
    assert.equal(failed.filter(event => event === 'close').length, 2);
    assert.equal(failed.filter(event => event === 'complete').length, 1);
    assert.equal(failed.filter(event => event === 'validation_scan-begin').length, 1);

    const dispatching = open => {
      const ref = {runDefinitionCid: 'physical-source-cleanup'};
      const stopped = [];
      let computes = 0;
      const access = {};
      const owner = installNodeClientDispatchOwner({
        moon: {clientProgramPrepareQueryAcquisition: () => ({$tag: 1})},
        control: {},
        journal: {reservePhysicalStart: () => true,
          markPhysicalClose: (...args) => stopped.push(args)},
        store: {confirmCommittedIndex: async () => undefined},
        startRun: async () => ({kind: 'reserved', ref}),
        hostConnection: () => true, observed: () => {},
        planFor: () => ({runDefinition: {wire: 'definition'}}),
        sourceProfile: {sourceAccess: access, async open(options) {
          try { return await open(options); }
          catch (error) { options.reportAcquisitionFailure(error); throw error; }
        }},
        runPublished: async () => { computes++; assert.fail('Compute must not start'); },
        now: () => '2026-10-01T00:00:00.000Z', namespaceId: 'namespace-a',
      });
      return {owner, ref, stopped, computes: () => computes,
        async start() {
          await owner.start({preparedProgram: {}, principalId: 'owner',
            connection: {}, requestId: 'source-cleanup'}, {},
          {ref, runDefinition: {wire: 'definition'}, dispatchReserved: false},
          {preparedSourceAccess: access, preparedSource: {}});
          return owner.operation(ref);
        }};
    };
    let opens = 0;
    const over = dispatching(({signal}) => {
      opens++;
      return runNativeQuery(grant, factory([], 'success'), {...limits, maxRows: 1}, signal);
    });
    await over.start();
    await over.owner.drain();
    assert.deepEqual(over.stopped, [[over.ref, 'failed']]);
    assert.equal(opens, 1);
    assert.equal(over.computes(), 0);

    const originalClose = DuckDBInstance.prototype.closeSync;
    let allowClose = false, acquired = 0;
    const closeMock = t.mock.method(DuckDBInstance.prototype, 'closeSync', function () {
      if (!allowClose) throw new Error('PhysicalCloseInjected');
      return originalClose.call(this);
    });
    const pending = dispatching(({signal}) => {
      acquired++;
      return runNativeQuery(grant, factory([], 'success'), {...limits, maxRows: 1}, signal);
    });
    const shutdownEvents = [];
    const shutdown = createInstalledHostShutdown({
      stop: () => { shutdownEvents.push('stop'); pending.owner.cancel(pending.ref); },
      drain: () => pending.owner.drain(),
      ...Object.fromEntries(['retire', 'checkpoint', 'journal', 'source', 'effect', 'store']
        .map(name => [name, () => { shutdownEvents.push(name); }])),
    });
    try {
      await pending.start();
      assert.deepEqual(pending.stopped, []);
      let closeFailure;
      await assert.rejects(shutdown.close(), error => {
        closeFailure = error;
        return error.code === 'ClientDispatchCleanupPending';
      });
      assert.deepEqual(shutdownEvents, ['stop']);
      assert.equal(closeFailure.cleanupPending, true);
      allowClose = true;
      await closeFailure.cleanupHandle.retry();
      assert.deepEqual(pending.stopped, [[pending.ref, 'cancelled']]);
      assert.deepEqual(shutdown.status().pending, []);
      await shutdown.close();
      assert.deepEqual(shutdownEvents,
        ['stop', 'retire', 'checkpoint', 'journal', 'source', 'effect', 'store']);
      assert.equal(acquired, 1);
      assert.equal(pending.computes(), 0);
    } finally { allowClose = true; await pending.owner.drain(); closeMock.mock.restore(); }

    let enter, release, reportFailure;
    const entered = new Promise(resolve => { enter = resolve; });
    const gate = new Promise(resolve => { release = resolve; });
    const failedAfterDeadline = new Promise(resolve => { reportFailure = resolve; });
    let delayedOpens = 0;
    const delayed = dispatching(async ({signal, reportAcquisitionFailure}) => {
      delayedOpens++;
      const prepare = verify => {
        const bridge = factory([], 'success')(verify);
        const finishMetadata = bridge.port.finishMetadata;
        bridge.port.finishMetadata = async (...args) => {
          finishMetadata(...args); enter(); await gate;
        };
        return bridge;
      };
      try { return await runNativeQuery(grant, prepare, {...limits, cancelWaitMs: 0}, signal); }
      catch (error) {
        reportAcquisitionFailure(error);
        reportFailure(error);
        throw error;
      }
    });
    const finishing = delayed.start();
    await entered;
    delayed.owner.cancel(delayed.ref);
    const deadlineFailure = await failedAfterDeadline;
    assert.equal(acquisitionOutcome(deadlineFailure).outcome, 'unknown');
    assert.equal(acquisitionOutcome(deadlineFailure).recovery.cleanupPending(), true);
    assert.deepEqual(delayed.stopped, []);
    release();
    await finishing;
    await delayed.owner.drain();
    assert.deepEqual(delayed.stopped, [[delayed.ref, 'cancelled']]);
    assert.equal(delayedOpens, 1);
    assert.equal(delayed.computes(), 0);

    let permitCaptureClose = false, successfulReads = 0, physicalCloses = 0;
    const postCapture = dispatching(async ({signal}) => {
      successfulReads++;
      const capture = await runNativeQuery(grant, factory([], 'success'), limits, signal);
      return {setup: {}, checkedSource: {},
        issueSourceEvidence: () => { throw new Error('PostAcquisitionEvidenceFailed'); },
        async close() {
          if (!permitCaptureClose) throw new Error('CaptureCloseInjected');
          capture.close(); physicalCloses++;
        },
      };
    });
    await postCapture.start();
    await assert.rejects(postCapture.owner.drain(), error => {
      assert.equal(error.failures[0].primary.message, 'PostAcquisitionEvidenceFailed');
      assert.equal(error.failures[0].cleanup.message, 'CaptureCloseInjected');
      return error.code === 'ClientDispatchCleanupPending';
    });
    assert.deepEqual(postCapture.stopped, []);
    permitCaptureClose = true;
    await postCapture.owner.drain();
    assert.deepEqual(postCapture.stopped, [[postCapture.ref, 'failed']]);
    await postCapture.owner.drain();
    assert.equal(successfulReads, 1);
    assert.equal(physicalCloses, 1);
    assert.equal(postCapture.computes(), 0);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

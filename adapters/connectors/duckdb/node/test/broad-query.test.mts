import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate as yieldToHost} from 'node:timers/promises';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runBroadQuery } from '../broad-query.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';
import {acquisitionOutcome} from '../../../../host-common/acquisition-outcome.mjs';

import type {BroadAcquisitionPort} from '../broad-acquisition.mjs';
import type {PrepareQuery} from '../settled-query.mjs';
import type {SourceRecovery} from '../source-acquisition.mjs';

type FixtureBridge = PrepareQuery<BroadAcquisitionPort, object, object, [fail: boolean], object>;
type FixtureFailure = Readonly<{code?: string; message: string}>;

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = { maxRows: 100, maxCells: 100, maxTransportBytes: 10000,
  maxSqlBytes: 1000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 };

// Only a lifecycle double for the trusted MoonBit bridge. This test does not
// manufacture or claim real ActQL records. Portable issuer tests cover them.
function bridgeFactory(log: string[], mode = 'success', cancellation?: AbortController): FixtureBridge {
  return verify => {
    const attempt = Object.freeze({});
    const observation = Object.freeze({});
    let view: object | undefined;
    let captured = false;
    const owns = (actual: object) => {
      if (view === undefined) view = actual;
      assert.equal(actual, view);
      assert.equal(verify(attempt), false);
    };
    const bridge: ReturnType<FixtureBridge> = {
      attempt,
      port: {
        metadataSql: () => 'SELECT table_type FROM information_schema.tables WHERE table_schema = ? AND table_name = ?',
        metadataParameters: () => ['main', 'records'].map(value => ({ type: { id: 'VARCHAR' }, value })),
        acceptMetadata(chunk, actual) { owns(actual); assert.deepEqual(chunk.columns, [['BASE TABLE']]); },
        finishMetadata(_fields, actual) { owns(actual); },
        scanSql: () => 'SELECT id FROM main.records',
        beginReceipt(_fields, actual) { owns(actual); log.push('begin'); },
        acceptChunk(chunk, actual) { owns(actual); assert.equal(chunk.rowCount, 1); log.push('chunk'); },
        finishReceipt(actual) {
          owns(actual); log.push('receipt');
          cancellation?.abort();
          return mode === 'foreign' ? Object.freeze({}) : attempt;
        },
        abort() { log.push('port-abort'); },
      },
      complete() {
        assert.equal(verify(attempt), true);
        assert.equal(verify(Object.freeze({})), false);
        log.push('complete');
        if (mode === 'guard-failure') throw new Error('MoonBit guard rejected');
        captured = true;
        return observation;
      },
      bindInput(value, fail) {
        assert.equal(value, observation);
        assert.equal(captured, true);
        assert.equal(verify(attempt), true);
        if (fail) throw new Error('consumer rejected');
        log.push('bind');
        return observation;
      },
      abort() { log.push('attempt-abort'); },
      close() { log.push('close'); assert.equal(verify(attempt), false); },
    };
    return bridge;
  };
}

test('real broad transport gates synchronous capture and keeps failed consumers independent', async () => {
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'broad-query-'));
  try {
    const path = join(directory, 'source.duckdb');
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try { await connection.run('CREATE TABLE records(id DOUBLE); INSERT INTO records VALUES (3)'); }
    finally { connection.closeSync(); db.closeSync(); }
    const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
    const events: string[] = [];
    let transferred = 0;
    const captured = await runBroadQuery(grant, bridgeFactory(events), limits, undefined, {
      started() { assert.deepEqual(events, []); },
      chargeTransfer(bytes) { transferred += bytes; assert(!events.includes('complete')); },
      settled(confirmed) {
        assert.equal(confirmed, true);
        assert(events.includes('receipt'));
        assert(!events.includes('complete'));
      },
    });
    assert(transferred > 0);
    assert.deepEqual(events, ['begin', 'chunk', 'receipt', 'complete']);
    assert.throws(() => captured.bindInput(true), /consumer rejected/);
    assert.equal(captured.bindInput(false), captured.observation);
    assert.equal(captured.bindInput(false), captured.observation);
    assert.equal(events.filter(event => event === 'begin').length, 1);
    captured.close(); captured.close();
    assert.throws(() => captured.bindInput(false), error => (error as FixtureFailure).code === 'IssuerClosed');
    assert.equal(events.filter(event => event === 'close').length, 1);
    const bounded: string[] = [];
    const boundedCapture = await runBroadQuery(grant, verify => {
      const bridge = bridgeFactory(bounded)(verify);
      return {...bridge, async completeBounded() {
        bounded.push('yield');
        await yieldToHost();
        assert.equal(verify(bridge.attempt), true);
        return bridge.complete();
      }};
    }, limits);
    assert.deepEqual(bounded, ['begin', 'chunk', 'receipt', 'yield', 'complete']);
    boundedCapture.close();

    const held: string[] = [];
    let stopped = false;
    let failure: unknown;
    await assert.rejects(runBroadQuery(grant, verify => {
      const bridge = bridgeFactory(held)(verify);
      return {...bridge, stopped: () => stopped, async completeBounded() {
        await yieldToHost();
        throw new Error('residual stop pending');
      }};
    }, limits), error => { failure = error; return true; });
    const recovery = acquisitionOutcome(failure) as Readonly<{outcome: unknown; recovery: SourceRecovery}>;
    assert.equal(recovery.outcome, 'unknown');
    assert.equal(recovery.recovery.cleanupPending(), true);
    assert.equal(held.includes('close'), false);
    assert.equal(held.includes('complete'), false);
    stopped = true;
    assert.equal(await recovery.recovery.cleanup(), true);
    assert.equal(recovery.recovery.cleanupPending(), false);
    assert.equal(held.filter(event => event === 'close').length, 1);
    assert.equal(held.filter(event => event === 'begin').length, 1);
    for (const mode of ['foreign', 'guard-failure']) {
      const failed: string[] = [];
      await assert.rejects(runBroadQuery(grant, bridgeFactory(failed, mode), limits),
        error => mode === 'foreign' ? (error as FixtureFailure).code === 'ForeignAcceptedAttempt' : /guard rejected/.test((error as FixtureFailure).message));
      assert.deepEqual(failed.slice(-2), ['attempt-abort', 'close']);
      assert.equal(failed.includes('bind'), false);
    }
    const cancelled: string[] = [];
    const controller = new AbortController();
    await assert.rejects(runBroadQuery(grant, bridgeFactory(cancelled, 'success', controller), limits, controller.signal));
    assert.equal(cancelled.includes('complete'), false);
    assert.equal(cancelled.at(-1), 'close');
  } finally { await rm(directory, { recursive: true, force: true }); }
});

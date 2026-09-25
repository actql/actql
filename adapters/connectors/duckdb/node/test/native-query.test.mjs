import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeQuery } from '../native-query.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';

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
        if (mode === 'completion-failure') throw new Error('capture rejected');
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
      close() { events.push('close'); assert.equal(verify(attempt), false); },
    };
  };
}

test('native coordinator requires both exact settled receipts and revokes failed or released ownership', async () => {
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
        if (mode.startsWith('foreign-')) return error.code === 'ForeignAcceptedAttempt';
        if (mode === 'async-completion') return error.code === 'InvalidCaptureCompletion';
        if (mode === 'completion-failure') return /capture rejected/.test(error.message);
        return error.code === 'Cancelled' || error.name === 'AbortError';
      });
      assert.deepEqual(failed.slice(-2), ['attempt-abort', 'close']);
      if (mode.startsWith('foreign-') || mode.startsWith('cancel-')) assert(!failed.includes('complete'));
      if (mode === 'cancel-validation_scan') assert(!failed.includes('native_result-begin'));
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

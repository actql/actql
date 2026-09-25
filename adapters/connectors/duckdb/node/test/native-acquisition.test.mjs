import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase } from '../session.mjs';
import { runNativeAcquisition } from '../native-acquisition.mjs';
import { runBroadAcquisition } from '../broad-acquisition.mjs';
import { matchesSourceAcquisition, releaseSourceAcquisition } from '../source-acquisition.mjs';
import {fixtureSourceAccess} from '../../../../host-node/authorization-fixture.mjs';

const root = fileURLToPath(new URL('../../../../..', import.meta.url));
const limits = Object.freeze({ maxRows: 100, maxCells: 1000, maxTransportBytes: 100000,
  maxSqlBytes: 10000, maxParameters: 10, maxColumns: 10,
  memoryBytes: 128 * 1024 * 1024, threads: 1 });

// This is a lifecycle test double, not the product MoonBit value verifier or
// an evidence issuer. Actual SQL comes from the MoonBit checked-query compiler.
function receiver(commands, rejectRole, abortController) {
  const events = [];
  const received = {};
  let view;
  const owns = current => { if (view) assert.equal(current, view); else view = current; };
  const port = {
    metadataSql: () => commands.metadata,
    metadataParameters: () => commands.metadataParameters,
    acceptMetadata(chunk, current) {
      owns(current); events.push('metadata');
      assert.deepEqual(chunk.columns, [['BASE TABLE']]);
    },
    finishMetadata(fields, current) {
      owns(current); assert.deepEqual(fields.map(f => f.name), ['table_type']);
      events.push('metadata-finished');
    },
    validationSql: () => commands.validation,
    nativeSql: () => { events.push('native-command'); return commands.native; },
    nativeParameters: () => commands.nativeParameters,
    beginReceipt(role, fields, current) {
      owns(current); events.push(`${role}-begin`); received[role] = [];
      assert.deepEqual(fields.map(f => f.name), role === 'validation_scan' ? ['amount', 'id'] : ['id']);
    },
    acceptChunk(role, chunk, current) {
      owns(current); events.push(`${role}-chunk`);
      if (role === rejectRole) throw new Error('receiver rejection');
      received[role].push(chunk);
    },
    finishReceipt(role, current) {
      owns(current); events.push(`${role}-finished`);
      if (role === 'validation_scan') abortController?.abort();
      return Object.freeze({ role });
    },
    abort(error, current) { owns(current); events.push('abort'); received.error = error; },
  };
  return { port, events, received };
}

test('generated native acquisition awaits validation on the same read view and counts both transfers', async () => {
  const { stdout } = await promisify(execFile)('moon', ['test', '--target', 'js',
    'src/query_integration/duckdb_native_transport_fixture_wbtest.mbt'], { cwd: root, maxBuffer: 2000000 });
  assert.match(stdout, /Total tests: 1, passed: 1, failed: 0/);
  const lines = stdout.split('\n').filter(line => line.startsWith('ACTQL_DUCKDB_NATIVE_FIXTURE '));
  assert.equal(lines.length, 1);
  const commands = JSON.parse(lines[0].slice('ACTQL_DUCKDB_NATIVE_FIXTURE '.length));
  const base = join(root, '_build/duckdb-fixtures');
  await mkdir(base, { recursive: true });
  const directory = await mkdtemp(join(base, 'native-read-'));
  try {
    const path = join(directory, 'source.duckdb');
    const instance = await DuckDBInstance.create(path);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records (id DOUBLE, amount DOUBLE)');
      await connection.run('INSERT INTO records VALUES (3, 30), (1, NULL), (2, 20)');
    } finally { connection.closeSync(); instance.closeSync(); }
    const grant = await authorizeLocalDatabase(path, fixtureSourceAccess);
    const good = receiver(commands);
    const accountingEvents = [];
    let charged = 0;
    const accounting = {
      started() { accountingEvents.push('started'); },
      chargeTransfer(bytes) { charged += bytes; accountingEvents.push('charge'); },
      settled(confirmed) { accountingEvents.push(confirmed); },
    };
    const result = await runNativeAcquisition(grant, good.port, limits, undefined, accounting);
    const phases = result.value.diagnostics;
    assert(Object.isFrozen(phases));
    for (const milliseconds of Object.values(phases)) {
      assert(Number.isFinite(milliseconds) && milliseconds >= 0);
    }
    assert.equal(phases.validationMilliseconds, result.value.validation.milliseconds);
    assert.equal(phases.nativeResultMilliseconds, result.value.native.milliseconds);
    assert(phases.bodyMilliseconds >= phases.metadataMilliseconds
      + phases.validationMilliseconds + phases.nativeResultMilliseconds);
    assert.equal(charged, result.usage.transportBytes);
    assert.equal(accountingEvents[0], 'started');
    assert.equal(accountingEvents.at(-1), true);
    assert(charged > result.value.validation.transport.transportBytes
      + result.value.native.transport.transportBytes); // Metadata is also charged.
    assert.equal(matchesSourceAcquisition(result, grant, good.port, result.value.readView), true);
    assert.equal(matchesSourceAcquisition({ ...result }, grant, good.port, result.value.readView), false);
    assert.equal(matchesSourceAcquisition(result, await authorizeLocalDatabase(path, fixtureSourceAccess), good.port, result.value.readView), false);
    assert.equal(matchesSourceAcquisition(result, grant, { ...good.port }, result.value.readView), false);
    assert.equal(matchesSourceAcquisition(result, grant, good.port, Object.freeze({})), false);
    assert.deepEqual(good.received.validation_scan[0].columns, [
      ['403e000000000000', null, '4034000000000000'],
      ['4008000000000000', '3ff0000000000000', '4000000000000000'],
    ]);
    assert.deepEqual(good.received.native_result[0].columns,
      [['4008000000000000', '4000000000000000']]);
    assert(good.events.indexOf('validation_scan-finished') < good.events.indexOf('native-command'));
    assert.equal(result.value.validation.transport.rows, 3);
    assert.equal(result.value.validation.transport.cells, 6);
    assert.equal(result.value.native.transport.rows, 2);
    assert.equal(result.value.native.transport.cells, 2);
    // Metadata is counted separately in the session, not hidden in a row receipt.
    assert.equal(result.usage.rows, 6);
    assert.equal(result.usage.statements, 3);
    // Broad uses the identical physical accounting boundary, with only one row
    // receipt. This receiver is a transport double, not semantic evidence.
    const broad = receiver(commands);
    const broadPort = {
      ...broad.port,
      scanSql: () => commands.validation,
      beginReceipt: (fields, view) => broad.port.beginReceipt('validation_scan', fields, view),
      acceptChunk: (chunk, view) => broad.port.acceptChunk('validation_scan', chunk, view),
      finishReceipt: view => broad.port.finishReceipt('validation_scan', view),
    };
    const beforeBroad = charged;
    const broadResult = await runBroadAcquisition(grant, broadPort, limits, undefined, accounting);
    assert.equal(charged - beforeBroad, broadResult.usage.transportBytes);
    assert.equal(broadResult.usage.statements, 2);
    assert.equal(accountingEvents.at(-1), true);
    // Rejection by the shared physical ledger occurs before a chunk reaches
    // the receiver. No receipt provenance is published after that failure.
    const denied = receiver(commands);
    const settlements = [];
    await assert.rejects(runNativeAcquisition(grant, denied.port, limits, undefined, {
      started() {},
      chargeTransfer() { throw new Error('physical ledger exhausted'); },
      settled(confirmed) { settlements.push(confirmed); },
    }), /physical ledger exhausted/);
    assert.deepEqual(denied.events, ['abort']);
    assert.deepEqual(settlements, [true]);
    // A caller deadline does not release the original read session's reserved
    // capacity while its receiver callback is still in flight.
    const pending = receiver(commands);
    const pendingAbort = new AbortController();
    let enter;
    let release;
    const entered = new Promise(resolve => { enter = resolve; });
    const held = new Promise(resolve => { release = resolve; });
    const pendingSettlements = [];
    const pendingPort = {
      ...pending.port,
      async acceptMetadata(chunk, view) {
        pending.port.acceptMetadata(chunk, view);
        enter();
        await held;
      },
    };
    const operation = runNativeAcquisition(grant, pendingPort,
      { ...limits, cancelWaitMs: 0 }, pendingAbort.signal, {
        started() {}, chargeTransfer() {},
        settled(confirmed) { pendingSettlements.push(confirmed); },
      });
    await entered;
    pendingAbort.abort();
    let pendingFailure;
    try {
      await assert.rejects(operation, error => {
        pendingFailure = error;
        return error.code === 'Cancelled' && error.cleanupPending === true;
      });
      assert.deepEqual(pendingSettlements, [false]);
      assert.equal(pendingFailure.cleanupHandle.status().pending, true);
      assert(!pending.events.includes('native-command'));
    } finally { release(); }
    assert.equal((await pendingFailure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(pendingSettlements, [false, true]);
    await assert.rejects(runNativeAcquisition(grant, good.port, limits), { code: 'AttemptAlreadyStarted' });
    const bad = receiver(commands, 'validation_scan');
    await assert.rejects(runNativeAcquisition(grant, bad.port, limits), /receiver rejection/);
    assert(!bad.events.includes('native-command'));
    assert.equal(bad.events.at(-1), 'abort');
    const controller = new AbortController();
    const cancelled = receiver(commands, undefined, controller);
    await assert.rejects(runNativeAcquisition(grant, cancelled.port, limits, controller.signal), { code: 'Cancelled' });
    assert(!cancelled.events.includes('native_result-begin'));
    const exhausted = receiver(commands);
    await assert.rejects(runNativeAcquisition(grant, exhausted.port, { ...limits, maxRows: 4 }), { code: 'Rows' });
    assert.equal(exhausted.events.at(-1), 'abort');
    // A new attempt/read view can retry after all prior native resources close.
    const retry = await runNativeAcquisition(grant, receiver(commands).port, limits);
    assert.notEqual(retry.value.readView, result.value.readView);
    assert.equal(matchesSourceAcquisition(result, grant, good.port, retry.value.readView), false);
    // Failed/cancelled sibling attempts do not consume successful provenance.
    assert.equal(matchesSourceAcquisition(result, grant, good.port, result.value.readView), true);
    releaseSourceAcquisition(result);
    assert.equal(matchesSourceAcquisition(result, grant, good.port, result.value.readView), false);
    releaseSourceAcquisition(result);
    const emptyPath = join(directory, 'empty.duckdb');
    const emptyDB = await DuckDBInstance.create(emptyPath);
    const emptyConnection = await emptyDB.connect();
    try { await emptyConnection.run('CREATE TABLE records (id DOUBLE, amount DOUBLE)'); }
    finally { emptyConnection.closeSync(); emptyDB.closeSync(); }
    const empty = receiver(commands);
    const emptyResult = await runNativeAcquisition(await authorizeLocalDatabase(emptyPath, fixtureSourceAccess), empty.port, limits);
    assert.equal(emptyResult.value.validation.transport.rows, 0);
    assert.equal(emptyResult.value.native.transport.rows, 0);
    assert(Number.isFinite(emptyResult.value.diagnostics.validationMilliseconds));
    assert(Number.isFinite(emptyResult.value.diagnostics.nativeResultMilliseconds));
    assert.deepEqual(empty.received.validation_scan, []);
    assert.deepEqual(empty.received.native_result, []);
    assert(empty.events.includes('validation_scan-begin'));
    assert(empty.events.includes('native_result-begin'));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

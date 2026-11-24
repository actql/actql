import test from 'node:test';
import assert from 'node:assert/strict';
import {DuckDBAppender, DuckDBConnection} from '@duckdb/node-api';
import { provisionComputeDatabase } from '../session.mjs';
import { runResidentFixedCompute, matchesFixedCompute, releaseFixedCompute } from '../fixed-compute.mjs';

import type {PhysicalScalar} from '../physical-values.mjs';
import type {SourceChunk, SourceSession} from '../source-acquisition.mjs';

type ResidentResult = Awaited<ReturnType<typeof runResidentFixedCompute>>;
type ResidentPhases = ResidentResult['value']['diagnostics'];
// The appender-only probes leave chargeTransfer absent, so unexpected transport still fails.
type ResidentAccounting = NonNullable<Parameters<Awaited<ReturnType<typeof provisionComputeDatabase>>['run']>[3]>;

const limits = Object.freeze({
  maxRows: 10000, maxCells: 100000, maxTransportBytes: 2000000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 20,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});
const discard = () => {};

test('resident publication waits for asynchronous holding and rolls back failed or cancelled finalization', async () => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  try {
    for (const mode of ['success', 'failure', 'cancel']) {
      const port = Object.freeze({queryParameters: () => []});
      const resident = Object.freeze({
        viewSqls: () => [],
        createResultSql: () => 'CREATE TABLE provisional AS SELECT 1 AS i',
        readResultSql: () => 'SELECT i FROM provisional',
      });
      let entered!: () => void, release!: () => void;
      const ready = new Promise<void>(resolve => { entered = resolve; });
      const holding = new Promise<void>(resolve => { release = resolve; });
      const controller = new AbortController();
      const settlements: boolean[] = [];
      let terminal = false;
      const operation = runResidentFixedCompute(db, port, resident, limits, discard,
        async () => {
          entered();
          await holding;
          if (mode === 'failure') throw new Error('holding seal failed');
        }, controller.signal, {
          started() {}, chargeTransfer() {}, settled(value) { settlements.push(value); },
        });
      // Observe without replacing the original result/rejection.
      operation.then(() => { terminal = true; }, () => { terminal = true; });
      await ready;
      try {
        assert.equal(terminal, false);
        assert.deepEqual(settlements, []);
        assert.equal(db.status().busy, true);
        if (mode === 'cancel') controller.abort();
      } finally { release(); }
      if (mode === 'success') {
        const result = await operation;
        assert(matchesFixedCompute(result, port, discard));
        assertResidentPhases(result.value.diagnostics);
        const rows = await db.run(limits, session => collect(session, 'SELECT i FROM provisional'));
        assert.deepEqual(rows.value, ['1']);
        releaseFixedCompute(result);
      } else {
        await assert.rejects(operation, mode === 'failure' ? /holding seal failed/ : {code: 'Cancelled'});
        // CREATE succeeds only if the earlier provisional table was rolled back.
        await db.run(limits, session => session.command('CREATE TABLE provisional(i INTEGER)', [], discard));
      }
      assert.deepEqual(settlements, [true]);
      await db.run(limits, session => session.command('DROP TABLE provisional', [], discard));
    }
  } finally { await db.close(); }
});

test('a swallowed falsy receiver failure rolls back resident publication', async () => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  try {
    for (const reason of [undefined, null, false, 0, '']) {
      let rejected = false;
      try {
        await db.run(limits, async session => {
          await session.command('CREATE TABLE failed_output(i INTEGER)', [], discard);
          try {
            await session.command('SELECT 1 AS i', [], () => { throw reason; });
          } catch (error) { assert.equal(error, reason); }
        });
      } catch (error) { rejected = true; assert.equal(error, reason); }
      assert.equal(rejected, true);
      // The table must not have committed, and the environment remains usable.
      await db.run(limits, async session => {
        await session.command('CREATE TABLE failed_output(i INTEGER)', [], discard);
        await session.command('DROP TABLE failed_output', [], discard);
      });
    }
  } finally { await db.close(); }
});

test('resident Compute materializes once and validates before publishing its table', async () => {
  const db = await provisionComputeDatabase(limits, { started() {}, settled() {} });
  const port = Object.freeze({ queryParameters: () => [] });
  const resident = Object.freeze({
    viewSqls: () => ['CREATE TEMP VIEW owned_input AS SELECT id FROM x'],
    createResultSql: () => 'CREATE TABLE a AS SELECT id FROM owned_input WHERE id > 2',
    readResultSql: () => 'SELECT id FROM a',
  });
  const received: PhysicalScalar[] = [];
  const consume = (chunk: SourceChunk) => received.push(...chunk.columns[0]);
  let result!: ResidentResult;
  try {
    await db.run(limits, async session => {
      await session.command('CREATE TABLE x(id INTEGER)', [], discard);
      await session.command('INSERT INTO x VALUES (3), (1), (3)', [], discard);
    });
    // Failed validation must not leave A committed. A later CREATE can succeed.
    await assert.rejects(runResidentFixedCompute(db, Object.freeze({ ...port }), resident,
      limits, discard, () => { throw new Error('guard'); }), /guard/);
    result = await runResidentFixedCompute(db, port, resident, limits, consume, fields => {
      assert.equal(fields[0].name, 'id');
      assert.deepEqual(received, ['3', '3']);
    });
    assert.equal(result.value.importedRows, 0);
    assertResidentPhases(result.value.diagnostics);
    assert(matchesFixedCompute(result, port, consume));
    assert(!matchesFixedCompute(result, { ...port }, consume));
    const next = await db.run(limits, session => collect(session, 'SELECT id FROM a'));
    assert.deepEqual(next.value, ['3', '3']);
  } finally { await db.close(); }
  assert(matchesFixedCompute(result, port, consume));
  releaseFixedCompute(result);
  assert(!matchesFixedCompute(result, port, consume));
});

test('resident appender commits exact rows and rejects swallowed partial input', async () => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  try {
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_0(id DOUBLE, text VARCHAR)', [], discard));
    const imported = await db.run(limits, async session => {
      const writer = await session.openResidentAppender('resident_0', 2);
      writer.append([{type: {id: 'DOUBLE'}, value: '3ff0000000000000'},
        {type: {id: 'VARCHAR'}, value: '日本語'}]);
      writer.append([{type: {id: 'DOUBLE'}, value: null},
        {type: {id: 'VARCHAR'}, value: '日本語'}]);
      writer.flush();
      writer.finish();
    });
    assert.equal(imported.usage.appendedRows, 2);
    const ordered = await db.run(limits, session =>
      collect(session, 'SELECT coalesce(text, \'\') FROM main.resident_0 ORDER BY rowid'));
    assert.deepEqual(ordered.value, ['日本語', '日本語']);
    await assert.rejects(db.run(limits, async session => {
      await session.command('CREATE TABLE main.resident_1(id DOUBLE)', [], discard);
      const writer = await session.openResidentAppender('resident_1', 1);
      try { writer.append([{type: {id: 'VARCHAR'}, value: 'wrong'}]); }
      catch { /* A swallowed native transport failure still aborts the task. */ }
    }), {code: 'ImportPhysicalType'});
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_1(id DOUBLE)', [], discard));
  } finally { await db.close(); }
});

test('unawaited appender acquisition settles and closes before the connection', async t => {
  const events: string[] = [];
  const settled: boolean[] = [];
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const createAppender = DuckDBConnection.prototype.createAppender;
  const closeAppender = DuckDBAppender.prototype.closeSync;
  const closeConnection = DuckDBConnection.prototype.closeSync;
  try {
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_0(id INTEGER)', [], discard));
    t.mock.method(DuckDBConnection.prototype, 'createAppender', async function (this: DuckDBConnection, ...args: Parameters<DuckDBConnection['createAppender']>) {
      events.push('acquiring');
      await gate;
      const appender = await createAppender.apply(this, args);
      events.push('acquired');
      return appender;
    });
    t.mock.method(DuckDBAppender.prototype, 'closeSync', function (this: DuckDBAppender) {
      events.push('appender-closed');
      return closeAppender.call(this);
    });
    t.mock.method(DuckDBConnection.prototype, 'closeSync', function (this: DuckDBConnection) {
      events.push('connection-closed');
      return closeConnection.call(this);
    });
    let finished = false;
    const operation = db.run(limits, session => {
      session.openResidentAppender('resident_0', 1).catch(() => {});
      return 'must not commit';
    }, undefined, {started() {}, settled(value) { settled.push(value); }} as ResidentAccounting);
    operation.then(() => { finished = true; }, () => { finished = true; });
    while (!events.includes('acquiring')) await new Promise<void>(resolve => setImmediate(resolve));
    await new Promise<void>(resolve => setImmediate(resolve));
    assert.equal(finished, false);
    assert.deepEqual(events, ['acquiring']);
    assert.deepEqual(settled, []);
    release();
    await assert.rejects(operation, {code: 'UnawaitedCommand'});
    assert.deepEqual(events, ['acquiring', 'acquired', 'appender-closed', 'connection-closed']);
    assert.deepEqual(settled, [true]);
  } finally {
    release();
    await db.close();
  }
});

test('failed body retains a late appender until acquisition and cleanup settle', async t => {
  const events: string[] = [];
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const createAppender = DuckDBConnection.prototype.createAppender;
  const closeAppender = DuckDBAppender.prototype.closeSync;
  const closeConnection = DuckDBConnection.prototype.closeSync;
  const primary = new Error('body failed');
  try {
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_0(id INTEGER)', [], discard));
    t.mock.method(DuckDBConnection.prototype, 'createAppender', async function (this: DuckDBConnection, ...args: Parameters<DuckDBConnection['createAppender']>) {
      events.push('acquiring');
      await gate;
      const appender = await createAppender.apply(this, args);
      events.push('acquired');
      return appender;
    });
    t.mock.method(DuckDBAppender.prototype, 'closeSync', function (this: DuckDBAppender) {
      events.push('appender-closed');
      return closeAppender.call(this);
    });
    t.mock.method(DuckDBConnection.prototype, 'closeSync', function (this: DuckDBConnection) {
      events.push('connection-closed');
      return closeConnection.call(this);
    });
    let finished = false;
    const operation = db.run(limits, session => {
      session.openResidentAppender('resident_0', 1).catch(() => {});
      throw primary;
    });
    operation.then(() => { finished = true; }, () => { finished = true; });
    while (!events.includes('acquiring')) await new Promise<void>(resolve => setImmediate(resolve));
    await new Promise<void>(resolve => setImmediate(resolve));
    assert.equal(finished, false);
    assert.deepEqual(events, ['acquiring']);
    release();
    await assert.rejects(operation, error => error === primary);
    assert.deepEqual(events, ['acquiring', 'acquired', 'appender-closed', 'connection-closed']);
  } finally {
    release();
    await db.close();
  }
});

test('caught falsy appender acquisition failure still aborts the session', async t => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  try {
    for (const reason of [undefined, null, false, 0, '']) {
      t.mock.method(DuckDBConnection.prototype, 'createAppender', async () => { throw reason; });
      let rejected = false;
      try {
        await db.run(limits, async session => {
          try { await session.openResidentAppender('resident_0', 1); }
          catch (error) { assert.equal(error, reason); }
        });
      } catch (error) { rejected = true; assert.equal(error, reason); }
      assert.equal(rejected, true);
      t.mock.reset();
    }
  } finally { await db.close(); }
});

test('cancelled appender acquisition waits for the late handle and closes it', async t => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  const controller = new AbortController();
  let release!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const createAppender = DuckDBConnection.prototype.createAppender;
  const closeAppender = DuckDBAppender.prototype.closeSync;
  let acquired = false;
  let closed = 0;
  try {
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_0(id INTEGER)', [], discard));
    t.mock.method(DuckDBConnection.prototype, 'createAppender', async function (this: DuckDBConnection, ...args: Parameters<DuckDBConnection['createAppender']>) {
      await gate;
      const appender = await createAppender.apply(this, args);
      acquired = true;
      return appender;
    });
    t.mock.method(DuckDBAppender.prototype, 'closeSync', function (this: DuckDBAppender) {
      closed++;
      return closeAppender.call(this);
    });
    let finished = false;
    const operation = db.run(limits, session => {
      session.openResidentAppender('resident_0', 1).catch(() => {});
      controller.abort();
    }, controller.signal);
    operation.then(() => { finished = true; }, () => { finished = true; });
    await new Promise<void>(resolve => setImmediate(resolve));
    assert.equal(finished, false);
    release();
    await assert.rejects(operation, {code: 'Cancelled'});
    assert.equal(acquired, true);
    assert.equal(closed, 1);
  } finally {
    release();
    await db.close();
  }
});

test('failed appender close retains cleanup responsibility for retry', async t => {
  const settled: boolean[] = [];
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  const closeAppender = DuckDBAppender.prototype.closeSync;
  let failOnce = true;
  let closed = 0;
  try {
    await db.run(limits, session =>
      session.command('CREATE TABLE main.resident_0(id INTEGER)', [], discard));
    t.mock.method(DuckDBAppender.prototype, 'closeSync', function (this: DuckDBAppender) {
      if (failOnce) { failOnce = false; throw new Error('injected appender close failure'); }
      closed++;
      return closeAppender.call(this);
    });
    let failure!: Readonly<{code: string; cleanupPending: boolean}>;
    try {
      await db.run(limits, async session => {
        await session.openResidentAppender('resident_0', 1);
      }, undefined, {started() {}, settled(value) { settled.push(value); }} as ResidentAccounting);
    } catch (error) { failure = error as typeof failure; }
    assert.equal(failure.code, 'UnclosedAppender');
    assert.equal(failure.cleanupPending, true);
    assert.deepEqual(settled, [false]);
    assert.equal(closed, 0);
    assert.equal(db.status().pending, true);
    await db.close();
    assert.deepEqual(settled, [false, true]);
    assert.equal(closed, 1);
  } finally {
    if (db.status().pending) await db.close();
  }
});
const collect = async (session: SourceSession, sql: string) => {
  const values: PhysicalScalar[] = [];
  await session.command(sql, [], chunk => values.push(...chunk.columns[0]));
  return values;
};

function assertResidentPhases(phases: ResidentPhases) {
  const names = ['inputVerificationMilliseconds', 'viewPreparationMilliseconds',
    'materializationMilliseconds', 'receiveMilliseconds',
    'finalizationMilliseconds', 'temporaryCleanupMilliseconds'] as const;
  assert(Object.isFrozen(phases));
  assert.deepEqual(Object.keys(phases), [...names, 'inputCallbackMilliseconds',
    'outputCallbackMilliseconds', 'directInputScans',
    'reusedInputIdentities', 'reusedInputValues', 'demandColumnScans',
    'reusedDemandMeasurements', 'workMilliseconds']);
  assert(Number.isInteger(phases.directInputScans));
  assert(Number.isInteger(phases.reusedInputIdentities));
  assert(Number.isInteger(phases.demandColumnScans));
  assert(phases.reusedInputIdentities <= phases.directInputScans + phases.reusedInputValues);
  for (const value of Object.values(phases)) assert(Number.isFinite(value) && value >= 0);
  assert(phases.inputCallbackMilliseconds <= phases.inputVerificationMilliseconds);
  assert(phases.outputCallbackMilliseconds <= phases.receiveMilliseconds);
  const sum = names.reduce((total, name) => total + phases[name], 0);
  assert(Math.abs(sum - phases.workMilliseconds) < 0.000001);
}

test('resident diagnostics include awaited input verification and holding without importing rows', async () => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  const events: (number | string)[] = [];
  const pause = () => new Promise(resolve => setTimeout(resolve, 15));
  const port = Object.freeze({
    queryParameters: () => [], importCount: () => 2,
    async consumeInput(input: number) { events.push(input); await pause(); },
  });
  const resident = Object.freeze({
    viewSqls: () => [],
    createResultSql: () => 'CREATE TABLE timed_output AS SELECT 1 AS i',
    readResultSql: () => 'SELECT i FROM timed_output',
    cleanupSqls: () => ['DROP TABLE timed_output'],
  });
  let result: ResidentResult | undefined;
  try {
    result = await runResidentFixedCompute(db, port, resident, limits, discard,
      async () => { events.push('holding'); await pause(); });
    assert.deepEqual(events, [0, 1, 'holding']);
    assert.equal(result.value.importedRows, 0);
    assert.equal(result.value.importedCells, 0);
    assertResidentPhases(result.value.diagnostics);
    // Loose lower bounds detect accidentally timing Promise creation instead
    // of awaiting it; no performance upper bound is asserted by this test.
    assert(result.value.diagnostics.inputVerificationMilliseconds >= 20);
    assert(result.value.diagnostics.finalizationMilliseconds >= 10);
    await db.run(limits, session => session.command('CREATE TABLE timed_output(i INTEGER)', [], discard));
  } finally { if (result) releaseFixedCompute(result); await db.close(); }
});

test('resident provider separates environment capacity from task settlement', async () => {
  const events: (string | boolean)[] = [];
  const db = await provisionComputeDatabase(limits, {
    started: () => events.push('reserve'), settled: value => events.push(value),
  });
  try {
    await db.run(limits, async session => {
      await session.command('CREATE TABLE x(id INTEGER)', [], discard);
      await session.command('INSERT INTO x VALUES (3), (1), (3), (2)', [], discard);
    });
    const a = await db.run(limits, async session => {
      await session.command('CREATE TABLE a AS SELECT id FROM x WHERE id > 2', [], discard);
      return collect(session, 'SELECT id FROM a');
    });
    assert.deepEqual(a.value, ['3', '3']);
    assert.deepEqual(events, ['reserve']);
    // Provisional B is rolled back; already committed A is not rolled back.
    await assert.rejects(db.run(limits, async session => {
      await session.command('CREATE TABLE b AS SELECT id FROM x', [], discard);
      throw new Error('guard failed');
    }), /guard failed/);
    const c = await db.run(limits, session => collect(session, 'SELECT id FROM a WHERE id > 1'));
    assert.deepEqual(c.value, ['3', '3']);
    assert.equal(db.status().live, true);
    // A second CREATE succeeding proves failed B did not publish its table.
    await db.run(limits, session => session.command('CREATE TABLE b(id INTEGER)', [], discard));
    await db.run(limits, session => session.command('DROP TABLE b', [], discard));
    await db.run(limits, session => session.command('CREATE TABLE b(id INTEGER)', [], discard));
    assert.deepEqual(events, ['reserve']);
  } finally { await db.close(); }
  assert.deepEqual(events, ['reserve', true]);
  await assert.rejects(db.run(limits, discard), { code: 'SessionClosed' });
});

test('resident provider rejects changed profiles and retains busy cleanup responsibility', async () => {
  const events: (string | boolean)[] = [];
  const db = await provisionComputeDatabase(limits, {
    started: () => events.push('reserve'), settled: value => events.push(value),
  });
  await assert.rejects(db.run({ ...limits, memoryBytes: limits.memoryBytes / 2 }, discard),
    { code: 'EnvironmentMismatch' });
  let release!: () => void;
  let entered!: () => void;
  const ready = new Promise<void>(resolve => { entered = resolve; });
  const wait = new Promise<void>(resolve => { release = resolve; });
  const task = db.run(limits, async () => { entered(); await wait; });
  await ready;
  await assert.rejects(db.run(limits, discard), { code: 'ConcurrentCommand' });
  await assert.rejects(db.close(), { code: 'CleanupInProgress' });
  assert.deepEqual(events, ['reserve', false]);
  assert.equal(db.status().pending, true);
  release();
  await task;
  await db.close();
  assert.deepEqual(events, ['reserve', false, true]);
});

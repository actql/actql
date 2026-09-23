import test from 'node:test';
import assert from 'node:assert/strict';
import { provisionComputeDatabase } from '../session.mjs';
import { runResidentFixedCompute, matchesFixedCompute, releaseFixedCompute } from '../fixed-compute.mjs';

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
      let entered, release;
      const ready = new Promise(resolve => { entered = resolve; });
      const holding = new Promise(resolve => { release = resolve; });
      const controller = new AbortController();
      const settlements = [];
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
  const received = [];
  const consume = chunk => received.push(...chunk.columns[0]);
  let result;
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
const collect = async (session, sql) => {
  const values = [];
  await session.command(sql, [], chunk => values.push(...chunk.columns[0]));
  return values;
};

function assertResidentPhases(phases) {
  const names = ['inputVerificationMilliseconds', 'viewPreparationMilliseconds',
    'materializationMilliseconds', 'receiveMilliseconds',
    'finalizationMilliseconds', 'temporaryCleanupMilliseconds'];
  assert(Object.isFrozen(phases));
  assert.deepEqual(Object.keys(phases), [...names, 'directInputScans',
    'reusedInputIdentities', 'reusedInputValues', 'workMilliseconds']);
  assert(Number.isInteger(phases.directInputScans));
  assert(Number.isInteger(phases.reusedInputIdentities));
  assert(phases.reusedInputIdentities <= phases.directInputScans + phases.reusedInputValues);
  for (const value of Object.values(phases)) assert(Number.isFinite(value) && value >= 0);
  const sum = names.reduce((total, name) => total + phases[name], 0);
  assert(Math.abs(sum - phases.workMilliseconds) < 0.000001);
}

test('resident diagnostics include awaited input verification and holding without importing rows', async () => {
  const db = await provisionComputeDatabase(limits, {started() {}, settled() {}});
  const events = [];
  const pause = () => new Promise(resolve => setTimeout(resolve, 15));
  const port = Object.freeze({
    queryParameters: () => [], importCount: () => 2,
    async consumeInput(input) { events.push(input); await pause(); },
  });
  const resident = Object.freeze({
    viewSqls: () => [],
    createResultSql: () => 'CREATE TABLE timed_output AS SELECT 1 AS i',
    readResultSql: () => 'SELECT i FROM timed_output',
    cleanupSqls: () => ['DROP TABLE timed_output'],
  });
  let result;
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
  const events = [];
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
  const events = [];
  const db = await provisionComputeDatabase(limits, {
    started: () => events.push('reserve'), settled: value => events.push(value),
  });
  await assert.rejects(db.run({ ...limits, memoryBytes: limits.memoryBytes / 2 }, discard),
    { code: 'EnvironmentMismatch' });
  let release;
  let entered;
  const ready = new Promise(resolve => { entered = resolve; });
  const wait = new Promise(resolve => { release = resolve; });
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

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
    assert(matchesFixedCompute(result, port, consume));
    assert(!matchesFixedCompute(result, { ...port }, consume));
    const next = await db.run(limits, session => collect(session, 'SELECT id FROM a'));
    assert.deepEqual(next.value, ['3', '3']);
  } finally { await db.close(); }
  assert(matchesFixedCompute(result, port, consume));
  releaseFixedCompute(result);
  assert(!matchesFixedCompute(result, port, consume));
});
const collect = async (session, sql) => {
  const values = [];
  await session.command(sql, [], chunk => values.push(...chunk.columns[0]));
  return values;
};

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

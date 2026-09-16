import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { fork } from 'node:child_process';
import { DuckDBInstance, DuckDBPreparedStatement } from '@duckdb/node-api';
import { authorizeLocalDatabase, withSourceDatabase, withComputeDatabase, DuckDBTransportError } from '../session.mjs';

const limits = Object.freeze({
  maxRows: 10000, maxCells: 100000, maxTransportBytes: 2000000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 20,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});
const discard = () => {};
async function rows(session, sql, parameters = []) {
  const result = [];
  await session.command(sql, parameters, chunk => {
    for (let r = 0; r < chunk.rowCount; r++) result.push(chunk.columns.map(column => column[r]));
  });
  return result;
}
const hasCode = code => error => error.code === code;

test('falsy receiver and body failures cannot become successful sessions', async () => {
  for (const reason of [undefined, null, false, 0, '']) {
    for (const deadline of [false, true]) {
      const signal = deadline ? new AbortController().signal : undefined;
      const settings = deadline ? {...limits, cancelWaitMs: 10} : limits;
      for (const caught of [false, true]) {
        let rejected = false;
        try {
          await withComputeDatabase(settings, async session => {
            if (!caught) throw reason;
            try {
              await session.command('SELECT 1 AS i', [], () => { throw reason; });
            } catch (error) { assert.equal(error, reason); }
            return 'must-not-publish';
          }, signal);
        } catch (error) { rejected = true; assert.equal(error, reason); }
        assert.equal(rejected, true, `caught=${caught}, deadline=${deadline}, reason=${String(reason)}`);
      }
    }
  }
});

test('reused INSERT keeps exact payloads and transfer charges without repeated preparation', async () => {
  const execute = (reuse, configuration = limits) => withComputeDatabase(configuration, async session => {
    await session.command('CREATE TEMP TABLE imported(i BIGINT, s VARCHAR, d DECIMAL(38,2))', [], discard);
    const insert = reuse ? session.insert : session.command;
    for (const value of ['9223372036854775807', null, '-9223372036854775808']) {
      await insert('INSERT INTO imported VALUES (?, ?, ?)', [
        {type: {id: 'BIGINT'}, value},
        {type: {id: 'VARCHAR'}, value: value === null ? null : '日本語'},
        {type: {id: 'DECIMAL', precision: 38, scale: 2}, value: '99999999999999999999999999999999999999'},
      ], discard);
    }
    return rows(session, 'SELECT * FROM imported');
  });
  const ordinary = await execute(false);
  const reused = await execute(true);
  assert.deepEqual(reused.value, ordinary.value);
  assert.deepEqual(reused.value.map(row => row[0]), ['9223372036854775807', null, '-9223372036854775808']);
  for (const field of ['rows', 'cells', 'transportBytes', 'statements', 'chunks']) {
    assert.equal(reused.usage[field], ordinary.usage[field], field);
  }
  assert.equal(ordinary.usage.preparations, 5);
  assert.equal(reused.usage.preparations, 3);
  assert(reused.usage.prepareMilliseconds <= reused.usage.commandMilliseconds);
  assert(reused.usage.receiveCallbackMilliseconds <= reused.usage.commandMilliseconds);
  assert(reused.usage.cleanupMilliseconds >= 0);
  await assert.rejects(execute(true, {...limits, maxTransportBytes: ordinary.usage.transportBytes - 1}),
    hasCode('TransportBytes'));
});

test('reused INSERT cannot swallow invalid types or continue after cancellation', async () => {
  const abort = new AbortController();
  let writes = 0;
  await assert.rejects(withComputeDatabase(limits, async session => {
    await session.command('CREATE TEMP TABLE imported(i BIGINT)', [], discard);
    await session.insert('INSERT INTO imported VALUES (?)', [{type: {id: 'BIGINT'}, value: '1'}], discard);
    writes++;
    abort.abort();
    await session.insert('INSERT INTO imported VALUES (?)', [{type: {id: 'BIGINT'}, value: '2'}], discard);
    writes++;
  }, abort.signal), hasCode('Cancelled'));
  assert.equal(writes, 1);
  await assert.rejects(withComputeDatabase(limits, async session => {
    await session.command('CREATE TEMP TABLE imported(i BIGINT)', [], discard);
    await session.insert('INSERT INTO imported VALUES (?)', [{type: {id: 'BIGINT'}, value: '1'}], discard);
    try {
      await session.insert('INSERT INTO imported VALUES (?)', [{type: {id: 'BIGINT'}, value: '9223372036854775808'}], discard);
    } catch { /* swallowed by orchestration must still fail the attempt */ }
  }));
  await assert.rejects(withComputeDatabase(limits,
    session => session.insert('SELECT 1', [], discard)), hasCode('StatementKind'));
});

test('cached INSERT destruction failure retains native cleanup ownership until explicit retry', async t => {
  const destroy = DuckDBPreparedStatement.prototype.destroySync;
  let rejectDestroy = false;
  t.mock.method(DuckDBPreparedStatement.prototype, 'destroySync', function () {
    if (rejectDestroy) throw Error('injected prepared destruction failure');
    return destroy.call(this);
  });
  const settled = [];
  let failure;
  try {
    await withComputeDatabase(limits, async session => {
      await session.command('CREATE TEMP TABLE imported(i BIGINT)', [], discard);
      await session.insert('INSERT INTO imported VALUES (?)', [{type: {id: 'BIGINT'}, value: '1'}], discard);
      rejectDestroy = true;
    }, undefined, {started() {}, chargeTransfer() {}, settled(value) { settled.push(value); }});
  } catch (error) { failure = error; }
  rejectDestroy = false;
  assert.equal(failure?.cleanupHandle?.status().pending, true);
  assert.deepEqual(settled, [false]);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(settled, [false, true]);
});

test('single-table filtering and projection preserve duplicate relative order across chunks', async () => {
  const root = fileURLToPath(new URL('../../../_build/duckdb-fixtures/', import.meta.url));
  await mkdir(root, { recursive: true });
  const dir = await mkdtemp(join(root, 'order-'));
  const path = join(dir, 'input.duckdb');
  const pattern = [[3, 0], [1, null], [2, 7], [3, 0]];
  const expected = Array.from({ length: 5000 }, (_, i) => pattern[i % 4]);
  try {
    const db = await DuckDBInstance.create(path);
    const connection = await db.connect();
    try {
      await connection.run('CREATE TABLE records(id INTEGER, amount INTEGER)');
      await connection.run(`INSERT INTO records VALUES ${expected.map(([id, amount]) => `(${id},${amount ?? 'NULL'})`).join(',')}`);
    } finally { connection.closeSync(); db.closeSync(); }
    const result = await withSourceDatabase(await authorizeLocalDatabase(path), limits, async session => {
      let scanChunks = 0;
      let nativeChunks = 0;
      const scan = [];
      const selected = [];
      await session.command('SELECT id, amount FROM records', [], chunk => {
        scanChunks++;
        for (let r = 0; r < chunk.rowCount; r++) scan.push(chunk.columns.map(column => column[r]));
      });
      await session.command('SELECT id FROM records WHERE CAST(id AS DOUBLE) > 1', [], chunk => {
        nativeChunks++; selected.push(...chunk.columns[0]);
      });
      assert(scanChunks > 1); assert(nativeChunks > 1);
      return { scan, selected };
    });
    assert.deepEqual(result.value.scan, expected.map(row => row.map(value => value === null ? null : String(value))));
    assert.deepEqual(result.value.selected, expected.filter(([id]) => id > 1).map(([id]) => String(id)));
    assert.equal(result.usage.rows, 8750); // Both actual receipts, not just selected rows.
  } finally { await rm(dir, { recursive: true, force: true }); }
});

for (const bounded of [false, true]) {
test(`exact physical scalar transport and prepared import preserve payloads (${bounded ? 'bounded' : 'whole-input'})`, async () => {
  const configuration = bounded ? {...limits, maxChunkRows: 128, maxChunkBytes: 4096} : limits;
  const output = await withComputeDatabase(configuration, async session => {
    const chunks = [];
    await session.command(`SELECT TRUE AS b, '日本語' AS s,
      9223372036854775807::BIGINT AS i, 18446744073709551615::UBIGINT AS u,
      999999999999999999999999999999999999.99::DECIMAL(38,2) AS d,
      DATE '0001-01-01' AS day,
      TIMESTAMPTZ '2026-09-13 12:34:56.123456+00' AS instant,
      TIMESTAMP '2026-09-13 12:34:56.123456' AS naive,
      -0.0::DOUBLE AS z, NULL::VARCHAR AS n`, [], chunk => chunks.push(chunk));
    assert.equal(chunks.length, 1);
    const chunk = chunks[0];
    assert(Object.isFrozen(chunk.columns[0]));
    assert.deepEqual(chunk.columns.slice(0, 5), [
      [true], ['日本語'], ['9223372036854775807'], ['18446744073709551615'],
      ['99999999999999999999999999999999999999'],
    ]);
    assert.equal(chunk.fields[6].type.id, 'TIMESTAMP_TZ');
    assert.equal(chunk.fields[7].type.id, 'TIMESTAMP');
    assert.equal(chunk.columns[6][0], '1789302896123456');
    assert.equal(chunk.columns[7][0], '1789302896123456');
    // No rounding/admission here: the microsecond remainder survives to MoonBit.
    const parameters = chunk.fields.map((field, i) => ({ type: field.type, value: chunk.columns[i][0] }));
    return rows(session, 'SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?', parameters);
  });
  assert.equal(output.value[0][4], '99999999999999999999999999999999999999');
  assert.equal(output.value[0][6], '1789302896123456');
  assert.equal(output.usage.statements, 2);
});
}

test('chunk transfer has cumulative bounds and immutable column payloads', async () => {
  const output = await withComputeDatabase(limits, async session => {
    const sizes = [];
    await session.command('SELECT i::BIGINT AS i FROM range(5000) t(i)', [], chunk => {
      sizes.push(chunk.rowCount);
      assert.throws(() => { chunk.columns[0][0] = 'broken'; }, TypeError);
    });
    assert(sizes.length > 1);
    return sizes.reduce((a, b) => a + b, 0);
  });
  assert.equal(output.value, 5000);
  assert.equal(output.usage.rows, 5000);
  await assert.rejects(withComputeDatabase({ ...limits, maxRows: 4999 },
    session => session.command('SELECT i::BIGINT FROM range(5000) t(i)', [], discard)), hasCode('Rows'));
  await assert.rejects(withComputeDatabase({ ...limits, maxRows: 1 }, async session => {
    await rows(session, 'SELECT 1');
    await rows(session, 'SELECT 2');
  }), hasCode('Rows'));
  await assert.rejects(withComputeDatabase({ ...limits, maxCells: 1 },
    session => rows(session, 'SELECT 1, 2')), hasCode('Cells'));
  await assert.rejects(withComputeDatabase({ ...limits, maxTransportBytes: 0 },
    session => rows(session, 'SELECT 1 WHERE FALSE')), hasCode('TransportBytes'));
});

test('source grants are opaque; existing file is read-only and isolated from Compute', async () => {
  const root = fileURLToPath(new URL('../../../_build/duckdb-fixtures/', import.meta.url));
  await mkdir(root, { recursive: true });
  const dir = await mkdtemp(join(root, 'source-'));
  const path = join(dir, 'input.duckdb');
  let db;
  let conn;
  try {
    db = await DuckDBInstance.create(path);
    conn = await db.connect();
    await conn.run('CREATE TABLE input(id BIGINT, amount DECIMAL(18,2))');
    await conn.run('INSERT INTO input VALUES (3, 1.25), (1, NULL), (3, 2.50)');
    conn.closeSync(); conn = undefined;
    db.closeSync(); db = undefined;
    const grant = await authorizeLocalDatabase(path);
    await assert.rejects(withSourceDatabase({ ...grant }, limits, discard), hasCode('UnauthorizedSource'));
    const read = await withSourceDatabase(grant, limits, session => rows(session, 'SELECT id FROM input WHERE id > 1'));
    assert.deepEqual(read.value, [['3'], ['3']]);
    await assert.rejects(withSourceDatabase(grant, limits,
      session => session.command('DELETE FROM input', [], discard)),
    error => error.code === 'StatementKind' || /read.only/i.test(error.message));
    await assert.rejects(withComputeDatabase(limits,
      session => rows(session, 'SELECT * FROM input')), /does not exist/i);
    const after = await withSourceDatabase(grant, limits, session => rows(session, 'SELECT id FROM input'));
    assert.deepEqual(after.value, [['3'], ['1'], ['3']]);
  } finally {
    conn?.closeSync(); db?.closeSync();
    // Only this test's uniquely created directory, never a user's source.
    await rm(dir, { recursive: true, force: true });
  }
});

test('cancelled, failed and unawaited commands cannot become successful sessions', async () => {
  const abort = new AbortController();
  abort.abort();
  let entered = false;
  await assert.rejects(withComputeDatabase(limits, () => { entered = true; }, abort.signal), hasCode('Cancelled'));
  assert.equal(entered, false);
  const mid = new AbortController();
  let captured;
  await assert.rejects(withComputeDatabase(limits, async session => {
    captured = session;
    await session.command('SELECT i FROM range(5000) t(i)', [], () => mid.abort());
    return 'must not publish';
  }, mid.signal), hasCode('Cancelled'));
  await assert.rejects(captured.command('SELECT 1', [], discard), hasCode('Cancelled'));
  await assert.rejects(withComputeDatabase(limits, async session => {
    try { await rows(session, 'SELECT * FROM missing'); } catch { /* cannot swallow failure */ }
    return 'must not publish';
  }), /does not exist/i);
  await assert.rejects(withComputeDatabase(limits, session => {
    session.command('SELECT count(*) FROM range(1000000000)', [], discard);
    return 'must not publish';
  }), hasCode('UnawaitedCommand'));
  const next = await withComputeDatabase(limits, session => rows(session, 'SELECT 42'));
  assert.deepEqual(next.value, [['42']]);
});

test('no external file access, parameter narrowing, or statement batches', async () => {
  await assert.rejects(withComputeDatabase(limits,
    session => rows(session, 'COMMIT')), hasCode('StatementKind'));
  await assert.rejects(withComputeDatabase(limits,
    session => rows(session, "SELECT * FROM read_csv('/etc/passwd')")), /disabled|permission/i);
  await assert.rejects(withComputeDatabase(limits,
    session => rows(session, 'SELECT 1; SELECT 2')), hasCode('StatementCount'));
  await assert.rejects(withComputeDatabase(limits,
    session => rows(session, 'SELECT ?', [{ type: { id: 'BIGINT' }, value: '9223372036854775808' }])), hasCode('InvalidPhysicalValue'));
  await assert.rejects(withComputeDatabase(limits,
    session => rows(session, 'SELECT ?', [{ type: { id: 'DECIMAL', precision: 3, scale: 2 }, value: '1000' }])), hasCode('InvalidPhysicalValue'));
});

test('wire byte accounting is exact for declared transport frames', async () => {
  const expectedBytes = Buffer.byteLength('{"parameters":[]}\n' +
    '{"fields":[{"name":"n","type":{"id":"INTEGER"}}]}\n' +
    '{"rowCount":1,"columns":[["42"]]}\n');
  const result = await withComputeDatabase({ ...limits, maxTransportBytes: expectedBytes },
    session => rows(session, 'SELECT 42::INTEGER AS n'));
  assert.equal(result.usage.transportBytes, expectedBytes);
  await assert.rejects(withComputeDatabase({ ...limits, maxTransportBytes: expectedBytes - 1 },
    session => rows(session, 'SELECT 42::INTEGER AS n')), hasCode('TransportBytes'));
});

test('trusted physical accounting charges before acceptance and acknowledges real cleanup', async () => {
  let charged = 0;
  let started = 0;
  const settled = [];
  const accounting = Object.freeze({
    started() { started++; },
    chargeTransfer(bytes) { charged += bytes; },
    settled(confirmed) { settled.push(confirmed); },
  });
  const result = await withComputeDatabase(limits, session => rows(session, 'SELECT 42'), undefined, accounting);
  assert.equal(charged, result.usage.transportBytes);
  assert.equal(started, 1);
  assert.deepEqual(settled, [true]);
  const spent = charged;
  let accepted = false;
  await assert.rejects(withComputeDatabase(limits,
    session => session.command('SELECT 42', [], () => { accepted = true; }), undefined, {
      started: accounting.started,
      chargeTransfer(bytes) {
        if (charged - spent + bytes > 20) throw new Error('HostTransferLimit');
        accounting.chargeTransfer(bytes);
      },
      settled: accounting.settled,
    }), /HostTransferLimit/);
  assert.equal(accepted, false);
  assert(charged > spent); // the already sent parameter frame is not refunded
  assert.deepEqual(settled, [true, true]);
});

test('cleanup failure retains primary failure and same owned resources until retry settles', async t => {
  const close = DuckDBInstance.prototype.closeSync;
  const primary = new DuckDBTransportError('PrimaryExecutionFailure');
  const cleanup = new Error('injected instance close failure');
  let failOnce = true;
  t.mock.method(DuckDBInstance.prototype, 'closeSync', function () {
    if (failOnce) { failOnce = false; throw cleanup; }
    return close.call(this);
  });
  const settled = [];
  let failure;
  try {
    await withComputeDatabase(limits, async session => {
      await rows(session, 'SELECT 42');
      throw primary;
    }, undefined, { started() {}, chargeTransfer() {}, settled(value) { settled.push(value); } });
  } catch (error) { failure = error; }
  assert.equal(failure.code, 'PrimaryExecutionFailure');
  assert.equal(failure.primaryFailure, primary);
  assert.deepEqual(failure.cleanupErrors, [cleanup]);
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.deepEqual(settled, [false]);
  try {
    const status = await failure.cleanupHandle.retry();
    assert.equal(status.pending, false);
    assert.deepEqual(status.errors, [cleanup]);
    assert.deepEqual(settled, [false, true]);
    assert.equal(failure.primaryFailure, primary);
  } finally {
    if (failure.cleanupHandle.status().pending) await failure.cleanupHandle.retry();
  }
});

test('abort waits for an active native command to settle before returning failure', async () => {
  const abort = new AbortController();
  let delivered = 0;
  await assert.rejects(withComputeDatabase(limits, async session => {
    const command = session.command(
      'SELECT sum(sin(i::DOUBLE)) FROM range(1000000000) t(i)', [],
      () => { delivered++; },
    );
    const timer = setTimeout(() => abort.abort(), 20);
    try { await command; }
    finally { clearTimeout(timer); }
  }, abort.signal), hasCode('Cancelled'));
  assert.equal(delivered, 0);
  // A fresh attempt cannot inherit interruption or an in-flight connection.
  assert.deepEqual((await withComputeDatabase(limits, session => rows(session, 'SELECT 42'))).value, [['42']]);
});

test('cancellation deadline returns the same pending cleanup responsibility without releasing capacity', async () => {
  const abort = new AbortController();
  let ready;
  let release;
  const entered = new Promise(resolve => { ready = resolve; });
  const held = new Promise(resolve => { release = resolve; });
  const settlements = [];
  let bodyCalls = 0;
  const operation = withComputeDatabase({ ...limits, cancelWaitMs: 0 }, async session => {
    bodyCalls++;
    await session.command('CREATE TABLE pending_input AS SELECT 1 AS id', [], discard);
    ready();
    await held;
    return 'not successful after cancellation';
  }, abort.signal, {
    started() {}, chargeTransfer() {}, settled(value) { settlements.push(value); },
  });
  await entered;
  abort.abort();
  let failure;
  try { await operation; assert.fail('cancelled session must reject'); }
  catch (error) { failure = error; }
  try {
    assert.equal(failure.code, 'Cancelled');
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(settlements, [false]);
  } finally { release(); }
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(settlements, [false, true]);
  assert.equal(bodyCalls, 1);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.deepEqual(settlements, [false, true]);
});

test('invalid cancellation deadlines fail before native resource creation', async () => {
  for (const cancelWaitMs of [-1, 0.5, 2147483648]) {
    let started = false;
    await assert.rejects(withComputeDatabase({ ...limits, cancelWaitMs }, () => {
      assert.fail('invalid limits must not enter body');
    }, new AbortController().signal, {
      started() { started = true; }, chargeTransfer() {}, settled() {},
    }), hasCode('InvalidLimits'));
    assert.equal(started, false);
  }
});

test('native memory exhaustion cannot publish or retain temporary Compute state', async () => {
  let succeeded = false;
  await assert.rejects(withComputeDatabase({ ...limits, memoryBytes: 1024 * 1024 }, async session => {
    await session.command('CREATE TABLE owned_input AS SELECT 1 AS id', [], discard);
    // Consecutive integers can compress inside a table; use a native hash
    // working set to exercise the configured memory ceiling instead.
    await session.command('SELECT i, count(*) FROM range(100000) t(i) GROUP BY i', [], discard);
    succeeded = true;
    return 'must not publish';
  }), /out of memory|failed to allocate|could not allocate/i);
  assert.equal(succeeded, false);
  await assert.rejects(withComputeDatabase(limits, session => rows(session, 'SELECT * FROM owned_input')),
    /does not exist/i);
  assert.deepEqual((await withComputeDatabase(limits, session => rows(session, 'SELECT 42'))).value, [['42']]);
});

test('another process holding the source lock fails without capture and releases cleanly', async () => {
  const root = fileURLToPath(new URL('../../../_build/duckdb-fixtures/', import.meta.url));
  await mkdir(root, { recursive: true });
  const dir = await mkdtemp(join(root, 'lock-'));
  const path = join(dir, 'input.duckdb');
  let child;
  let exited;
  try {
    const instance = await DuckDBInstance.create(path);
    const connection = await instance.connect();
    try { await connection.run('CREATE TABLE input AS SELECT 7 AS id'); }
    finally { connection.closeSync(); instance.closeSync(); }
    const grant = await authorizeLocalDatabase(path);
    child = fork(fileURLToPath(new URL('./fixtures/hold-writer.mjs', import.meta.url)), [path], {
      stdio: ['ignore', 'ignore', 'pipe', 'ipc'],
    });
    let stderr = '';
    child.stderr.on('data', data => { stderr += data; });
    exited = new Promise(resolve => child.once('exit', (code, signal) => resolve({ code, signal })));
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('lock fixture startup timed out')), 10000);
      child.once('message', message => {
        clearTimeout(timer);
        if (message.ready === true) resolve();
        else reject(new Error('invalid lock fixture message'));
      });
      child.once('error', error => { clearTimeout(timer); reject(error); });
      exited.then(() => { clearTimeout(timer); reject(new Error(`lock fixture exited: ${stderr}`)); });
    });
    let entered = false;
    await assert.rejects(withSourceDatabase(grant, limits, () => { entered = true; }), /lock/i);
    assert.equal(entered, false);
    child.send('release');
    assert.deepEqual(await exited, { code: 0, signal: null });
    child = undefined;
    assert.deepEqual((await withSourceDatabase(grant, limits, session => rows(session, 'SELECT id FROM input'))).value, [['7']]);
  } finally {
    if (child) { child.kill(); await exited; }
    await rm(dir, { recursive: true, force: true });
  }
});

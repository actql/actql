import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { fork } from 'node:child_process';
import { DuckDBInstance } from '@duckdb/node-api';
import { authorizeLocalDatabase, withSourceDatabase, withComputeDatabase } from '../session.mjs';

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

test('exact physical scalar transport and prepared import preserve payloads', async () => {
  const output = await withComputeDatabase(limits, async session => {
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

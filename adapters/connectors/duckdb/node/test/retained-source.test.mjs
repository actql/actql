import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp, readdir, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DuckDBInstance} from '@duckdb/node-api';
import {retainedCase, workloads} from '../../../../../benchmarks/retained-results/fixtures.mjs';

const create = (database, workload, layout, rows) => promisify(execFile)(process.execPath,
  [fileURLToPath(new URL('../bench/create-retained-source.mjs', import.meta.url)), database,
    workload, layout, String(rows)], {timeout: 10000, maxBuffer: 65536});

test('separate source generator closes all nine fixture shapes before the consumer opens them', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-source-generator-'));
  try {
    let index = 0;
    for (const workload of workloads) for (const layout of ['narrow', 'numeric-64', 'text-1024']) {
      const fixture = retainedCase(workload, layout, 100);
      const database = join(directory, `${index++}.duckdb`);
      await create(database, workload, layout, 100);
      const db = await DuckDBInstance.create(database, {access_mode: 'READ_ONLY'});
      let connection;
      try {
        connection = await db.connect();
        const actual = (await connection.runAndReadAll('SELECT * FROM records ORDER BY rowid')).getRowObjects();
        assert.deepEqual(actual, Array.from({length: 100}, (_, i) => fixture.sourceRow(i)), fixture.id);
      } finally { connection?.closeSync(); db.closeSync(); }
    }
    const before = await readdir(directory);
    await assert.rejects(create(join(directory, 'invalid.duckdb'), workloads[0], 'narrow', '100junk'));
    assert.deepEqual(await readdir(directory), before, 'invalid arguments do not create a database');
  } finally { await rm(directory, {recursive: true, force: true}); }
});

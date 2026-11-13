import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {prepareSourceNodeClient} from './fixtures/source-node-client.mjs';
const {open} = await prepareSourceNodeClient({assemble: true, duckdb: false});

test('ordinary Local SQL evaluates Window functions with installed finite policy', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-local-analytic-'));
  const client = await open({stateDir: directory});
  try {
    const prefix = 'WITH t AS (SELECT 1 AS id, 3 AS v UNION ALL SELECT 2 AS id, 5 AS v) ';
    assert.deepEqual(await client.sql(prefix + 'SELECT id, SUM(v) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS total FROM t').all(),
      [{id: 1, total: 3}, {id: 2, total: 8}]);
    assert.deepEqual(await client.sql(prefix + 'SELECT id, ROW_NUMBER() OVER (ORDER BY id) AS n FROM t').all(),
      [{id: 1, n: 1}, {id: 2, n: 2}]);
    assert.deepEqual(await client.sql('SELECT 9 AS healthy').all(), [{healthy: 9}]);
  } finally {
    await client.close();
    await rm(directory, {recursive: true, force: true});
  }
});

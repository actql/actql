import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {open} from '../../packages/node/index.mjs';

test('public Local publishes scalar count groups within its unchanged capacity policy', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-grouped-count-capacity-'));
  const db = await open({stateDir});
  const input = 'FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x)';
  try {
    for (const [query, expected] of [
      [`SELECT x, COUNT(*) AS n ${input} GROUP BY x HAVING COUNT(*) > 1`, [{x: 1, n: 2}]],
      [`SELECT x, COUNT(*) AS n ${input} GROUP BY x ORDER BY x`, [{x: 1, n: 2}, {x: 2, n: 1}]],
      [`SELECT COUNT(*) AS n ${input}`, [{n: 3}]],
      [`SELECT x, COUNT(*) AS n ${input} GROUP BY x HAVING x = 1`, [{x: 1, n: 2}]],
      [`SELECT x, COUNT(*) AS n ${input} GROUP BY x HAVING COUNT(*) > 1`, [{x: 1, n: 2}]],
      ['SELECT 7 AS v', [{v: 7}]],
    ]) {
      assert.deepEqual(await db.sql(query, undefined, {signal: AbortSignal.timeout(20000)}).all(), expected, query);
    }
  } finally {
    await db.close();
    await rm(stateDir, {recursive: true, force: true});
  }
});

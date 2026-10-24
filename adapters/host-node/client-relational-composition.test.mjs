import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {open} from '../../packages/node/index.mjs';

// Expected rows are independent scalar/bag calculations, not engine snapshots.
test('source-free scalar compositions use checked value capacity without changing semantics', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-relational-composition-'));
  const db = await open({stateDir});
  try {
    assert.deepEqual(await db.sql('SELECT x FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) ORDER BY x LIMIT 1 OFFSET 1').all(), [{x: 2}]);
    assert.deepEqual(await db.sql('SELECT x, COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x HAVING COUNT(*) > 1').all(), [{x: 1, n: 2}]);
    assert.deepEqual(await db.aql('FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 1 |> EXTEND x * 2 AS y |> ORDER BY y DESC |> LIMIT 1 |> SELECT y').all(), [{y: 6}]);
    assert.deepEqual(await db.sql('SELECT x, b FROM (SELECT CAST(NULL AS NUMBER) AS x, TRUE AS b UNION ALL SELECT 2 AS x, CAST(NULL AS BOOLEAN) AS b UNION ALL SELECT 1 AS x, FALSE AS b) ORDER BY x NULLS LAST').all(), [{x: 1, b: false}, {x: 2, b: null}, {x: null, b: true}]);
    assert.deepEqual(await db.sql("SELECT 'wide fallback' AS s").all(), [{s: 'wide fallback'}]);
    assert.deepEqual(await db.sql('SELECT 1 AS healthy').all(), [{healthy: 1}]);
  } finally {
    await db.close();
    await rm(stateDir, {recursive: true, force: true});
  }
});

test('scalar capacity counts row containers, both join ports, repeated ports and cumulative steps', async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-relational-capacity-'));
  const db = await open({stateDir});
  const type = {type: 'number', nullable: false};
  async function execute(steps, expected) {
    const program = {version: 'actql/0.1', id: 'scalar-capacity', stages: [{id: 'main', inputs: {}, steps,
      results: {rows: {from: steps.at(-1).as, fields: ['k']}}}], results: {answer: {from: {stage: 'main', result: 'rows'}}}};
    const run = await db.start(program);
    const state = await run.wait({signal: AbortSignal.timeout(20000)});
    assert.equal(state.status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), expected);
  }
  try {
    for (const n of [50, 51, 100]) {
      const rows = Array.from({length: n}, (_, k) => ({k}));
      const values = {as: 'l', values: {schema: {k: type}, rows}};
      await execute([values], rows);
      await execute([values, {as: 'f', from: 'l', filter: 'k >= 0'},
        {as: 'd', from: 'f', derive: {m: 'k + 1'}},
        {as: 's', from: 'd', select: ['k']}], rows);
    }
    for (const n of [25, 26, 49, 50]) {
      const rows = Array.from({length: n}, (_, k) => ({k}));
      const left = {as: 'l', values: {schema: {k: type}, rows}};
      const right = {as: 'r', values: {schema: {k: type}, rows}};
      const joinStep = withName => ({as: 'j', from: 'l', join: {with: withName, kind: 'inner',
        on: [{left: 'k', right: 'k'}], max_output_rows: 100, select: {k: 'left.k'}}});
      await execute([left, right, joinStep('r')], rows);
      await execute([left, joinStep('l')], rows);
    }
  } finally {
    await db.close();
    await rm(stateDir, {recursive: true, force: true});
  }
});

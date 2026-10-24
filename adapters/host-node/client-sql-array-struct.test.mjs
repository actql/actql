import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';

async function withClient(run) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-sql-array-struct-'));
  let client;
  try {
    client = await open({stateDir: directory});
    await run(client);
  } finally {
    if (client) await client.close();
    await rm(directory, {recursive: true, force: true});
  }
}
const all = (client, sql) => client.sql(sql, undefined, {signal: AbortSignal.timeout(15000)}).all();

test('ordinary SQL array offsets and named STRUCTs execute the three refused matrix cases', async () => {
  await withClient(async client => {
    for (const [source, value] of [
      ['[1,2,3][OFFSET(0)]', 1],
      ['[1,2,3][SAFE_OFFSET(99)]', null],
      ['STRUCT(1 AS x, 2 AS y).x', 1],
    ]) assert.deepEqual(await all(client, `SELECT ${source} AS v`), [{v: value}], source);
  });
});

test('SQL offset indexes preserve NULL, integral range and SAFE failure ownership', async () => {
  await withClient(async client => {
    for (const [source, value] of [
      ['[7,8][1]', 8], ['[7,8][OFFSET(1)]', 8], ['[7,8][SAFE_OFFSET(1)]', 8],
      ['[1][SAFE_OFFSET(-1)]', null], ['[1][SAFE_OFFSET(1e100)]', null],
      ['[1][OFFSET(NULL)]', null], ['[1][SAFE_OFFSET(NULL)]', null],
      ['ARRAY<NUMBER>[][SAFE_OFFSET(0)]', null],
      ['CAST(NULL AS ARRAY<NUMBER>)[OFFSET(0)]', null],
      ['CAST(NULL AS ARRAY<NUMBER>)[OFFSET(-1)]', null],
      ['[1,CAST(NULL AS NUMBER)][OFFSET(1)]', null],
      ['[STRUCT(7 AS x)][OFFSET(0)].x', 7],
      ['IF(FALSE,[1][OFFSET(99)],7)', 7],
    ]) assert.deepEqual(await all(client, `SELECT ${source} AS v`), [{v: value}], source);
    assert.deepEqual(await all(client, 'SELECT a[OFFSET(i)] AS v FROM (SELECT [7,8] AS a,1 AS i)'), [{v:8}]);
    assert.deepEqual(await all(client, 'SELECT a[SAFE_OFFSET(i)] AS v FROM (SELECT [7,8] AS a,99 AS i)'), [{v:null}]);
    for (const source of [
      '[1][OFFSET(-1)]', '[1][OFFSET(1)]', '[1][OFFSET(1e100)]',
      'ARRAY<NUMBER>[][OFFSET(0)]', '[1][OFFSET(0.5)]', '[1][SAFE_OFFSET(0.5)]',
      '[1/0][SAFE_OFFSET(99)]', '[1][SAFE_OFFSET(1/0)]',
      'CAST(NULL AS ARRAY<NUMBER>)[SAFE_OFFSET(1/0)]',
    ]) await assert.rejects(all(client, `SELECT ${source} AS v`), {code: 'ExecutionUnsuccessful'}, source);
  });
});

test('named STRUCT construction preserves nested values and checked field access', async () => {
  await withClient(async client => {
    for (const [source, value] of [
      ['STRUCT(1 AS x,2 AS y)', {x:1,y:2}], ['STRUCT(STRUCT(7 AS z) AS x).x.z', 7],
      ['STRUCT(1+2 AS x).x', 3], ['STRUCT([3,4] AS a).a[OFFSET(1)]', 4],
      ['STRUCT(7 AS `select`).`select`', 7],
    ]) assert.deepEqual(await all(client, `SELECT ${source} AS v`), [{v: value}], source);
    await assert.rejects(all(client, 'SELECT STRUCT(1 AS x,1/0 AS y).x AS v'), {code:'ExecutionUnsuccessful'});
    for (const source of ['STRUCT(1 AS x,2 AS x)', 'STRUCT(1 AS x).absent', '[1][OFFSET(TRUE)]'])
      await assert.rejects(all(client, `SELECT ${source} AS v`), {code:'SubmissionNotAccepted'}, source);
    assert.deepEqual(await all(client, 'SELECT STRUCT(x AS y).y AS v FROM (SELECT 3 AS x)'), [{v:3}]);
  });
});

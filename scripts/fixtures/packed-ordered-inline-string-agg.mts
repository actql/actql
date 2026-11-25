import assert from 'node:assert/strict';
import {open} from '@actql/node';
import type {ClientError} from '@actql/sdk';
import {withFixtureClientCleanup} from './client-cleanup.mjs';

export async function checkOrderedInlineStringAgg(stateDir: string) {
  const db = await open({stateDir});
  await withFixtureClientCleanup(db, async () => {
    const rows = 'WITH r AS (SELECT 1 AS id, 10 AS v UNION ALL SELECT 2, 20 UNION ALL SELECT 3, 20)';
    for (const [source, value] of [
      ['FROM r |> ASSERT UNIQUE BY (id)', 'CAST(id AS STRING)'],
      ['FROM r |> EXTEND CAST(id AS STRING) AS s |> ASSERT UNIQUE BY (id)', 's'],
    ]) {
      const text = `${rows}
${source}
|> AGGREGATE STRING_AGG(${value}, ',' ORDER BY id DESC) AS ids`;
      assert.deepEqual(await db.aql(text).all(), [{ids: '3,2,1'}], text);
    }
    await assert.rejects(db.aql(
      `WITH t AS (
 SELECT 1 AS n, 'a' AS s, 10 AS v UNION ALL
 SELECT 2 AS n, 'b' AS s, 20 AS v UNION ALL
 SELECT 3 AS n, 'a' AS s, 30 AS v)
SELECT STRING_AGG(s, ',') AS x FROM t`).all(),
    (error: ClientError & {outcome: {problem: {code: string}}}) =>
      error.code === 'SubmissionNotAccepted' && error.outcome.problem.code === 'ClientProgramAggregateOrderRequired');
  });
}

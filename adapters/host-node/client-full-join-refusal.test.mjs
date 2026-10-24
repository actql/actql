import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {open} from '../../packages/node/index.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';

test('FULL Values JOIN without stable identities is a known refusal, not an unknown submission', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-full-join-refusal-'));
  const client = await open({stateDir: directory});
  try {
    const query = 'SELECT l.k AS lk, r.k AS rk FROM (SELECT 1 AS k) l ' +
      'FULL JOIN (SELECT 2 AS k) r ON l.k = r.k';
    const checked = await client.check(query, {kind: 'text', format: 'sql', scope: 'bound_input'});
    assert.equal(checked.outcome, 'completed');
    assert.equal(checked.report.verdict, 'invalid');
    assert.equal(checked.report.runnable.verdict, 'no');
    assert.ok(!JSON.stringify(checked.report).includes('check_unclassified'));
    await assert.rejects(client.startSource(query, {format: 'sql'}), error => {
      assert.equal(error.code, 'SubmissionNotAccepted');
      const outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'not_accepted');
      assert.deepEqual(outcome.problem,
        {classification: 'invalid_input', code: 'ClientProgramInvalidInput'});
      return true;
    });
    assert.deepEqual(await client.sql('SELECT 9 AS healthy').all(), [{healthy: 9}]);
  } finally {
    await client.close();
    await rm(directory, {recursive: true, force: true});
  }
});

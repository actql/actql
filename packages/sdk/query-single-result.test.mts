import assert from 'node:assert/strict';
import test from 'node:test';
import {connectInProcess} from './host-port.mjs';
import {readySubmissionAttempt, submissionEpoch} from './submission-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'single-result', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'single-result', capabilities: [], submissionEpoch,
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};

for (const entry of ['query', 'result']) {
  for (const [method, rows, options, code] of [
    ['one', [], undefined, 'ExpectedOneRow'],
    ['one', [{n: 1}, {n: 2}], undefined, 'ExpectedOneRow'],
    ['scalar', [{n: 1, other: 2}], undefined, 'ExpectedOneColumn'],
    ['one', [{n: 1}], {maxRowRetainedValueBytes: 1}, 'ResultRowRetainedLimit'],
  ]) {
    test(`${entry} ${method} retains ${code} for ${rows.length} rows`, async t => {
      const calls = [];
      const client = await connectInProcess({mode: 'local', owner: 'local'}, {
        perform(operation, body) {
          calls.push(operation);
          if (operation === 'connect') return profile;
          if (operation === 'submit-intent') return readySubmissionAttempt(body, {ref, durability: 'volatile', revision: 1});
          if (operation === 'attach') return {ref, durability: 'volatile', revision: 1};
          if (operation === 'wait') return {version: 'actql-run-state/0.1', run_id: 'single-result', revision: 1,
            status: 'succeeded', updated_at: '2026-10-21T00:00:00.000Z', result_available: true,
            next_action: {kind: 'read_result', results: ['answer']},
            result_availability: {answer: {state: 'available', reason: 'confirmed_present',
              observed_at: '2026-10-21T00:00:00.000Z'}}};
          assert.equal(operation, 'read');
          return {kind: 'rows', frames: (async function* () {
            for (const row of rows) yield {value: row, byteLength: Buffer.byteLength(JSON.stringify(row))};
          })()};
        },
      });
      t.after(() => client.close());
      const target = entry === 'query' ? client.sql('SELECT 1 AS n')
        : (await client.attach(ref)).result('answer');
      await assert.rejects(target[method](options), {code});
      assert.equal(calls.filter(x => x === 'read').length, 1);
      assert.equal(calls.filter(x => x === 'submit-intent').length, entry === 'query' ? 1 : 0);
      assert.equal(calls.filter(x => x === 'wait').length, entry === 'query' ? 1 : 0);
    });
  }
}

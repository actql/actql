import assert from 'node:assert/strict';
import {before, test} from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent} from '../../scripts/verify-local-source-runtime.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
let open, coherence;
before(async () => {
  coherence = await verifyLocalSourceRuntime(root);
  ({open} = await import('../../packages/node/index.mjs'));
});

async function assertAllRows(current, count) {
  let read = 0, sum = 0n, squares = 0n;
  for await (const row of current.result('answer0').rows()) {
    assert.deepEqual(Object.keys(row), ['v0']);
    assert.equal(row.v0, read);
    const value = BigInt(row.v0);
    read++; sum += value; squares += value * value;
  }
  const n = BigInt(count);
  assert.equal(read, count);
  assert.equal(sum, n * (n - 1n) / 2n);
  assert.equal(squares, n * (n - 1n) * (2n * n - 1n) / 6n);
}

for (const count of [1000, 10000, 10001, 100000]) {
  test(`ordinary numeric ${count} rows streams exact values before and after reopen with confirmed stop`, async () => {
    const program = {
      version: 'actql/0.1', id: 'numeric-scale',
      stages: [{id: 'main', inputs: {}, steps: [{as: 'v', values: {
        schema: {v0: {type: 'number', nullable: false}},
        rows: Array.from({length: count}, (_, v0) => ({v0})),
      }}], results: {rows: {from: 'v', fields: ['v0']}}}],
      results: {answer0: {from: {stage: 'main', result: 'rows'}}},
    };
    const directory = await mkdtemp(join(tmpdir(), 'actql-numeric-scale-test-'));
    let db = await open({stateDir: directory}), completed = false;
    try {
      const run = await db.start(program);
      const outcome = await run.wait({signal: AbortSignal.timeout(300000)});
      assert.equal(outcome.status, 'succeeded', JSON.stringify(outcome));
      await assertAllRows(run, count);
      const ref = run.ref;
      await db.close(); db = undefined;
      db = await open({stateDir: directory});
      const restored = await db.attach(ref);
      assert.equal((await restored.status()).control.physical_stop, 'confirmed');
      await assertAllRows(restored, count);
      completed = true;
    } finally {
      if (db) await db.close();
      assertSourceRuntimeReceiptCurrent(coherence);
      if (completed) await rm(directory, {recursive: true, force: true});
    }
  });
}

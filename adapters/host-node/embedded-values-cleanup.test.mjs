import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import test from 'node:test';
import {open} from '../../packages/node/index.mjs';

const exec = promisify(execFile);
const entry = new URL('../../packages/node/index.mjs', import.meta.url).href;
const rowsFor = n => Array.from({length: n}, (_, i) => ({
  customer_id: i % 100, amount: (i * 17) % 100 + 1, quantity: i % 5 + 1,
  region: ['central', 'east', 'north', 'south', 'west'][i % 5],
}));
const valuesProgram = rows => ({
  version: 'actql/0.1', id: 'finite-values-cleanup',
  stages: [{id: 'main', inputs: {}, steps: [{as: 'orders', values: {
    schema: {customer_id: {type: 'number', nullable: false},
      amount: {type: 'number', nullable: false}, quantity: {type: 'number', nullable: false},
      region: {type: 'string', nullable: false}}, rows,
  }}], results: {rows: {from: 'orders', fields: ['customer_id', 'amount', 'quantity', 'region']}}}],
  results: {answer: {from: {stage: 'main', result: 'rows'}}},
});

for (const n of [100, 500, 1000]) for (const read of [false, true]) {
  test(`finite Values ${n} closes and reopens original Result, read=${read}`, async () => {
    const stateDir = await mkdtemp(join(tmpdir(), 'actql-values-cleanup-'));
    const client = await open({stateDir, installation: {valuesMaxRows: 2000}});
    let closed = false, reopenedClosed = false;
    try {
      const expected = rowsFor(n);
      const run = await client.start(valuesProgram(expected));
      assert.equal((await run.wait({signal: AbortSignal.timeout(10000)})).status, 'succeeded');
      if (read) assert.deepEqual(await run.result('answer').all(), expected);
      await client.close();
      closed = true;
      // A fresh process can only attach to the original saved Run. No start,
      // source preparation or Compute callback exists in this consumer.
      const {stdout} = await exec(process.execPath, ['--input-type=module', '--eval', `
        import assert from 'node:assert/strict';
        import {open} from ${JSON.stringify(entry)};
        const client = await open({stateDir: process.env.CLEANUP_STATE,
          installation: {valuesMaxRows: 2000}});
        try {
          const ref = JSON.parse(process.env.CLEANUP_REF);
          const run = await client.attach(ref);
          assert.deepEqual(run.ref, ref);
          const expected = (${rowsFor.toString()})(Number(process.env.CLEANUP_ROWS));
          assert.deepEqual(await run.result('answer').all(), expected);
          console.log(expected.length);
        } finally { await client.close(); }
      `], {env: {...process.env, CLEANUP_STATE: stateDir,
        CLEANUP_REF: JSON.stringify(run.ref), CLEANUP_ROWS: String(n)}, timeout: 15000});
      assert.equal(stdout.trim(), String(n));
      reopenedClosed = true;
    } finally {
      if (!closed) await client.close().catch(() => {});
      // A failing cleanup retains its test-owned store for diagnosis; never
      // remove a pending exclusion to make a reopen assertion pass.
      if (closed && reopenedClosed) await rm(stateDir, {recursive: true, force: true});
    }
  });
}

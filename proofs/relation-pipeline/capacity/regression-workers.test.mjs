import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import test from 'node:test';
import { runCapacityRegressionWorkers } from './regression-workers.mjs';

function fixture(t, body) {
  const directory = mkdtempSync(join(tmpdir(), 'actql-capacity-workers-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const path = join(directory, 'worker.mjs');
  writeFileSync(path, `import { parentPort, workerData } from 'node:worker_threads';\n${body}`);
  return pathToFileURL(path);
}

test('at most two actual isolates overlap and every exit is joined after its result', async t => {
  const shared = new SharedArrayBuffer(12), counts = new Int32Array(shared);
  const workerURL = fixture(t, `
    const counts = new Int32Array(workerData.shared);
    const active = Atomics.add(counts, 0, 1) + 1;
    for (;;) {
      const old = Atomics.load(counts, 1);
      if (old >= active || Atomics.compareExchange(counts, 1, old, active) === old) break;
    }
    parentPort.postMessage({slot: workerData.slot, result: {status:1, stdout:'', stderr:workerData.slot, timings:{}}});
    setTimeout(() => { Atomics.sub(counts, 0, 1); Atomics.add(counts, 2, 1); }, 60);
  `);
  const slots = ['js', 'wasm', 'bytes', 'edge', 'history', 'compiler', 'core-js', 'core-wasm', 'custody-js', 'custody-wasm'];
  const states = [];
  const records = await runCapacityRegressionWorkers(slots.map(slot => ({ slot, shared })), {
    workerURL, onUpdate(records) { states.push(records.map(({ state }) => state)); },
  });
  assert.equal(counts[0], 0); assert.equal(counts[1], 2); assert.equal(counts[2], 10);
  assert.deepEqual(states[0], slots.map(() => 'unexecuted'));
  assert(states.every(state => state.filter(value => value === 'running').length <= 2));
  assert.deepEqual(records.map(({ slot }) => slot), slots);
  assert.equal(new Set(records.map(({ threadId }) => threadId)).size, 10);
  for (const record of records) {
    assert.equal(record.state, 'closed'); assert.equal(record.exitCode, 0); assert.equal(record.error, undefined);
    assert.equal(record.result.stderr, record.slot);
  }
});

test('worker exceptions, abnormal exit, missing, duplicate and foreign results never become a semantic refusal', async t => {
  const workerURL = fixture(t, `
    const result = {slot:workerData.slot, result:{status:1, stdout:'', stderr:'expected semantic text', timings:{}}};
    if (workerData.slot === 'throw') throw new Error('OriginalWorkerFailure');
    if (workerData.slot === 'exit') process.exit(17);
    if (workerData.slot !== 'missing') parentPort.postMessage({...result, slot:workerData.slot === 'foreign' ? 'other' : workerData.slot});
    if (workerData.slot === 'duplicate') parentPort.postMessage(result);
  `);
  const slots = ['throw', 'exit', 'missing', 'duplicate', 'foreign', 'healthy-worker'];
  const records = await runCapacityRegressionWorkers(slots.map(slot => ({ slot })), { workerURL });
  assert.deepEqual(records.map(({ state }) => state), slots.map(() => 'closed'));
  for (const record of records.slice(0, -1)) {
    assert.equal(record.result, undefined); assert(record.error);
  }
  assert.match(records[0].error, /OriginalWorkerFailure/);
  assert.equal(records[1].exitCode, 17);
  assert.match(records[2].error, /Missing or duplicate/);
  assert.match(records[3].error, /Missing or duplicate/);
  assert.match(records[4].error, /Foreign/);
  assert.equal(records.at(-1).exitCode, 0); assert.equal(records.at(-1).result.status, 1);
});

test('evidence errors fail only after all actual worker exits, and duplicate planned slots never launch', async t => {
  const shared = new SharedArrayBuffer(4), count = new Int32Array(shared);
  const workerURL = fixture(t, `
    parentPort.postMessage({slot:workerData.slot, result:{status:0, stdout:'', stderr:'', timings:{}}});
    setTimeout(() => { Atomics.add(new Int32Array(workerData.shared), 0, 1); }, 30);
  `);
  await assert.rejects(runCapacityRegressionWorkers(['a', 'b', 'c'].map(slot => ({ slot, shared })), {
    workerURL, onUpdate() { throw new Error('OriginalEvidenceWriteFailure'); },
  }), /evidence could not be retained/);
  assert.equal(count[0], 3);
  await assert.rejects(runCapacityRegressionWorkers([{ slot: 'a' }, { slot: 'a' }], { workerURL }), /Duplicate/);
  assert.equal(count[0], 3);
});

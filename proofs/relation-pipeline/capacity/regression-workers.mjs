import assert from 'node:assert/strict';
import { Worker } from 'node:worker_threads';

// Each negative owns a fresh isolate and full validator. Join its actual exit,
// not just a result message. Threads cannot outlive this parent process, and no
// compiler or producer child is launched by the read-only validator.
export async function runCapacityRegressionWorkers(cases, {
  workerURL = new URL('./regression-worker.mjs', import.meta.url), onUpdate = () => {},
} = {}) {
  assert.equal(new Set(cases.map(entry => entry.slot)).size, cases.length, 'Duplicate capacity regression slot');
  const records = cases.map(({ slot }) => ({ slot, state: 'unexecuted' }));
  const observerErrors = [];
  const update = () => { try { onUpdate(records); } catch (error) { observerErrors.push(error); } };
  let next = 0;
  async function run() {
    while (next < cases.length) {
      const index = next++, record = records[index];
      record.state = 'running'; record.startedAt = new Date().toISOString();
      update();
      const started = performance.now();
      await new Promise(resolve => {
        const messages = [], errors = [];
        let worker;
        try { worker = new Worker(workerURL, { workerData: cases[index] }); }
        catch (error) {
          record.error = error.stack;
          resolve(); return;
        }
        record.threadId = worker.threadId;
        worker.on('message', message => messages.push(message));
        worker.on('error', error => errors.push(error.stack));
        worker.once('exit', code => {
          record.exitCode = code;
          try {
            assert.equal(code, 0, 'Capacity regression worker did not exit normally');
            assert.deepEqual(errors, [], 'Capacity regression worker threw');
            assert.equal(messages.length, 1, 'Missing or duplicate capacity regression result');
            assert.equal(messages[0].slot, record.slot, 'Foreign capacity regression result');
            const result = messages[0].result;
            assert([0, 1].includes(result?.status) && typeof result.stdout === 'string' &&
              typeof result.stderr === 'string' && result.timings && typeof result.timings === 'object',
            'Invalid capacity regression result');
            record.result = result;
          } catch (error) { record.error = [...errors, error.stack].join('\n'); }
          resolve();
        });
      });
      record.state = 'closed'; record.closedAt = new Date().toISOString();
      record.workerMs = performance.now() - started;
      update();
    }
  }
  update();
  await Promise.all([run(), run()]);
  if (observerErrors.length) throw new AggregateError(observerErrors, 'Capacity regression evidence could not be retained');
  return records;
}

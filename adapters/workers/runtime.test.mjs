import test from 'node:test';
import assert from 'node:assert/strict';
import {createTestRuntime} from './runtime.mjs';

test('real workerd has Node compatibility disabled and rejects outbound traffic', async () => {
  let attempts = 0;
  const runtime = createTestRuntime(`
    export default {async fetch() {
      const denied = await fetch('https://must-not-resolve.invalid/');
      return Response.json({process:typeof process, Buffer:typeof Buffer, status:denied.status});
    }};
  `, () => attempts++);
  try {
    const response = await runtime.dispatchFetch('http://worker.test/');
    assert.deepEqual(await response.json(), {process:'undefined', Buffer:'undefined', status:503});
    assert.equal(attempts, 1);
  } finally { await runtime.dispose(); }
});

test('Node builtin module import is rejected by the runtime, not polyfilled', async () => {
  const runtime = createTestRuntime(`import fs from 'node:fs'; export default {
    fetch() { return new Response(String(fs)); }
  };`);
  let startup;
  try {
    await assert.rejects(runtime.ready, error => {
      startup = error;
      return error.code === 'ERR_RUNTIME_FAILURE' && /node:fs/.test(error.message);
    });
  } finally {
    // This pinned harness also propagates its failed startup through dispose.
    // Only that same startup error is acceptable; other cleanup failures fail.
    try { await runtime.dispose(); }
    catch (error) { assert.equal(error, startup); }
  }
});

test('injected module-initialization I/O fails before a Worker can serve a request', async () => {
  let outgoing = 0;
  const runtime = createTestRuntime(`
    const initialized = await fetch('https://must-not-resolve.invalid/');
    export default { fetch() { return new Response(String(initialized.status)); } };
  `, () => outgoing++);
  let startup;
  try {
    await assert.rejects(runtime.ready, error => {
      startup = error;
      return error.code === 'ERR_RUNTIME_FAILURE' && /global scope/.test(error.message);
    });
    assert.equal(outgoing,0);
  } finally {
    try { await runtime.dispose(); }
    catch (error) { assert.equal(error,startup); }
  }
});

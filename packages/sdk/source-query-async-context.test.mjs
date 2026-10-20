import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

// Async hook failures can escape ordinary Promise rejection handling. Keep the
// actual Node hook boundary in a fresh process, not in the test supervisor.
test('native short queries retain one operation when async context starts after query creation', () => {
  const child = spawnSync(process.execPath, ['--input-type=module', '--eval', `
    import assert from 'node:assert/strict';
    import {AsyncLocalStorage} from 'node:async_hooks';
    import {setImmediate} from 'node:timers/promises';
    import {sourceQuery} from ${JSON.stringify(new URL('./source-query.mjs', import.meta.url).href)};
    class ClientError extends Error {}
    const calls = {start: 0, wait: 0, read: 0};
    const context = {original: 'query-observation'};
    const storage = new AsyncLocalStorage();
    const result = {async all() {
      assert.strictEqual(storage.getStore(), context);
      calls.read++;
      await setImmediate();
      assert.strictEqual(storage.getStore(), context);
      return [{id: 1}];
    }};
    const execution = {ref: {original: 'run'}, async wait() {
      calls.wait++;
      await setImmediate();
      return {status: 'succeeded', result_availability: {answer: {state: 'available'}}};
    }, result(name) {assert.equal(name, 'answer'); return result;}};
    const retain = () => undefined;
    const query = sourceQuery(() => {
      calls.start++;
      return Promise.resolve(execution);
    }, ClientError, retain, () => {}, 'sql', 'SELECT 1 AS id', undefined,
      {requestId: 'original-query'});
    assert(query instanceof Promise);
    for (const name of ['requestId', 'all', 'one', 'scalar']) {
      const descriptor = Object.getOwnPropertyDescriptor(query, name);
      assert.equal(descriptor.writable, false);
      assert.equal(descriptor.configurable, false);
    }
    await storage.run(context, async () => {
      assert.deepEqual(await query.all(), [{id: 1}]);
      assert.strictEqual(await query, result);
      assert.strictEqual(await Promise.resolve(query), result);
      assert.strictEqual(await query.finally(() => {}), result);
      assert.equal(query.requestId, 'original-query');
    });
    assert.deepEqual(calls, {start: 1, wait: 1, read: 1});
    storage.disable();
    console.log('original-query-context-complete');
  `], {encoding: 'utf8', timeout: 15000, env: {...process.env, NODE_OPTIONS: ''}});
  assert.ifError(child.error);
  assert.equal(child.signal, null, child.stderr);
  assert.equal(child.status, 0, child.stderr);
  assert.equal(child.stdout.trim(), 'original-query-context-complete');
});

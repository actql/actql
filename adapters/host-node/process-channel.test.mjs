import test from 'node:test';
import assert from 'node:assert/strict';
import { prepareManagedExecution, startManagedExecution } from './process-channel.mjs';

const configuration = () => ({
  entry: new URL('./process-fixture.mjs', import.meta.url), run: 'owned-run',
  frames: { maxBytes: 4096, maxNodes: 100, maxDepth: 10 },
  maxRequests: 4, graceMs: 50, startupMs: 5000,
});

test('pure preparation snapshots configuration and is consumed by exactly one launch', async t => {
  const config = configuration();
  const prepared = prepareManagedExecution(config);
  config.entry.pathname = '/missing-executor.mjs';
  config.run = 'changed-run';
  config.frames.maxBytes = 1;
  const channel = await startManagedExecution(prepared);
  t.after(() => channel.close());
  assert.equal(channel.identity().run, 'owned-run');
  assert.equal((await channel.request({command: 'echo', value: 3})).value, 3);
  await assert.rejects(startManagedExecution(prepared));
});

test('managed execution uses a separate process and bounded sequential requests', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  const first = await channel.request({ command: 'echo', value: 'a' });
  assert.notEqual(first.pid, process.pid);
  assert.equal(first.value, 'a');
  const second = await channel.request({ command: 'echo', value: 'b' });
  assert.equal(second.pid, first.pid);
  assert.equal(channel.status().requests, 2);
  assert.equal(channel.cleanupHandle.status().pending, true);
  await channel.close();
  assert.equal(channel.status().exited, true);
  assert.equal(channel.cleanupHandle.status().pending, false);
});

test('invalid request is correctable without consuming the sequence', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'echo', value: 'x'.repeat(5000) }), { code: 'FrameByteLimit' });
  assert.equal(channel.status().requests, 0);
  assert.equal((await channel.request({ command: 'echo', value: 1 })).value, 1);
});

test('undefined rejection is failure and prevents another dispatch', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'undefined-failure' }), { code: 'ExecutionFailed' });
  await assert.rejects(channel.request({ command: 'echo', value: 1 }), { code: 'ExecutionNotReady' });
  await channel.close();
});

test('cancelled unstarted requests consume nothing; running cancellation retains cleanup until exit', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  await assert.rejects(channel.request({ command: 'echo', value: 1 }, AbortSignal.abort()));
  assert.equal(channel.status().requests, 0);
  const controller = new AbortController();
  const work = channel.request({ command: 'wait' }, controller.signal);
  const rejected = assert.rejects(work, { code: 'ExecutionCancelled' });
  controller.abort();
  assert.equal(channel.cleanupHandle.status().pending, true);
  await rejected;
  await channel.cleanupHandle.retry();
  assert.equal(channel.status().exited, true);
});

test('noncooperative process is terminated without pretending cancellation settled it', async t => {
  const channel = await startManagedExecution(configuration());
  t.after(() => channel.close());
  const work = channel.request({ command: 'hang' });
  const rejected = assert.rejects(work, { code: 'ExecutionExited' });
  assert.equal(channel.status().exited, false);
  await channel.close();
  await rejected;
  assert.equal(channel.status().exit.signal, 'SIGKILL');
});

test('spawn and handshake failures retain an explicit process cleanup handle', async () => {
  let error;
  try { await startManagedExecution({ ...configuration(), entry: new URL('./missing-executor.mjs', import.meta.url) }); }
  catch (caught) { error = caught; }
  assert.ok(error);
  assert.equal(typeof error.cleanupHandle.retry, 'function');
  await error.cleanupHandle.retry();
  assert.equal(error.cleanupHandle.status().pending, false);
});

for (const corrupt of ['run', 'session', 'sequence', 'extra']) {
  test(`foreign ${corrupt} response cannot authorize another request`, async t => {
    const channel = await startManagedExecution({
      ...configuration(), entry: new URL('./foreign-process-fixture.mjs', import.meta.url),
    });
    t.after(() => channel.close());
    await assert.rejects(channel.request({ corrupt }), {
      code: corrupt === 'sequence' ? 'UnexpectedExecutionMessage' : 'ForeignExecutionMessage',
    });
    assert.equal(channel.status().stopped, true);
    assert.equal(channel.status().requests, 1);
    await assert.rejects(channel.request({ corrupt }), { code: 'ExecutionNotReady' });
    await channel.cleanupHandle.retry();
    assert.equal(channel.cleanupHandle.status().pending, false);
  });
}

for (const corrupt of ['missing-usage', 'usage-run', 'usage-session', 'usage-sequence', 'usage-terminal', 'usage-duplicate']) {
  test(`delegated channel rejects ${corrupt} independently of ordinary reply contents`, async t => {
    let reports = 0;
    const channel = await startManagedExecution({...configuration(),
      entry: new URL('./foreign-process-fixture.mjs', import.meta.url),
      accounting: {limits: {planning_work: 0, attempts: 1, holdings: 0,
        transfer_bytes: 0n, retained_bytes: 0n, execution_bytes: 1n},
      report: () => { reports++; }},
    });
    t.after(() => channel.close());
    await assert.rejects(channel.request({corrupt}), {
      code: corrupt === 'missing-usage' ? 'MissingExecutionAccounting'
        : ['usage-run', 'usage-session'].includes(corrupt) ? 'ForeignExecutionMessage' : 'InvalidExecutionAccounting',
    });
    assert.equal(reports, corrupt === 'usage-duplicate' ? 1 : 0);
    await assert.rejects(channel.request({corrupt}), {code: 'ExecutionNotReady'});
  });
}

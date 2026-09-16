import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareManagedExecution, startManagedExecution} from './process-channel.mjs';

const configuration = (invoke, extra = {}) => ({
  entry: new URL('./process-fixture.mjs', import.meta.url), run: 'resource-run',
  frames: {maxBytes: 4096, maxNodes: 100, maxDepth: 10},
  maxRequests: 5, maxHostCalls: 2, graceMs: 50, startupMs: 5000,
  hostService: {invoke, cleanupHandle: {status: () => ({pending: false}), retry: async () => {}}},
  ...extra,
});

test('installed Host service is snapshotted and bound to the current process session and request', async t => {
  const calls = [];
  const config = configuration(async (payload, signal, owner) => {
    signal.throwIfAborted(); calls.push(owner); return {received: payload};
  });
  const prepared = prepareManagedExecution(config);
  config.hostService.invoke = () => assert.fail('changed service');
  const channel = await startManagedExecution(prepared);
  t.after(() => channel.close());
  for (const value of [1, 2]) {
    const result = await channel.request({command: 'host-call', value});
    assert.deepEqual({...result.value}, {received: value});
    assert.notEqual(result.pid, process.pid);
  }
  assert.deepEqual(calls, [1, 2].map(sequence => ({...channel.identity(), sequence, call: sequence})));
  assert.equal(channel.status().hostCalls, 2);
  await assert.rejects(channel.request({command: 'host-call', value: 3}), {code: 'InvalidHostServiceRequest'});
  assert.equal(calls.length, 2);
});

test('Host call failures remain failures even without an exception payload and consume their quota', async t => {
  for (const error of [undefined, null]) {
    const channel = await startManagedExecution(configuration(async () => { throw error; }));
    t.after(() => channel.close());
    assert.deepEqual({...await channel.request({command: 'host-caught', value: null})}, {failed: true});
    assert.equal(channel.status().hostCalls, 1);
    await assert.rejects(channel.request({command: 'host-call', value: null}), {code: 'ExecutionFailed'});
    assert.equal(channel.status().hostCalls, 2);
  }
});

test('cancellation waits for started Host work independently of actual worker exit', async t => {
  let entered, release, serviceSignal;
  const inside = new Promise(resolve => { entered = resolve; });
  const gate = new Promise(resolve => { release = resolve; });
  const channel = await startManagedExecution(configuration(async (_, signal) => {
    serviceSignal = signal; entered(); await gate; return null;
  }));
  t.after(async () => { release(); await channel.close(); });
  const controller = new AbortController();
  const work = channel.request({command: 'host-call', value: null}, controller.signal);
  const rejected = assert.rejects(work, {code: 'ExecutionCancelled'});
  await inside;
  controller.abort();
  await rejected;
  await channel.cleanupHandle.whenStopped();
  assert.equal(serviceSignal.aborted, true);
  assert.equal(channel.status().exited, true);
  assert.equal(channel.cleanupHandle.status().pending, true);
  release();
  await channel.close();
  assert.equal(channel.cleanupHandle.status().pending, false);
});

test('service-owned cleanup survives worker exit and only its explicit retry confirms release', async () => {
  let pending = true, retries = 0;
  const service = {invoke: async () => null,
    cleanupHandle: {status: () => ({pending}), retry: async () => { retries++; pending = false; }}};
  const channel = await startManagedExecution(configuration(service.invoke, {hostService: service}));
  await channel.request({command: 'host-call', value: null});
  await channel.close();
  assert.equal(channel.cleanupHandle.status().pending, true);
  assert.equal(retries, 0);
  assert.deepEqual(await channel.cleanupHandle.retry(), {pending: false});
  assert.equal(retries, 1);
});

test('invalid Host service installation fails pure validation and absent service cannot be invoked', async () => {
  for (const extra of [{maxHostCalls: 0}, {maxHostCalls: -1}, {hostService: {}},
    {hostService: {invoke() {}, cleanupHandle: {status() {}}}}]) {
    assert.throws(() => prepareManagedExecution(configuration(() => null, extra)),
      {code: 'InvalidExecutionConfiguration'});
  }
  const channel = await startManagedExecution(configuration(() => null, {hostService: undefined, maxHostCalls: 0}));
  try {
    await assert.rejects(channel.request({command: 'host-call', value: null}), {code: 'InvalidHostServiceRequest'});
  } finally { await channel.close(); }
});

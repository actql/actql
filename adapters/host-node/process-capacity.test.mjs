import test from 'node:test';
import assert from 'node:assert/strict';
import {createManagedProcessHost} from './process-capacity.mjs';

const limits = () => ({planning_work: 0, attempts: 8, holdings: 0,
  transfer_bytes: 0n, retained_bytes: 100n, execution_bytes: 200n});
const capacity = {retainedBytes: 100n, executionBytes: 200n};
const configuration = () => ({
  entry: new URL('./process-fixture.mjs', import.meta.url), run: 'capacity-run',
  frames: {maxBytes: 4096, maxNodes: 100, maxDepth: 10},
  maxRequests: 4, graceMs: 100, startupMs: 5000,
});

const childLimits = () => ({planning_work: 5, attempts: 2, holdings: 2,
  transfer_bytes: 20n, retained_bytes: 100n, execution_bytes: 200n});
const delegatedConfiguration = () => ({...configuration(), entry: new URL('./delegation-fixture.mjs', import.meta.url)});
const delegatedCapacity = () => ({...capacity, childLimits: childLimits()});

test('delegated process uses snapshotted subledger and returns unused quotas only after exit', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const cap = delegatedCapacity();
  const starting = host.start(delegatedConfiguration(), cap);
  cap.childLimits.attempts = 200;
  const channel = await starting;
  try {
    assert.equal(host.usage().reserved_transfer_bytes, 20n);
    assert.equal((await channel.request({command: 'limits'})).limits.attempts, 2);
    await channel.request({command: 'allocate'});
    assert.equal(host.usage().attempts, 2);
    assert.equal(host.usage().reserved_execution_bytes, 200n);
    await assert.rejects(host.start(configuration(), capacity));
    assert.equal(host.usage().attempts, 2);
  } finally { await channel.close(); }
  assert.equal(host.usage().attempts, 2);
  assert.equal(host.usage().reserved_transfer_bytes, 0n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
});

test('unknown exit consumes unreported delegated quotas without refunding provisioning', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const channel = await host.start(delegatedConfiguration(), delegatedCapacity());
  await channel.request({command: 'allocate'});
  await assert.rejects(channel.request({command: 'crash'}));
  await channel.cleanupHandle.whenStopped();
  assert.equal(host.usage().attempts, 3);
  assert.equal(host.usage().planning_work, 5);
  assert.equal(host.usage().holdings, 2);
  assert.equal(host.usage().transferred_bytes, 0n);
  assert.equal(host.usage().uncertain_transfer_bytes, 20n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  await assert.rejects(host.start(configuration(), capacity));
});

test('real child ledger refuses work beyond the delegated attempt limit', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const channel = await host.start(delegatedConfiguration(), delegatedCapacity());
  await channel.request({command: 'allocate'});
  await channel.request({command: 'allocate'});
  assert.equal(host.usage().attempts, 3);
  await assert.rejects(channel.request({command: 'allocate'}), {code: 'ExecutionFailed'});
  await channel.close();
  assert.equal(host.usage().attempts, 3);
  assert.equal(host.usage().transferred_bytes, 0n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
});

test('cancellation keeps delegated capacity until actual stop and preserves exact completed work', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const channel = await host.start(delegatedConfiguration(), delegatedCapacity());
  await channel.request({command: 'allocate'});
  const controller = new AbortController();
  const pending = channel.request({command: 'wait'}, controller.signal);
  const rejected = assert.rejects(pending, {code: 'ExecutionCancelled'});
  controller.abort();
  assert.equal(channel.status().exited, false);
  assert.equal(host.usage().reserved_execution_bytes, 200n);
  await rejected;
  await channel.close();
  assert.equal(host.usage().attempts, 2);
  assert.equal(host.usage().transferred_bytes, 0n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
});

test('invalid usage and missing accounting support cannot pass delegated admission', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const channel = await host.start(delegatedConfiguration(), delegatedCapacity());
  await assert.rejects(channel.request({command: 'invalid-report'}));
  await channel.close();
  assert.equal(host.usage().attempts, 3);
  assert.equal(host.usage().transferred_bytes, 0n);
  assert.equal(host.usage().uncertain_transfer_bytes, 20n);
  const other = await createManagedProcessHost({...childLimits(), attempts: 3});
  let failure;
  try { await other.start(configuration(), delegatedCapacity()); } catch (error) { failure = error; }
  assert(failure?.cleanupHandle);
  await failure.cleanupHandle.retry();
  assert.equal(other.usage().attempts, 3);
});

test('undersized process envelope and caller accounting fail before reservation', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const before = host.usage();
  await assert.rejects(host.start(delegatedConfiguration(), {...delegatedCapacity(), retainedBytes: 99n}));
  await assert.rejects(host.start(delegatedConfiguration(), {...delegatedCapacity(), executionBytes: 199n}));
  await assert.rejects(host.start({...delegatedConfiguration(), accounting: {}}, delegatedCapacity()));
  assert.deepEqual(host.usage(), before);
});

test('process-only settlement cannot erase independent Host service cleanup', async () => {
  const host = await createManagedProcessHost(limits());
  let pending = true;
  const channel = await host.start({...configuration(), maxHostCalls: 1,
    hostService: {invoke: async () => null, cleanupHandle: {
      status: () => ({pending}), retry: async () => { pending = false; },
    }},
  }, capacity);
  await channel.request({command: 'host-call', value: null});
  await channel.close();
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  assert.equal(host.usage().attempts, 1);
  assert.equal(channel.cleanupHandle.status().pending, true);
  assert.deepEqual(await channel.cleanupHandle.retry(), {pending: false});
});

test('process capacity is reserved before launch and retained until actual exit', async t => {
  const host = await createManagedProcessHost(limits());
  const channel = await host.start(configuration(), capacity);
  t.after(() => channel.close());
  assert.equal(host.usage().attempts, 1);
  assert.equal(host.usage().reserved_retention_bytes, 100n);
  assert.equal(host.usage().reserved_execution_bytes, 200n);
  await assert.rejects(host.start(configuration(), capacity));
  assert.equal(host.usage().attempts, 1);
  const controller = new AbortController();
  const work = channel.request({command: 'wait'}, controller.signal);
  const rejected = assert.rejects(work, {code: 'ExecutionCancelled'});
  controller.abort();
  assert.equal(channel.cleanupHandle.status().pending, true);
  assert.equal(host.usage().reserved_execution_bytes, 200n);
  await rejected;
  await channel.close();
  assert.equal(host.usage().reserved_retention_bytes, 0n);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  assert.equal(host.usage().attempts, 1);
  await channel.close();
  assert.equal(host.usage().attempts, 1);
});

test('invalid configuration and capacity have no admission charge', async () => {
  const host = await createManagedProcessHost(limits());
  const before = host.usage();
  await assert.rejects(host.start({...configuration(), startupMs: 0}, capacity));
  await assert.rejects(host.start(configuration(), {...capacity, executionBytes: 0n}));
  await assert.rejects(host.start(configuration(), capacity, AbortSignal.abort()));
  assert.deepEqual(host.usage(), before);
  await assert.rejects(createManagedProcessHost({...limits(), attempts: NaN}));
  await assert.rejects(createManagedProcessHost({...limits(), execution_bytes: 1}));
});

test('unexpected exit returns process-only capacity without requiring a cleanup retry', async t => {
  const host = await createManagedProcessHost(limits());
  const channel = await host.start(configuration(), capacity);
  t.after(() => channel.close());
  await assert.rejects(channel.request({command: 'crash'}));
  await channel.cleanupHandle.whenStopped();
  assert.equal(channel.status().exited, true);
  assert.equal(channel.status().exit.code, 9);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  assert.equal(host.usage().reserved_retention_bytes, 0n);
  assert.equal(host.usage().attempts, 1);
});

test('startup failure releases its exact reservation only when its process stops', async () => {
  const host = await createManagedProcessHost(limits());
  let failure;
  try {
    await host.start({...configuration(), entry: new URL('./missing-worker.mjs', import.meta.url)}, capacity);
  } catch (error) { failure = error; }
  assert.ok(failure?.cleanupHandle);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  assert.equal(host.usage().reserved_retention_bytes, 0n);
  assert.equal(host.usage().attempts, 1);
});

test('a failed request keeps cleanup ownership and separate Hosts do not share capacity', async t => {
  const left = await createManagedProcessHost(limits());
  const right = await createManagedProcessHost(limits());
  const a = await left.start(configuration(), capacity);
  const b = await right.start(configuration(), capacity);
  t.after(() => a.close());
  t.after(() => b.close());
  let failure;
  try { await a.request({command: 'undefined-failure'}); }
  catch (error) { failure = error; }
  assert.ok(failure?.cleanupHandle);
  await failure.cleanupHandle.retry();
  assert.equal(left.usage().reserved_execution_bytes, 0n);
  assert.equal(right.usage().reserved_execution_bytes, 200n);
  assert.equal((await b.request({command: 'echo', value: 2})).value, 2);
});

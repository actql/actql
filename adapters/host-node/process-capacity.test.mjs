import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readdir, rmdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createManagedProcessHost} from './process-capacity.mjs';
import {createProcessRetainedStore} from '../store-local/process-service.mjs';

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
  // Domain stop releases its live holding slots, not independent Store files.
  // No retained allocation was created by this worker's allocate operation.
  assert.equal(host.usage().holdings, 0);
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

test('actual writer crash settles process capacity but preserves sealed files and uncertain Store cleanup', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-capacity-store-crash-'));
  const store = createProcessRetainedStore({parentDirectory: directory,
    capacityBytes: 200, maxFrameBytes: 100, maxEntries: 2});
  const host = await createManagedProcessHost(limits());
  let channel;
  t.after(async () => {
    await channel?.close();
    await store.close();
    await store.cleanupHandle.retry();
    await rmdir(directory);
  });
  channel = await host.start({...configuration(),
    entry: new URL('../store-local/process-service-fixture.mjs', import.meta.url),
    maxHostCalls: 8, hostService: store.service,
  }, capacity);
  store.observe(channel);
  await channel.request({command: 'write', output: 'sealed'});
  assert.equal(host.usage().reserved_execution_bytes, 200n);
  assert.equal(store.status().reservedBytes, 10);
  await assert.rejects(channel.request({command: 'crash', output: 'partial'}),
    error => ['ExecutionExited', 'ExecutionChannelClosed'].includes(error.code));
  await channel.cleanupHandle.whenStopped();
  assert.equal(channel.status().exit.code, 9);
  assert.equal(host.usage().reserved_execution_bytes, 0n);
  assert.equal(host.usage().reserved_retention_bytes, 0n);
  // Store capacity is independently owned; native/process settlement cannot
  // pretend that an unreported write was zero bytes or already reclaimed.
  assert.equal(store.status().uncertainWriteBytes, 100);
  assert.equal(channel.cleanupHandle.status().pending, true);
  assert.equal(store.body('partial'), undefined);
  const sealed = store.body('sealed');
  const pieces = [];
  await sealed.consume(chunk => pieces.push(Buffer.from(chunk)));
  assert.equal(Buffer.concat(pieces).toString(), '[{"id":3}]');
  assert.deepEqual(await channel.cleanupHandle.retry(), {pending: false});
  assert.equal(store.status().reservedBytes, 10);
  assert.equal(store.status().admittedWriteBytes, 10);
  assert.equal(sealed.available(), true);
  // Retrying uncertain cleanup neither revokes nor double-frees the earlier
  // sealed file. Explicit Store close, not child exit, releases that holding.
  assert.deepEqual(await channel.cleanupHandle.retry(), {pending: false});
  await store.close();
  await store.cleanupHandle.retry();
  assert.equal(sealed.available(), false);
  assert.equal(store.status().reservedBytes, 0);
  assert.deepEqual(await readdir(directory), []);
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


test('actual child Core usage crosses worker IPC and parent Core with thirteen exact fields', async t => {
  // Logical transfer accounting only: no giant buffer or file is allocated.
  const exact = 9007199254740993n;
  const child = {...childLimits(), transfer_bytes: exact};
  const host = await createManagedProcessHost({...child, attempts: 3});
  const channel = await host.start(delegatedConfiguration(), {...capacity, childLimits: child});
  t.after(() => channel.close());
  await channel.request({command: 'read-exact'});
  assert.deepEqual(host.usage(), {
    planning_work: 0, attempts: 2, reserved_attempts: 0, holdings: 0,
    live_reservations: 2, live_delegations: 1,
    transferred_bytes: exact, uncertain_transfer_bytes: 0n, reserved_transfer_bytes: 0n,
    held_bytes: 0n, reserved_retention_bytes: 100n, reserved_execution_bytes: 200n,
    peak_retention_bytes: 100n,
  });
  await channel.close();
  assert.deepEqual(host.usage(), {
    planning_work: 0, attempts: 2, reserved_attempts: 0, holdings: 0,
    live_reservations: 0, live_delegations: 0,
    transferred_bytes: exact, uncertain_transfer_bytes: 0n, reserved_transfer_bytes: 0n,
    held_bytes: 0n, reserved_retention_bytes: 0n, reserved_execution_bytes: 0n,
    peak_retention_bytes: 100n,
  });
});

test('actual worker cannot downgrade Core usage to a legacy ten-field report', async () => {
  const host = await createManagedProcessHost({...childLimits(), attempts: 3});
  const channel = await host.start(delegatedConfiguration(), delegatedCapacity());
  try { await assert.rejects(channel.request({command: 'legacy-report'})); }
  finally { await channel.close(); }
  assert.equal(channel.cleanupHandle.status().pending, false);
  assert.equal(host.usage().attempts, 3); // Missing final accounting remains Unknown.
  assert.equal(host.usage().live_reservations, 0);
  assert.equal(host.usage().live_delegations, 0);
});


test('actual bridge reservation and delegation preserve original Start and settlement transitions', async () => {
  const runtime = await import('../../_build/js/release/build/process_host_bridge/process_host_bridge.js');
  const {checked} = await import('../host-common/runtime-result.mjs');
  for (const delegated of [false, true]) {
    const original = checked(runtime.processLedgerCreate({...childLimits(), attempts: 4}));
    const foreign = checked(runtime.processLedgerCreate({...childLimits(), attempts: 4}));
    const ticket = delegated
      ? checked(runtime.processDelegate(original, childLimits(), 100n, 200n))
      : checked(runtime.processReserve(original, 100n, 200n));
    const enter = delegated ? runtime.processDelegationStarted : runtime.processStarted;
    const reserved = runtime.processLedgerUsage(original);
    assert.equal(reserved.attempts, 0);
    assert.equal(reserved.reserved_attempts, 1);
    assert.throws(() => checked(enter(foreign, ticket)));
    assert.deepEqual(runtime.processLedgerUsage(original), reserved);
    checked(enter(original, ticket));
    const started = runtime.processLedgerUsage(original);
    assert.equal(started.attempts, 1);
    assert.equal(started.reserved_attempts, 0);
    checked(enter(original, ticket));
    assert.deepEqual(runtime.processLedgerUsage(original), started);
    if (delegated) {
      const unused = checked(runtime.processLedgerCreate(childLimits()));
      checked(runtime.processDelegationStopped(original, ticket, runtime.processLedgerUsage(unused)));
    } else checked(runtime.processStopped(original, ticket));
    const stopped = runtime.processLedgerUsage(original);
    assert.equal(stopped.attempts, 1);
    assert.equal(stopped.live_reservations, 0);
    assert.equal(stopped.live_delegations, 0);
    assert.equal(stopped.reserved_retention_bytes, 0n);
    assert.equal(stopped.reserved_execution_bytes, 0n);
    assert.throws(() => checked(enter(original, ticket)));
    assert.deepEqual(runtime.processLedgerUsage(original), stopped);
  }
});

test('actual failed physical spawn keeps its attempted provisioning debit and releases occupancy', async () => {
  for (const delegated of [false, true]) {
    const host = await createManagedProcessHost({...childLimits(), attempts: 3});
    const before = host.usage();
    await assert.rejects(host.start(delegatedConfiguration(),
      delegated ? delegatedCapacity() : capacity, AbortSignal.abort()));
    assert.deepEqual(host.usage(), before);
    let failure;
    try {
      await host.start({...delegatedConfiguration(), runtime: new URL('file:///actql-missing-physical-runtime')},
        delegated ? delegatedCapacity() : capacity);
    } catch (error) { failure = error; }
    assert.equal(failure.code, 'ExecutionSpawnFailure');
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.equal(host.usage().attempts, delegated ? 3 : 1);
    assert.equal(host.usage().reserved_attempts, 0);
    assert.equal(host.usage().live_reservations, 0);
    assert.equal(host.usage().live_delegations, 0);
    assert.equal(host.usage().reserved_retention_bytes, 0n);
    assert.equal(host.usage().reserved_execution_bytes, 0n);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdir, mkdtemp, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {installLocalRetainedStore} from './retained-store.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {createInProcessExecutionSite, executionSiteStatus,
  prepareExecutionSitePolicy} from '../host-common/execution-sites.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import * as portableRuntime from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';


const ok = value => ({$tag: 1, _0: value});
function fixture({seal = async () => {}, cleanup = async () => {}, steps = 1,
  lease} = {}) {
  const events = [], material = {}, input = {};
  let releaseCheck, closed = false, clean = false, bound = false, allocated = false, index = 0;
  let advanced = 0, stopRequested = false, stopped = false;
  const configuration = installLocalRetainedStore((key, bytes, frame) => {
    assert.equal(key, 'task-2'); assert.equal(bytes, 100); assert.equal(frame, 64);
    assert.equal(typeof releaseCheck, 'function');
    events.push('lease'); allocated = true;
    if (lease) return lease;
    return {
      status: () => ({reservedBytes: clean ? 0 : 100, cleanupPending: closed && !clean}),
      reserve: value => {
        assert.equal(value, 100);
        return {
          start: async () => {events.push('start');},
          append: async text => {events.push(['append', text]);},
          seal: async identity => {
            events.push(['seal', identity]); await seal();
            return {available: () => !closed, close() {closed = true;}, consume: async () => {}};
          },
        };
      },
      close() {closed = true; events.push('store-close');},
      async cleanup() {events.push('cleanup'); await cleanup(); clean = true;},
    };
  });
  const output = {
    key: 'task-2', limits: {wire: {max_bytes: 100}, max_batch_bytes: 64},
    install: check => {events.push('install'); releaseCheck = check; return ok();},
    begin: () => {events.push('begin'); return ok();},
    next: () => ok(index++ === 0 ? '[{"n":1}' : undefined),
    finish: () => ok({cid: `sha256:${createHash('sha256').update('[{"n":1}]').digest('hex')}`,
      bytes: 9, rows: 1, tail: ']',
      bind: available => {
        assert.equal(available(), true); events.push('bind'); bound = true;
        return ok({material, readable: read => read === input});
      },
    }),
    refresh: () => {events.push('refresh'); return ok(releaseCheck());},
  };
  const operations = {
    inputs: [], output,
    // Bounded computation: `steps` advances, each yielding to the Host.
    advance: quantum => {
      if (stopRequested) {
        stopped = true; events.push('stopped');
        return {$tag: 0, _0: new Error('Stopped')};
      }
      events.push('advance');
      advanced++;
      return ok({complete: advanced >= steps, progress: 1n, work: BigInt(Math.min(quantum, 1))});
    },
    request_cancel: () => {events.push('request-cancel'); stopRequested = true; return true;},
    execution_stopped: () => stopped,
    settle: () => {events.push('settle'); return ok();},
    complete: () => {assert(bound); events.push('complete'); return ok();},
    guard_usage: () => [0, 0, 0],
    close: () => {events.push('task-close');},
  };
  const moon = {...portableRuntime,
    strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local-test',
    strategyModule_local_NextCarrierPath: () => false,
    strategyHostNextTask: () => 2,
    strategyHostManagedProducers: () => [],
    strategyHostManagedInputCount: () => 0,
    strategyModule_local_Dispatch: () => {events.push('reserved'); return ok(operations);}};
  const entry = localStrategyContribution(moon, {}, checked, configuration);
  return {entry, events, configuration, allocated: () => allocated, released: () => releaseCheck?.()};
}

test('Local output seals exact content before completion and retains cleanup until physical confirmation', async () => {
  let allowCleanup = false;
  const f = fixture({cleanup: async () => {if (!allowCleanup) throw Error('busy');}});
  assert.equal(f.allocated(), false);
  const result = await f.entry.run({});
  assert.equal(result.diagnostic.outputRepresentation, 'retained-file');
  assert(f.events.indexOf('bind') < f.events.indexOf('complete'));
  assert(f.events.indexOf('install') < f.events.indexOf('lease'));
  let failure;
  await assert.rejects(result.close(), error => {failure = error; return true;});
  assert.equal(failure.cleanupPending, true,
    'Site holding release must recognize the retained cleanup authority');
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(f.released(), false);
  allowCleanup = true;
  await failure.cleanupHandle.retry();
  assert.equal(f.released(), true);
  assert.equal(failure.cleanupHandle.status().pending, false);
});

test('physical Local output recovery releases Site holdings and permits full capacity reuse', async () => {
  const parent = fileURLToPath(new URL('../../_build/cleanup-regressions/', import.meta.url));
  await mkdir(parent, {recursive: true});
  const directory = await mkdtemp(join(parent, 'local-output-'));
  const site = createInProcessExecutionSite({key: 'local-output-reuse',
    generation: 1, runtimeRevision: 'test/1', maxRetainedBytes: 100n,
    maxExecutionBytes: 0n});
  for (const failCleanup of ['before', 'after', undefined]) {
    const store = await createLocalRetainedStore({parentDirectory: directory,
      capacityBytes: 100, maxFrameBytes: 64, maxEntries: 1});
    let injected = failCleanup, retries = 0;
    const lease = {
      status: store.status, reserve: store.reserve, close: store.close,
      async cleanup() {
        retries++;
        if (injected === 'before') { injected = false; throw new Error('LocalCleanupInjected'); }
        const result = await store.cleanup();
        if (injected === 'after') { injected = false; throw new Error('LocalCleanupInjected'); }
        return result;
      },
    };
    const f = fixture({lease});
    const core = {
      siteControl: runtimeCore(portableRuntime).siteControl,
      count: () => 2, next: () => ({index: 1}), task: task => task.index,
      registration: () => f.entry.registration, taskCapacity: () => [100n, 0n],
      completed: () => f.events.includes('complete'),
      finished: () => f.events.includes('complete'),
      stop() {}, closeOutputs() {}, output: () => undefined,
      usage: () => ({}), explain: () => ({}),
    };
    const report = await runInstalledStrategy({}, core, [f.entry], undefined,
      undefined, prepareExecutionSitePolicy({sites: [site]}));
    assert.equal(report.status, 'host-tasks-completed', report.failure?.stack);
    assert.equal(executionSiteStatus(site).holdings, 1);
    assert.equal(executionSiteStatus(site).heldBytes, 100n);
    if (failCleanup) {
      await assert.rejects(report.close(), /LocalCleanupInjected/);
      const physicallyPending = failCleanup === 'before';
      assert.equal(report.cleanupPending(), physicallyPending);
      assert.equal(executionSiteStatus(site).holdings, physicallyPending ? 1 : 0);
      assert.equal(executionSiteStatus(site).heldBytes, physicallyPending ? 100n : 0n);
      assert.equal(store.status().reservedBytes, physicallyPending ? 9 : 0);
    } else await report.close();
    assert.equal(await report.cleanup(), true);
    assert.equal(report.cleanupPending(), false);
    assert.equal(executionSiteStatus(site).holdings, 0);
    assert.equal(executionSiteStatus(site).heldBytes, 0n);
    assert.equal(store.status().reservedBytes, 0);
    assert.deepEqual(await readdir(directory), []);
    assert.equal(f.events.filter(event => event === 'advance').length, 1);
    assert.equal(f.events.filter(event => event === 'task-close').length, 1);
    assert.equal(retries, failCleanup === 'before' ? 2 : 1);
  }
});

test('retained Store configuration excludes the in-memory managed offer', async () => {
  const f = fixture();
  assert.equal(await f.entry.prepareNext(new Map()), undefined);
  assert.equal(f.allocated(), false);
});

test('cancel during Local storage seal waits for the started work and never publishes', async () => {
  let release, entered;
  const arrived = new Promise(resolve => {entered = resolve;});
  const gate = new Promise(resolve => {release = resolve;});
  const f = fixture({seal: async () => {entered(); await gate;}});
  const controller = new AbortController();
  const work = f.entry.run({}, controller.signal);
  await arrived;
  controller.abort();
  assert.equal(f.events.includes('task-close'), false);
  release();
  let failure;
  await assert.rejects(work, error => {failure = error; return error.name === 'AbortError';});
  assert.equal(f.events.includes('complete'), false);
  assert.equal(f.events.includes('bind'), false);
  assert.equal(f.released(), false);
  assert.equal(f.events.includes('settle'), false);
  await failure.cleanupHandle.retry();
  assert.equal(f.released(), true);
  assert.equal(f.events.includes('settle'), true);
});

test('cancel during asynchronous Store acquisition never reserves or publishes',
  async () => {
    let resolveLease;
    const lease = new Promise(resolve => { resolveLease = resolve; });
    const controller = new AbortController();
    let closed = false, cleaned = false, reserves = 0;
    const store = {
      status: () => ({reservedBytes: cleaned ? 0 : 100,
        cleanupPending: closed && !cleaned}),
      reserve() { reserves++; throw new Error('UnexpectedStoreReservation'); },
      close() { closed = true; },
      async cleanup() { cleaned = true; },
    };
    const f = fixture({lease});
    const work = f.entry.run({}, controller.signal);
    await new Promise(resolve => setImmediate(resolve));
    assert.ok(f.events.includes('lease'));
    controller.abort();
    resolveLease(store);
    let failure;
    await assert.rejects(work, error => {
      failure = error;
      return error.name === 'AbortError';
    });
    assert.equal(reserves, 0);
    assert.equal(f.events.includes('complete'), false);
    await failure.cleanupHandle.retry();
    assert.equal(cleaned, true);
    assert.equal(f.released(), true);
  });

test('reasonless Store rejection remains failed and copied Local wiring is not accepted', async () => {
  const f = fixture({seal: () => Promise.reject()});
  let failure;
  await assert.rejects(f.entry.run({}), error => {failure = error; return true;});
  assert.equal(f.events.includes('complete'), false);
  assert.equal(failure.cleanupHandle.status().pending, true);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.throws(() => localStrategyContribution({}, {}, checked, {...f.configuration}), /InvalidLocalStoreConfiguration/);
});

test('abort between bounded Local advances stops computation before any Store write', async () => {
  const controller = new AbortController();
  const f = fixture({steps: 1000});
  const work = f.entry.run({}, controller.signal);
  // The computation yields to the event loop between quanta.
  while (f.events.filter(event => event === 'advance').length < 3) {
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  controller.abort();
  let failure;
  await assert.rejects(work, error => {failure = error; return error.name === 'AbortError';});
  assert(f.events.filter(event => event === 'advance').length < 1000);
  assert(f.events.indexOf('request-cancel') > 0);
  // One final advance reports the actual stop before settlement.
  assert(f.events.indexOf('stopped') > f.events.indexOf('request-cancel'));
  assert.equal(f.allocated(), false);
  assert.equal(f.events.includes('lease'), false);
  assert.equal(f.events.includes('complete'), false);
  await failure.cleanupHandle?.retry();
});

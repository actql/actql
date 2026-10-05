import test from 'node:test';
import assert from 'node:assert/strict';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {withLocalExecutionPauseHandler} from './retained-store.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {createExecutionSiteControlFixture} from '../host-common/execution-site-control.fixture.mjs';
import * as runtime from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const ok = value => ({$tag: 1, _0: value});
const pause = (waiting, settlement) => ({complete: false, waiting, settlement, progress: 0n, work: 0n});
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
function fixture(first, handler) {
  const setup = {}, registration = {}, task = {index: 1};
  let advances = 0, completed = 0, stopped = false, cancelled = false;
  let reclaim = true, closed = 0;
  const operations = {
    inputs: [],
    advance() {
      advances++;
      if (cancelled) { stopped = true; return {$tag: 0, _0: new Error('Stopped')}; }
      return ok(advances === 1 ? first : {complete: true, progress: 1n, work: 1n});
    },
    request_cancel() { cancelled = true; return true; },
    execution_stopped: () => stopped,
    settle: () => ok(),
    complete() { completed++; stopped = true; return ok(); },
    close() { closed++; },
    cleanup_refresh: () => stopped && reclaim,
    guard_usage: () => [],
  };
  const entry = localStrategyContribution({...runtime,
    strategyModule_local_Registration: () => registration,
    strategyHostRegistrationSelectionKey: () => 'local-pause',
    strategyHostTask: () => 1,
    strategyHostNextTask: () => -1,
    strategyHostManagedProducers: () => [],
    strategyModule_local_Dispatch: () => ok(operations),
    strategyModule_local_ManagedStart: () => ok(operations),
  }, setup, checked, handler === undefined ? undefined
    : withLocalExecutionPauseHandler(undefined, handler));
  return {entry, setup, registration, task,
    prepared: {task: 1, inputs: [], configuration: {}},
    advances: () => advances, completed: () => completed,
    stopped: () => stopped, closed: () => closed,
    reclaim: value => { reclaim = value; }};
}

test('Local waits for authority and Store custody without polling or replay', async () => {
  for (const waiting of [true, false]) {
    let resume;
    const ready = new Promise(resolve => { resume = resolve; });
    const f = fixture(pause(waiting, waiting ? undefined : 2), async observation => {
      assert.equal(observation.status, waiting ? 'waiting' : 'settling');
      assert.equal(observation.slot, waiting ? undefined : 2);
      assert.equal(observation.task, 1);
      await ready;
      return {action: 'resume'};
    });
    const running = f.entry.run(f.task);
    await tick();
    await tick();
    assert.equal(f.advances(), 1);
    assert.equal(f.completed(), 0);
    resume();
    await running;
    assert.equal(f.advances(), 2);
    assert.equal(f.completed(), 1);
  }
});

test('Local checkpoint pause skips success and keeps the original cleanup owner', async () => {
  const checkpoint = Object.freeze({persisted: true});
  const f = fixture(pause(true), () => ({action: 'waiting_checkpoint', checkpoint}));
  f.reclaim(false);
  const result = await f.entry.runPrepared(f.prepared);
  assert.equal(result.status, 'waiting_checkpoint');
  assert.equal(result.checkpoint, checkpoint);
  assert.equal(f.completed(), 0);
  assert.equal(f.stopped(), true);
  assert.equal(f.advances(), 2, 'one pause plus one physical stop observation');
  assert.equal(result.cleanupPending, true);
  assert.equal(result.cleanupHandle.status().pending, true);
  f.reclaim(true);
  await result.cleanupHandle.retry();
  assert.equal(result.cleanupHandle.status().pending, false);
  assert.equal(f.advances(), 2, 'cleanup never resumes Compute');
});

test('strategy returns durable Waiting and prevents every later task and publication', async () => {
  const checkpoint = Object.freeze({persisted: true});
  const f = fixture(pause(true), () => ({action: 'waiting_checkpoint', checkpoint}));
  f.reclaim(false);
  let stops = 0, dispatches = 0;
  const core = {
    siteControl: createExecutionSiteControlFixture(),
    count: () => 3,
    next: () => { dispatches++; return f.task; },
    task: () => 1, taskCapacity: () => [0n, 0n],
    registration: () => f.registration,
    completed: () => false, finished: () => false,
    stop() { stops++; }, closeOutputs() {}, output: () => undefined,
    usage: () => ({}), explain: () => ({}),
  };
  const result = await runInstalledStrategy(f.setup, core, [f.entry]);
  assert.equal(result.status, 'host-tasks-waiting');
  assert.equal(result.checkpoint, checkpoint);
  assert.equal(result.failure, undefined);
  assert.deepEqual(result.completed, []);
  assert.equal(dispatches, 1);
  assert.equal(stops, 1);
  assert.equal(result.cleanupPending(), true);
  await result.close();
  f.reclaim(true);
  assert.equal(await result.cleanup(), true);
  assert.equal(result.cleanupPending(), false);
  assert.equal(f.completed(), 0);
  await assert.rejects(result.publishEffectFreeRun({}, {}), /ReleasedStrategy/);
});

test('abort during settlement keeps Store ownership until its awaited callback settles', async () => {
  let release;
  const pending = new Promise(resolve => { release = resolve; });
  const controller = new AbortController();
  const f = fixture(pause(false, 0), async () => { await pending; return {action: 'resume'}; });
  let returned = false;
  const running = f.entry.run(f.task, controller.signal).finally(() => { returned = true; });
  await tick();
  controller.abort();
  await tick();
  assert.equal(returned, false);
  assert.equal(f.stopped(), true);
  assert.equal(f.completed(), 0);
  release();
  await assert.rejects(running, {name: 'AbortError'});
  assert.equal(f.completed(), 0);
});

test('ordinary zero-work Continue remains invalid and explicit pause requires a handler', async () => {
  for (const [observation, expected] of [
    [{complete: false, progress: 0n, work: 0n}, /InvalidLocalManagedAdvance/],
    [pause(true), /MissingLocalExecutionPauseHandler/],
  ]) {
    const f = fixture(observation);
    await assert.rejects(f.entry.run(f.task), expected);
    assert.equal(f.completed(), 0);
    assert.equal(f.stopped(), true);
  }
});

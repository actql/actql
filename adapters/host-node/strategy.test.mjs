import test from 'node:test';
import assert from 'node:assert/strict';
import {runInstalledStrategy} from '../host-common/strategy.mjs';

// Protocol test double, not semantic execution proof. Real checked/capture and
// reservation enforcement are exercised by the standard Host conformance suite.
function fixture(registrations) {
  const setup = {};
  const tasks = registrations.map((registration, i) => ({registration, index: i + 1}));
  const complete = new Set();
  let next = 0;
  let stopped = 0;
  let closed = 0;
  const core = {
    count: () => tasks.length + 1,
    next: () => tasks[next++],
    task: task => task.index,
    registration: task => task.registration,
    completed: (_, index) => complete.has(index),
    finished: () => complete.size === tasks.length,
    stop: () => { stopped++; },
    closeOutputs: () => { closed++; },
    output: (_, task) => complete.has(task) ? task : undefined,
    usage: () => ({completed: complete.size}),
    explain: () => ({completed: [...complete]}),
  };
  return {setup, core, complete, stopped: () => stopped, closed: () => closed};
}

test('opaque registrations choose installed execution without a backend classification', async () => {
  const a = {}, b = {}, c = {};
  const f = fixture([a, c, b]);
  const calls = [];
  const entries = [a, b, c].map((registration, id) => ({
    registration,
    async run(task) {
      calls.push(id);
      f.complete.add(task.index);
      return {diagnostic: {realization: `implementation-${id}`, task: 999}};
    },
  }));
  const result = await runInstalledStrategy(f.setup, f.core, entries);
  assert.equal(result.status, 'host-tasks-completed');
  assert.deepEqual(calls, [0, 2, 1]);
  assert.deepEqual(result.completed.map(value => value.task), [1, 2, 3]);
  result.close(); result.close();
  assert.equal(f.closed(), 1);
});

test('equal names in foreign registration and callback success cannot publish completion', async () => {
  const registration = {name: 'same'};
  const foreign = fixture([{name: 'same'}]);
  let called = false;
  const rejected = await runInstalledStrategy(foreign.setup, foreign.core, [{
    registration, run() { called = true; },
  }]);
  assert.equal(rejected.failure.code, 'MissingStrategyImplementation');
  assert.equal(called, false);
  const incomplete = fixture([registration]);
  const result = await runInstalledStrategy(incomplete.setup, incomplete.core, [{
    registration, async run() { return {diagnostic: {realization: 'success'}}; },
  }]);
  assert.equal(result.failure.code, 'TaskNotCompleted');
  assert.deepEqual(result.completed, []);
  assert.equal(incomplete.stopped(), 1);
});

test('installation snapshots callbacks before awaits and rejects duplicate entries', async () => {
  const registration = {};
  const f = fixture([registration]);
  let resume;
  const wait = new Promise(resolve => { resume = resolve; });
  const entry = {registration, beforeNext: () => wait, run(task) { f.complete.add(task.index); }};
  const entries = [entry];
  const running = runInstalledStrategy(f.setup, f.core, entries);
  entry.run = () => assert.fail('replaced callback');
  f.core.next = () => assert.fail('replaced core');
  entries.length = 0;
  await assert.rejects(runInstalledStrategy(f.setup, f.core, []), {code: 'StrategyAlreadyRunning'});
  resume();
  assert.equal((await running).status, 'host-tasks-completed');
  const duplicate = fixture([]);
  await assert.rejects(runInstalledStrategy(duplicate.setup, duplicate.core, [entry, entry]),
    {code: 'InvalidStrategyInstallation'});
  assert.equal(duplicate.stopped(), 0);
});

test('failure stops later tasks and cleanup confirmation does not retry execution', async () => {
  const registration = {};
  const f = fixture([registration, registration, registration]);
  let calls = 0, pending = true, retries = 0, outputClosed = 0, finished = 0;
  const cleanupHandle = {
    status: () => ({pending}),
    async retry() { retries++; pending = false; },
  };
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run(task) {
      calls++;
      if (task.index === 2) throw Object.assign(new Error('failed'), {cleanupHandle});
      f.complete.add(task.index);
      return {close() { outputClosed++; }};
    },
    finish() { finished++; },
  }]);
  assert.equal(calls, 2);
  assert.equal(finished, 1);
  assert.equal(result.output(1), 1);
  assert.equal(result.cleanupPending(), true);
  assert.equal(await result.cleanup(), true);
  assert.equal(retries, 1);
  assert.equal(calls, 2);
  result.close();
  assert.equal(outputClosed, 1);
  assert.throws(() => result.output(1), {code: 'ReleasedStrategy'});
});

test('result close attempts every release even if one implementation fails', async () => {
  const registration = {};
  const f = fixture([registration, registration]);
  const released = [];
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run(task) {
      f.complete.add(task.index);
      return {close() { released.push(task.index); if (task.index === 1) throw new Error('close'); }};
    },
  }]);
  assert.throws(() => result.close(), /close/);
  assert.deepEqual(released, [1, 2]);
  assert.equal(f.closed(), 1);
  assert.equal(result.cleanupPending(), true);
  assert.equal(await result.cleanup(), false);
  result.close();
  assert.deepEqual(released, [1, 2]);
});

test('reasonless and non-Error failures preserve the first payload across every execution phase', async () => {
  for (const phase of ['beforeNext', 'run', 'finish']) {
    for (const payload of [undefined, null, 'first failure']) {
      const registration = {}, unused = {};
      const f = fixture([registration, registration]);
      let runs = 0, finishes = 0;
      const result = await runInstalledStrategy(f.setup, f.core, [{
        registration,
        beforeNext() { if (phase === 'beforeNext') return Promise.reject(payload); },
        run(task) {
          runs++;
          if (phase === 'run') return Promise.reject(payload);
          f.complete.add(task.index);
        },
        finish() { finishes++; if (phase === 'finish') return Promise.reject(payload); },
      }, {
        registration: unused,
        run() { assert.fail('unused'); },
        finish() { finishes++; throw new Error('secondary'); },
      }]);
      assert.equal(result.status, 'host-tasks-failed');
      assert.equal(result.failure, payload);
      assert.equal(runs, phase === 'beforeNext' ? 0 : phase === 'run' ? 1 : 2);
      assert.equal(finishes, 2);
    }
  }
});

test('close recovery retains all handles, attempts every retry and never repeats releases', async () => {
  const registration = {};
  const f = fixture([registration, registration]);
  const pending = [true, true, true], retries = [0, 0, 0], closes = [0, 0, 0];
  const handles = pending.map((_, i) => ({
    status: () => ({pending: pending[i]}),
    async retry() {
      retries[i]++;
      if (i === 0 && retries[i] === 1) throw undefined;
      pending[i] = false;
    },
  }));
  const release = i => { closes[i]++; throw Object.assign(new Error(`close ${i}`), {cleanupHandle: handles[i]}); };
  f.core.closeOutputs = () => release(2);
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run(task) { f.complete.add(task.index); return {close: () => release(task.index - 1)}; },
  }]);
  assert.throws(() => result.close(), /close 0/);
  assert.throws(() => result.output(1), {code: 'ReleasedStrategy'});
  assert.deepEqual(closes, [1, 1, 1]);
  assert.equal(result.cleanupPending(), true);
  await assert.rejects(result.cleanup(), error => {
    assert.ok(error instanceof AggregateError);
    assert.deepEqual(error.errors, [undefined]);
    return true;
  });
  assert.deepEqual(retries, [1, 1, 1]);
  assert.deepEqual(pending, [true, false, false]);
  assert.equal(result.cleanupPending(), true);
  assert.equal(await result.cleanup(), true);
  assert.equal(result.cleanupPending(), false);
  result.close();
  assert.deepEqual(closes, [1, 1, 1]);
  assert.deepEqual(retries, [2, 1, 1]);
});

test('reasonless release failure remains unconfirmed without guessing a safe retry', async () => {
  for (const phase of ['output', 'core']) {
    const registration = {}, f = fixture([registration]);
    let closes = 0;
    if (phase === 'core') f.core.closeOutputs = () => { closes++; throw undefined; };
    const result = await runInstalledStrategy(f.setup, f.core, [{
      registration,
      run(task) {
        f.complete.add(task.index);
        return {close() { if (phase === 'output') { closes++; throw undefined; } }};
      },
    }]);
    let threw = false;
    try { result.close(); } catch (error) { threw = true; assert.equal(error, undefined); }
    assert.equal(threw, true);
    assert.equal(result.cleanupPending(), true);
    assert.equal(await result.cleanup(), false);
    result.close();
    assert.equal(closes, 1);
  }
});

test('concurrent cleanup calls share the same in-flight recovery', async () => {
  const registration = {}, f = fixture([registration]);
  let pending = true, retries = 0, resume;
  const wait = new Promise(resolve => { resume = resolve; });
  const handle = {status: () => ({pending}), async retry() { retries++; await wait; pending = false; }};
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run(task) { f.complete.add(task.index); return {close() { throw {cleanupHandle: handle}; }}; },
  }]);
  assert.throws(() => result.close());
  const first = result.cleanup(), second = result.cleanup();
  assert.equal(first, second);
  resume();
  assert.equal(await first, true);
  assert.equal(retries, 1);
});

test('cancellation prevents dispatch and still finalizes every installed implementation', async () => {
  const a = {}, b = {};
  const f = fixture([a, b]);
  const controller = new AbortController();
  controller.abort(new Error('cancelled before dispatch'));
  const finalized = [];
  const result = await runInstalledStrategy(f.setup, f.core, [a, b].map((registration, i) => ({
    registration,
    run() { assert.fail('cancelled task must not start'); },
    finish() { finalized.push(i); },
  })), controller.signal);
  assert.equal(result.status, 'host-tasks-failed');
  assert.equal(result.failure.message, 'cancelled before dispatch');
  assert.deepEqual(result.completed, []);
  assert.deepEqual(finalized, [0, 1]);
  assert.equal(f.stopped(), 1);
});

test('unconfirmed cleanup remains pending without destroying independently completed output', async () => {
  const a = {}, b = {};
  const f = fixture([a]);
  let pending = true, retries = 0, secondFinalized = false;
  const cleanupHandle = {
    status: () => ({pending}),
    async retry() { retries++; if (retries > 1) pending = false; },
  };
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration: a,
    run(task) { f.complete.add(task.index); },
    finish() { throw Object.assign(new Error('cleanup not confirmed'), {cleanupHandle}); },
  }, {
    registration: b,
    run() { assert.fail('unselected implementation'); },
    finish() { secondFinalized = true; },
  }]);
  assert.equal(result.status, 'host-tasks-failed');
  assert.equal(secondFinalized, true);
  assert.equal(result.output(1), 1);
  assert.equal(await result.cleanup(), false);
  assert.equal(result.cleanupPending(), true);
  assert.equal(await result.cleanup(), true);
  assert.equal(result.cleanupPending(), false);
  assert.equal(result.output(1), 1);
});

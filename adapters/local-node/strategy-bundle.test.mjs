import test from 'node:test';
import assert from 'node:assert/strict';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {registerRetainedInput} from '../store-local/representations.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {createExecutionSiteControlFixture} from
  '../host-common/execution-site-control.fixture.mjs';
import {numericStrategyContribution} from
  '../reference-compute-node/strategy-bundle.mjs';
import {registerManagedMemoryInput} from
  '../store-local/managed-memory-representations.mjs';
import {beginExecutionSiteTeardown, createInProcessExecutionSite,
  executionSiteStatus, prepareExecutionSitePolicy,
  revokeExecutionSite} from '../host-common/execution-sites.mjs';

const siteControl = createExecutionSiteControlFixture();
const ok = value => ({$tag: 1, _0: value});
const failed = value => ({$tag: 0, _0: value});
function installed(consume, completionFailure) {
  const events = [], material = {}, input = {}, task = {}, setup = {};
  registerRetainedInput(material, value => value === input, {consume},
    {maxFrameBytes: 32, wire: {max_bytes: 32}});
  const operations = {
    inputs: [{material, input,
      frames: {maxBytes: 32, maxRows: 2, maxRowBytes: 32, maxFrameBytes: 32, maxDepth: 4},
      begin: () => { events.push('begin'); return ok(); },
      charge: bytes => { events.push(['charge', bytes]); return ok(); },
      append: row => { events.push(['row', row]); return ok(); },
      finish: () => { events.push('verified'); return ok(); },
    }],
    execute: () => { events.push('execute'); return ok(); },
    settle: () => { events.push('settle'); return ok(); },
    complete: () => {
      events.push('complete');
      if (completionFailure) return {$tag: 0, _0: completionFailure};
      return ok();
    },
    close: () => { events.push('close'); },
  };
  const entry = localStrategyContribution({
    strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local-test',
    strategyModule_local_Dispatch: (owner, work) => {
      assert.equal(owner, setup); assert.equal(work, task);
      events.push('reserved'); return ok(operations);
    },
  }, setup, checked);
  return {entry, task, events};
}

test('Local contribution admits, reads, executes and completes before exposing its close operation', async () => {
  const f = installed(async accept => { await accept(new TextEncoder().encode('[{"id":3}]')); });
  const output = await f.entry.run(f.task);
  assert.deepEqual(f.events, ['reserved', 'begin', ['charge', 10n], ['row', '{"id":3}'],
    'verified', 'execute', 'settle', 'complete']);
  assert.deepEqual(output.diagnostic, {realization: 'local', importedRows: 1, importedBytes: '10'});
  output.close();
  assert.equal(f.events.at(-1), 'close');
});

test('standard Local legacy completion observes forced Site loss', async () => {
  for (const forced of [true, false]) {
    const setup = {}, registration = {}, task = {};
    const selectedSite = createInProcessExecutionSite({
      key: forced ? 'local-forced-loss' : 'local-graceful-stop',
      generation: 1,
      runtimeRevision: 'local-test-runtime/1',
    });
    let completed = false, completionCalls = 0;
    const operations = {
      inputs: [],
      execute() {
        if (forced) revokeExecutionSite(selectedSite);
        else beginExecutionSiteTeardown(selectedSite);
        return ok();
      },
      settle: () => ok(),
      complete() {
        completionCalls++;
        completed = true;
        return ok();
      },
      close() {},
    };
    const entry = localStrategyContribution({
      strategyModule_local_Registration: () => registration,
      strategyHostRegistrationSelectionKey: () => 'local-test',
      strategyHostNextTask: () => -1,
      strategyHostManagedProducers: () => [],
      strategyModule_local_Dispatch: (owner, work) => {
        assert.equal(owner, setup);
        assert.equal(work, task);
        return ok(operations);
      },
    }, setup, checked);
    const core = {
      siteControl,
      count: () => 2,
      next: () => task,
      task: () => 1,
      taskCapacity: () => [0n, 0n],
      registration: () => registration,
      completed: () => completed,
      finished: () => completed,
      stop() {},
      closeOutputs() {},
      output: () => completed ? {} : undefined,
      usage: () => ({}),
      explain: () => ({}),
    };
    const result = await runInstalledStrategy(
      setup,
      core,
      [entry],
      undefined,
      undefined,
      prepareExecutionSitePolicy({sites: [selectedSite]}),
    );
    assert.equal(result.status,
      forced ? 'host-tasks-failed' : 'host-tasks-completed');
    assert.equal(completionCalls, forced ? 0 : 1);
    assert.equal(completed, !forced);
    await result.close();
    const status = executionSiteStatus(selectedSite);
    assert.equal(status.teardownComplete, true,
      `${forced ? 'forced revocation' : 'graceful teardown'}: ${JSON.stringify(
        status,
        (_key, value) => typeof value === 'bigint' ? String(value) : value,
      )}`);
  }
});

test('Local cancellation stops before reservation or awaits the current reader before settlement', async () => {
  for (const before of [true, false]) {
    let release;
    const gate = new Promise(resolve => { release = resolve; });
    const f = installed(async () => { await gate; f.events.push('reader-returned'); });
    const controller = new AbortController();
    if (before) controller.abort();
    const work = f.entry.run(f.task, controller.signal);
    controller.abort();
    if (!before) assert.deepEqual(f.events, ['reserved', 'begin']);
    release();
    await assert.rejects(work, {name: 'AbortError'});
    assert.deepEqual(f.events, before ? [] : ['reserved', 'begin', 'reader-returned', 'close', 'settle']);
  }
});

test('reader rejection retains its cleanup handle and completion failure does not settle twice', async () => {
  for (const failure of [undefined, null, Object.assign(new Error('read'), {cleanupHandle: {}})]) {
    const f = installed(async () => { throw failure; });
    let rejected = false;
    try { await f.entry.run(f.task); }
    catch (error) { rejected = true; assert.equal(error, failure); }
    assert.equal(rejected, true);
    assert.deepEqual(f.events, ['reserved', 'begin', 'close', 'settle']);
  }
  const f = installed(async accept => { await accept(new TextEncoder().encode('[]')); }, 'capacity');
  await assert.rejects(f.entry.run(f.task), {code: 'MoonBitHostFailure'});
  assert.equal(f.events.filter(value => value === 'settle').length, 1);
  assert.equal(f.events.at(-1), 'close');
});

test('an inapplicable managed connector does not hide a capable alternative', async () => {
  for (const [localSupported, reverse] of [[false, false], [false, true],
    [true, false], [true, true]]) {
    const setup = {}, inputMaterial = {}, inputCompleted = {};
    registerManagedMemoryInput(
      inputMaterial,
      () => true,
      () => true,
      {async read() {}},
      () => {},
    );
    const registrations = {source: {}, local: {}, alternate: {}};
    const local = localStrategyContribution({
      strategyModule_local_Registration: () => registrations.local,
      strategyHostRegistrationSelectionKey: () => 'local',
      strategyHostNextTask: () => 2,
      strategyHostManagedProducers: () => [1],
      strategyHostManagedInputCount: () => 1,
      strategyHostManagedRequiresLogicalIdentity: () => ok(false),
      strategyHostReleasableManagedProducers: () => [],
      strategyModule_local_ManagedDuration: () => 1n,
      strategyModule_local_ManagedCapacity: () => [0n, 0n],
      strategyModule_local_ManagedDispatch: () => ok(
        localSupported ? {configuration: true} : undefined),
    }, setup, checked);
    let complete = false, selected, ran;
    const core = {
      siteControl,
      count: () => 3,
      taskCapacity: () => [0n, 0n],
      next: () => ({task: 1}),
      task: task => task.task,
      registration: () => registrations.source,
      nextTask: () => complete ? -1 : 2,
      managedProducers: () => complete ? [] : [1],
      selectManaged: (_, __, registration) => { selected = registration; return true; },
      managedMatches: () => true,
      completed: (_, task) => task === 1 || complete,
      finished: () => complete,
      stop: () => {}, closeOutputs: () => {},
      output: (_, task) => task === 1 ? inputCompleted : undefined,
      usage: () => ({}), explain: () => ({}),
    };
    const source = {
      registration: registrations.source,
      run() {
        return {completed: inputCompleted, material: inputMaterial};
      },
    };
    const alternate = {
      registration: registrations.alternate,
      managedSelectionKey: 'alternate',
      run() { assert.fail('legacy alternate'); },
      prepareNext(outputs) {
        return outputs.size && !localSupported
          ? {task: 2, durationMilliseconds: 1n} : undefined;
      },
      runPrepared() {
        ran = 'alternate'; complete = true;
        return {completed: {}, material: {}};
      },
    };
    const productLocal = {
      ...local,
      runPrepared() {
        ran = 'local'; complete = true;
        return {completed: {}, material: {}};
      },
    };
    const candidates = reverse
      ? [alternate, productLocal] : [productLocal, alternate];
    const result = await runInstalledStrategy(
      setup, core, [source, ...candidates],
    );
    assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
    assert.equal(ran, localSupported ? 'local' : 'alternate');
    assert.equal(selected, registrations[ran]);
  }
});

test('reference preparation propagates fatal failures instead of hiding them as unsupported', async () => {
  const setup = {}, material = {};
  registerManagedMemoryInput(
    material, () => true, () => true, {async read() {}}, () => {},
  );
  const fatal = new Error('ForeignPreparation');
  const entry = numericStrategyContribution({
    strategyModule_reference_compute_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'reference',
    strategyHostNextTask: () => 2,
    strategyHostManagedProducers: () => [1],
    strategyHostManagedRequiresLogicalIdentity: () => ok(false),
    strategyModule_reference_compute_ManagedDispatch: () => failed(fatal),
  }, setup, checked);
  await assert.rejects(
    entry.prepareNext(new Map([[1, {material, completed: {}}]])),
    error => error.code === 'MoonBitHostFailure' && error.cause === fatal,
  );
});

test('Local preparation delegates checked zero-input applicability to MoonBit', async () => {
  const setup = {}, registration = {}, configuration = {};
  const seen = [];
  const entry = localStrategyContribution({
    strategyModule_local_Registration: owner => {
      assert.equal(owner, setup);
      return registration;
    },
    strategyHostRegistrationSelectionKey: value => {
      assert.equal(value, registration);
      return 'local';
    },
    strategyHostNextTask: owner => {
      assert.equal(owner, setup);
      return 1;
    },
    strategyHostManagedProducers: owner => {
      assert.equal(owner, setup);
      return [];
    },
    strategyHostManagedInputCount: owner => {
      assert.equal(owner, setup);
      return 0;
    },
    strategyHostManagedRequiresLogicalIdentity: owner => {
      assert.equal(owner, setup);
      return ok(false);
    },
    strategyHostReleasableManagedProducers: owner => {
      assert.equal(owner, setup);
      return [];
    },
    strategyModule_local_ManagedDispatch: (owner, inputs, bytes) => {
      assert.equal(owner, setup);
      seen.push(inputs);
      assert.equal(bytes, 0n);
      return ok(configuration);
    },
    strategyModule_local_ManagedDuration: value => {
      assert.equal(value, configuration);
      return 1n;
    },
    strategyModule_local_ManagedCapacity: value => {
      assert.equal(value, configuration);
      return [0n, 0n];
    },
  }, setup, checked);
  const prepared = await entry.prepareNext(new Map());
  assert.equal(prepared.configuration, configuration);
  assert.deepEqual(prepared.inputs, []);
  assert.deepEqual(seen, [[]]);
});

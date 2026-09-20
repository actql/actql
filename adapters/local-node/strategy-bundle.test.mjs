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
import {installManagedRepresentation} from
  '../store-local/managed-memory-representations.mjs';
import {beginExecutionSiteTeardown, createInProcessExecutionSite,
  executionSiteStatus, prepareExecutionSitePolicy,
  revokeExecutionSite} from '../host-common/execution-sites.mjs';
import * as portableRuntime from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';

const siteControl = createExecutionSiteControlFixture();
const ok = value => ({$tag: 1, _0: value});
const failed = value => ({$tag: 0, _0: value});
const managedFailureAction = (
  additionalClosed,
  operationsCloseAttempted,
  operationsClosed,
  cleanupStopped,
  executionSettled,
  cleanupRefreshed,
) => {
  if (!additionalClosed) return 0;
  if (!operationsCloseAttempted) return 1;
  if (!cleanupStopped) return 2;
  if (!executionSettled) return 3;
  if (!operationsClosed) return 1;
  if (!cleanupRefreshed) return 4;
  return 5;
};
function installed(consume, completionFailure, options = {}) {
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
    close: () => {
      events.push('close');
      options.close?.();
    },
  };
  const entry = localStrategyContribution({
    ...portableRuntime,
    strategyModule_local_Registration: () => ({}),
    strategyHostRegistrationSelectionKey: () => 'local-test',
    strategyHostManagedFailureAction: managedFailureAction,
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
      strategyHostManagedFailureAction: managedFailureAction,
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

test('legacy Local defers settlement until provider cleanup is confirmed',
  async () => {
    let pending = true, retries = 0;
    const cleanupHandle = Object.freeze({
      status: () => ({pending}),
      async retry() {
        retries++;
        pending = false;
        return cleanupHandle.status();
      },
    });
    const primary = Object.assign(new Error('provider-read'), {
      cleanupPending: true,
      cleanupHandle,
    });
    const f = installed(async () => { throw primary; });
    let failure;
    try { await f.entry.run(f.task); }
    catch (error) { failure = error; }
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(f.events, ['reserved', 'begin', 'close']);

    const status = await failure.cleanupHandle.retry();
    assert.equal(retries, 1);
    assert.equal(status.pending, false);
    assert.deepEqual(f.events, ['reserved', 'begin', 'close', 'settle']);
  });

test('legacy Local preserves its primary failure when operation close fails',
  async () => {
    const primary = new Error('provider-read');
    const closeFailure = new Error('operation-close');
    let closeAttempts = 0;
    const f = installed(async () => { throw primary; }, undefined, {
      close() {
        closeAttempts++;
        if (closeAttempts === 1) throw closeFailure;
      },
    });
    let failure;
    try { await f.entry.run(f.task); }
    catch (error) { failure = error; }
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupPending, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(failure.cleanupHandle.status().errors.includes(closeFailure),
      true);
    assert.deepEqual(f.events,
      ['reserved', 'begin', 'close', 'settle']);

    const status = await failure.cleanupHandle.retry();
    assert.equal(status.pending, false);
    assert.equal(closeAttempts, 2);
    assert.deepEqual(f.events,
      ['reserved', 'begin', 'close', 'settle', 'close']);
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
      strategyHostManagedFailureAction: managedFailureAction,
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
    strategyHostManagedFailureAction: managedFailureAction,
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
    strategyHostManagedFailureAction: managedFailureAction,
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

test('standard Host runs Local with mixed memory and provider inputs',
  async () => {
    for (const memoryFirst of [true, false]) {
      const setup = {};
      const registrations = {memory: {}, file: {}, local: {}};
      const complete = new Set();
      const inputByMaterial = new Map();
      const rowsByMaterial = new Map();
      const outputs = new Map();
      const memoryMaterial = {}, fileMaterial = {};
      for (const [material, row] of [
        [memoryMaterial, '{"side":"memory"}'],
        [fileMaterial, '{"side":"file"}'],
      ]) {
        inputByMaterial.set(material, {});
        rowsByMaterial.set(material, row);
      }
      const memory = registerManagedMemoryInput(
        memoryMaterial,
        input => input === inputByMaterial.get(memoryMaterial),
        () => true,
        Object.freeze({
          async read(_file, emit) {
            await emit(rowsByMaterial.get(memoryMaterial));
          },
        }),
        () => {},
      );
      let providerUses = 0;
      const providerUse = async (
        occurrences, authorize, append, use, signal, _beforeRead, commit,
      ) => {
        providerUses++;
        signal?.throwIfAborted();
        assert.equal(occurrences.length, 1);
        assert.equal(authorize(occurrences[0].input, 0), true);
        await append(0, rowsByMaterial.get(fileMaterial));
        const provisional = await use();
        assert.equal(authorize(occurrences[0].input, 0), true);
        return typeof commit === 'function'
          ? commit(provisional)
          : provisional;
      };
      installManagedRepresentation(fileMaterial, {
        readable: input => input === inputByMaterial.get(fileMaterial),
        rowProvider: Object.freeze({async read() {}}),
        rowUse: providerUse,
      });
      const orderedMaterials = memoryFirst
        ? [memoryMaterial, fileMaterial]
        : [fileMaterial, memoryMaterial];
      const sourceEntries = orderedMaterials.map((material, offset) => {
        const task = offset + 1;
        const registration = offset === 0
          ? registrations.memory : registrations.file;
        return {
          registration,
          managedSelectionKey: `source-${task}`,
          run() { assert.fail('managed source used the legacy path'); },
          prepareNext() {
            return complete.has(task) || [...complete].some(value => value > task)
              ? undefined
              : task === (complete.has(1) ? 2 : 1)
                ? {task, inputs: [], durationMilliseconds: 0n}
                : undefined;
          },
          runPrepared() {
            complete.add(task);
            const result = {
              completed: {task},
              material,
              close: material === memoryMaterial
                ? () => memory.close()
                : () => {},
            };
            outputs.set(task, result);
            return result;
          },
        };
      });
      const appended = [[], []];
      const outputMaterial = {};
      const outputCompleted = {};
      const operations = {
        inputs: orderedMaterials.map((material, index) => ({
          input: inputByMaterial.get(material),
          append: row => { appended[index].push(row); return ok(); },
          finish: () => ok(),
        })),
        execute: () => ok(),
        settle: () => ok(),
        complete: () => { complete.add(3); return ok(outputCompleted); },
        material: () => outputMaterial,
        output_rows: () => 1,
        output_row: () => ok('{"joined":true}'),
        storage_bytes: 16,
        close() {},
      };
      const local = localStrategyContribution({
        strategyModule_local_Registration: () => registrations.local,
        strategyHostRegistrationSelectionKey: () => 'local',
        strategyHostManagedFailureAction: managedFailureAction,
        strategyHostNextTask: () => complete.has(3) ? -1 : 3,
        strategyHostManagedProducers: () => complete.has(2) ? [1, 2] : [],
        strategyHostManagedInputCount: () => 2,
        strategyHostManagedRequiresLogicalIdentity: () => ok(false),
        strategyHostReleasableManagedProducers: () => [1, 2],
        strategyModule_local_ManagedDispatch: () => ok({}),
        strategyModule_local_ManagedDuration: () => 0n,
        strategyModule_local_ManagedCapacity: () => [16n, 16n],
        strategyModule_local_ManagedStart: () => ok(operations),
        strategyHostManagedInputMatchesMaterial: (input, material) =>
          inputByMaterial.get(material) === input,
      }, setup, checked);
      const current = () => complete.has(1)
        ? complete.has(2) ? complete.has(3) ? -1 : 3 : 2
        : 1;
      const core = {
        siteControl,
        count: () => 4,
        next: () => assert.fail('managed fixture used the legacy path'),
        nextTask: current,
        managedProducers: () => current() === 3 ? [1, 2] : [],
        selectManaged: () => true,
        managedMatches: () => true,
        taskCapacity: () => [0n, 0n],
        completed: (_owner, task) => complete.has(task),
        finished: () => complete.has(3),
        stop() {},
        closeOutputs() {},
        output: () => undefined,
        usage: () => ({}),
        explain: () => ({}),
      };
      const result = await runInstalledStrategy(
        setup, core, [...sourceEntries, local],
      );
      assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
      assert.equal(providerUses, 1);
      assert.deepEqual(appended, orderedMaterials.map(material =>
        [rowsByMaterial.get(material)]));
      await result.close();
    }
  });

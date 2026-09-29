import test from 'node:test';
import assert from 'node:assert/strict';
import {localStrategyContribution} from './strategy-bundle.mjs';
import {installLocalRetainedStore} from './retained-store.mjs';
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

const completedAdvance = run => () => {
  const result = run();
  return result?.$tag === 1
    ? {$tag: 1, _0: {complete: true, progress: 0n, work: 0n}} : result;
};

const siteControl = createExecutionSiteControlFixture();
const ok = value => ({$tag: 1, _0: value});
const failed = value => ({$tag: 0, _0: value});
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
    advance: completedAdvance(() => { events.push('execute'); return ok(); }),
    guard_usage: () => options.guardUsage ?? [12, 34, 5],
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
  assert.deepEqual(output.diagnostic, {realization: 'local', importedRows: 1,
    importedBytes: '10', measuredGuardWork: 12, measuredGuardBytes: 34,
    measuredGuardNodes: 5});
  output.close();
  assert.equal(f.events.at(-1), 'close');
});

test('Local completion does not invent unavailable guard usage', async () => {
  const f = installed(async accept => { await accept(new TextEncoder().encode('[]')); },
    undefined, {guardUsage: []});
  const output = await f.entry.run(f.task);
  assert.deepEqual(output.diagnostic, {realization: 'local', importedRows: 0,
    importedBytes: '2'});
  output.close();
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
      advance() {
        if (forced) revokeExecutionSite(selectedSite);
        else beginExecutionSiteTeardown(selectedSite);
        return ok({complete: true, progress: 0n, work: 0n});
      },
      settle: () => ok(),
      guard_usage: () => [0, 0, 0],
      complete() {
        completionCalls++;
        completed = true;
        return ok();
      },
      close() {},
    };
    const entry = localStrategyContribution({
      ...portableRuntime,
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
      ...portableRuntime,
      strategyModule_local_Registration: () => registrations.local,
      strategyHostRegistrationSelectionKey: () => 'local',
      strategyHostNextTask: () => 2,
      strategyHostManagedProducers: () => [1],
      strategyHostManagedInputCount: () => 1,
      strategyHostManagedRequiresLogicalIdentity: () => ok(false),
      strategyHostReleasableManagedProducers: () => [],
      strategyModule_local_ManagedDuration: () => 1n,
      strategyModule_local_ManagedCapacity: () => [0n, 0n],
      strategyModule_local_ManagedCarrierDispatch: () => ok(
        localSupported ? {configuration: true} : undefined),
      strategyModule_local_RelationOutput: value => value,
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
    ...portableRuntime,
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

test('Local delegates zero-input and identity applicability to MoonBit', async () => {
  const setup = {}, registration = {}, configuration = {};
  const seen = [];
  let nextTask = 1;
  const entry = localStrategyContribution({
    ...portableRuntime,
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
      return nextTask;
    },
    strategyHostManagedProducers: owner => {
      assert.equal(owner, setup);
      return [];
    },
    strategyHostManagedInputCount: owner => {
      assert.equal(owner, setup);
      return 0;
    },
    strategyHostManagedRequiresLogicalIdentity: () =>
      assert.fail('JavaScript re-decided a managed identity obligation'),
    strategyHostReleasableManagedProducers: owner => {
      assert.equal(owner, setup);
      return [];
    },
    strategyModule_local_ManagedCarrierDispatch: (owner, inputs, bytes) => {
      assert.equal(owner, setup);
      seen.push(inputs);
      assert.equal(bytes, 0n);
      return ok(configuration);
    },
    strategyModule_local_RelationOutput: value => value,
    strategyModule_local_ManagedDuration: value => {
      assert.equal(value, configuration);
      return 1n;
    },
    strategyModule_local_ManagedCapacity: value => {
      assert.equal(value, configuration);
      return [0n, 0n];
    },
  }, setup, checked);
  for (const task of [1, 0]) {
    nextTask = task;
    const prepared = await entry.prepareNext(new Map());
    assert.equal(prepared.task, task);
    assert.equal(prepared.configuration, configuration);
    assert.deepEqual(prepared.inputs, []);
  }
  assert.deepEqual(seen, [[], []]);
});

test('Local keeps supplied inputs inside the MoonBit Run boundary', async () => {
  const setup = {}, registration = {}, configuration = {}, marker = {};
  const entry = localStrategyContribution({
    strategyModule_local_Registration: () => registration,
    strategyHostRegistrationSelectionKey: () => 'local',
    strategyHostNextTask: () => 1,
    strategyHostManagedProducers: () => [-1],
    strategyHostManagedInputCount: () => 1,
    strategyHostReleasableManagedProducers: () => [],
    strategyModule_local_RelationOutput: () => assert.fail('relation output'),
    strategyModule_local_CarrierOutput: () => assert.fail('carrier output'),
    strategyModule_local_CapturedRelationInput: () =>
      assert.fail('acquisition input'),
    strategyModule_local_SuppliedRelationInput: () => marker,
    strategyModule_local_ManagedCarrierDispatch: (owner, inputs, bytes) => {
      assert.equal(owner, setup);
      assert.deepEqual(inputs, [marker]);
      assert.equal(bytes, 0n);
      return ok(configuration);
    },
    strategyModule_local_ManagedUsesProvider: value => {
      assert.equal(value, configuration);
      return true;
    },
    strategyModule_local_ManagedDuration: () => 1n,
    strategyModule_local_ManagedCapacity: () => [0n, 0n],
  }, setup, checked);
  const prepared = await entry.prepareNext(new Map());
  assert.equal(prepared.configuration, configuration);
  assert.deepEqual(prepared.inputs, []);
  assert.equal(prepared.dispatchInputs[0].suppliedRelation, true);
});

test('bounded Local yields so cancellation reaches the active kernel',
  async () => {
    const setup = {}, registration = {}, configuration = {};
    const events = [];
    let cancelled = false, stopped = false, cleanupCalls = 0;
    const operations = {
      inputs: [],
      execute: () => assert.fail('bounded execution used execute'),
      advance: quantum => {
        events.push(['advance', quantum]);
        if (cancelled) {
          stopped = true;
          return failed(new Error('Stopped'));
        }
        return ok({complete: false, progress: 1n, work: 1n});
      },
      request_cancel() {
        events.push('cancel');
        cancelled = true;
        return true;
      },
      execution_stopped: () => stopped,
      settle() { events.push('settle'); return ok(); },
      close() { events.push('close'); },
      cleanup_refresh() {
        events.push('cleanup');
        cleanupCalls++;
        return stopped && cleanupCalls > 1;
      },
    };
    const entry = localStrategyContribution({
      ...portableRuntime,
      strategyModule_local_Registration: () => registration,
      strategyHostRegistrationSelectionKey: () => 'local',
      strategyHostNextTask: () => 1,
      strategyHostManagedProducers: () => [],
      strategyHostManagedInputCount: () => 0,
      strategyHostManagedRequiresLogicalIdentity: () => ok(false),
      strategyHostReleasableManagedProducers: () => [],
      strategyModule_local_ManagedCarrierDispatch: () => ok(configuration),
      strategyModule_local_RelationOutput: value => value,
      strategyModule_local_ManagedDuration: () => 1n,
      strategyModule_local_ManagedCapacity: () => [0n, 0n],
      strategyModule_local_ManagedStart: () => ok(operations),
    }, setup, checked);
    const prepared = await entry.prepareNext(new Map());
    const controller = new AbortController();
    setTimeout(() => controller.abort(), 0);
    const failure = await entry.runPrepared(prepared, controller.signal)
      .then(() => assert.fail('cancelled execution completed'), error => error);
    assert.equal(failure.name, 'AbortError');
    assert.equal(failure.cleanupPending, true);
    assert.equal(stopped, true);
    assert.equal(failure.cleanupHandle.status().pending, true);
    await failure.cleanupHandle.retry();
    assert.equal(failure.cleanupHandle.status().pending, false);
    assert.deepEqual(events, [
      ['advance', 256],
      'cancel',
      ['advance', 1],
      'close',
      'settle',
      'cleanup',
      'cleanup',
    ]);
  });

test('bounded Local yields while finalizing a completed kernel', async () => {
  const setup = {}, registration = {}, configuration = {};
  const events = [];
  let cancelled = false, cleanupCalls = 0, finalizationSteps = 0;
  const operations = {
    inputs: [],
    execute: () => assert.fail('bounded execution used execute'),
    advance: quantum => {
      events.push(['execute', quantum]);
      return ok({complete: true, progress: 1n, work: 1n});
    },
    prepare_finalization() {
      events.push('prepare-finalization');
      return ok();
    },
    advance_finalization(quantum) {
      events.push(['finalize', quantum]);
      finalizationSteps++;
      return ok({complete: false, progress: BigInt(finalizationSteps), work: 1n});
    },
    request_cancel() {
      events.push('cancel');
      cancelled = true;
      return true;
    },
    execution_stopped: () => cancelled,
    settle() { events.push('settle'); return ok(); },
    complete: () => assert.fail('cancelled finalization completed'),
    close() { events.push('close'); },
    cleanup_refresh() {
      events.push('cleanup');
      cleanupCalls++;
      return cancelled && cleanupCalls > 1;
    },
    storage_bytes: 0,
  };
  const entry = localStrategyContribution({
    ...portableRuntime,
    strategyModule_local_Registration: () => registration,
    strategyHostRegistrationSelectionKey: () => 'local',
    strategyHostNextTask: () => 1,
    strategyHostManagedProducers: () => [],
    strategyHostManagedInputCount: () => 0,
    strategyHostManagedRequiresLogicalIdentity: () => ok(false),
    strategyHostReleasableManagedProducers: () => [],
    strategyModule_local_ManagedCarrierDispatch: () => ok(configuration),
    strategyModule_local_RelationOutput: value => value,
    strategyModule_local_ManagedDuration: () => 1n,
    strategyModule_local_ManagedCapacity: () => [0n, 0n],
    strategyModule_local_ManagedStart: () => ok(operations),
  }, setup, checked);
  const prepared = await entry.prepareNext(new Map());
  const controller = new AbortController();
  setTimeout(() => controller.abort(), 0);
  const failure = await entry.runPrepared(prepared, controller.signal)
    .then(() => assert.fail('cancelled finalization completed'), error => error);
  assert.equal(failure.name, 'AbortError');
  assert.equal(finalizationSteps, 1);
  assert.equal(failure.cleanupPending, true);
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  assert.deepEqual(events, [
    ['execute', 256],
    'prepare-finalization',
    ['finalize', 32],
    'cancel',
    'close',
    'settle',
    'cleanup',
    'cleanup',
  ]);
});

test('bounded Local validates terminal execution and finalization reports',
  async () => {
    const reports = [
      {complete: true, progress: 0n, work: 257n},
      {complete: true, progress: -1n, work: 0n},
      {complete: true, progress: 0n, work: -1n},
      {complete: true, progress: 0n, work: 1},
      {complete: true, work: 0n},
    ];
    const runMalformed = async (report, finalization) => {
      const setup = {}, registration = {}, configuration = {};
      let cancelled = false;
      const operations = {
        inputs: [],
        advance: () => finalization
          ? ok({complete: true, progress: 0n, work: 0n})
          : ok(report),
        prepare_finalization: () => ok(),
        advance_finalization: () => ok(report),
        request_cancel() { cancelled = true; return true; },
        execution_stopped: () => cancelled,
        settle: () => ok(),
        complete: () => assert.fail('invalid report reached completion'),
        close() {},
        cleanup_refresh: () => true,
        carrier_material: () => undefined,
        material: () => undefined,
        storage_bytes: 0n,
      };
      const entry = localStrategyContribution({
        ...portableRuntime,
        strategyModule_local_Registration: () => registration,
        strategyHostRegistrationSelectionKey: () => 'local-invalid-report',
        strategyHostNextTask: () => 1,
        strategyHostManagedProducers: () => [],
        strategyHostManagedInputCount: () => 0,
        strategyHostManagedRequiresLogicalIdentity: () => ok(false),
        strategyHostReleasableManagedProducers: () => [],
        strategyModule_local_ManagedCarrierDispatch: () => ok(configuration),
        strategyModule_local_RelationOutput: value => value,
        strategyModule_local_ManagedDuration: () => 1n,
        strategyModule_local_ManagedCapacity: () => [0n, 0n],
        strategyModule_local_ManagedStart: () => ok(operations),
      }, setup, checked);
      const prepared = await entry.prepareNext(new Map());
      return entry.runPrepared(prepared).then(
        () => assert.fail('invalid terminal report was accepted'),
        error => error,
      );
    };
    for (const report of reports) {
      assert.equal(
        (await runMalformed(report, false)).message,
        'InvalidLocalManagedAdvance',
      );
      assert.equal(
        (await runMalformed(report, true)).message,
        'InvalidLocalManagedFinalizationAdvance',
      );
    }
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
      let advances = 0;
      const operations = {
        inputs: orderedMaterials.map((material, index) => ({
          input: inputByMaterial.get(material),
          append: row => { appended[index].push(row); return ok(); },
          finish: () => ok(),
        })),
        execute: () => assert.fail('bounded managed execution used execute'),
        advance: quantum => {
          assert.equal(quantum, 256);
          advances++;
          return ok({complete: advances === 2, progress: 1n, work: 1n});
        },
        request_cancel: () => false,
        execution_stopped: () => advances >= 2,
        settle: () => ok(),
        complete: () => { complete.add(3); return ok(outputCompleted); },
        material: () => outputMaterial,
        output_rows: () => 1,
        output_row: () => ok('{"joined":true}'),
        storage_bytes: 16,
        close() {},
      };
      const local = localStrategyContribution({
        ...portableRuntime,
        strategyModule_local_Registration: () => registrations.local,
        strategyHostRegistrationSelectionKey: () => 'local',
        strategyHostNextTask: () => complete.has(3) ? -1 : 3,
        strategyHostManagedProducers: () => complete.has(2) ? [1, 2] : [],
        strategyHostManagedInputCount: () => 2,
        strategyHostManagedRequiresLogicalIdentity: () => ok(false),
        strategyHostReleasableManagedProducers: () => [1, 2],
        strategyModule_local_ManagedCarrierDispatch: () => ok({}),
        strategyModule_local_RelationOutput: value => value,
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
      assert.equal(advances, 2);
      assert.deepEqual(appended, orderedMaterials.map(material =>
        [rowsByMaterial.get(material)]));
      await result.close();
    }
  });

test('standard Local dispatches a Carrier input to a Carrier output',
  async () => {
    const setup = {};
    const registration = {};
    const inputCompleted = {};
    const inputMaterial = {};
    const outputCompleted = {};
    const outputMaterial = {};
    const configuration = {};
    const wrappedInput = {};
    const outputs = new Map([[1, {
      completed: inputCompleted,
      carrierMaterial: inputMaterial,
      close() {},
    }]]);
    let settled = false;
    let closed = false;
    const operations = {
      inputs: [],
      advance: quantum => {
        assert.equal(quantum, 256);
        return ok({complete: true, progress: 1n, work: 1n});
      },
      request_cancel: () => false,
      execution_stopped: () => true,
      settle: () => { settled = true; return ok(); },
      complete_carrier: () => {
        assert.equal(settled, true);
        return ok(outputCompleted);
      },
      carrier_material: () => outputMaterial,
      material: () => undefined,
      storage_bytes: 32n,
      close: () => { closed = true; },
    };
    const local = localStrategyContribution({
      ...portableRuntime,
      strategyModule_local_Registration: () => registration,
      strategyHostRegistrationSelectionKey: () => 'local-carrier',
      strategyHostNextTask: () => 2,
      strategyHostManagedProducers: () => [1],
      strategyHostManagedInputCount: () => 1,
      strategyHostReleasableManagedProducers: () => [1],
      strategyModule_local_RelationOutput: () =>
        assert.fail('Carrier input was wrapped as a Relation'),
      strategyModule_local_CarrierOutput: (completed, material) => {
        assert.equal(completed, inputCompleted);
        assert.equal(material, inputMaterial);
        return wrappedInput;
      },
      strategyModule_local_ManagedCarrierDispatch: (
        owner, inputs, outputBytes,
      ) => {
        assert.equal(owner, setup);
        assert.deepEqual(inputs, [wrappedInput]);
        assert.equal(outputBytes, 0n);
        return ok(configuration);
      },
      strategyModule_local_ManagedDuration: value => {
        assert.equal(value, configuration);
        return 0n;
      },
      strategyModule_local_ManagedCapacity: value => {
        assert.equal(value, configuration);
        return [32n, 16n];
      },
      strategyModule_local_ManagedStart: value => {
        assert.equal(value, configuration);
        return ok(operations);
      },
    }, setup, checked);
    const prepared = await local.prepareNext(outputs);
    assert.equal(prepared.task, 2);
    const result = await local.runPrepared(prepared);
    assert.equal(result.completed, outputCompleted);
    assert.equal(result.carrierMaterial, outputMaterial);
    assert.equal(result.diagnostic.outputRepresentation,
      'managed-local-carrier');
    assert.equal(settled, true);
    result.close();
    assert.equal(closed, true);
  });

test('configured row Store selects typed Carrier paths',
  async () => {
    const setup = {};
    const configuration = {};
    const carrierMaterial = {};
    const completed = {};
    let storeCalls = 0;
    const store = installLocalRetainedStore(() => {
      storeCalls++;
      assert.fail('a Carrier generation is not a retained row file');
    });
    let carrierPath = true;
    const local = localStrategyContribution({
      ...portableRuntime,
      strategyModule_local_Registration: () => ({}),
      strategyHostRegistrationSelectionKey: () => 'local-carrier',
      strategyHostNextTask: () => 1,
      strategyModule_local_NextCarrierPath: () => carrierPath,
      strategyHostManagedProducers: () => [],
      strategyHostManagedInputCount: () => 0,
      strategyHostReleasableManagedProducers: () => [],
      strategyModule_local_ManagedCarrierDispatch: () => ok(configuration),
      strategyModule_local_ManagedDuration: () => 0n,
      strategyModule_local_ManagedCapacity: () => [32n, 16n],
      strategyModule_local_ManagedStart: () => ok({
        inputs: [],
        advance: () => ok({complete: true, progress: 1n, work: 1n}),
        request_cancel: () => false,
        execution_stopped: () => true,
        settle: () => ok(),
        complete_carrier: () => ok(completed),
        carrier_material: () => carrierMaterial,
        material: () => undefined,
        storage_bytes: 32n,
        close() {},
      }),
    }, setup, checked, store);
    const prepared = await local.prepareNext(new Map());
    assert.equal(prepared.task, 1);
    const result = await local.runPrepared(prepared);
    assert.equal(result.completed, completed);
    assert.equal(result.carrierMaterial, carrierMaterial);
    assert.equal(result.diagnostic.outputRepresentation,
      'managed-local-carrier');
    assert.equal(storeCalls, 0);
    result.close();
    carrierPath = false;
    assert.equal(await local.prepareNext(new Map()), undefined);
  });

test('standard Host retains an exact Carrier across task dispatch', async () => {
  const setup = {};
  const complete = new Set();
  const sourceRegistration = {};
  const localRegistration = {};
  const inputCompleted = {};
  const inputMaterial = {};
  const outputCompleted = {};
  const outputMaterial = {};
  const configuration = {};
  const wrappedInput = {};
  let sourceClosed = false;
  let outputClosed = false;
  const current = () => complete.has(1) ? complete.has(2) ? -1 : 2 : 1;
  const source = {
    registration: sourceRegistration,
    managedSelectionKey: 'carrier-source',
    run() { assert.fail('Carrier source used the legacy path'); },
    prepareNext() {
      return current() === 1
        ? {task: 1, inputs: [], durationMilliseconds: 0n}
        : undefined;
    },
    runPrepared() {
      complete.add(1);
      return {
        completed: inputCompleted,
        carrierMaterial: inputMaterial,
        close() { sourceClosed = true; },
      };
    },
  };
  const operations = {
    inputs: [],
    advance: quantum => {
      assert.equal(quantum, 256);
      return ok({complete: true, progress: 1n, work: 1n});
    },
    request_cancel: () => false,
    execution_stopped: () => true,
    settle: () => ok(),
    complete_carrier: () => {
      complete.add(2);
      return ok(outputCompleted);
    },
    carrier_material: () => outputMaterial,
    material: () => undefined,
    storage_bytes: 32n,
    close: () => { outputClosed = true; },
  };
  const local = localStrategyContribution({
    ...portableRuntime,
    strategyModule_local_Registration: () => localRegistration,
    strategyHostRegistrationSelectionKey: () => 'local-carrier',
    strategyHostNextTask: current,
    strategyHostManagedProducers: () => current() === 2 ? [1] : [],
    strategyHostManagedInputCount: () => current() === 2 ? 1 : 0,
    strategyHostReleasableManagedProducers: () => [1],
    strategyModule_local_RelationOutput: () =>
      assert.fail('Carrier input was wrapped as a Relation'),
    strategyModule_local_CarrierOutput: (completed, material) => {
      assert.equal(completed, inputCompleted);
      assert.equal(material, inputMaterial);
      return wrappedInput;
    },
    strategyModule_local_ManagedCarrierDispatch: () =>
      ok(current() === 2 ? configuration : undefined),
    strategyModule_local_ManagedDuration: value => {
      assert.equal(value, configuration);
      return 0n;
    },
    strategyModule_local_ManagedCapacity: value => {
      assert.equal(value, configuration);
      return [32n, 16n];
    },
    strategyModule_local_ManagedStart: value => {
      assert.equal(value, configuration);
      return ok(operations);
    },
  }, setup, checked);
  const core = {
    siteControl,
    count: () => 3,
    next: () => assert.fail('Carrier fixture used the legacy path'),
    nextTask: current,
    managedProducers: () => current() === 2 ? [1] : [],
    selectManaged: () => true,
    managedMatches: () => assert.fail('Carrier used Relation completion'),
    managedCarrierMatches: (_owner, task, completed) =>
      task === 1
        ? completed === inputCompleted
        : task === 2 && completed === outputCompleted,
    taskCapacity: () => [0n, 0n],
    completed: (_owner, task) => complete.has(task),
    finished: () => complete.has(2),
    stop() {},
    closeOutputs() {},
    output: () => undefined,
    usage: () => ({}),
    explain: () => ({}),
  };
  const result = await runInstalledStrategy(setup, core, [source, local]);
  assert.equal(result.status, 'host-tasks-completed', result.failure?.stack);
  assert.equal(sourceClosed, true);
  assert.equal(outputClosed, false);
  await result.close();
  assert.equal(outputClosed, true);
});

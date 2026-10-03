import test from 'node:test';
import assert from 'node:assert/strict';
import {runInstalledStrategy} from '../host-common/strategy.mjs';
import {finalizerCase, asynchronousCloseCase} from './finalizer-fixture.mjs';
import {installCompletionObserver, completionObserver} from '../host-common/completion-observer.mjs';
import {beginExecutionSiteTeardown, createInProcessExecutionSite,
  executionSiteStatus, prepareExecutionSitePolicy,
  revokeExecutionSite} from
  '../host-common/execution-sites.mjs';
import {managedMemoryTransferContract} from
  '../store-local/managed-memory-transfer.mjs';
import {createExecutionSiteControlFixture} from
  '../host-common/execution-site-control.fixture.mjs';
import {accountEntry, fixtureAuthorization} from './authorization-fixture.mjs';

const siteControl = createExecutionSiteControlFixture();

test('scoped Host observes asynchronous close failures even after recovery succeeds', async () => {
  for (const kind of ['undefined', 'null', 'recoverable']) {
    assert.deepEqual(await asynchronousCloseCase(kind), {failed: true, firstPreserved: true,
      pending: kind !== 'recoverable', closed: 1, retries: kind === 'recoverable' ? 1 : 0});
  }
});

test('finalizer failure without a retry handle retains its owner on direct and scoped Hosts', async () => {
  for (const kind of ['error', 'undefined', 'null']) {
    assert.deepEqual(await finalizerCase(kind), {
      failed: true, firstPreserved: true, output: 1, pending: true,
      cleanups: [false, false], cleanup: false, finished: 2, closed: 1,
    });
    assert.deepEqual(await finalizerCase(kind, true), {
      failed: true, firstPreserved: true, pending: true, cleanup: false,
      finished: 2, closed: 1, consumed: 0,
    });
  }
});

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
    siteControl,
    count: () => tasks.length + 1,
    next: () => tasks[next++],
    task: task => task.index,
    taskCapacity: () => [0n, 0n],
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

test('installed completion observer receives the exact core output only after publication', async () => {
  const registration = {}, f = fixture([registration]);
  const output = {}, fake = {}, seen = [];
  f.core.output = () => output;
  const installed = installCompletionObserver(value => { seen.push(value); });
  assert.throws(() => completionObserver({...installed}), /ForeignCompletionObserver/);
  assert.throws(() => completionObserver(() => {}), /ForeignCompletionObserver/);
  const result = await runInstalledStrategy(f.setup, f.core, [{registration,
    run() { f.complete.add(1); return {output: fake, diagnostic: {output: fake}}; },
  }], undefined, completionObserver(installed));
  assert.equal(result.status, 'host-tasks-completed');
  assert.equal(seen.length, 1);
  assert.equal(seen[0].task, 1);
  assert.equal(seen[0].output, output);
  assert(Object.isFrozen(seen[0]));
  result.close();
});

test('installed Host snapshots the checked Program and Result inventory', async () => {
  const registration = {}, f = fixture([registration]);
  const programDefinitionCid = `sha256:${'1'.repeat(64)}`;
  const inventory = [
    {
      name: 'first',
      task: 1,
      definition: {
        program_definition_cid: programDefinitionCid,
        result_definition_cid:
          'sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966',
        result_name: 'first',
        version: 'actql-result-definition/0.1',
      },
    },
    {
      name: 'second',
      task: 1,
      definition: {
        program_definition_cid: programDefinitionCid,
        result_definition_cid:
          'sha256:e11eba03bcf3d0704ba0f54930d687a118b5a14875f160a46ccc189e142b2ae2',
        result_name: 'second',
        version: 'actql-result-definition/0.1',
      },
    },
  ];
  f.core.programDefinitionCid = () => programDefinitionCid;
  f.core.resultInventory = () => inventory;
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run() { f.complete.add(1); },
  }]);
  inventory[0].name = 'changed';
  inventory.push({name: 'third', task: 1});
  assert.equal(result.programDefinitionCid, programDefinitionCid);
  assert.deepEqual(result.resultInventory, [
    {name: 'first', task: 1},
    {name: 'second', task: 1},
  ]);
  assert.deepEqual(
    result.publicationInventory.occurrences.map(value => ({
      name: value.name,
      task: value.task,
      programDefinitionCid: value.definition.program_definition_cid,
    })),
    [
      {name: 'first', task: 1, programDefinitionCid},
      {name: 'second', task: 1, programDefinitionCid},
    ],
  );
  assert.deepEqual(
    result.publicationInventory.requestInventory.map(value =>
      value.result_name),
    ['first', 'second'],
  );
  assert(Object.isFrozen(result.resultInventory));
  assert(result.resultInventory.every(Object.isFrozen));
  assert(Object.isFrozen(result.publicationInventory));
  result.close();
});

test('publication preflight finishes before any Compute contribution starts',
  async () => {
    const registration = {};
    const admitted = fixture([registration]);
    const programDefinitionCid = `sha256:${'1'.repeat(64)}`;
    admitted.core.programDefinitionCid = () => programDefinitionCid;
    admitted.core.resultInventory = () => [{
      name: 'answer',
      task: 1,
      definition: {
        program_definition_cid: programDefinitionCid,
        result_definition_cid: `sha256:${'2'.repeat(64)}`,
        result_name: 'answer',
        version: 'actql-result-definition/0.1',
      },
      definitionContract: Object.freeze({name: 'result_definition'}),
    }];
    let runs = 0;
    const preflight = Object.freeze({kind: 'publication-preflight'});
    const result = await runInstalledStrategy(
      admitted.setup,
      admitted.core,
      [{
        registration,
        run() {
          runs++;
          admitted.complete.add(1);
        },
      }],
      undefined,
      undefined,
      undefined,
      facts => {
        assert.equal(runs, 0);
        assert.equal(facts.programDefinitionCid, programDefinitionCid);
        assert.deepEqual(facts.resultInventory, [
          {name: 'answer', task: 1},
        ]);
        assert.equal(facts.publicationInventory.occurrences.length, 1);
        return preflight;
      },
    );
    assert.equal(runs, 1);
    assert.equal(result.publicationPreflight, preflight);
    result.close();

    const rejected = fixture([registration]);
    rejected.core.programDefinitionCid = () => programDefinitionCid;
    rejected.core.resultInventory = admitted.core.resultInventory;
    let rejectedRuns = 0;
    await assert.rejects(runInstalledStrategy(
      rejected.setup,
      rejected.core,
      [{
        registration,
        run() {
          rejectedRuns++;
          rejected.complete.add(1);
        },
      }],
      undefined,
      undefined,
      undefined,
      () => { throw new Error('publication capacity rejected'); },
    ), /publication capacity rejected/u);
    assert.equal(rejectedRuns, 0);
    assert.equal(rejected.stopped(), 1);
  });

test('standard Host owns publication control and exact execution binding', async () => {
  const registration = {}, f = fixture([registration]);
  const programDefinitionCid = `sha256:${'1'.repeat(64)}`;
  f.core.programDefinitionCid = () => programDefinitionCid;
  f.core.resultInventory = () => [{
    name: 'answer',
    task: 1,
    definition: {
      program_definition_cid: programDefinitionCid,
      result_definition_cid:
        'sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966',
      result_name: 'answer',
      version: 'actql-result-definition/0.1',
    },
    definitionContract: Object.freeze({
      name: 'result_definition',
      identity:
        'sha256:33cc81bf0c5e877d80d3dacf71d80fb8ef5472d6e224c83efac057853e67d966',
      wire: '{}',
    }),
  }];
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run() { f.complete.add(1); },
  }]);
  await assert.rejects(
    result.publishEffectFreeRun({}, {control: {}}, undefined),
    {code: 'InvalidRunPublicationRequest'},
  );
  await assert.rejects(
    result.publishEffectFreeRun({}, {}, undefined),
    {code: 'InvalidRunPublicationPreflight'},
  );
  result.close();
  await assert.rejects(
    result.publishEffectFreeRun({}, {}, undefined),
    {code: 'ReleasedStrategy'},
  );
});

test('Effectful computation cannot use Effect-free publication', async () => {
  const registration = {}, f = fixture([registration]);
  f.core.programHasEffects = () => true;
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run() { f.complete.add(1); },
  }]);
  await assert.rejects(
    result.publishEffectFreeRun({}, {}, undefined),
    {code: 'EffectfulProgramRequiresEffectRun'},
  );
  result.close();
});

test('checked Results cannot lose their Program Definition identity', async () => {
  const registration = {}, f = fixture([registration]);
  f.core.resultInventory = () => [{name: 'r', task: 1, definition: {}}];
  await assert.rejects(
    runInstalledStrategy(f.setup, f.core, [{
      registration,
      run() { f.complete.add(1); },
    }]),
    {code: 'InvalidCheckedResultInventory'},
  );
});

test('resolved connector callback without common completion cannot issue an observed output', async () => {
  const registration = {}, f = fixture([registration]);
  let observed = 0;
  const result = await runInstalledStrategy(f.setup, f.core, [{registration, run() { return {output: {}}; }}],
    undefined, () => { observed++; });
  assert.equal(result.failure.code, 'TaskNotCompleted');
  assert.equal(observed, 0);
  result.close();
});

test('failed completion delivery stops future work but preserves completed output and cleanup responsibility', async () => {
  for (const reason of [undefined, null, new Error('delivery failed')]) {
    const registration = {}, f = fixture([registration, registration]);
    let started = 0, finished = 0;
    const result = await runInstalledStrategy(f.setup, f.core, [{registration,
      run(task) { started++; f.complete.add(task.index); }, finish() { finished++; },
    }], undefined, () => Promise.reject(reason));
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.failure, reason);
    assert.equal(started, 1);
    assert.equal(finished, 1);
    assert.equal(result.completed.length, 1);
    assert.equal(result.output(1), 1);
    assert.equal(result.cleanupPending(), true);
    result.close();
    assert.equal(await result.cleanup(), false);
  }
});

test('cancellation while delivering completed output cannot start another task', async () => {
  const registration = {}, f = fixture([registration, registration]);
  const controller = new AbortController();
  let entered, release, started = 0;
  const observing = new Promise(resolve => { entered = resolve; });
  const waiting = new Promise(resolve => { release = resolve; });
  const pending = runInstalledStrategy(f.setup, f.core, [{registration,
    run(task) { started++; f.complete.add(task.index); },
  }], controller.signal, async () => { entered(); await waiting; });
  await observing;
  controller.abort();
  release();
  const result = await pending;
  assert.equal(result.status, 'host-tasks-failed');
  assert.equal(started, 1);
  assert.equal(result.output(1), 1);
  assert.equal(result.cleanupPending(), false);
  result.close();
});

test('cancellation after preparation or task selection stops normal work but finalizes all entries', async () => {
  for (const phase of ['preparation','dispatch']) {
    const registration = {}, f = fixture([registration]);
    const abort = new AbortController();
    let resumes, preparations = 0, executions = 0, finishes = 0;
    const wait = new Promise(resolve => { resumes = resolve; });
    if (phase === 'dispatch') {
      const next = f.core.next;
      f.core.next = () => { abort.abort(); return next(); };
    }
    const entries = [registration,{}].map((registration,index) => ({
      registration,
      async beforeNext() { preparations++; if (phase === 'preparation' && index === 0) await wait; },
      run() { executions++; }, finish() { finishes++; },
    }));
    const pending = runInstalledStrategy(f.setup,f.core,entries,abort.signal);
    if (phase === 'preparation') { abort.abort(); resumes(); }
    const result = await pending;
    assert.equal(result.status,'host-tasks-failed');
    assert.equal(executions,0);
    assert.equal(preparations,phase === 'preparation' ? 1 : 2);
    assert.equal(finishes,2);
    assert.equal(f.stopped(),1);
    result.close();
    assert.equal(await result.cleanup(),true);
  }
});

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
  assert(result.completed.every(value =>
    Number.isFinite(value.taskElapsedMilliseconds) && value.taskElapsedMilliseconds >= 0));
  result.close(); result.close();
  assert.equal(f.closed(), 1);
});

test('managed equal-cost choice is stable when installation order is reversed', async () => {
  for (const reverse of [false, true]) {
    const setup = {}, registrations = {a: {}, z: {}};
    let completed = false, selected, ran;
    const core = {
      siteControl,
      count: () => 2,
      taskCapacity: () => [0n, 0n],
      nextTask: () => completed ? -1 : 1,
      managedProducers: () => completed ? [] : [0],
      selectManaged: (_, task, registration) => {
        assert.equal(task, 1);
        selected = registration;
        return true;
      },
      managedMatches: () => true,
      completed: () => completed,
      finished: () => completed,
      stop: () => {},
      closeOutputs: () => {},
      output: () => undefined,
      usage: () => ({}),
      explain: () => ({}),
    };
    const entries = Object.entries(registrations).map(([key, registration]) => ({
      registration,
      managedSelectionKey: key,
      run() { assert.fail('legacy run'); },
      prepareNext() {
        return completed ? undefined : {task: 1, durationMilliseconds: 5n};
      },
      runPrepared() {
        ran = key;
        completed = true;
        return {completed: {}, material: {}};
      },
    }));
    if (reverse) entries.reverse();
    const result = await runInstalledStrategy(setup, core, entries);
    assert.equal(result.status, 'host-tasks-completed');
    assert.equal(ran, 'a');
    assert.equal(selected, registrations.a);
  }
});

test('a checked source-free root enters the installed managed task lifecycle',
  async () => {
    const setup = {}, registration = {};
    const output = Object.freeze({name: 'source-free-output'});
    let completed = false;
    let starts = 0;
    const core = {
      siteControl,
      count: () => 1,
      taskCapacity: () => [0n, 0n],
      nextTask: () => completed ? -1 : 0,
      managedProducers: () => [],
      selectManaged: (_setup, task, selected) =>
        task === 0 && selected === registration,
      managedMatches: () => true,
      completed: () => completed,
      finished: () => completed,
      stop: () => {},
      closeOutputs: () => {},
      output: () => completed ? output : undefined,
      usage: () => ({}),
      explain: () => ({}),
    };
    const entry = {
      registration,
      managedSelectionKey: 'local',
      run() { assert.fail('source-free root must use managed execution'); },
      prepareNext() {
        return completed ? undefined : {
          task: 0, inputs: [], durationMilliseconds: 1n,
        };
      },
      runPrepared() {
        starts++;
        completed = true;
        return {completed: output, material: {}};
      },
    };
    const result = await runInstalledStrategy(setup, core, [entry]);
    assert.equal(result.status, 'host-tasks-completed',
      result.failure?.code ?? result.failure?.message);
    assert.equal(starts, 1);
    assert.equal(result.output(0), output);
    result.close();
  });

test('managed choice compares known cost before its stable registration key', async () => {
  const setup = {}, registrations = {cheap: {}, expensive: {}, unknown: {}};
  let completed = false, ran;
  const core = {
    siteControl,
    count: () => 2,
    taskCapacity: () => [0n, 0n],
    nextTask: () => completed ? -1 : 1,
    managedProducers: () => completed ? [] : [0],
    selectManaged: () => true,
    managedMatches: () => true,
    completed: () => completed,
    finished: () => completed,
    stop: () => {},
    closeOutputs: () => {},
    output: () => undefined,
    usage: () => ({}),
    explain: () => ({}),
  };
  const costs = {cheap: 1n, expensive: 10n, unknown: null};
  const entries = ['unknown', 'expensive', 'cheap'].map(key => ({
    registration: registrations[key],
    managedSelectionKey: key,
    run() { assert.fail('legacy run'); },
    prepareNext() {
      return completed ? undefined : {
        task: 1,
        durationMilliseconds: costs[key],
      };
    },
    runPrepared() {
      ran = key;
      completed = true;
      return {completed: {}, material: {}};
    },
  }));
  const result = await runInstalledStrategy(setup, core, entries);
  assert.equal(result.status, 'host-tasks-completed');
  assert.equal(ran, 'cheap');
  assert(result.candidateExclusions.some(value =>
    value.registrationKey === 'unknown' &&
    value.reason === 'MissingDurationEstimate'));
  result.close();
});

test('Site startup and Transfer costs participate in standard managed choice', async () => {
  for (const transferMilliseconds of [1n, 20n]) {
    const setup = {};
    const registrations = {producer: {}, same: {}, moved: {}};
    const sourceSite = createInProcessExecutionSite({
      key: `source-${transferMilliseconds}`,
      generation: 1,
      runtimeRevision: 'site-cost-test/1',
      startupMilliseconds: 0n,
      transferMilliseconds: 0n,
    });
    const destinationSite = createInProcessExecutionSite({
      key: `destination-${transferMilliseconds}`,
      generation: 1,
      runtimeRevision: 'site-cost-test/1',
      startupMilliseconds: 0n,
      transferMilliseconds,
    });
    const complete = new Set();
    const selected = [];
    let producerOutput;
    const currentTask = () => complete.has(1) ? complete.has(2) ? -1 : 2 : 1;
    const core = {
      siteControl,
      count: () => 3,
      taskCapacity: () => [0n, 0n],
      next: () => assert.fail('legacy execution is not part of this protocol test'),
      nextTask: currentTask,
      managedProducers: () => currentTask() === 2 ? [1] : [],
      selectManaged: (_setup, task, registration) => {
        selected.push([task, registration]);
        return true;
      },
      managedMatches: () => true,
      completed: (_setup, task) => complete.has(task),
      finished: () => complete.has(1) && complete.has(2),
      stop: () => {},
      closeOutputs: () => {},
      output: () => undefined,
      usage: () => ({}),
      explain: () => ({}),
    };
    const producer = {
      registration: registrations.producer,
      managedSelectionKey: 'producer',
      run() { assert.fail('legacy execution is not part of this protocol test'); },
      prepareNext() {
        return currentTask() === 1
          ? {task: 1, inputs: [], durationMilliseconds: 1n}
          : undefined;
      },
      runPrepared(prepared) {
        assert.equal(prepared.executionSite, sourceSite);
        complete.add(1);
        producerOutput = {completed: {}, material: {}};
        return producerOutput;
      },
    };
    const consumer = (key, registration, expectedSite, duration) => ({
      registration,
      managedSelectionKey: key,
      run() { assert.fail('legacy execution is not part of this protocol test'); },
      prepareNext(outputs) {
        if (currentTask() !== 2) return undefined;
        const input = outputs.get(1);
        assert(input);
        return {
          task: 2,
          inputs: [input],
          acceptsSiteTransfer: true,
          durationMilliseconds: duration,
        };
      },
      runPrepared(prepared) {
        assert.equal(prepared.executionSite, expectedSite);
        throw Object.assign(new Error('stop after observing selected Site'), {
          code: 'ObservedSelectedExecutionSite',
        });
      },
    });
    const entries = [
      producer,
      consumer('same', registrations.same, sourceSite, 10n),
      consumer('moved', registrations.moved, destinationSite, 1n),
    ];
    const estimate = Object.freeze({
      transferBytes: 1n,
      retainedBytes: 1n,
      executionBytes: 1n,
    });
    const policy = prepareExecutionSitePolicy({
      sites: [sourceSite, destinationSite],
      placements: new Map([
        ['producer', [sourceSite]],
        ['same', [sourceSite]],
        ['moved', [destinationSite]],
      ]),
      transferProvider: Object.freeze({
        contract: managedMemoryTransferContract,
        estimate: () => estimate,
        copy() { assert.fail('candidate comparison must not perform Transfer I/O'); },
      }),
    });
    const result = await runInstalledStrategy(
      setup, core, entries, undefined, undefined, policy,
    );
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.failure?.code, 'ObservedSelectedExecutionSite');
    assert.equal(selected.length, 2);
    assert.equal(selected[0][1], registrations.producer);
    assert.equal(selected[1][1], transferMilliseconds === 1n
      ? registrations.moved : registrations.same);
    assert.deepEqual(result.completed.map(value => value.executionSite.key),
      [executionSiteStatus(sourceSite).key]);
    result.close();
    beginExecutionSiteTeardown(sourceSite);
    beginExecutionSiteTeardown(destinationSite);
    assert.equal(executionSiteStatus(sourceSite).teardownComplete, true);
    assert.equal(executionSiteStatus(destinationSite).teardownComplete, true);
    assert(producerOutput);
  }
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

test('unconfirmed execution cleanup cannot release Site capacity or teardown', async () => {
  const cases = [
    ['missing-handle', undefined, false],
    ['missing-status', Object.freeze({retry() {}}), false],
    ['invalid-status', Object.freeze({status: 'unknown'}), false],
    ['invalid-result', Object.freeze({status: () => ({pending: 'unknown'})}), false],
    ['throwing-status', Object.freeze({status() { throw new Error('status failed'); }}), true],
  ];
  for (const [name, cleanupHandle, cleanupRejects] of cases) {
    const registration = {};
    const selectedSite = createInProcessExecutionSite({
      key: `unconfirmed-${name}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
      maxRetainedBytes: 1000n,
      maxExecutionBytes: 1000n,
    });
    const f = fixture([registration]);
    f.core.taskCapacity = () => [100n, 200n];
    const failure = Object.assign(new Error(name), {
      cleanupPending: true,
    });
    if (cleanupHandle !== undefined) failure.cleanupHandle = cleanupHandle;
    const result = await runInstalledStrategy(
      f.setup,
      f.core,
      [{registration, managedSelectionKey: name, run() { throw failure; }}],
      undefined,
      undefined,
      prepareExecutionSitePolicy({sites: [selectedSite]}),
    );
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.cleanupPending(), true);
    assert.deepEqual(executionSiteStatus(selectedSite), {
      ...executionSiteStatus(selectedSite),
      activeOperations: 1,
      reservedRetentionBytes: 100n,
      reservedExecutionBytes: 200n,
      teardownComplete: false,
    });
    assert.equal(beginExecutionSiteTeardown(selectedSite).teardownComplete,
      false);
    if (cleanupRejects) {
      await assert.rejects(result.cleanup(), /Strategy cleanup failed/);
    } else {
      assert.equal(await result.cleanup(), false);
    }
    assert.equal(executionSiteStatus(selectedSite).activeOperations, 1);
    assert.equal(executionSiteStatus(selectedSite).teardownComplete, false);
    result.close();
  }
});

test('confirmed execution cleanup releases Site capacity exactly once', async () => {
  const registration = {};
  const selectedSite = createInProcessExecutionSite({
    key: 'confirmed-execution-cleanup',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    maxRetainedBytes: 1000n,
    maxExecutionBytes: 1000n,
  });
  const f = fixture([registration]);
  f.core.taskCapacity = () => [100n, 200n];
  let pending = true, retries = 0;
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending}),
    async retry() {
      retries++;
      pending = false;
      return this.status();
    },
  });
  const result = await runInstalledStrategy(
    f.setup,
    f.core,
    [{
      registration,
      managedSelectionKey: 'confirmed-cleanup',
      run() {
        throw Object.assign(new Error('cleanup pending'), {
          cleanupPending: true,
          cleanupHandle,
        });
      },
    }],
    undefined,
    undefined,
    prepareExecutionSitePolicy({sites: [selectedSite]}),
  );
  assert.equal(executionSiteStatus(selectedSite).activeOperations, 1);
  assert.equal(await result.cleanup(), true);
  assert.equal(retries, 1);
  assert.equal(result.cleanupPending(), false);
  assert.equal(executionSiteStatus(selectedSite).activeOperations, 0);
  assert.equal(executionSiteStatus(selectedSite).reservedRetentionBytes, 0n);
  assert.equal(executionSiteStatus(selectedSite).reservedExecutionBytes, 0n);
  assert.equal(beginExecutionSiteTeardown(selectedSite).teardownComplete, true);
  assert.equal(await result.cleanup(), true);
  assert.equal(retries, 1);
  result.close();
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

test('Site teardown waits for retained result reclamation and its retry', async () => {
  const registration = {};
  const contribution = {
    registration,
    managedSelectionKey: 'retained-result',
  };
  const selectedSite = createInProcessExecutionSite({
    key: 'retained-site',
    generation: 3,
    runtimeRevision: 'test-runtime/1',
  });
  const sitePolicy = prepareExecutionSitePolicy({sites: [selectedSite]});
  let pending = true;
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending}),
    async retry() { pending = false; return this.status(); },
  });
  const f = fixture([registration]);
  contribution.run = task => {
    f.complete.add(task.index);
    return Object.freeze({
      close() {
        throw Object.assign(new Error('retained cleanup pending'), {
          cleanupPending: true,
          cleanupHandle,
        });
      },
    });
  };
  const result = await runInstalledStrategy(
    f.setup, f.core, [contribution], undefined, undefined, sitePolicy,
  );
  assert.equal(result.status, 'host-tasks-completed');
  assert.equal(beginExecutionSiteTeardown(selectedSite).teardownComplete, false);
  assert.throws(() => result.close(), /retained cleanup pending/);
  assert.equal(executionSiteStatus(selectedSite).holdings, 1);
  assert.equal(executionSiteStatus(selectedSite).teardownComplete, false);
  assert.equal(await result.cleanup(), true);
  assert.equal(executionSiteStatus(selectedSite).holdings, 0);
  assert.equal(executionSiteStatus(selectedSite).teardownComplete, true);
});

test('legacy dispatch enforces Site bytes and retains Core-owned output', async () => {
  const registration = {};
  const rejectedSite = createInProcessExecutionSite({
    key: 'legacy-rejected-site',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    maxRetainedBytes: 5n,
  });
  const rejectedPolicy = prepareExecutionSitePolicy({sites: [rejectedSite]});
  const rejected = fixture([registration]);
  rejected.core.taskCapacity = () => [6n, 0n];
  let dispatched = false;
  const denied = await runInstalledStrategy(
    rejected.setup,
    rejected.core,
    [{
      registration,
      run() {
        dispatched = true;
        rejected.complete.add(1);
      },
    }],
    undefined,
    undefined,
    rejectedPolicy,
  );
  assert.equal(denied.failure?.code, 'ExecutionSiteCapacityEstimateExceeded');
  assert.equal(dispatched, false);
  assert.equal(executionSiteStatus(rejectedSite).reservedRetentionBytes, 0n);

  const retainedSite = createInProcessExecutionSite({
    key: 'legacy-retained-site',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    maxRetainedBytes: 4n,
  });
  const retainedPolicy = prepareExecutionSitePolicy({sites: [retainedSite]});
  const retained = fixture([registration]);
  const output = {};
  retained.core.taskCapacity = () => [4n, 0n];
  retained.core.output = () => output;
  const completed = await runInstalledStrategy(
    retained.setup,
    retained.core,
    [{registration, run() { retained.complete.add(1); }}],
    undefined,
    undefined,
    retainedPolicy,
  );
  assert.equal(completed.status, 'host-tasks-completed');
  assert.equal(executionSiteStatus(retainedSite).heldBytes, 4n);
  assert.equal(beginExecutionSiteTeardown(retainedSite).teardownComplete, false);
  completed.close();
  assert.equal(executionSiteStatus(retainedSite).heldBytes, 0n);
  assert.equal(executionSiteStatus(retainedSite).teardownComplete, true);
});

test('legacy dispatch compares every placement before reserving or starting', async () => {
  const runCase = async ({name, sites, placements, capacity, expected,
    expectedComparisons, expectedExclusions = 0}) => {
    const registration = {};
    const f = fixture([registration]);
    f.core.taskCapacity = () => capacity;
    const result = await runInstalledStrategy(
      f.setup,
      f.core,
      [{
        registration,
        managedSelectionKey: `legacy-${name}`,
        run(task) { f.complete.add(task.index); },
      }],
      undefined,
      undefined,
      prepareExecutionSitePolicy({
        sites,
        placements: new Map([[`legacy-${name}`, placements]]),
      }),
    );
    assert.equal(result.status, 'host-tasks-completed');
    assert.equal(result.completed[0].executionSite.key,
      executionSiteStatus(expected).key);
    assert.equal(result.candidateComparisons.length, expectedComparisons);
    assert.equal(result.candidateExclusions.length, expectedExclusions);
    for (const site of sites) {
      assert.equal(executionSiteStatus(site).peakRetainedBytes,
        site === expected ? capacity[0] : 0n);
    }
    result.close();
    for (const site of sites) beginExecutionSiteTeardown(site);
    assert(sites.every(site => executionSiteStatus(site).teardownComplete));
  };

  for (const reverse of [false, true]) {
    const slow = createInProcessExecutionSite({
      key: `legacy-slow-${reverse}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
      startupMilliseconds: 100n,
    });
    const fast = createInProcessExecutionSite({
      key: `legacy-fast-${reverse}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
      startupMilliseconds: 1n,
    });
    await runCase({
      name: `cost-${reverse}`,
      sites: [slow, fast],
      placements: reverse ? [fast, slow] : [slow, fast],
      capacity: [10n, 0n],
      expected: fast,
      expectedComparisons: 2,
    });
  }

  const insufficient = createInProcessExecutionSite({
    key: 'legacy-insufficient',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    maxRetainedBytes: 50n,
  });
  const sufficient = createInProcessExecutionSite({
    key: 'legacy-sufficient',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    maxRetainedBytes: 1000n,
  });
  await runCase({
    name: 'capacity',
    sites: [insufficient, sufficient],
    placements: [insufficient, sufficient],
    capacity: [100n, 0n],
    expected: sufficient,
    expectedComparisons: 1,
    expectedExclusions: 1,
  });

  const stopped = createInProcessExecutionSite({
    key: 'legacy-stopped',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
  });
  const available = createInProcessExecutionSite({
    key: 'legacy-available',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
  });
  beginExecutionSiteTeardown(stopped);
  await runCase({
    name: 'availability',
    sites: [stopped, available],
    placements: [stopped, available],
    capacity: [10n, 0n],
    expected: available,
    expectedComparisons: 1,
    expectedExclusions: 1,
  });

  for (const reverse of [false, true]) {
    const a = createInProcessExecutionSite({
      key: `legacy-a-${reverse}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
      startupMilliseconds: 1n,
    });
    const z = createInProcessExecutionSite({
      key: `legacy-z-${reverse}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
      startupMilliseconds: 1n,
    });
    await runCase({
      name: `tie-${reverse}`,
      sites: [z, a],
      placements: reverse ? [a, z] : [z, a],
      capacity: [10n, 0n],
      expected: a,
      expectedComparisons: 2,
    });
  }
});

test('legacy completion permit rejects forced revocation but not graceful teardown', async () => {
  for (const forced of [true, false]) {
    const registration = {};
    const selectedSite = createInProcessExecutionSite({
      key: forced ? 'legacy-forced-loss' : 'legacy-graceful-stop',
      generation: 1,
      runtimeRevision: 'test-runtime/1',
    });
    const f = fixture([registration]);
    let observed = 0;
    const result = await runInstalledStrategy(
      f.setup,
      f.core,
      [{
        registration,
        run(task, _signal, permit) {
          if (forced) revokeExecutionSite(selectedSite);
          else beginExecutionSiteTeardown(selectedSite);
          permit.assertAvailable();
          f.complete.add(task.index);
        },
      }],
      undefined,
      () => { observed++; },
      prepareExecutionSitePolicy({sites: [selectedSite]}),
    );
    assert.equal(result.status,
      forced ? 'host-tasks-failed' : 'host-tasks-completed');
    assert.equal(f.complete.has(1), !forced);
    assert.equal(result.completed.length, forced ? 0 : 1);
    assert.equal(observed, forced ? 0 : 1);
    result.close();
    assert.equal(executionSiteStatus(selectedSite).teardownComplete, true);
  }
});

test('cleanup advances a stopped reader before awaiting its retained output close', async () => {
  const registration = {};
  const f = fixture([registration, registration]);
  let releaseClose;
  const closeWait = new Promise(resolve => { releaseClose = resolve; });
  let pending = true, retries = 0;
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending}),
    async retry() {
      retries++;
      pending = false;
      releaseClose();
      return this.status();
    },
  });
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run(task) {
      if (task.index === 1) {
        f.complete.add(task.index);
        return {close: () => closeWait};
      }
      throw Object.assign(new Error('reader stop pending'), {
        cleanupPending: true,
        cleanupHandle,
      });
    },
  }]);
  assert.equal(result.status, 'host-tasks-failed');
  const closing = result.close();
  assert(closing instanceof Promise);
  assert.equal(await result.cleanup(), true);
  await closing;
  assert.equal(retries, 1);
});

test('early managed release recovery also releases its Site holding', async () => {
  for (const asynchronous of [false, true]) {
    const selectedSite = createInProcessExecutionSite({
      key: asynchronous ? 'early-async-release' : 'early-sync-release',
      generation: 1,
      runtimeRevision: 'test-runtime/1',
    });
    const registration = {};
    let next = 1, pending = true, closes = 0, retries = 0;
    const completedTasks = new Set();
    const cleanupHandle = Object.freeze({
      status: () => Object.freeze({pending}),
      async retry() {
        retries++;
        pending = false;
        return this.status();
      },
    });
    const closeFailure = Object.assign(new Error('release failed'), {
      cleanupPending: true,
      cleanupHandle,
    });
    const core = {
      siteControl,
      count: () => 3,
      taskCapacity: () => [0n, 0n],
      nextTask: () => next,
      managedProducers: () => [],
      selectManaged: () => true,
      managedMatches: () => true,
      completed: (_, task) => completedTasks.has(task),
      finished: () => completedTasks.size === 2,
      stop() {}, closeOutputs() {}, output() {},
      usage: () => ({}), explain: () => ({}),
    };
    const contribution = {
      registration,
      managedSelectionKey: 'local',
      run() { assert.fail('unexpected legacy dispatch'); },
      prepareNext(outputs) {
        return {
          task: next,
          inputs: [],
          durationMilliseconds: 0n,
          siteCapacity: {retainedBytes: 10n, executionBytes: 0n},
          outputs,
          releasableProducers: next === 2 ? [1] : [],
        };
      },
      runPrepared() {
        const task = next++;
        completedTasks.add(task);
        return {
          completed: {},
          material: {},
          close() {
            if (task !== 1) return;
            closes++;
            if (asynchronous) return Promise.reject(closeFailure);
            throw closeFailure;
          },
        };
      },
    };
    const result = await runInstalledStrategy(
      {}, core, [contribution], undefined, undefined,
      prepareExecutionSitePolicy({sites: [selectedSite]}),
    );
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.cleanupPending(), true);
    const closing = result.close();
    if (asynchronous) await assert.rejects(closing, /release failed/);
    else await closing;
    assert.equal(await result.cleanup(), true);
    assert.equal(closes, 1);
    assert.equal(retries, 1);
    assert.equal(executionSiteStatus(selectedSite).holdings, 0);
    assert.equal(executionSiteStatus(selectedSite).heldBytes, 0n);
    assert.equal(beginExecutionSiteTeardown(selectedSite).teardownComplete,
      true);
  }
});

test('early managed release without recovery remains explicitly unconfirmed', async () => {
  for (const reason of [undefined, null, false, 0, '']) {
    const selectedSite = createInProcessExecutionSite({
      key: `early-unconfirmed-${String(reason)}`,
      generation: 1,
      runtimeRevision: 'test-runtime/1',
    });
    const registration = {};
    let next = 1;
    const completedTasks = new Set();
    const core = {
      siteControl,
      count: () => 3,
      taskCapacity: () => [0n, 0n],
      nextTask: () => next,
      managedProducers: () => [],
      selectManaged: () => true,
      managedMatches: () => true,
      completed: (_, task) => completedTasks.has(task),
      finished: () => completedTasks.size === 2,
      stop() {}, closeOutputs() {}, output() {},
      usage: () => ({}), explain: () => ({}),
    };
    const contribution = {
      registration,
      managedSelectionKey: 'local',
      run() { assert.fail('unexpected legacy dispatch'); },
      prepareNext(outputs) {
        return {
          task: next,
          inputs: [],
          durationMilliseconds: 0n,
          siteCapacity: {retainedBytes: 10n, executionBytes: 0n},
          outputs,
          releasableProducers: next === 2 ? [1] : [],
        };
      },
      runPrepared() {
        const task = next++;
        completedTasks.add(task);
        return {
          completed: {}, material: {},
          close() { if (task === 1) throw reason; },
        };
      },
    };
    const result = await runInstalledStrategy(
      {}, core, [contribution], undefined, undefined,
      prepareExecutionSitePolicy({sites: [selectedSite]}),
    );
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.cleanupPending(), true);
    await result.close();
    assert.equal(await result.cleanup(), false);
    assert.equal(executionSiteStatus(selectedSite).holdings, 1);
    assert.equal(beginExecutionSiteTeardown(selectedSite).teardownComplete,
      false);
  }
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

test('dependent output cleanup preserves responsibility across explicit passes', async () => {
  const registration = {}, f = fixture([registration, registration]);
  let sourcePending = true, outputPending = true, runs = 0;
  const closes = [0, 0], retries = [0, 0];
  const output = {status: () => ({pending: outputPending}), async retry() {
    retries[0]++;
    if (!sourcePending) outputPending = false;
  }};
  const source = {status: () => ({pending: sourcePending}), async retry() {
    retries[1]++;
    sourcePending = false;
  }};
  const result = await runInstalledStrategy(f.setup, f.core, [{registration,
    run(task) {
      runs++;
      f.complete.add(task.index);
      return {close() {
        closes[task.index - 1]++;
        throw Object.assign(new Error(`pending ${task.index}`), {
          cleanupPending: true,
          cleanupHandle: task.index === 1 ? output : source,
        });
      }};
    },
  }]);
  assert.throws(() => result.close(), /pending 1/);
  assert.equal(await result.cleanup(), false);
  assert.equal(result.cleanupPending(), true);
  assert.equal(outputPending, true);
  assert.equal(sourcePending, false);
  assert.deepEqual(retries, [1, 1]);
  assert.equal(await result.cleanup(), true);
  assert.equal(result.cleanupPending(), false);
  assert.deepEqual(retries, [2, 1]);
  assert.deepEqual(closes, [1, 1]);
  assert.equal(runs, 2, 'recovery must not repeat Compute');
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

test('asynchronous output close stays pending until all releases and explicit recoveries settle', async () => {
  const registration = {}, f = fixture([registration, registration]);
  let resume, closes = 0, retries = 0, pending = true;
  const wait = new Promise(resolve => { resume = resolve; });
  const handle = {status: () => ({pending}), retry() { retries++; pending = false; }};
  const failure = Object.assign(new Error('file cleanup failed'), {cleanupHandle: handle});
  const result = await runInstalledStrategy(f.setup, f.core, [{registration, run(task) {
    f.complete.add(task.index);
    return {async close() { closes++; await wait; if (task.index === 1) throw failure; }};
  }}]);
  const closing = result.close();
  assert.equal(result.close(), closing);
  assert.equal(closes, 2);
  assert.equal(f.closed(), 1);
  assert.throws(() => result.output(1), {code: 'ReleasedStrategy'});
  assert.equal(result.cleanupPending(), true);
  let cleaned = false;
  const cleanup = result.cleanup().then(value => { cleaned = value; });
  await Promise.resolve();
  assert.equal(cleaned, false);
  assert.equal(retries, 0);
  resume();
  await assert.rejects(closing, error => error === failure);
  await cleanup;
  assert.equal(cleaned, true);
  assert.equal(result.cleanupPending(), false);
  assert.equal(retries, 1);
  assert.equal(closes, 2);
});

test('reasonless asynchronous close is not forgotten or implicitly retried', async () => {
  for (const reason of [undefined, null]) {
    const registration = {}, f = fixture([registration]);
    let closes = 0;
    const result = await runInstalledStrategy(f.setup, f.core, [{registration, run(task) {
      f.complete.add(task.index);
      return {close() { closes++; return Promise.reject(reason); }};
    }}]);
    await assert.rejects(result.close(), error => error === reason);
    assert.equal(result.cleanupPending(), true);
    assert.equal(await result.cleanup(), false);
    assert.equal(closes, 1);
  }
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

test('a refused protected activation stops the Run before any start', async () => {
  const registration = {};
  for (const [entries, code] of [
    [[], 'ExecutionAuthorizationDenied'],
    [[accountEntry('site', 'delegate', {connection: 'in-process-default'})],
      'ExecutionAuthorizationDecisionFailed'],
  ]) {
    const f = fixture([registration, registration]);
    const grants = [];
    f.core.requireActivation = () => {};
    f.core.coverActivation = (_setup, index) => { grants.push(index); return true; };
    let runs = 0;
    const gate = await fixtureAuthorization(entries, {
      protectedSites: ['in-process-default'],
      decide: () => { throw new Error('DecisionServiceDown'); },
      answeringAuthorities: ['reviewer'],
    });
    const result = await runInstalledStrategy(f.setup, f.core, [{
      registration,
      run() { runs++; f.complete.add(1); },
    }], undefined, undefined, undefined, undefined, gate);
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(result.failure.code, code);
    assert.equal(runs, 0);
    assert.deepEqual(grants, []);
    assert.equal(f.stopped(), 1);
    assert.equal(result.completed.length, 0);
    await result.close();
  }
});

test('covered activations grant each task once with no evaluation', async () => {
  const registration = {};
  const f = fixture([registration, registration, registration]);
  const grants = [];
  let required = 0;
  f.core.requireActivation = () => { required++; };
  f.core.coverActivation = (_setup, index) => { grants.push(index); return true; };
  const gate = await fixtureAuthorization([], {
    decide: () => assert.fail('covered work asked the Host'),
    answeringAuthorities: ['reviewer'],
  });
  let index = 0;
  const result = await runInstalledStrategy(f.setup, f.core, [{
    registration,
    run() { f.complete.add(++index); },
  }], undefined, undefined, undefined, undefined, gate);
  assert.equal(result.status, 'host-tasks-completed');
  assert.equal(required, 1);
  assert.deepEqual(grants, [1, 2, 3]);
  assert.equal(gate.counters().evaluations, 0);
  assert.equal(gate.counters().coveredOperations, 3);
  await result.close();
});

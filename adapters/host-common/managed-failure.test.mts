import test from 'node:test';
import assert from 'node:assert/strict';
import * as manifestControl from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {localStrategyContribution} from '../local-node/strategy-bundle.mjs';
import {numericStrategyContribution} from
  '../reference-compute-node/strategy-bundle.mjs';
import {registerManagedMemoryInput} from
  '../store-local/managed-memory-representations.mjs';
import {createLocalRetainedStore} from '../store-local/files.mjs';
import {registerManagedInput} from '../store-local/managed-representations.mjs';
import {managedPhysicalRepresentation as createManagedPhysicalRepresentation} from
  '../store-local/managed-physical-representation.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid,
  managedColumnRowProvider} from '../connectors/duckdb/node/managed-column-codec.mjs';
import {checked} from './runtime-result.mjs';
import {runInstalledStrategy} from './strategy.mjs';
import {createInProcessExecutionSite, prepareExecutionSitePolicy} from
  './execution-sites.mjs';
import {createExecutionSiteControlFixture} from
  './execution-site-control.fixture.mjs';
import type {ManagedCleanupStatus, ManagedFailure} from './managed-failure.mjs';
import type {SynchronousResultCheck, SynchronousRuntimeData} from './runtime-result.mjs';

type Core = Parameters<typeof runInstalledStrategy>[0]['runtime']['core'];
type Contribution = Parameters<typeof runInstalledStrategy>[0]['runtime']['contributions'][number];
type LocalBindings = Parameters<typeof localStrategyContribution>[0];
type ReferenceBindings = Parameters<typeof numericStrategyContribution>[0];
type FixtureBindings = Partial<LocalBindings & ReferenceBindings>;
type FixtureProvider = Parameters<typeof registerManagedMemoryInput>[3];
type ManagedResult = {$tag: number; _0: unknown};
type Overrides = Partial<{
  execute(): ManagedResult;
  advance(): ManagedResult;
  complete(): ManagedResult;
  close(): void;
  settle(): ManagedResult;
}>;
type ManagedFixtureTask = Parameters<ReturnType<typeof localStrategyContribution>['runPrepared']>[0] &
  Parameters<ReturnType<typeof numericStrategyContribution>['runPrepared']>[0];
type ManagedTaskPreparation = NonNullable<Awaited<ReturnType<NonNullable<Contribution['prepareNext']>>>>;

const checkFixtureResult: SynchronousResultCheck = result => checked(result) as SynchronousRuntimeData;
// Only the bindings selected by these failure scenarios are supplied.
const localFixture = (moon: FixtureBindings, setup: object, verify: SynchronousResultCheck) =>
  localStrategyContribution(moon as LocalBindings, setup, verify);
const referenceFixture = (moon: FixtureBindings, setup: object, verify: SynchronousResultCheck) =>
  numericStrategyContribution(moon as ReferenceBindings, setup, verify);
const fixtureStrategies = [
  ['Local', localFixture, 'local'],
  ['reference', referenceFixture, 'reference_compute'],
] as const;

function hostFixture(entry: ReturnType<typeof localFixture> | ReturnType<typeof referenceFixture>,
  prepareNext: NonNullable<Contribution['prepareNext']>,
  managedSelectionKey = entry.managedSelectionKey): Contribution {
  return Object.freeze({
    ...entry, managedSelectionKey, prepareNext,
    runPrepared(...[task, signal, relationSample]: Parameters<NonNullable<Contribution['runPrepared']>>) {
      assert('configuration' in task && 'inputs' in task && Array.isArray(task.inputs));
      return entry.runPrepared(task as ManagedFixtureTask, signal, relationSample);
    },
  });
}

async function captureManagedFailure(run: Promise<unknown>): Promise<ManagedFailure> {
  try {await run;}
  catch (error) {
    assert(error instanceof Error && 'primaryFailure' in error && 'cleanupHandle' in error);
    const failure = error as ManagedFailure;
    assert(typeof failure.cleanupHandle.status === 'function' && typeof failure.cleanupHandle.retry === 'function');
    return failure;
  }
  assert.fail('Expected original managed failure');
}

const completedAdvance = (run: () => ManagedResult) => () => {
  const result = run();
  return result?.$tag === 1
    ? {$tag: 1, _0: {complete: true, progress: 0n, work: 0n}} : result;
};

const ok = (_0?: unknown) => ({$tag: 1, _0});
const failed = (_0: unknown) => ({$tag: 0, _0});
const siteControl = createExecutionSiteControlFixture();
type RepresentationArguments = Parameters<typeof createManagedPhysicalRepresentation>;
const managedPhysicalRepresentation = (...arguments_: [RepresentationArguments[0], RepresentationArguments[1],
  RepresentationArguments[2], RepresentationArguments[3], RepresentationArguments[4]]) =>
  createManagedPhysicalRepresentation(...arguments_, manifestControl);
const siteCase = (key: string) => {
  const site = createInProcessExecutionSite({
    key,
    generation: 1,
    runtimeRevision: 'managed-failure-test/1',
  });
  return {
    site,
    policy: prepareExecutionSitePolicy({sites: [site]}),
    input: <Input extends {material: object},>(value: Input) => Object.freeze({
      ...value,
      task: 0,
      site,
      siteMaterial: value.material,
      materialGeneration: value.material,
    }),
  };
};

function managedCase(factory: typeof localFixture | typeof referenceFixture, prefix: string,
  provider: FixtureProvider, overrides: Overrides = {}) {
  const material = {}, input = {}, events: string[] = [];
  const memory = registerManagedMemoryInput(
    material,
    value => value === input,
    () => true,
    provider,
    () => events.push('released'),
  );
  const operations = {
    inputs: [{input, append: () => ok(), finish: () => ok()}],
    execute: () => ok(), advance: completedAdvance(() => ok()),
    settle: () => { events.push('settle'); return ok(); },
    complete: () => ok({}),
    material: () => ({}),
    output_rows: () => 0,
    output_row: () => failed(new Error('NoRow')),
    storage_bytes: 0n,
    close: () => { events.push('close'); },
    cleanup_refresh: () => true,
    ...overrides,
  };
  const moon: FixtureBindings = {
    [`strategyModule_${prefix}_Registration`]: () => ({}),
    strategyHostRegistrationSelectionKey: () => prefix,
    [`strategyModule_${prefix}_ManagedStart`]: () => ok(operations),
    strategyHostManagedInputMatchesMaterial: () => true,
    strategyHostBeginManagedFailureProgress:
      manifestControl.strategyHostBeginManagedFailureProgress,
    strategyHostRecordManagedFailureAdditionalClosed:
      manifestControl.strategyHostRecordManagedFailureAdditionalClosed,
    strategyHostRecordManagedFailureOperationsCloseAttempted:
      manifestControl.strategyHostRecordManagedFailureOperationsCloseAttempted,
    strategyHostRecordManagedFailureOperationsClosed:
      manifestControl.strategyHostRecordManagedFailureOperationsClosed,
    strategyHostRecordManagedFailureCleanupStopped:
      manifestControl.strategyHostRecordManagedFailureCleanupStopped,
    strategyHostRecordManagedFailureExecutionSettled:
      manifestControl.strategyHostRecordManagedFailureExecutionSettled,
    strategyHostRecordManagedFailureCleanupRefreshed:
      manifestControl.strategyHostRecordManagedFailureCleanupRefreshed,
    strategyHostManagedFailureAction:
      manifestControl.strategyHostManagedFailureAction,
  };
  const entry = factory(moon, {}, checkFixtureResult);
  const managedInput = {task: 0, material, completed: undefined};
  const prepared: ManagedFixtureTask & Pick<ManagedTaskPreparation, 'releasableProducers' | 'outputs'> = {
    task: 0,
    releasableProducers: [],
    outputs: new Map(),
    inputs: [managedInput],
    configuration: {},
  };
  return {entry, prepared, events, memory};
}

test('Local optional Sample preserves its first failure while the same prefix return is pending', async () => {
  const prefix = Object.freeze({});
  const first = new Error('original Sample visitor refusal');
  const pending = new Error('original Sample reservation return is blocked');
  const owner = {}, profile = {};
  let allowed = false, firstReturns = 0, commits = 0, adoptions = 0;
  const fixture = managedCase((moon, setup, verify) => localFixture({
    ...moon,
    strategyModule_local_ManagedStartSample(configuration, retained, original, selected, task,
      maxBytes, maxNodes, maxDepth, current, adopt, retainPending, result) {
      assert.equal(original, owner);
      assert.equal(selected, profile);
      const operations = verify(moon.strategyModule_local_ManagedStart!(configuration)) as {
        complete(): ManagedResult};
      return ok({...operations, complete() {
        const completed = operations.complete();
        commits++;
        assert.equal(current(), true);
        assert.equal(adopt(prefix), false);
        retainPending(prefix);
        // The lower boundary ledger may report no pending return yet.
        result(failed(first), false, false);
        return completed;
      }});
    },
    strategyModule_local_ReturnPendingSample(original) {
      assert.equal(original, prefix);
      firstReturns++;
      return allowed ? ok() : failed(pending);
    },
  }, setup, verify), 'local', {async read() {}});
  const failure = await captureManagedFailure(fixture.entry.runPrepared(fixture.prepared, undefined, {
    owner, profile, maxWireBytes: 4096, maxNodes: 128, maxDepth: 16, current: () => true,
    adopt(original) {
      assert.equal(original, prefix);
      adoptions++;
      throw first;
    },
  }));
  assert.equal(failure.primaryFailure, first);
  const handle = failure.cleanupHandle;
  assert.equal(handle.status().pending, true);
  assert.ok(handle.status().errors.some(error => error instanceof Error && error.cause === pending));
  assert.ok(firstReturns >= 1);
  assert.equal(fixture.events.includes('close'), false);
  allowed = true;
  assert.equal((await handle.retry()).pending, false);
  assert.equal(fixture.events.includes('close'), true);
  const settledReturns = firstReturns;
  assert.equal((await handle.retry()).pending, false);
  assert.equal(firstReturns, settledReturns);
  assert.equal(adoptions, 1);
  assert.equal(commits, 1);
});

for (const [name, factory, prefix] of fixtureStrategies) {
  test(`${name} managed completion observes the common Site readiness gate`, async () => {
    let completionCalls = 0;
    const f = managedCase(factory, prefix, {async read() {}}, {
      complete() {
        completionCalls++;
        return ok({});
      },
    });
    await assert.rejects(
      f.entry.runPrepared({...f.prepared, siteCompletionReady: () => false}),
      {message: 'ExecutionSiteCompletionNotReady'},
    );
    assert.equal(completionCalls, 0);
    assert.deepEqual(f.events, ['close', 'settle']);
  });

  test(`${name} managed reader and evaluation failures close and settle`, async () => {
    for (const phase of ['read', 'execute']) {
      const primary = new Error(`${phase} failed`);
      const f = managedCase(
        factory,
        prefix,
        {async read() { if (phase === 'read') throw primary; }},
        phase === 'execute' ? {execute: () => failed(primary), advance: completedAdvance(() => failed(primary))} : {},
      );
      await assert.rejects(f.entry.runPrepared(f.prepared), error =>
        phase === 'read' ? error === primary :
          error instanceof Error && 'code' in error && error.code === 'MoonBitHostFailure' && error.cause === primary);
      assert.deepEqual(f.events.slice(0, 2), ['close', 'settle']);
    }
  });

  test(`${name} managed settlement waits for unconfirmed reader stop`, async () => {
    let pending = true;
    const primary = Object.assign(new Error('read pending'), {
      cleanupPending: true,
      cleanupHandle: {
        status: () => ({pending}),
        async retry() { pending = false; return {pending}; },
      },
    });
    const f = managedCase(factory, prefix, {
      async read() { throw primary; },
    });
    const failure = await captureManagedFailure(f.entry.runPrepared(f.prepared));
    assert.equal(failure.primaryFailure, primary);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.deepEqual(f.events, ['close']);
    assert.equal(f.memory.status().readers, 1);
    let sourceClosed = false;
    const closing = f.memory.close().then(() => { sourceClosed = true; });
    await Promise.resolve();
    assert.equal(sourceClosed, false);
    assert.equal(f.events.includes('released'), false);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    await closing;
    assert.equal(f.memory.status().readers, 0);
    assert.deepEqual(f.events, ['close', 'released', 'settle']);
  });

  test(`${name} managed close failure does not skip settlement`, async () => {
    const primary = new Error('read failed');
    let first = true;
    const f = managedCase(factory, prefix, {
      async read() { throw primary; },
    }, {
      close() {
        f.events.push('close');
        if (first) { first = false; throw new Error('close failed'); }
      },
    });
    const failure = await captureManagedFailure(f.entry.runPrepared(f.prepared));
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(f.events, ['close', 'settle']);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(f.events, ['close', 'settle', 'close']);
  });

  test(`${name} managed repeated cleanup retains first/latest originals without acknowledging stop`, async () => {
    const primary = Object.freeze(new Error('original managed read failure'));
    const first = Object.freeze(new Error('original first close failure'));
    const repeated = [first, undefined, first, 'primitive close failure'];
    let allowClose = false, closeCalls = 0, latest;
    const f = managedCase(factory, prefix, {async read() {throw primary;}}, {
      close() {
        f.events.push('close');
        closeCalls++;
        if (!allowClose) {
          latest = repeated[(closeCalls - 1) % repeated.length];
          throw latest;
        }
      },
    });
    const failure = await captureManagedFailure(f.entry.runPrepared(f.prepared));
    assert.equal(failure.primaryFailure, primary);
    const snapshots: ManagedCleanupStatus[] = [];
    for (let attempt = 0; attempt < 4; attempt++) {
      if (attempt !== 0) await failure.cleanupHandle.retry();
      const status = failure.cleanupHandle.status(); snapshots.push(status);
      assert.equal(status.pending, true);
      assert.deepEqual(status.errors, closeCalls === 1 ? [first] : [first, latest]);
      assert.ok(Object.isFrozen(status) && Object.isFrozen(status.errors));
      for (const previous of snapshots) {
        assert.equal(previous.errors[0], first);
        assert.ok(previous.errors.length <= 2);
      }
      assert.equal(f.events.filter(event => event === 'settle').length, 1);
    }
    const before = closeCalls;
    allowClose = true;
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(closeCalls, before + 1);
    assert.equal(f.events.filter(event => event === 'settle').length, 1);
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(failure.cleanupErrors, [first, latest]);
  });

  test(`${name} managed unknown reader cleanup never guesses stopped`, async () => {
    const primary = Object.assign(new Error('unknown reader stop'), {
      cleanupPending: true,
    });
    const f = managedCase(factory, prefix, {
      async read() { throw primary; },
    });
    const failure = await captureManagedFailure(f.entry.runPrepared(f.prepared));
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(f.events, ['close']);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.deepEqual(f.events, ['close']);
  });

  test(`${name} managed failures settle through the standard Host`, async () => {
    for (const phase of ['reader', 'evaluation-budget', 'cancellation']) {
      const readEntered = Promise.withResolvers<void>();
      const readWait = Promise.withResolvers<void>();
      const primary = Object.assign(new Error(`${phase} failed`), {
        code: phase === 'evaluation-budget'
          ? 'EvaluationBudgetExceeded' : 'ManagedReadFailed',
      });
      let reservedExecutionBytes = 1024n;
      let reservedRetentionBytes = 256n;
      const provider: FixtureProvider = {
        async read(_file, _emit, signal) {
          if (phase === 'reader') throw primary;
          if (phase === 'cancellation') {
            readEntered.resolve();
            await readWait.promise;
            signal?.throwIfAborted();
          }
        },
      };
      const f = managedCase(factory, prefix, provider, {
        execute: () => phase === 'evaluation-budget'
          ? failed(primary) : ok(), advance: completedAdvance(() => phase === 'evaluation-budget'
          ? failed(primary) : ok()),
        settle: () => {
          f.events.push('settle');
          reservedExecutionBytes = 0n;
          reservedRetentionBytes = 0n;
          return ok();
        },
      });
      const registration = f.entry.registration;
      const placed = siteCase(`${prefix}-${phase}`);
      const entry = hostFixture(f.entry, () => Object.freeze({
        ...f.prepared,
        task: 1,
        durationMilliseconds: 1n,
        inputs: f.prepared.inputs.map(placed.input),
      }), `${prefix}-failure`);
      const core: Core = {
        siteControl,
        count: () => 2,
        next: () => assert.fail('Managed failure fixture entered the legacy dispatcher'),
        taskCapacity: () => assert.fail('Managed failure fixture quoted a legacy task'),
        nextTask: () => 1,
        managedProducers: () => [0],
        selectManaged: (_, task, selected) =>
          task === 1 && selected === registration,
        managedMatches: () => false,
        completed: () => false,
        finished: () => false,
        stop: () => {},
        closeOutputs: () => {},
        output: () => undefined,
        usage: () => ({reservedExecutionBytes, reservedRetentionBytes}),
        explain: () => ({}),
      };
      const controller = new AbortController();
      const running = runInstalledStrategy({
        setup: {},
        runtime: {
          core,
          contributions: [entry],
          sitePolicy: placed.policy,
        },
        control: {
          signal: controller.signal,
        },
      });
      if (phase === 'cancellation') {
        await readEntered.promise;
        controller.abort();
        readWait.resolve();
      }
      const result = await running;
      assert.equal(result.status, 'host-tasks-failed');
      assert.deepEqual(f.events.slice(-2), ['close', 'settle']);
      assert.partialDeepStrictEqual(result.usage(), {reservedExecutionBytes: 0n, reservedRetentionBytes: 0n});
      result.close();
      assert.equal(await result.cleanup(), true);
    }
  });
}

test('standard file-to-Local cancellation closes the real read before settlement', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'actql-local-file-failure-'));
  const store = await createLocalRetainedStore({
    parentDirectory: directory,
    capacityBytes: 8 * 1024 * 1024,
    maxFrameBytes: 8 * 1024 * 1024,
  });
  t.after(async () => {
    store.close();
    await store.cleanup();
    await rm(directory, {recursive: true, force: true});
  });
  const fields = Object.freeze([
    Object.freeze({name: 'id', type: Object.freeze({id: 'DOUBLE'})}),
    Object.freeze({name: 'label', type: Object.freeze({id: 'VARCHAR'})}),
  ]);
  const double = (value: number) => {
    const bytes = Buffer.alloc(8);
    bytes.writeDoubleBE(value);
    return bytes.toString('hex');
  };
  const frame = encodeManagedColumnFrame(
    fields,
    [Array(5000).fill(double(1)), Array(5000).fill('雪'.repeat(256))],
    5000,
    0,
  );
  const writer = store.reserve(frame.byteLength);
  await writer.start();
  await writer.appendBytes(frame);
  const body = await writer.sealPhysical();
  const material = {}, input = {}, completed = {};
  const fieldsFrame = JSON.stringify(fields.map(field =>
    [field.name, field.type.id, null, null]));
  const representation = managedPhysicalRepresentation(
    body, 5000, managedColumnCodecContractCid, fieldsFrame, [0, 1],
  );
  const provider = managedColumnRowProvider(fieldsFrame);
  registerManagedInput(
    material,
    value => value === input,
    store,
    body,
    managedColumnCodecContractCid,
    representation.manifest,
    provider,
  );

  const events: (string | [string, number])[] = [];
  const controller = new AbortController();
  let rows = 0;
  let reservedExecutionBytes = 1024n;
  let reservedRetentionBytes = 256n;
  const operations = {
    inputs: [{
      input,
      append: () => {
        rows++;
        controller.abort(new Error('cancel file read'));
        return ok();
      },
      finish: () => ok(),
    }],
    execute: () => ok(), advance: completedAdvance(() => ok()),
    settle: () => {
      events.push(['settle-readers', store.status().activeReaders]);
      reservedExecutionBytes = 0n;
      reservedRetentionBytes = 0n;
      return ok();
    },
    complete: () => ok({}),
    material: () => ({}),
    output_rows: () => 0,
    output_row: () => failed(new Error('NoRow')),
    storage_bytes: 0n,
    close: () => events.push('close'),
    cleanup_refresh: () => true,
  };
  const registration = {};
  const setup = {};
  const placed = siteCase('local-file-cancellation');
  const product = localFixture({
    ...manifestControl,
    strategyModule_local_Registration: () => registration,
    strategyHostRegistrationSelectionKey: () => 'local-file',
    strategyModule_local_ManagedStart: () => ok(operations),
    strategyHostManagedInputMatchesMaterial: (actual, expected) =>
      actual === input && expected === material,
  }, setup, checkFixtureResult);
  const entry = Object.freeze({
    ...product,
    prepareNext: () => Object.freeze({
      task: 1,
      durationMilliseconds: 1n,
      releasableProducers: [],
      outputs: new Map(),
      inputs: [placed.input({material, completed})],
      configuration: {},
    }),
  });
  const core: Core = {
    siteControl,
    count: () => 2,
    next: () => assert.fail('Managed cancellation fixture entered the legacy dispatcher'),
    taskCapacity: () => assert.fail('Managed cancellation fixture quoted a legacy task'),
    nextTask: () => 1,
    managedProducers: () => [0],
    selectManaged: (_, task, selected) =>
      task === 1 && selected === registration,
    managedMatches: () => false,
    completed: () => false,
    finished: () => false,
    stop: () => {},
    closeOutputs: () => {},
    output: () => undefined,
    usage: () => ({reservedExecutionBytes, reservedRetentionBytes}),
    explain: () => ({}),
  };
  const result = await runInstalledStrategy({
    setup,
    runtime: {
      core,
      contributions: [entry],
      sitePolicy: placed.policy,
    },
    control: {
      signal: controller.signal,
    },
  });
  assert.equal(result.status, 'host-tasks-failed');
  assert.equal(result.failure, controller.signal.reason);
  assert.equal(rows, 1);
  assert.deepEqual(provider.status(), {activeReads: 0, completedReads: 1});
  assert.deepEqual(events, ['close', ['settle-readers', 0]]);
  assert.equal(store.status().activeReaders, 0);
  assert.partialDeepStrictEqual(result.usage(), {reservedExecutionBytes: 0n, reservedRetentionBytes: 0n});
  result.close();
  assert.equal(await result.cleanup(), true);
  body.close();
  await body.cleanupHandle.retry();
});

for (const [name, factory, prefix] of fixtureStrategies) {
  test(`${name} standard Host never completes before final file integrity`, async t => {
    const directory = await mkdtemp(join(
      tmpdir(), `actql-${prefix}-final-integrity-`,
    ));
    const store = await createLocalRetainedStore({
      parentDirectory: directory,
      capacityBytes: 1024 * 1024,
      maxFrameBytes: 1024 * 1024,
    });
    t.after(async () => {
      store.close();
      await store.cleanup();
      await rm(directory, {recursive: true, force: true});
    });
    const fields = Object.freeze([
      Object.freeze({name: 'id', type: Object.freeze({id: 'DOUBLE'})}),
    ]);
    const number = Buffer.alloc(8);
    number.writeDoubleBE(1);
    const frame = encodeManagedColumnFrame(
      fields, [[number.toString('hex')]], 1, 0,
    );
    const writer = store.reserve(frame.byteLength);
    await writer.start();
    await writer.appendBytes(frame);
    const body = await writer.sealPhysical();
    const material = {}, input = {}, completed = {};
    const fieldsFrame = JSON.stringify([['id', 'DOUBLE', null, null]]);
    const representation = managedPhysicalRepresentation(
      body, 1, managedColumnCodecContractCid, fieldsFrame, [0],
    );
    const base = managedColumnRowProvider(fieldsFrame);
    const changed = Buffer.from(frame);
    changed[changed.length - 2] = changed[changed.length - 2] === 125 ? 93 : 125;
    registerManagedInput(
      material,
      value => value === input,
      store,
      body,
      managedColumnCodecContractCid,
      representation.manifest,
      Object.freeze<FixtureProvider>({
        async read(file, emit, signal) {
          assert(file && typeof file === 'object' && 'path' in file && typeof file.path === 'string');
          await base.read(file as {path: string}, emit, signal);
          await writeFile(file.path, changed);
        },
      }),
    );
    const events: string[] = [];
    let reservedExecutionBytes = 1024n;
    let reservedRetentionBytes = 256n;
    let commonCompleted = false;
    const operations = {
      inputs: [{
        input,
        append: () => ok(),
        finish: () => { events.push('finish'); return ok(); },
      }],
      execute: () => { events.push('execute'); return ok(); }, advance: completedAdvance(() => { events.push('execute'); return ok(); }),
      settle: () => {
        events.push('settle');
        reservedExecutionBytes = 0n;
        reservedRetentionBytes = 0n;
        return ok();
      },
      complete: () => {
        commonCompleted = true;
        events.push('complete');
        return ok({});
      },
      material: () => ({}),
      output_rows: () => 0,
      output_row: () => failed(new Error('NoRow')),
      storage_bytes: 0n,
      close: () => events.push('close'),
      cleanup_refresh: () => true,
    };
    const registration = {};
    const placed = siteCase(`${prefix}-integrity`);
    const moon: FixtureBindings = {
      ...manifestControl,
      [`strategyModule_${prefix}_Registration`]: () => registration,
      strategyHostRegistrationSelectionKey: () => `${prefix}-integrity`,
      [`strategyModule_${prefix}_ManagedStart`]: () => ok(operations),
      strategyHostManagedInputMatchesMaterial: (actual, expected) =>
        actual === input && expected === material,
    };
    const product = factory(moon, {}, checkFixtureResult);
    const entry = hostFixture(product, () => Object.freeze({
      task: 1,
      durationMilliseconds: 1n,
      releasableProducers: [],
      outputs: new Map(),
      inputs: [placed.input({material, completed})],
      configuration: {},
    }));
    const core: Core = {
      siteControl,
      count: () => 2,
      next: () => assert.fail('Managed integrity fixture entered the legacy dispatcher'),
      taskCapacity: () => assert.fail('Managed integrity fixture quoted a legacy task'),
      nextTask: () => 1,
      managedProducers: () => [0],
      selectManaged: (_, task, selected) =>
        task === 1 && selected === registration,
      managedMatches: () => false,
      completed: () => commonCompleted,
      finished: () => false,
      stop: () => {},
      closeOutputs: () => {},
      output: () => undefined,
      usage: () => ({reservedExecutionBytes, reservedRetentionBytes}),
      explain: () => ({}),
    };
    const result = await runInstalledStrategy({setup: {}, runtime: {core, contributions: [entry], sitePolicy: placed.policy}});
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(commonCompleted, false);
    assert.deepEqual(events, ['finish', 'execute', 'close', 'settle']);
    assert.equal(store.status().activeReaders, 0);
    assert.partialDeepStrictEqual(result.usage(), {reservedExecutionBytes: 0n, reservedRetentionBytes: 0n});
    result.close();
    assert.equal(await result.cleanup(), true);
    body.close();
    await body.cleanupHandle.retry();
  });
}

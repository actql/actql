import test from 'node:test';
import assert from 'node:assert/strict';
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
import {managedPhysicalRepresentation} from
  '../store-local/managed-physical-representation.mjs';
import {encodeManagedColumnFrame, managedColumnCodecContractCid,
  managedColumnRowProvider} from '../duckdb-node/managed-column-codec.mjs';
import {checked} from './runtime-result.mjs';
import {runInstalledStrategy} from './strategy.mjs';
import {createInProcessExecutionSite, prepareExecutionSitePolicy} from
  './execution-sites.mjs';

const ok = _0 => ({$tag: 1, _0});
const failed = _0 => ({$tag: 0, _0});
const siteCase = key => {
  const site = createInProcessExecutionSite({
    key,
    generation: 1,
    runtimeRevision: 'managed-failure-test/1',
  });
  return {
    site,
    policy: prepareExecutionSitePolicy({sites: [site]}),
    input: value => Object.freeze({
      ...value,
      task: 0,
      site,
      siteMaterial: value.material,
      materialGeneration: value.material,
    }),
  };
};

function managedCase(factory, prefix, provider, overrides = {}) {
  const material = {}, input = {}, events = [];
  const memory = registerManagedMemoryInput(
    material,
    value => value === input,
    () => true,
    provider,
    () => events.push('released'),
  );
  const operations = {
    inputs: [{input, append: () => ok(), finish: () => ok()}],
    execute: () => ok(),
    settle: () => { events.push('settle'); return ok(); },
    complete: () => ok({}),
    material: () => ({}),
    output_rows: () => 0,
    output_row: () => failed(new Error('NoRow')),
    storage_bytes: 0n,
    close: () => { events.push('close'); },
    ...overrides,
  };
  const moon = {
    [`strategyModule_${prefix}_Registration`]: () => ({}),
    strategyHostRegistrationSelectionKey: () => prefix,
    [`strategyModule_${prefix}_ManagedStart`]: () => ok(operations),
    strategyHostManagedInputMatchesMaterial: () => true,
  };
  const entry = factory(moon, {}, checked);
  const prepared = {
    releasableProducers: [],
    outputs: new Map(),
    inputs: [{material}],
    configuration: {},
  };
  return {entry, prepared, events, memory};
}

for (const [name, factory, prefix] of [
  ['Local', localStrategyContribution, 'local'],
  ['reference', numericStrategyContribution, 'reference_compute'],
]) {
  test(`${name} managed completion observes the common Site readiness gate`, async () => {
    let completionCalls = 0;
    const f = managedCase(factory, prefix, {async read() {}}, {
      complete() {
        completionCalls++;
        return ok({});
      },
    });
    f.prepared.siteCompletionReady = () => false;
    await assert.rejects(
      f.entry.runPrepared(f.prepared),
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
        phase === 'execute' ? {execute: () => failed(primary)} : {},
      );
      await assert.rejects(f.entry.runPrepared(f.prepared), error =>
        phase === 'read' ? error === primary :
          error.code === 'MoonBitHostFailure' && error.cause === primary);
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
    let failure;
    try { await f.entry.runPrepared(f.prepared); }
    catch (error) { failure = error; }
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
    let failure;
    try { await f.entry.runPrepared(f.prepared); }
    catch (error) { failure = error; }
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(f.events, ['close', 'settle']);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(f.events, ['close', 'settle', 'close']);
  });

  test(`${name} managed unknown reader cleanup never guesses stopped`, async () => {
    const primary = Object.assign(new Error('unknown reader stop'), {
      cleanupPending: true,
    });
    const f = managedCase(factory, prefix, {
      async read() { throw primary; },
    });
    let failure;
    try { await f.entry.runPrepared(f.prepared); }
    catch (error) { failure = error; }
    assert.equal(failure.primaryFailure, primary);
    assert.deepEqual(f.events, ['close']);
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, true);
    assert.deepEqual(f.events, ['close']);
  });

  test(`${name} managed failures settle through the standard Host`, async () => {
    for (const phase of ['reader', 'evaluation-budget', 'cancellation']) {
      let enterRead;
      let releaseRead;
      const readEntered = new Promise(resolve => { enterRead = resolve; });
      const readWait = new Promise(resolve => { releaseRead = resolve; });
      const primary = Object.assign(new Error(`${phase} failed`), {
        code: phase === 'evaluation-budget'
          ? 'EvaluationBudgetExceeded' : 'ManagedReadFailed',
      });
      let reservedExecutionBytes = 1024n;
      let reservedRetentionBytes = 256n;
      const provider = {
        async read(_file, _emit, signal) {
          if (phase === 'reader') throw primary;
          if (phase === 'cancellation') {
            enterRead();
            await readWait;
            signal?.throwIfAborted();
          }
        },
      };
      const f = managedCase(factory, prefix, provider, {
        execute: () => phase === 'evaluation-budget'
          ? failed(primary) : ok(),
        settle: () => {
          f.events.push('settle');
          reservedExecutionBytes = 0n;
          reservedRetentionBytes = 0n;
          return ok();
        },
      });
      const registration = f.entry.registration;
      const placed = siteCase(`${prefix}-${phase}`);
      const entry = Object.freeze({
        ...f.entry,
        managedSelectionKey: `${prefix}-failure`,
        prepareNext: () => Object.freeze({
          ...f.prepared,
          task: 1,
          durationMilliseconds: 1n,
          inputs: f.prepared.inputs.map(placed.input),
        }),
      });
      const core = {
        count: () => 2,
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
      const running = runInstalledStrategy(
        {}, core, [entry], controller.signal, undefined, placed.policy,
      );
      if (phase === 'cancellation') {
        await readEntered;
        controller.abort();
        releaseRead();
      }
      const result = await running;
      assert.equal(result.status, 'host-tasks-failed');
      assert.deepEqual(f.events.slice(-2), ['close', 'settle']);
      assert.equal(result.usage().reservedExecutionBytes, 0n);
      assert.equal(result.usage().reservedRetentionBytes, 0n);
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
  const double = value => {
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

  const events = [];
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
    execute: () => ok(),
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
  const product = localStrategyContribution({
    strategyModule_local_Registration: () => registration,
    strategyHostRegistrationSelectionKey: () => 'local-file',
    strategyModule_local_ManagedStart: () => ok(operations),
    strategyHostManagedInputMatchesMaterial: (actual, expected) =>
      actual === input && expected === material,
  }, setup, checked);
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
  const core = {
    count: () => 2,
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
  const result = await runInstalledStrategy(
    setup, core, [entry], controller.signal, undefined, placed.policy,
  );
  assert.equal(result.status, 'host-tasks-failed');
  assert.equal(result.failure, controller.signal.reason);
  assert.equal(rows, 1);
  assert.deepEqual(provider.status(), {activeReads: 0, completedReads: 1});
  assert.deepEqual(events, ['close', ['settle-readers', 0]]);
  assert.equal(store.status().activeReaders, 0);
  assert.equal(result.usage().reservedExecutionBytes, 0n);
  assert.equal(result.usage().reservedRetentionBytes, 0n);
  result.close();
  assert.equal(await result.cleanup(), true);
  body.close();
  await body.cleanupHandle.retry();
});

for (const [name, factory, prefix] of [
  ['Local', localStrategyContribution, 'local'],
  ['reference', numericStrategyContribution, 'reference_compute'],
]) {
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
      Object.freeze({
        async read(file, emit, signal) {
          await base.read(file, emit, signal);
          await writeFile(file.path, changed);
        },
      }),
    );
    const events = [];
    let reservedExecutionBytes = 1024n;
    let reservedRetentionBytes = 256n;
    let commonCompleted = false;
    const operations = {
      inputs: [{
        input,
        append: () => ok(),
        finish: () => { events.push('finish'); return ok(); },
      }],
      execute: () => { events.push('execute'); return ok(); },
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
    const moon = {
      [`strategyModule_${prefix}_Registration`]: () => registration,
      strategyHostRegistrationSelectionKey: () => `${prefix}-integrity`,
      [`strategyModule_${prefix}_ManagedStart`]: () => ok(operations),
      strategyHostManagedInputMatchesMaterial: (actual, expected) =>
        actual === input && expected === material,
    };
    const product = factory(moon, {}, checked);
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
    const core = {
      count: () => 2,
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
    const result = await runInstalledStrategy(
      {}, core, [entry], undefined, undefined, placed.policy,
    );
    assert.equal(result.status, 'host-tasks-failed');
    assert.equal(commonCompleted, false);
    assert.deepEqual(events, ['finish', 'execute', 'close', 'settle']);
    assert.equal(store.status().activeReaders, 0);
    assert.equal(result.usage().reservedExecutionBytes, 0n);
    assert.equal(result.usage().reservedRetentionBytes, 0n);
    result.close();
    assert.equal(await result.cleanup(), true);
    body.close();
    await body.cleanupHandle.retry();
  });
}

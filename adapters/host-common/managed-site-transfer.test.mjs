import test from 'node:test';
import assert from 'node:assert/strict';
import {
  beginExecutionSiteTeardown,
  createInProcessExecutionSite,
  executionSiteCandidate,
  executionSiteStatus,
  installExecutionSites,
  prepareExecutionSitePolicy,
  revokeExecutionSite,
} from './execution-sites.mjs';
import {createManagedSiteTransferCoordinator} from
  './managed-site-transfer.mjs';
import {createManagedMemoryTransferProvider, managedMemoryTransferContract} from
  '../store-local/managed-memory-transfer.mjs';
import {registerManagedMemoryInput} from
  '../store-local/managed-memory-representations.mjs';

const estimate = Object.freeze({
  transferBytes: 4096n,
  retainedBytes: 16384n,
  executionBytes: 64n,
});

const site = key => createInProcessExecutionSite({
  key,
  generation: 1,
  runtimeRevision: 'transfer-test-runtime/1',
});

// Protocol test double for Coordinator lifecycle mechanics only. The real
// MoonBit ledger and common completion authority are exercised by the standard
// two-Site Host test; this object cannot issue a product task completion.
function coreFor(input, logicalMaterial, events = []) {
  let attempt = 0;
  const inputs = Array.isArray(input) ? input : [input];
  const materials = Array.isArray(logicalMaterial)
    ? logicalMaterial : [logicalMaterial];
  return Object.freeze({
    managedInputMatches(value, material) {
      return inputs.some((candidate, index) =>
        value === candidate && material === materials[index]);
    },
    transferBegin(_setup, sourceTask, transfer, retained, execution) {
      events.push(['begin', sourceTask, transfer, retained, execution]);
      return {attempt: ++attempt, sourceTask, transferred: 0n, settled: false};
    },
    transferCharge(_setup, transfer, bytes) {
      transfer.transferred += bytes;
      events.push(['charge', bytes]);
    },
    transferSettle(_setup, transfer, confirmed) {
      events.push(['settle', confirmed]);
      if (confirmed) transfer.settled = true;
    },
    transferComplete(_setup, transfer, retained) {
      assert.equal(transfer.settled, true);
      events.push(['complete', retained]);
      return {transfer, retained};
    },
    transferReceipt(receipt) {
      return [receipt.transfer.sourceTask, receipt.transfer.attempt,
        receipt.transfer.transferred, receipt.retained, 1];
    },
    transferAbort(_setup, transfer, confirmed) {
      assert.equal(confirmed, true);
      transfer.settled = true;
      events.push(['abort']);
    },
    transferRelease(_setup, receipt) {
      events.push(['release', receipt.transfer.attempt]);
    },
  });
}

function setup(provider, sourceSite = site('source'), destinationSite = site('destination')) {
  const contribution = Object.freeze({
    registration: Object.freeze({}),
    managedSelectionKey: 'consumer',
  });
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: sourceSite === destinationSite
      ? [sourceSite] : [sourceSite, destinationSite],
    placements: new Map([['consumer', [destinationSite]]]),
    transferProvider: provider.contract ? provider : Object.freeze({
      contract: managedMemoryTransferContract,
      ...provider,
    }),
  }), [contribution]);
  return {sourceSite, destinationSite, contribution, installation};
}

function candidateFor(
  context, sourceMaterial, logicalMaterial, generation = {}, sourceTask = 1,
  transferMode,
) {
  const occurrence = Object.freeze({
    task: sourceTask,
    material: logicalMaterial,
    site: context.sourceSite,
    siteMaterial: sourceMaterial,
    materialGeneration: generation,
    transferMode,
  });
  const candidate = executionSiteCandidate({
    installation: context.installation,
    contribution: context.contribution,
    site: context.destinationSite,
    task: sourceTask + 1,
    registration: context.contribution.registration,
    inputs: [occurrence],
    durationMilliseconds: 1n,
    acceptsSiteTransfer: true,
  });
  assert.equal(candidate.excluded, undefined);
  return {candidate, occurrence};
}

test('explicit same-Site preservation copy creates a new material generation', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  const source = registerManagedMemoryInput(
    sourceMaterial,
    value => value === input,
    () => true,
    Object.freeze({
      async read(_file, emit) {
        await emit('{"id":1}');
        await emit('{"id":1}');
      },
    }),
    () => {},
    estimate,
  );
  const sameSite = site('same-site');
  const context = setup(createManagedMemoryTransferProvider({
    maxBatchRows: 1,
    maxBatchBytes: 64,
  }), sameSite, sameSite);
  const {candidate} = candidateFor(
    context,
    sourceMaterial,
    logicalMaterial,
    {},
    1,
    'preserve-to-independent-material',
  );
  assert.equal(candidate.transfers.length, 1);
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial), context.installation,
  );
  const result = await coordinator.resolve(candidate, [input]);
  assert.notEqual(result.materials[0], sourceMaterial);
  assert.equal(result.records[0].sourceSite.key, 'same-site');
  assert.equal(result.records[0].destinationSite.key, 'same-site');
  assert.equal(result.records[0].rows, 2);
  await coordinator.close();
  await source.close();
  beginExecutionSiteTeardown(sameSite);
  assert.equal(executionSiteStatus(sameSite).teardownComplete, true);
});

test('cache shares only the exact source occurrence, not a physical handle', async () => {
  const firstInput = {}, secondInput = {};
  const firstLogical = {}, secondLogical = {}, sourceMaterial = {};
  const source = registerManagedMemoryInput(
    sourceMaterial,
    value => value === firstInput || value === secondInput,
    () => true,
    Object.freeze({
      async read(_file, emit) { await emit('{"id":1}'); },
    }),
    () => {},
    estimate,
  );
  const context = setup(createManagedMemoryTransferProvider({
    maxBatchRows: 2,
    maxBatchBytes: 64,
  }));
  const first = candidateFor(
    context, sourceMaterial, firstLogical, {}, 1,
  );
  const second = candidateFor(
    context, sourceMaterial, secondLogical, {}, 2,
  );
  const events = [];
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(
      [firstInput, secondInput], [firstLogical, secondLogical], events,
    ), context.installation,
  );
  const firstResult = await coordinator.resolve(
    first.candidate, [firstInput],
  );
  const secondResult = await coordinator.resolve(
    second.candidate, [secondInput],
  );
  assert.notEqual(firstResult.materials[0], secondResult.materials[0]);
  assert.notEqual(firstResult.records[0].transferAttempt,
    secondResult.records[0].transferAttempt);
  assert.equal(firstResult.records[0].sourceTask, 1);
  assert.equal(secondResult.records[0].sourceTask, 2);
  assert.equal(events.filter(([name]) => name === 'begin').length, 2);
  await coordinator.releaseSource(first.occurrence);
  assert.deepEqual(events.filter(([name]) => name === 'release')
    .map(([, attempt]) => attempt), [1]);
  const secondAgain = await coordinator.resolve(
    second.candidate, [secondInput],
  );
  assert.equal(secondAgain.materials[0], secondResult.materials[0],
    'releasing one occurrence must not close another occurrence on the same physical source');
  assert.equal(events.filter(([name]) => name === 'begin').length, 2);
  await coordinator.close();
  assert.deepEqual(events.filter(([name]) => name === 'release')
    .map(([, attempt]) => attempt), [1, 2]);
  await source.close();
});

test('delayed source stop retains its exact pin but not destination cleanup', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let stopped = false;
  const nativeCleanup = Object.freeze({
    status: () => Object.freeze({pending: !stopped}),
    async retry() { stopped = true; return this.status(); },
  });
  const source = registerManagedMemoryInput(
    sourceMaterial,
    value => value === input,
    () => true,
    Object.freeze({
      async read() {
        throw Object.assign(new Error('source still stopping'), {
          cleanupPending: true,
          cleanupHandle: nativeCleanup,
        });
      },
    }),
    () => {},
    estimate,
  );
  const provider = createManagedMemoryTransferProvider({
    maxBatchRows: 2,
    maxBatchBytes: 64,
  });
  const context = setup(provider);
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const events = [];
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial, events), context.installation,
  );
  let failure;
  try { await coordinator.resolve(candidate, [input]); }
  catch (error) { failure = error; }
  assert(failure);
  assert.equal(failure.cleanupPending, true);
  assert.equal(source.status().readers, 1);
  assert.equal(executionSiteStatus(context.sourceSite).activeTransfers, 1);
  assert.equal(executionSiteStatus(context.destinationSite).activeTransfers, 0);
  assert.equal(beginExecutionSiteTeardown(context.sourceSite).teardownComplete,
    false);
  assert.equal(beginExecutionSiteTeardown(
    context.destinationSite).teardownComplete, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(source.status().readers, 0);
  assert.equal(beginExecutionSiteTeardown(
    context.sourceSite).teardownComplete, true);
  assert.deepEqual(events.filter(([name]) => name === 'abort'), [['abort']]);
  await source.close();
});

test('Transfer commit rejects forced loss of either admitted Site generation', async () => {
  for (const lost of ['sourceSite', 'destinationSite']) {
    const input = {}, logicalMaterial = {}, sourceMaterial = {};
    let context;
    const source = registerManagedMemoryInput(
      sourceMaterial,
      value => value === input,
      () => true,
      Object.freeze({
        async read(_file, emit) {
          await emit('{"id":1}');
          revokeExecutionSite(context[lost]);
        },
      }),
      () => {},
      estimate,
    );
    context = setup(createManagedMemoryTransferProvider({
      maxBatchRows: 1,
      maxBatchBytes: 64,
    }));
    const {candidate} = candidateFor(
      context, sourceMaterial, logicalMaterial,
    );
    const events = [];
    const coordinator = createManagedSiteTransferCoordinator(
      {}, coreFor(input, logicalMaterial, events), context.installation,
    );
    let failure;
    try { await coordinator.resolve(candidate, [input]); }
    catch (error) { failure = error; }
    assert.equal(failure?.code, 'ExecutionSiteTransferCommitRejected');
    assert.equal(events.some(([name]) => name === 'complete'), false);
    assert.equal(executionSiteStatus(context.destinationSite).holdings, 0);
    assert.equal(failure.cleanupPending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.equal(executionSiteStatus(context.sourceSite).activeTransfers, 0);
    assert.equal(executionSiteStatus(context.destinationSite).activeTransfers, 0);
    assert.equal(executionSiteStatus(context.destinationSite).holdings, 0);
    assert.deepEqual(events.filter(([name]) => name === 'abort'), [['abort']]);
    await source.close();
  }
});

test('graceful teardown permits admitted Transfer and committed copy survives source loss', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let context;
  const source = registerManagedMemoryInput(
    sourceMaterial,
    value => value === input,
    () => true,
    Object.freeze({
      async read(_file, emit) {
        await emit('{"id":1}');
        beginExecutionSiteTeardown(context.sourceSite);
      },
    }),
    () => {},
    estimate,
  );
  context = setup(createManagedMemoryTransferProvider({
    maxBatchRows: 1,
    maxBatchBytes: 64,
  }));
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const events = [];
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial, events), context.installation,
  );
  const first = await coordinator.resolve(candidate, [input]);
  assert.equal(first.records.length, 1);
  assert.equal(events.filter(([name]) => name === 'complete').length, 1);
  revokeExecutionSite(context.sourceSite);
  const second = await coordinator.resolve(candidate, [input]);
  assert.equal(second.materials[0], first.materials[0]);
  assert.equal(second.records[0].transferAttempt,
    first.records[0].transferAttempt);
  await coordinator.close();
  assert.equal(executionSiteStatus(context.destinationSite).holdings, 0);
  await source.close();
});

test('destination-generation failure does not invalidate a trusted source', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let copies = 0;
  const provider = Object.freeze({
    estimate: () => estimate,
    async copy() {
      copies++;
      throw Object.assign(new Error('destination failed'), {
        code: 'DestinationGenerationFailed',
      });
    },
  });
  const context = setup(provider);
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const events = [];
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial, events), context.installation,
  );
  await assert.rejects(coordinator.resolve(candidate, [input]), {
    code: 'DestinationGenerationFailed',
  });
  assert.equal(copies, 1);
  assert.equal(executionSiteStatus(context.sourceSite).activeTransfers, 0);
  assert.equal(executionSiteStatus(context.destinationSite).activeTransfers, 0);
  assert.deepEqual(events.filter(([name]) => name === 'abort'), [['abort']]);
});

test('a Transfer cannot relabel the source material or generation', async () => {
  for (const reuse of ['material', 'generation']) {
    const input = {}, logicalMaterial = {}, sourceMaterial = {};
    const sourceGeneration = {};
    const provider = Object.freeze({
      estimate: () => estimate,
      async copy() {
        return Object.freeze({
          material: reuse === 'material' ? sourceMaterial : {},
          generation: reuse === 'generation' ? sourceGeneration : {},
          rows: 0,
          batches: 0,
          maxBatchRows: 1,
          maxBatchBytes: 64,
          bytes: 0n,
          retainedBytes: 0n,
          status: () => Object.freeze({released: false}),
          close() {},
        });
      },
    });
    const context = setup(provider);
    const {candidate} = candidateFor(
      context, sourceMaterial, logicalMaterial, sourceGeneration,
    );
    const events = [];
    const coordinator = createManagedSiteTransferCoordinator(
      {}, coreFor(input, logicalMaterial, events), context.installation,
    );
    let failure;
    try { await coordinator.resolve(candidate, [input]); }
    catch (error) { failure = error; }
    assert.equal(failure?.code, 'InvalidTransferDestination');
    assert.equal(failure.cleanupPending, true);
    assert.equal((await failure.cleanupHandle.retry()).pending, false);
    assert.deepEqual(events.filter(([name]) => name === 'abort'), [['abort']]);
    assert.equal(beginExecutionSiteTeardown(
      context.sourceSite).teardownComplete, true);
    assert.equal(beginExecutionSiteTeardown(
      context.destinationSite).teardownComplete, true);
  }
});

test('failure after Transfer commit releases the receipt instead of aborting it', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let closes = 0;
  const provider = Object.freeze({
    estimate: () => estimate,
    async copy({authorize, charge}) {
      assert.equal(authorize(input), true);
      charge(3n);
      return Object.freeze({
        material: {},
        generation: {},
        rows: 1,
        batches: 1,
        maxBatchRows: 1,
        maxBatchBytes: 64,
        bytes: 3n,
        retainedBytes: 8n,
        status: () => Object.freeze({released: closes === 1}),
        async close() { closes++; },
      });
    },
  });
  const context = setup(provider);
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const events = [];
  const base = coreFor(input, logicalMaterial, events);
  const core = Object.freeze({
    ...base,
    transferReceipt() { throw new Error('receipt transport failed'); },
  });
  const coordinator = createManagedSiteTransferCoordinator(
    {}, core, context.installation,
  );
  let failure;
  try { await coordinator.resolve(candidate, [input]); }
  catch (error) { failure = error; }
  assert(failure);
  assert.equal(failure.cleanupPending, true);
  assert.equal(beginExecutionSiteTeardown(
    context.sourceSite).teardownComplete, true);
  assert.equal(beginExecutionSiteTeardown(
    context.destinationSite).teardownComplete, false,
  );
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(closes, 1);
  assert.equal(executionSiteStatus(context.destinationSite).teardownComplete,
    true);
  assert.equal(events.filter(([name]) => name === 'release').length, 1);
  assert.equal(events.filter(([name]) => name === 'abort').length, 0);
});

test('one-sided destination cleanup retries without retaining the source Site', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let closes = 0, cleanupRetries = 0, cleanupPending = true;
  const destinationMaterial = {};
  const cleanupHandle = Object.freeze({
    status: () => Object.freeze({pending: cleanupPending}),
    async retry() {
      cleanupRetries++;
      cleanupPending = false;
      return this.status();
    },
  });
  const provider = Object.freeze({
    estimate: () => estimate,
    async copy({authorize, charge}) {
      assert.equal(authorize(input), true);
      charge(3n);
      return Object.freeze({
        material: destinationMaterial,
        generation: {},
        rows: 1,
        batches: 1,
        maxBatchRows: 1,
        maxBatchBytes: 64,
        bytes: 3n,
        retainedBytes: 8n,
        status: () => Object.freeze({released: !cleanupPending}),
        async close() {
          closes++;
          throw Object.assign(new Error('destination cleanup failed'), {
            cleanupPending: true,
            cleanupHandle,
          });
        },
      });
    },
  });
  const context = setup(provider);
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const events = [];
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial, events), context.installation,
  );
  const first = await coordinator.resolve(candidate, [input]);
  const second = await coordinator.resolve(candidate, [input]);
  assert.equal(first.materials[0], destinationMaterial);
  assert.equal(second.materials[0], destinationMaterial);
  assert.equal(first.records[0].transferAttempt,
    second.records[0].transferAttempt,
    'a completed destination generation may be shared');
  assert.equal(events.filter(([name]) => name === 'begin').length, 1);
  assert.equal(beginExecutionSiteTeardown(context.sourceSite).teardownComplete,
    true, 'the Transfer source pin ended when copying stopped');
  assert.equal(beginExecutionSiteTeardown(
    context.destinationSite).teardownComplete, false);
  let failure;
  try { await coordinator.close(); }
  catch (error) { failure = error; }
  assert(failure);
  assert.equal(failure.cleanupPending, true);
  assert.equal(executionSiteStatus(context.sourceSite).teardownComplete, true);
  assert.equal(executionSiteStatus(context.destinationSite).teardownComplete,
    false);
  assert.equal((await failure.cleanupHandle.retry()).pending, false);
  assert.equal(closes, 1,
    'cleanup recovery must not guess that close itself is retryable');
  assert.equal(cleanupRetries, 1);
  assert.equal(executionSiteStatus(context.destinationSite).teardownComplete,
    true);
  assert.equal(events.filter(([name]) => name === 'release').length, 1);
});

test('destination cleanup without an explicit recovery handle is never retried', async () => {
  const input = {}, logicalMaterial = {}, sourceMaterial = {};
  let closes = 0;
  const provider = Object.freeze({
    estimate: () => estimate,
    async copy({authorize}) {
      assert.equal(authorize(input), true);
      return Object.freeze({
        material: {},
        generation: {},
        rows: 1,
        batches: 1,
        maxBatchRows: 1,
        maxBatchBytes: 64,
        bytes: 0n,
        retainedBytes: 8n,
        status: () => Object.freeze({released: false}),
        close() {
          closes++;
          throw new Error('no retry contract');
        },
      });
    },
  });
  const context = setup(provider);
  const {candidate} = candidateFor(
    context, sourceMaterial, logicalMaterial,
  );
  const coordinator = createManagedSiteTransferCoordinator(
    {}, coreFor(input, logicalMaterial), context.installation,
  );
  await coordinator.resolve(candidate, [input]);
  let failure;
  try { await coordinator.close(); }
  catch (error) { failure = error; }
  assert(failure);
  assert.equal(failure.cleanupPending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal((await failure.cleanupHandle.retry()).pending, true);
  assert.equal(closes, 1);
  assert.equal(beginExecutionSiteTeardown(
    context.sourceSite).teardownComplete, true);
  assert.equal(beginExecutionSiteTeardown(
    context.destinationSite).teardownComplete, false);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  beginExecutionSiteTeardown,
  bindExecutionSiteCandidate,
  createInProcessExecutionSite,
  executionSiteCandidate,
  executionSitePlacements,
  executionSiteStatus,
  installExecutionSites as installProductExecutionSites,
  prepareExecutionSitePolicy,
  releaseExecutionSiteCleanup,
  releaseExecutionSiteHolding,
  retainExecutionSiteCleanup,
  retainExecutionSiteHolding,
  retainExecutionSiteOperationHolding,
  retainExecutionSiteTransferHolding,
  revokeExecutionSite,
  settleExecutionSiteOperation,
  settleExecutionSiteTransferDestination,
  settleExecutionSiteTransferSource,
  startExecutionSiteTransferOperation,
  startExecutionSiteOperation,
} from './execution-sites.mjs';
import {createExecutionSiteControlFixture} from
  './execution-site-control.fixture.mjs';
import {managedMemoryTransferContract} from
  '../store-local/managed-memory-transfer.mjs';

const transferProvider = provider => Object.freeze({
  contract: managedMemoryTransferContract,
  ...provider,
});
const siteControl = createExecutionSiteControlFixture();

const site = (key, generation = 1, extra = {}) => {
  const value = createInProcessExecutionSite({
    key,
    generation,
    runtimeRevision: 'test-runtime/1',
    ...extra,
  });
  installProductExecutionSites(
    prepareExecutionSitePolicy({sites: [value]}),
    [Object.freeze({registration: {}, managedSelectionKey: 'fixture'})],
    siteControl,
  );
  return value;
};
const contribution = key => Object.freeze({
  registration: Object.freeze({}),
  managedSelectionKey: key,
});
const installExecutionSites = (policy, contributions) =>
  installProductExecutionSites(policy, contributions, siteControl);

test('product Site installation has no JavaScript semantic fallback', () => {
  const value = createInProcessExecutionSite({
    key: 'requires-portable-control',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
  });
  assert.throws(() => installProductExecutionSites(
    prepareExecutionSitePolicy({sites: [value]}),
    [contribution('implementation')],
  ), {code: 'MissingExecutionSiteControl'});
});

test('Site placement is independent from implementation registration', () => {
  const a = site('a');
  const b = site('b');
  const first = contribution('first');
  const second = contribution('second');
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [a, b],
    placements: new Map([
      ['first', [a, b]],
      ['second', [b]],
    ]),
  }), [first, second]);
  assert.deepEqual(executionSitePlacements(installation, first), [a, b]);
  assert.deepEqual(executionSitePlacements(installation, second), [b]);
});

test('candidate comparison facts are pure and missing estimates are explicit', () => {
  const a = site('a');
  const b = site('b', 1, {startupMilliseconds: 2n,
    transferMilliseconds: 3n});
  const implementation = contribution('implementation');
  const source = {};
  const input = Object.freeze({
    task: 1,
    material: {},
    site: a,
    siteMaterial: source,
    materialGeneration: {},
  });
  const withoutEstimate = installExecutionSites(prepareExecutionSitePolicy({
    sites: [a, b],
    placements: new Map([['implementation', [b]]]),
    transferProvider: transferProvider({estimate: () => undefined, copy() {}}),
  }), [implementation]);
  assert.equal(executionSiteCandidate({
    installation: withoutEstimate,
    contribution: implementation,
    site: b,
    task: 2,
    registration: implementation.registration,
    inputs: [input],
    durationMilliseconds: 5n,
    acceptsSiteTransfer: true,
  }).excluded, 'MissingTransferEstimate');

  const estimate = Object.freeze({
    transferBytes: 10n,
    retainedBytes: 20n,
    executionBytes: 30n,
  });
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [a, b],
    placements: new Map([['implementation', [b]]]),
    transferProvider: transferProvider({
      estimate: value => value === source ? estimate : undefined,
      copy() {},
    }),
  }), [implementation]);
  const candidate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: b,
    task: 2,
    registration: implementation.registration,
    inputs: [input],
    durationMilliseconds: 5n,
    acceptsSiteTransfer: true,
  });
  assert.equal(candidate.excluded, undefined);
  assert.equal(candidate.durationMilliseconds, 10n);
  assert.equal(candidate.transfers[0].estimate, estimate);
  const duplicate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: b,
    task: 2,
    registration: implementation.registration,
    inputs: [input, input],
    durationMilliseconds: 5n,
    acceptsSiteTransfer: true,
  });
  assert.equal(duplicate.durationMilliseconds, 10n,
    'one exact physical Transfer is not estimated twice for duplicate logical ports');
  assert.equal(duplicate.transfers.length, 2,
    'logical input occurrences remain independently represented');
  assert.equal(duplicate.transfers[1].sharedWith, input);
  const distinct = Object.freeze({...input, siteMaterial: source,
    materialGeneration: {}});
  const separate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: b,
    task: 2,
    registration: implementation.registration,
    inputs: [input, distinct],
    durationMilliseconds: 5n,
    acceptsSiteTransfer: true,
  });
  assert.equal(separate.durationMilliseconds, 13n,
    'physically distinct generations keep separate Transfer cost');
  assert.equal(executionSiteStatus(a).activeOperations, 0,
    'support and estimation must not acquire Site resources');
  assert.equal(executionSiteStatus(b).activeOperations, 0);
});

test('Site candidate facts fit the portable signed 64-bit boundary', () => {
  const tooLarge = 9223372036854775808n;
  assert.throws(() => createInProcessExecutionSite({
    key: 'oversized-duration',
    generation: 1,
    runtimeRevision: 'test-runtime/1',
    startupMilliseconds: tooLarge,
  }), {code: 'InvalidExecutionSite'});

  const source = site('bounded-source');
  const destination = site('bounded-destination');
  const implementation = contribution('bounded-implementation');
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [source, destination],
    placements: new Map([['bounded-implementation', [destination]]]),
    transferProvider: transferProvider({
      estimate: () => ({
        transferBytes: tooLarge,
        retainedBytes: 1n,
        executionBytes: 1n,
      }),
      copy() {},
    }),
  }), [implementation]);
  assert.throws(() => executionSiteCandidate({
    installation,
    contribution: implementation,
    site: destination,
    task: 2,
    registration: implementation.registration,
    inputs: [Object.freeze({
      task: 1,
      material: {},
      site: source,
      siteMaterial: {},
      materialGeneration: {},
    })],
    durationMilliseconds: 1n,
    acceptsSiteTransfer: true,
  }), {code: 'InvalidTransferEstimate'});
});

test('binding rechecks Site state and teardown waits for live owners', () => {
  const a = site('a', 4, {maxConcurrentOperations: 1});
  const implementation = contribution('implementation');
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [a], placements: new Map([['implementation', [a]]]),
  }), [implementation]);
  const candidate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: a,
    task: 1,
    registration: implementation.registration,
    inputs: [],
    durationMilliseconds: 0n,
  });
  const operation = startExecutionSiteOperation(
    bindExecutionSiteCandidate(candidate),
  );
  const holding = retainExecutionSiteHolding(a, {});
  assert.equal(beginExecutionSiteTeardown(a).teardownComplete, false);
  assert.throws(() => bindExecutionSiteCandidate(candidate), {
    code: 'StaleExecutionSiteBinding',
  });
  assert.equal(settleExecutionSiteOperation(operation), true);
  assert.equal(executionSiteStatus(a).teardownComplete, false);
  assert.equal(releaseExecutionSiteHolding(holding), true);
  assert.equal(executionSiteStatus(a).teardownComplete, true);
});

test('revocation invalidates a selected candidate before dispatch', () => {
  const a = site('a');
  const implementation = contribution('implementation');
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [a], placements: new Map([['implementation', [a]]]),
  }), [implementation]);
  const candidate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: a,
    task: 1,
    registration: implementation.registration,
    inputs: [],
    durationMilliseconds: 0n,
  });
  revokeExecutionSite(a);
  assert.throws(() => bindExecutionSiteCandidate(candidate), {
    code: 'StaleExecutionSiteBinding',
  });
});

test('candidate and binding retain exact registration and source Site generation', () => {
  const source = site('source');
  const destination = site('destination');
  const implementation = Object.freeze({
    registration: {},
    managedSelectionKey: 'implementation',
  });
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [source, destination],
    placements: new Map([['implementation', [destination]]]),
    transferProvider: transferProvider({
      estimate: () => ({
        transferBytes: 1n,
        retainedBytes: 1n,
        executionBytes: 1n,
      }),
      copy() {},
    }),
  }), [implementation]);
  const input = Object.freeze({
    task: 1,
    material: {},
    site: source,
    siteMaterial: {},
    materialGeneration: {},
  });
  assert.throws(() => executionSiteCandidate({
    installation,
    contribution: implementation,
    site: destination,
    task: 2,
    registration: {},
    inputs: [input],
    durationMilliseconds: 1n,
    acceptsSiteTransfer: true,
  }), {code: 'InvalidExecutionSiteCandidate'});
  const candidate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: destination,
    task: 2,
    registration: implementation.registration,
    inputs: [input],
    durationMilliseconds: 1n,
    acceptsSiteTransfer: true,
  });
  revokeExecutionSite(source);
  assert.throws(() => bindExecutionSiteCandidate(candidate), {
    code: 'StaleExecutionSiteBinding',
  });
});

test('binding rechecks the selected Transfer estimate before dispatch', () => {
  const source = site('source');
  const destination = site('destination');
  const implementation = contribution('implementation');
  const material = {};
  const estimate = Object.freeze({
    transferBytes: 1n,
    retainedBytes: 2n,
    executionBytes: 3n,
  });
  let current = estimate;
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [source, destination],
    placements: new Map([['implementation', [destination]]]),
    transferProvider: transferProvider({
      estimate: value => value === material ? current : undefined,
      copy() {},
    }),
  }), [implementation]);
  const candidate = executionSiteCandidate({
    installation,
    contribution: implementation,
    site: destination,
    task: 2,
    registration: implementation.registration,
    inputs: [{task: 1, material: {}, site: source, siteMaterial: material,
      materialGeneration: {}}],
    durationMilliseconds: 1n,
    acceptsSiteTransfer: true,
  });
  current = undefined;
  assert.throws(() => bindExecutionSiteCandidate(candidate), {
    code: 'StaleExecutionSiteBinding',
  });
  assert.equal(executionSiteStatus(source).activeTransfers, 0);
  assert.equal(executionSiteStatus(destination).activeTransfers, 0);
});

test('Transfer source and destination stop independently during teardown', () => {
  const source = site('source');
  const destination = site('destination');
  const operation = startExecutionSiteTransferOperation(source, destination);
  beginExecutionSiteTeardown(source);
  beginExecutionSiteTeardown(destination);
  assert.equal(executionSiteStatus(source).activeTransfers, 1);
  assert.equal(executionSiteStatus(destination).activeTransfers, 1);
  settleExecutionSiteTransferSource(operation);
  assert.equal(executionSiteStatus(source).teardownComplete, true);
  assert.equal(executionSiteStatus(destination).teardownComplete, false);
  settleExecutionSiteTransferDestination(operation);
  assert.equal(executionSiteStatus(destination).teardownComplete, true);
});

test('stopped destination work does not hide unreclaimed Site state', () => {
  const source = site('source');
  const destination = site('destination');
  const operation = startExecutionSiteTransferOperation(source, destination);
  const cleanup = retainExecutionSiteCleanup(destination, operation);
  settleExecutionSiteTransferSource(operation);
  settleExecutionSiteTransferDestination(operation);
  beginExecutionSiteTeardown(source);
  beginExecutionSiteTeardown(destination);
  assert.equal(executionSiteStatus(source).teardownComplete, true);
  assert.equal(executionSiteStatus(destination).activeTransfers, 0);
  assert.equal(executionSiteStatus(destination).cleanupResponsibilities, 1);
  assert.equal(executionSiteStatus(destination).teardownComplete, false);
  assert.equal(releaseExecutionSiteCleanup(cleanup), true);
  assert.equal(executionSiteStatus(destination).cleanupResponsibilities, 0);
  assert.equal(executionSiteStatus(destination).teardownComplete, true);
});

test('Transfer admission rechecks finite capacity at both Sites', () => {
  const source = site('source', 1, {maxConcurrentTransfers: 1});
  const destination = site('destination', 1, {maxConcurrentTransfers: 1});
  const first = startExecutionSiteTransferOperation(source, destination);
  assert.throws(
    () => startExecutionSiteTransferOperation(source, destination),
    {code: 'ExecutionSiteTransferAdmissionRejected'},
  );
  settleExecutionSiteTransferSource(first);
  assert.throws(
    () => startExecutionSiteTransferOperation(source, destination),
    {code: 'ExecutionSiteTransferAdmissionRejected'},
    'destination capacity remains owned until its mutation stops',
  );
  settleExecutionSiteTransferDestination(first);
  const second = startExecutionSiteTransferOperation(source, destination);
  settleExecutionSiteTransferSource(second);
  settleExecutionSiteTransferDestination(second);
});

test('Site byte sub-scope reserves atomically and follows holding lifetime', () => {
  const target = site('bounded', 1, {
    maxRetainedBytes: 10n,
    maxExecutionBytes: 5n,
    maxConcurrentOperations: 2,
  });
  const implementation = contribution('implementation');
  const installation = installExecutionSites(prepareExecutionSitePolicy({
    sites: [target],
    placements: new Map([['implementation', [target]]]),
  }), [implementation]);
  const candidateForCapacity = capacity => executionSiteCandidate({
    installation,
    contribution: implementation,
    site: target,
    task: 1,
    registration: implementation.registration,
    inputs: [],
    durationMilliseconds: 0n,
    capacity,
  });
  const operation = startExecutionSiteOperation(bindExecutionSiteCandidate(
    candidateForCapacity({retainedBytes: 8n, executionBytes: 4n}),
  ));
  assert.deepEqual(executionSiteStatus(target), {
    ...executionSiteStatus(target),
    heldBytes: 0n,
    reservedRetentionBytes: 8n,
    reservedExecutionBytes: 4n,
    peakRetainedBytes: 8n,
  });
  assert.throws(() => startExecutionSiteOperation(bindExecutionSiteCandidate(
    candidateForCapacity({retainedBytes: 3n, executionBytes: 1n}),
  )), {code: 'ExecutionSiteAdmissionRejected'});
  assert.equal(executionSiteStatus(target).reservedRetentionBytes, 8n,
    'failed admission must not leave a partial Site reservation');
  const holding = retainExecutionSiteOperationHolding(operation, {}, 7n);
  settleExecutionSiteOperation(operation);
  assert.equal(executionSiteStatus(target).heldBytes, 7n);
  assert.equal(executionSiteStatus(target).reservedRetentionBytes, 0n);
  assert.equal(executionSiteStatus(target).reservedExecutionBytes, 0n);
  revokeExecutionSite(target);
  assert.equal(executionSiteStatus(target).heldBytes, 7n,
    'Site revocation does not release an unreclaimed allocation');
  releaseExecutionSiteHolding(holding);
  assert.equal(executionSiteStatus(target).heldBytes, 0n);
});

test('same-Site preservation Transfer keeps one operation and a distinct allocation', () => {
  const target = site('same-site', 1, {
    maxRetainedBytes: 10n,
    maxExecutionBytes: 5n,
  });
  const operation = startExecutionSiteTransferOperation(target, target, {
    retainedBytes: 8n,
    executionBytes: 4n,
  });
  assert.equal(executionSiteStatus(target).activeTransfers, 1);
  settleExecutionSiteTransferSource(operation);
  assert.equal(executionSiteStatus(target).activeTransfers, 1,
    'a same-Site operation remains live while destination mutation continues');
  const holding = retainExecutionSiteTransferHolding(operation, {}, 6n);
  settleExecutionSiteTransferDestination(operation);
  assert.equal(executionSiteStatus(target).activeTransfers, 0);
  assert.equal(executionSiteStatus(target).heldBytes, 6n);
  assert.equal(executionSiteStatus(target).reservedRetentionBytes, 0n);
  assert.equal(executionSiteStatus(target).reservedExecutionBytes, 0n);
  releaseExecutionSiteHolding(holding);
  assert.equal(executionSiteStatus(target).heldBytes, 0n);
});

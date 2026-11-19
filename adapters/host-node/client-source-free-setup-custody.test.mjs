import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientDispatchOwner} from './client-dispatch-owner.mjs';
import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';

function fixture({reserved = true, failCleanup = false, unresolved = false} = {}) {
  const ref = {runDefinitionCid: 'source-free-setup-custody'};
  const setup = {};
  const stops = [];
  let closes = 0, computes = 0, cancellation = false, revision = 1;
  const runDefinition = {wire: 'definition'};
  let frame = Object.freeze({cancellationRequested: cancellation,
    revision, runDefinition, physicalCloseConfirmed: false});
  const currentFrame = () => {
    if (frame.revision !== revision) frame = Object.freeze({...frame,
      cancellationRequested: cancellation, revision});
    return frame;
  };
  let held, resume;
  const ready = new Promise(resolve => { held = resolve; });
  const barrier = new Promise(resolve => { resume = resolve; });
  let retry = !failCleanup;
  const owner = installNodeClientDispatchOwner({
    moon: {clientProgramOpenSourceFreeLocalHost: () => setup,
      clientProgramRequiresAcquisitionResultPublication: () => false,
      strategyHostStop: value => assert.equal(value, setup),
      strategyHostCloseOutputs(value) {
        assert.equal(value, setup);
        closes++;
        if (!retry) throw new Error('SetupCleanupPending');
      },
      strategyHostUsage: () => Array(ledgerUsageFields.length).fill(0n)},
    control: {runDefinitionRunId: () => 'setup-run',
      runCancellationConfirmed: runtimeCore(moon).publicationControl.runCancellationConfirmed},
    journal: {reservePhysicalStart: () => reserved,
      lookupRunDefinition: currentFrame,
      lookupReconciliationState: () => unresolved ? {} : undefined,
      markPhysicalClose(originalRef, outcome, original) {
        assert.equal(originalRef, ref);
        assert.equal(original, currentFrame());
        frame = Object.freeze({...frame, revision: ++revision, physicalCloseConfirmed: true});
        stops.push([originalRef, outcome]);
      },
      markPreDispatchFailure() { assert.fail('Cancellation is not pre-dispatch failure'); }},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: 'values'}),
    runPublished() { computes++; assert.fail('The cancelled setup must not enter Compute'); },
    async faultInjection(name) {
      if (name === 'physical_start_reserved') { held(); await barrier; }
    },
    namespaceId: 'setup-namespace',
  });
  const start = gate => owner.start({preparedProgram: {}, principalId: 'owner',
    connection: {}, requestId: 'setup-request'}, {},
  {ref, runDefinition, dispatchReserved: false,
    cancellationRequested: false}, {}, undefined, gate);
  return {owner, ref, start, ready, resume, stops,
    closes: () => closes, computes: () => computes,
    retry: () => { retry = true; },
    cancel() { cancellation = true; revision++; owner.cancel(ref); }};
}

test('source-free setup is held across cancellation and failed cleanup until same-owner retry', async () => {
  const f = fixture({failCleanup: true});
  assert.equal(await f.start(), 'started');
  await f.ready;
  f.cancel(); f.resume();
  await f.owner.operation(f.ref);
  assert.deepEqual(f.stops, []);
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  f.retry();
  await f.owner.drain();
  assert.equal(f.computes(), 0);
  assert.deepEqual(f.stops, [[f.ref, 'cancelled']]);
  const closes = f.closes();
  await f.owner.drain();
  assert.equal(f.closes(), closes, 'released setup cannot be closed twice');
});

test('confirmed setup cleanup does not turn unresolved Effect responsibility into cancellation', async () => {
  const f = fixture({unresolved: true});
  await f.start(); await f.ready;
  f.cancel(); f.resume();
  await f.owner.operation(f.ref); await f.owner.drain();
  assert.equal(f.computes(), 0);
  assert.deepEqual(f.stops, [[f.ref, null]]);
});

for (const reason of ['reservation', 'resume-gate']) {
  test(`source-free setup is reclaimed when ${reason} refuses before physical start`, async () => {
    const f = fixture({reserved: reason !== 'reservation'});
    const result = await f.start(reason === 'resume-gate' ? {
      beforePhysicalStart() { throw new Error('ResumeNotCurrent'); },
    } : undefined);
    if (reason === 'reservation') assert.equal(result, 'not_started');
    else assert.equal(result.refused.message, 'ResumeNotCurrent');
    await f.owner.operation(f.ref); await f.owner.drain();
    assert.equal(f.closes(), 1);
    assert.equal(f.computes(), 0);
    assert.deepEqual(f.stops, [], 'no physical-start claim was committed');
  });
}

// These explicit opaque Core ports qualify the imported Node supervisor. They
// do not issue a Core Request, Source capture, physical Ledger or permission.
function originalDispatchFixture({source = false, managed = true, retained = false,
  lease = true, borrow = 'owned', host = 'owned', sourceCapacity = 'owned',
  sourceLedger = 'owned', cleanupReady = true, physicalStart = false,
  whole = false, capture = false, placement = 'owned'} = {}) {
  const prepared = {}, request = {}, run = {}, holder = {}, setup = {}, capacity = {}, ledger = {};
  const ref = {runDefinitionCid: 'original-dispatch-custody'};
  const runDefinition = {wire: 'definition'}, failures = [];
  const calls = {borrowed: 0, returned: 0, opened: 0, closed: 0,
    leaseRetired: 0, sourceRetired: 0, physicalClaims: 0, managedLedger: 0, legacyLedger: 0,
    wholeLedger: 0, captureOpened: 0, sourceClosed: 0, bound: 0, stopped: 0, retention: 0};
  const marker = new Error('OriginalResourceParked');
  const bindingFailure = new Error('OriginalCaptureBindingStopped');
  const sourceOriginal = {}, capturedIdentity = {}, compiled = {}, dag = {};
  const sourceEvidence = {}, publicationPreparation = run, authoringContextOriginal = {};
  const originalRetention = Object.freeze({wire: 'original-retention'});
  const dataPolicyCid = 'fixture-policy';
  let ready = cleanupReady, failed, entered, resume;
  const failure = new Promise(resolve => { failed = resolve; });
  const physicalEntered = new Promise(resolve => { entered = resolve; });
  const physicalBarrier = new Promise(resolve => { resume = resolve; });
  const ok = value => ({$tag: 1, _0: value});
  const stops = [];
  let frame = Object.freeze({cancellationRequested: false, revision: 1,
    runDefinition, physicalCloseConfirmed: false});
  const moon = {
    clientProgramRequiresAcquisitionResultPublication() {
      assert.equal(whole, false, 'The adopted Whole Plan must not inspect a Query prefix');
      return false;
    },
    clientProgramInstalledManagedRequiresAcquisitionResultPublication(actualRun, value, identity) {
      assert.equal(this, moon); assert.equal(actualRun, run);
      assert.equal(value, prepared); assert.equal(identity, request);
      if (placement === 'parked') throw marker;
      return ok(placement === 'unsupported');
    },
    clientProgramInstalledManagedPreparationBorrow(actualRun, value, identity) {
      assert.equal(this, moon); assert.equal(actualRun, run);
      assert.equal(value, prepared); assert.equal(identity, request);
      calls.borrowed++; return ok(holder);
    },
    clientProgramPreparationBorrowRead(value) {
      assert.equal(this, moon); assert.equal(value, holder);
      if (borrow === 'parked') throw marker;
      return borrow === 'foreign' ? {} : prepared;
    },
    clientProgramPreparationBorrowReturn(value) {
      assert.equal(this, moon); assert.equal(value, holder); calls.returned++;
      return ok(undefined);
    },
    clientProgramOpenInstalledManagedSourceFreeHost(actualRun, value, identity,
      registry, values, fragment, ordered, selectedRetained) {
      assert.equal(this, moon); assert.equal(actualRun, run);
      assert.equal(value, prepared); assert.equal(identity, request);
      assert.deepEqual([registry, values, fragment, ordered], ['registry', 'values', 'fragment', 'ordered']);
      assert.equal(selectedRetained, retained);
      calls.opened++;
      if (host === 'parked') throw marker;
      return ok(setup);
    },
    clientProgramOpenSourceFreeLocalHost() { assert.fail('No accounting fallback for a managed Run'); },
    clientProgramOpenSourceFreeLocalRetainedHost() { assert.fail('No retained accounting fallback for a managed Run'); },
    strategyHostStop(value) { assert.equal(value, setup); calls.stopped++; },
    strategyHostCloseOutputs(value) {
      assert.equal(value, setup); calls.closed++;
      if (capture) assert.equal(calls.sourceClosed, 1, 'Borrowed Source closes before output reclamation');
      if (!ready) throw new Error('OriginalSetupCleanupPending');
    },
    strategyHostUsage: () => Array(ledgerUsageFields.length).fill(0n),
  };
  if (host === 'missing') delete moon.clientProgramOpenInstalledManagedSourceFreeHost;
  if (borrow === 'missing') delete moon.clientProgramInstalledManagedPreparationBorrow;
  if (placement === 'missing') delete moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication;
  const sourceAccess = {authorization: {}}, preparedSource = {checkedSource: {sourceRef: 'fixture-source'}};
  const captureHandle = {
    source() { assert.equal(calls.sourceClosed, 0); return sourceOriginal; },
    retainTask(actual, task) {
      assert.equal(actual, dag); assert.equal(task, 0); assert.equal(calls.opened, 1);
      assert.equal(calls.retention, 1, 'The same Run retention must precede capture binding');
      calls.bound++;
      // Exercise the supervisor's real custody after the fallible binding;
      // no fabricated completed Compute or public Result is issued here.
      throw bindingFailure;
    },
  };
  const captured = {inputKind: 'whole-input', wholeCapacity: capacity, logicalInput: {},
    checkedSource: {sourceDataPolicyCid: dataPolicyCid}, identity: capturedIdentity, capture: captureHandle,
    async prepareSourceEvidenceOriginal(options) {
      assert.equal(options.authorityScopeCid, 'fixture-scope');
      assert.equal(options.effectiveDataPolicyCid, dataPolicyCid);
    },
    async close() {
      if (host === 'owned') assert(calls.stopped > 0, 'Stop the borrowed Compute before Source close');
      calls.sourceClosed++;
    },
  };
  const adapter = source ? {sourceAccess, admitsSource: value => value === 'fixture-source',
    ledgerCapacity(value) {
      assert.equal(value, preparedSource);
      return {capacity, transferBytes: whole ? 19n : 3n, executionBytes: whole ? 31n : 5n,
        ...(whole ? {wholeInput: true} : {}),
        ...(sourceCapacity === 'missing' || !managed ? {} :
          {managedRun: sourceCapacity === 'foreign' ? {} : run})};
    },
    retirePreparedSource(value) { assert.equal(this, adapter); assert.equal(value, preparedSource); calls.sourceRetired++; },
    open(options) {
      assert.equal(capture, true, 'Refused physical start must not acquire Source DATA');
      assert.equal(options.preparedProgram, prepared); assert.equal(options.preparedSource, preparedSource);
      assert.equal(options.ledger, ledger); assert.equal(options.sourceAccess, sourceAccess);
      calls.captureOpened++; return captured;
    },
  } : undefined;
  if (source) {
    moon.clientProgramAcquisitionCount = value => { assert.equal(value, prepared); return 1; };
    moon.clientProgramInstalledManagedRunPrepareLedger = (actualRun, value, identity,
      capacities, transfer, execution, registry, values, fragment, ordered) => {
      assert.equal(actualRun, run); assert.equal(value, prepared); assert.equal(identity, request);
      assert.deepEqual(capacities, [capacity]); assert.deepEqual(transfer, [3n]); assert.deepEqual(execution, [5n]);
      assert.deepEqual([registry, values, fragment, ordered], ['registry', 'values', 'fragment', 'ordered']);
      calls.managedLedger++;
      if (sourceLedger === 'parked') throw marker;
      return ok(ledger);
    };
    moon.clientProgramPrepareSingleCapturedLocalInstalledLedger = (value, selected, transfer,
      execution, registry, values, fragment, ordered) => {
      assert.equal(whole, false, 'Whole capacity is not an array of Query capacities');
      assert.equal(managed, false, 'A missing managed original cannot select accounting');
      assert.equal(value, prepared); assert.equal(selected, capacity);
      assert.deepEqual([transfer, execution], [3n, 5n]);
      assert.deepEqual([registry, values, fragment, ordered], ['registry', 'values', 'fragment', 'ordered']);
      calls.legacyLedger++; return ledger;
    };
    if (sourceLedger === 'missing') delete moon.clientProgramInstalledManagedRunPrepareLedger;
    moon.clientProgramInstalledManagedWholeSourceLedger = function(actualRun, value, identity,
      selected, transfer, execution) {
      assert.equal(this, moon); assert.equal(actualRun, run);
      assert.equal(value, prepared); assert.equal(identity, request); assert.equal(selected, capacity);
      assert.deepEqual([transfer, execution], [19n, 31n]); calls.wholeLedger++;
      if (sourceLedger === 'parked') throw marker;
      return ok(ledger);
    };
    if (sourceLedger === 'missing') delete moon.clientProgramInstalledManagedWholeSourceLedger;
  }
  const control = {runDefinitionRunId: () => 'original-run',
    runCancellationConfirmed: runtimeCore(moonRuntime).publicationControl.runCancellationConfirmed};
  if (capture) {
    moon.clientProgramPublicationDataPolicyCid = value => { assert.equal(value, prepared); return dataPolicyCid; };
    moon.clientProgramCapturedSourceMatches = (value, original) => {
      assert.equal(value, prepared); assert.equal(original, sourceOriginal); return true;
    };
    moon.clientProgramDefinitionCid = value => { assert.equal(value, prepared); return 'fixture-program'; };
    moon.clientProgramCapturedSourceLogicalCid = identity => { assert.equal(identity, capturedIdentity); return 'fixture-logical'; };
    moon.clientProgramResultCount = () => 1;
    moon.clientProgramInstalledManagedPublicationLimits = actualRun => {
      assert.equal(actualRun, run); return resultOutputLimitFields.map(() => 1000);
    };
    moon.clientProgramOpenInstalledManagedCaptureHost = function(actualRun, value, identity, originals) {
      assert.equal(this, moon); assert.equal(actualRun, run);
      assert.equal(value, prepared); assert.equal(identity, request); assert.deepEqual(originals, [sourceOriginal]);
      calls.opened++;
      if (host === 'parked') throw marker;
      return ok(setup);
    };
    moon.clientProgramOpenSingleCapturedLocalHost = () => assert.fail('No independent captured Host fallback');
    moon.strategyHostRun = value => { assert.equal(value, setup); return dag; };
    if (host === 'missing') delete moon.clientProgramOpenInstalledManagedCaptureHost;
    Object.assign(control, {
      issueProgramInitialRetention(original, value, identity, policy, selection, dependencies) {
        assert.equal(this, control); assert.equal(original, run);
        assert.equal(value, prepared); assert.equal(identity, request); assert.equal(policy, dataPolicyCid);
        assert.deepEqual(selection, {availableUntil: '2026-11-15T01:00:00.000Z',
          deleteBy: '2026-11-15T02:00:00.000Z', metadataDeleteBy: '2026-11-22T00:00:00.000Z'});
        assert.deepEqual(dependencies.map(value => value.kind),
          ['retention_contract', 'metadata_retention_policy', 'clock_contract']);
        assert.equal(calls.retention++, 0); return originalRetention;
      },
      takeSourceEvidenceOriginal(original) { assert.equal(original, captureHandle); return sourceEvidence; },
      checkClientCompiledRunOwner(original, value) { assert.equal(original, compiled); assert.equal(value, prepared); },
      issueCheckedClientCompiledInvocation(original, definition, options, _limits, preparation, value) {
        assert.equal(original, compiled); assert.equal(definition, runDefinition); assert.equal(value, prepared);
        assert.equal(preparation, publicationPreparation); assert.equal(options.source.captured, captured);
        assert.equal(calls.retention, 1, 'Original retention is established before invocation issuance');
        assert.equal(options.source.sourceEvidence, sourceEvidence);
        return {observation: {}, invocation: {}};
      },
      seal: (_kind, wire) => Object.freeze({wire}),
      sealRunEvidence: (_kind, wire) => Object.freeze({wire}),
      preparedClientNormalizationEvidence(value) {
        assert.strictEqual(value, prepared); return Object.freeze({wire: '{}'});
      },
      preparedClientAuthoringContextEvidence(value, original) {
        assert.strictEqual(value, prepared); assert.strictEqual(original, authoringContextOriginal);
        return Object.freeze({wire: '{}'});
      },
      compiledRunResultTransformation: () => undefined,
    });
  }
  const owner = installNodeClientDispatchOwner({moon,
    control,
    journal: {
      reservePhysicalStart() { calls.physicalClaims++; return physicalStart; },
      lookupRunDefinition: () => frame,
      lookupReconciliationState: () => undefined,
      markPreDispatchFailure(value) { assert.equal(value, ref); },
      markPhysicalClose(value, outcome, original) {
        assert.equal(physicalStart, true); assert.equal(value, ref);
        assert.equal(original, frame); assert.equal(frame.physicalCloseConfirmed, false);
        frame = Object.freeze({...frame, revision: frame.revision + 1, physicalCloseConfirmed: true});
        stops.push(outcome);
      },
    },
    preparationCustody: {begin(submission) {
      assert.equal(submission.preparedProgram, prepared);
      return lease ? {preparedProgram: prepared, retire() { calls.leaseRetired++; }} : undefined;
    }},
    store: {confirmCommittedIndex: async () => undefined},
    startRun: async () => ({kind: 'reserved', ref}),
    hostConnection: () => true,
    planFor: () => ({kind: source ? 'tasks' : 'values', compiled, runDefinition,
      publicationPreparation, requestIdentity: request, authoringContextOriginal, admission: {}, compiledPlan: {identity: 'fixture-compiled'},
      createdAt: '2026-11-15T00:00:00.000Z'}),
    sourceProfile: adapter,
    prepareAcquisition() { assert.fail('The same prepared Source must not be reacquired'); },
    observed(name, detail) { if (name === 'dispatch_failed') { failures.push(detail); failed(detail); } },
    async faultInjection(name) {
      if (physicalStart && name === 'physical_start_reserved') { entered(); await physicalBarrier; }
    },
    registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered',
    managedComputeRequired: true, retainedRelationOutput: retained,
    runPublished() { assert.fail('Refused physical start must not enter Compute'); },
    namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope',
    now: () => '2026-11-15T00:00:00.000Z',
  });
  const held = {...(managed ? {managedRun: run} : {}),
    ...(source ? {preparedSource, preparedSourceAccess: sourceAccess} : {})};
  return {owner, moon, calls, marker, failures, failure, ref, stops, physicalEntered,
    ready() { ready = true; },
    resume,
    cancel() {
      frame = Object.freeze({...frame, revision: frame.revision + 1, cancellationRequested: true});
      owner.cancel(ref);
    },
    start() { return owner.start({preparedProgram: prepared, principalId: 'owner',
      connection: {}, requestId: 'fixture-request'}, request,
    {ref, runDefinition, dispatchReserved: false, cancellationRequested: false}, held); }};
}

// Keep the compiled cancellation projection separate from the explicit Node
// fixture's opaque resource ports; no fixture port can issue a cancellation.
const moonRuntime = moon;

test('imported dispatcher opens the same managed Run for both retained output choices and returns its borrow once', async () => {
  for (const retained of [false, true]) {
    const f = originalDispatchFixture({retained});
    assert.equal(await f.start(), 'not_started');
    await f.owner.drain();
    assert.equal(f.calls.opened, 1); assert.equal(f.calls.borrowed, 1);
    assert.equal(f.calls.returned, 1); assert.equal(f.calls.leaseRetired, 1);
    assert.equal(f.calls.closed, 1); assert.equal(f.calls.physicalClaims, 1);
    assert.deepEqual(f.failures, []);
    assert.equal(f.owner.operation(f.ref), undefined);
    await f.owner.drain(); assert.equal(f.calls.returned, 1);
  }
});

test('imported dispatcher preserves missing and parked managed Host refusals without an accounting fallback', async () => {
  for (const [options, expected, opened] of [
    [{managed: false}, 'InstalledManagedComputeRunUnavailable', 0],
    [{host: 'missing'}, 'InstalledManagedComputeHostUnavailable', 0],
    [{host: 'parked'}, 'OriginalResourceParked', 1],
  ]) {
    const f = originalDispatchFixture(options);
    assert.equal(await f.start(), 'not_started');
    assert.equal((await f.failure).code, expected);
    await f.owner.drain();
    assert.equal(f.calls.opened, opened); assert.equal(f.calls.physicalClaims, 0);
    assert.equal(f.calls.returned, f.calls.borrowed); assert.equal(f.calls.leaseRetired, 1);
    assert.equal(f.owner.operation(f.ref), undefined);
  }
});

test('imported dispatcher refuses missing or foreign preparation custody and returns only its original borrow', async () => {
  for (const [options, expected, returned] of [
    [{borrow: 'missing'}, 'PreparationHostCustodyUnavailable', 0],
    [{lease: false}, 'ForeignPreparationHostCustody', 1],
    [{borrow: 'foreign'}, 'ForeignPreparationHostCustody', 1],
    [{borrow: 'parked'}, 'OriginalResourceParked', 1],
  ]) {
    const f = originalDispatchFixture(options);
    assert.equal(await f.start(), 'not_started');
    assert.equal((await f.failure).code, expected);
    await f.owner.drain();
    assert.equal(f.calls.returned, returned); assert.equal(f.calls.opened, 0);
    assert.equal(f.calls.physicalClaims, 0);
    assert.equal(f.owner.operation(f.ref), undefined);
  }
});

test('imported dispatcher retains setup and the captured return receiver until same-owner cleanup succeeds', async () => {
  const f = originalDispatchFixture({cleanupReady: false});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'OriginalSetupCleanupPending');
  f.moon.clientProgramPreparationBorrowReturn = () => assert.fail('No replacement return receiver');
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(f.calls.returned, 0); assert.equal(f.calls.leaseRetired, 0);
  assert.notEqual(f.owner.operation(f.ref), undefined);
  f.ready(); await f.owner.drain();
  assert.equal(f.calls.returned, 1); assert.equal(f.calls.leaseRetired, 1);
  assert.equal(f.calls.opened, 1); assert.equal(f.owner.operation(f.ref), undefined);
  const closed = f.calls.closed;
  await f.owner.drain(); assert.equal(f.calls.returned, 1); assert.equal(f.calls.closed, closed);
});

test('imported managed dispatcher keeps its original preparation borrow across cancellation until physical cleanup is confirmed', async () => {
  const f = originalDispatchFixture({physicalStart: true, cleanupReady: false});
  assert.equal(await f.start(), 'started'); await f.physicalEntered;
  f.cancel(); f.resume(); await f.owner.operation(f.ref);
  assert.equal(await f.start(), 'not_started');
  await assert.rejects(f.owner.drain(), {code: 'ClientDispatchCleanupPending'});
  assert.equal(f.calls.returned, 0); assert.equal(f.calls.leaseRetired, 0);
  assert.deepEqual(f.stops, []);
  f.ready(); await f.owner.drain();
  assert.equal(f.calls.returned, 1); assert.equal(f.calls.leaseRetired, 1);
  assert.equal(f.calls.opened, 1); assert.equal(f.calls.physicalClaims, 1);
  assert.deepEqual(f.stops, ['cancelled']);
  assert.equal(f.owner.operation(f.ref), undefined);
  await f.owner.drain(); assert.equal(f.calls.returned, 1);
});

test('imported single Source dispatcher uses its original managed parent and exact selected capacities before physical start', async () => {
  const f = originalDispatchFixture({source: true});
  assert.equal(await f.start(), 'not_started'); await f.owner.drain();
  assert.equal(f.calls.managedLedger, 1); assert.equal(f.calls.legacyLedger, 0);
  assert.equal(f.calls.physicalClaims, 1); assert.equal(f.calls.sourceRetired, 1);
  assert.equal(f.calls.leaseRetired, 1); assert.deepEqual(f.failures, []);
  assert.equal(f.owner.operation(f.ref), undefined);
});

test('imported single Source dispatcher refuses foreign missing and parked managed originals before Source or accounting fallback', async () => {
  for (const options of [{sourceCapacity: 'foreign'}, {sourceCapacity: 'missing'},
    {sourceLedger: 'missing'}, {sourceLedger: 'parked'}]) {
    const f = originalDispatchFixture({source: true, ...options});
    assert.equal(await f.start(), 'not_started');
    assert.equal((await f.failure).code, options.sourceLedger === 'parked'
      ? 'OriginalResourceParked' : 'InstalledSingleSourceOriginalRunUnavailable');
    await f.owner.drain();
    assert.equal(f.calls.legacyLedger, 0); assert.equal(f.calls.physicalClaims, 0);
    assert.equal(f.calls.sourceRetired, 1); assert.equal(f.calls.leaseRetired, 1);
    assert.equal(f.owner.operation(f.ref), undefined);
  }
});

test('imported unprepared single Source keeps its finite accounting constructor without manufacturing a managed original', async () => {
  const f = originalDispatchFixture({source: true, managed: false});
  assert.equal(await f.start(), 'not_started'); await f.owner.drain();
  assert.equal(f.calls.legacyLedger, 1); assert.equal(f.calls.managedLedger, 0);
  assert.equal(f.calls.physicalClaims, 1); assert.equal(f.calls.sourceRetired, 1);
  assert.equal(f.calls.leaseRetired, 1); assert.deepEqual(f.failures, []);
  assert.equal(f.owner.operation(f.ref), undefined);
});

test('imported Whole dispatcher retains the opened original Host when capture binding refuses and closes both original owners', async () => {
  const f = originalDispatchFixture({source: true, whole: true, capture: true, physicalStart: true});
  assert.equal(await f.start(), 'started'); await f.physicalEntered; f.resume();
  await f.owner.operation(f.ref); await f.owner.drain();
  assert.equal((await f.failure).code, 'OriginalCaptureBindingStopped');
  assert.equal(f.calls.wholeLedger, 1); assert.equal(f.calls.managedLedger, 0); assert.equal(f.calls.legacyLedger, 0);
  assert.equal(f.calls.captureOpened, 1); assert.equal(f.calls.opened, 1); assert.equal(f.calls.bound, 1);
  assert.equal(f.calls.retention, 1);
  assert.equal(f.calls.sourceClosed, 1); assert.equal(f.calls.closed, 1);
  assert.equal(f.calls.borrowed, 1); assert.equal(f.calls.returned, 1); assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.stops, ['failed']); assert.equal(f.owner.operation(f.ref), undefined);
  await f.owner.drain(); assert.equal(f.calls.bound, 1); assert.equal(f.calls.closed, 1);
});

test('imported Whole dispatcher preserves missing or parked original opener refusal without fabricating a pending Host', async () => {
  for (const host of ['missing', 'parked']) {
    const f = originalDispatchFixture({source: true, whole: true, capture: true, physicalStart: true, host});
    assert.equal(await f.start(), 'started'); await f.physicalEntered; f.resume();
    await f.owner.operation(f.ref); await f.owner.drain();
    assert.equal((await f.failure).code, host === 'missing'
      ? 'InstalledManagedComputeHostUnavailable' : 'OriginalResourceParked');
    assert.equal(f.calls.captureOpened, 1); assert.equal(f.calls.bound, 0);
    assert.equal(f.calls.retention, 1);
    assert.equal(f.calls.sourceClosed, 1); assert.equal(f.calls.closed, 0); assert.equal(f.calls.stopped, 0);
    assert.equal(f.calls.returned, 1); assert.equal(f.calls.leaseRetired, 1);
    assert.deepEqual(f.stops, ['failed']); assert.equal(f.owner.operation(f.ref), undefined);
  }
});

test('imported Whole ledger selection uses only its same original Run and capacity and preserves current refusals', async () => {
  for (const options of [{}, {sourceCapacity: 'foreign'}, {sourceLedger: 'missing'}, {sourceLedger: 'parked'}]) {
    const f = originalDispatchFixture({source: true, whole: true, ...options});
    assert.equal(await f.start(), 'not_started'); await f.owner.drain();
    if (Object.keys(options).length) assert.equal((await f.failure).code,
      options.sourceLedger === 'parked' ? 'OriginalResourceParked' : 'InstalledSingleSourceOriginalRunUnavailable');
    else assert.deepEqual(f.failures, []);
    assert.equal(f.calls.managedLedger, 0); assert.equal(f.calls.legacyLedger, 0);
    assert.equal(f.calls.captureOpened, 0); assert.equal(f.calls.sourceRetired, 1);
    assert.equal(f.calls.leaseRetired, 1); assert.equal(f.owner.operation(f.ref), undefined);
  }
});

test('imported Whole Result-placement check consumes the adopted original Plan and refuses before Source work', async () => {
  for (const [placement, expected] of [['owned', undefined],
    ['unsupported', 'InstalledAcquisitionResultPublicationUnsupported'],
    ['missing', 'InstalledManagedSourcePlanUnavailable'], ['parked', 'OriginalResourceParked']]) {
    const f = originalDispatchFixture({source: true, whole: true, placement});
    assert.equal(await f.start(), 'not_started'); await f.owner.drain();
    if (expected === undefined) assert.deepEqual(f.failures, []);
    else assert.equal((await f.failure).code, expected);
    assert.equal(f.calls.wholeLedger, expected === undefined ? 1 : 0);
    assert.equal(f.calls.physicalClaims, expected === undefined ? 1 : 0);
    assert.equal(f.calls.captureOpened, 0); assert.equal(f.calls.sourceRetired, 1);
    assert.equal(f.calls.leaseRetired, 1); assert.equal(f.owner.operation(f.ref), undefined);
  }
});

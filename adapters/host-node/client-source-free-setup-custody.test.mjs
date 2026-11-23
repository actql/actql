import assert from 'node:assert/strict';
import {getEventListeners} from 'node:events';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientDispatchOwner, installNodeRelationSampleStart,
  installNodeRelationSampleDebugEntry} from './client-dispatch-owner.mjs';
import {ledgerUsageFields} from '../host-common/ledger-contract.generated.mjs';
import {resultOutputLimitFields} from '../host-common/result-output-limits.mjs';
import {sourceFreeValuesPlan} from './local-values-plan.mjs';
import {installedHostShutdown} from './embedded-local-lifecycle.mjs';
import {CapturedRunPublicationError} from './entry.mjs';

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
  whole = false, capture = false, placement = 'owned', sampleStart = false,
  sampleStartCoreFailure = false, sampleStartCapacityFailure = false,
  sampleStartMissingReady = false, sampleProfileFailure = false,
  missingSampleProfile = false, sampleReadCapacityFailure = false, normalCompute = false,
  sampleWriterMissing = false, ordinaryDebug = false, replaceSampleAccountAtAck = false,
  debugResumeUntil, debugReplyLost = false, jointStart = 'confirmed', debugEntry = false, laterDebugPark = false} = {}) {
  const prepared = {}, request = {}, run = {}, holder = {}, setup = {}, capacity = {}, ledger = {};
  const ref = {runDefinitionCid: 'original-dispatch-custody'};
  const runDefinition = {identity: ref.runDefinitionCid, wire: 'definition'}, failures = [];
  // SQLite admits its own copy. The checked Core receiver still expects the
  // original Definition that the compiled plan and setup own.
  const acceptedDefinition = sampleStart ? {...runDefinition} : runDefinition;
  const calls = {borrowed: 0, returned: 0, opened: 0, closed: 0,
    leaseRetired: 0, sourceRetired: 0, physicalClaims: 0, managedLedger: 0, legacyLedger: 0,
    wholeLedger: 0, captureOpened: 0, sourceClosed: 0, bound: 0, stopped: 0, retention: 0,
    computed: 0, preDispatchFailures: 0};
  const marker = new Error('OriginalResourceParked');
  const bindingFailure = new Error('OriginalCaptureBindingStopped');
  const sourceOriginal = {}, capturedIdentity = {}, compiled = {}, dag = {};
  const sourceEvidence = {}, publicationPreparation = run, authoringContextOriginal = {};
  const originalRetention = Object.freeze({wire: 'original-retention'});
  const dataPolicyCid = 'fixture-policy';
  let ready = laterDebugPark || cleanupReady, laterReady = cleanupReady, failed, entered, resume;
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
  const sampleEvents = [];
  const sampleObservation = {}, profile = {}, checkedProfile = {}, startTicket = {};
  const committedPrefix = {}, scopedTicket = {}, originalReceipt = {};
  const originalAccount = {};
  let account = originalAccount, allowsSampleCapture = true;
  moon.clientProgramAdvanceRelationSampleStartControl = function(
    actualProfile, owner, actualSetup, actualAccount, principalId, site, acknowledged) {
    assert.equal(sampleStart, true, 'Only an explicitly selected original profile may enter the controller');
    assert.equal(this, moon);
    assert.equal(actualProfile, checkedProfile);
    assert.equal(owner, run);
    assert.equal(actualSetup, setup);
    assert.equal(actualAccount, originalAccount);
    assert.equal(principalId, 'owner');
    assert.equal(site, 'installed-fixture-authority');
    assert.equal(acknowledged, sampleEvents.includes('core'));
    sampleEvents.push(acknowledged ? 'received' : 'prepared');
    return ok(undefined);
  };
  if (sampleStart) {
    moon.strategyHostRun = value => { assert.equal(value, setup); return dag; };
    control.reserveClientRelationSampleStart = (owner, identity, execution, definition, configured, journalBytes, debugEntry) => {
      assert.equal(owner, run);
      assert.equal(identity, request);
      assert.equal(execution.program, prepared);
      assert.equal(definition, runDefinition);
      assert.equal(configured, setup);
      assert.equal(Object.hasOwn(held, 'sampleProfile'), false, 'The original profile is selected once before funding');
      if (journalBytes === undefined) {
        assert.equal(debugEntry, debugResumeUntil !== undefined);
        sampleEvents.push('reserve');
        if (sampleStartCapacityFailure) throw marker;
      } else {
        assert.equal(journalBytes, 12345);
        sampleEvents.push('reserve-original');
        if (sampleReadCapacityFailure) throw marker;
      }
    };
    control.prepareClientLogicalObservation = (owner, execution, definition, limits) => {
      assert.equal(owner, run);
      assert.equal(execution.program, prepared);
      assert.equal(definition, runDefinition);
      assert.ok(limits.maxWireBytes > 0);
      sampleEvents.push('observation');
      return ok(sampleObservation);
    };
    moon.clientProgramLogicalObservationCleanup = () => assert.fail('The original observation was prepared');
    moon.clientProgramReturnLogicalObservation = function(value) {
      assert.equal(this, moon);
      assert.equal(value, sampleObservation);
      sampleEvents.push('return-observation');
      if (!ready) throw new Error('OriginalSampleObservationReturnPending');
      return ok(true);
    };
    control.acknowledgeClientRelationSampleStart = (owner, identity, execution, definition, captured, revision) => {
      assert.equal(owner, run);
      assert.equal(identity, request);
      assert.equal(execution.program, prepared);
      assert.equal(definition, runDefinition);
      assert.equal(captured, dag);
      assert.equal(revision, debugResumeUntil === undefined ? 2 : 4);
      sampleEvents.push('core');
      if (sampleStartCoreFailure) throw marker;
    };
  }
  const samplePlan = sampleStart ? sourceFreeValuesPlan({
    // Real Plan association and dispatch with explicit component ports for
    // the compiler and setup. This test observes scheduling and custody.
    moon: {clientProgramPreparedLocalPublicationLimits: () => resultOutputLimitFields.map(() => 1),
      clientProgramDefinitionCid: () => 'fixture-program', clientProgramResultCount: () => 0},
    control: {
      prepareCheckedClientCompiledRun: () => ({compiledPlan: {identity: 'fixture-compiled'},
        preparedEvidence: {wire: ''}, authorization: {wire: ''}}),
      defineCheckedClientCompiledRun: () => runDefinition,
      issueCheckedClientCompiledInvocation: () => ({}),
      seal: (_kind, wire) => ({wire}),
      preparedClientNormalizationEvidence: () => ({}),
      preparedClientAuthoringContextEvidence: () => ({}),
      captureOriginalClientRunPlan: () => ({}),
    },
    preparedProgram: prepared, publicationOriginal: {kind: 'preparation', value: {}},
    namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope',
    now: () => '2026-11-15T00:00:00.000Z',
  }) : undefined;
  const hostConnection = () => true;
  const debugEvents = [], debugCid = `sha256:${'3'.repeat(64)}`;
  const debugWitness = Object.freeze({commandCid: debugCid, acceptedRevision: 3, physicalStartRevision: 4,
    until: debugResumeUntil});
  const taskControl = Object.freeze({phase: () => 'runnable', waitForResume: assert.fail});
  let installedDebug, debugRunnable = true;
  const atTaskBoundary = Promise.withResolvers();
  const continueToPark = Promise.withResolvers();
  const taskParked = Promise.withResolvers();
  const completedStepId = `sha256:${'6'.repeat(64)}`;
  const nextStepId = `sha256:${'7'.repeat(64)}`;
  moon.clientProgramAdvanceRelationSampleDebugEntry = function(actualProfile, owner, actual, admitted,
    principal, site, command, revision) {
    assert.equal(this, moon);
    assert.equal(actualProfile, checkedProfile);
    assert.equal(owner, run);
    assert.equal(actual, setup);
    assert.equal(admitted, originalAccount);
    assert.equal(principal, 'owner');
    assert.equal(site, 'installed-fixture-authority');
    assert.equal(revision, command === 'prepare' ? 0 : 4);
    if (command !== 'prepare') {
      assert.equal(sampleEvents.at(-1), 'core', 'Sample acknowledges the winning revision before activation');
      sampleEvents.push('debug-resume');
    }
    debugEvents.push(command);
    return ok(undefined);
  };
  moon.clientProgramRelationSampleDebugEntryRunnable = function(actualProfile, owner, actual, revision) {
    assert.equal(this, moon);
    assert.equal(actualProfile, checkedProfile);
    assert.equal(owner, run);
    assert.equal(actual, setup);
    assert.equal(revision, 4);
    return ok(debugRunnable);
  };
  moon.clientProgramRelationSampleDebugTaskPause = (profile, owner, actual, revision) => {
    assert.equal(laterDebugPark, true);
    assert.equal(profile, checkedProfile);
    assert.equal(owner, run);
    assert.equal(actual, setup);
    assert.equal(revision, 4);
    return ok({_0: 2, _1: completedStepId, _2: nextStepId, _3: 7});
  };
  moon.clientProgramResumeRelationSampleDebugTask = assert.fail;
  moon.clientProgramRelationSampleDebugResumeAllowed = () => true;
  const debugEntryExpiresAt = Date.parse('2026-11-15T00:00:05Z');
  const debugPausedAt = Date.parse('2026-11-15T00:00:00Z');
  const entryParked = Promise.withResolvers();
  const prepareDebug = installNodeRelationSampleDebugEntry(moon, () => account,
    hostConnection, 'installed-fixture-authority', {
      journal: {
        parkDebugTask(original, {startRevision, expectedRevision, controlRevision, stepId, nextStepId: selectedNext, committedGeneration, current}) {
          assert.equal(laterDebugPark, true);
          assert.equal(original, ref);
          assert.equal(startRevision, 4);
          assert.equal(expectedRevision, 4);
          assert.equal(controlRevision, 2);
          assert.equal(stepId, completedStepId);
          assert.equal(committedGeneration, 7);
          assert.equal(current(), true);
          frame = Object.freeze({...frame, revision: 5});
          debugEvents.push('park-task');
          taskParked.resolve();
          assert.equal(selectedNext, nextStepId);
          return {kind: 'parked', revision: 5, controlRevision, stepId, nextStepId: selectedNext, committedGeneration,
            expiresAt: debugEntryExpiresAt, pausedAt: debugPausedAt};
        },
        acceptDebugTaskResume: assert.fail,
        debugPauseCurrent(original, {parked, startRevision, current}) {
          assert.equal(original, ref);
          assert.equal(parked.revision, parked.stepId === undefined ? 2 : 5);
          assert.equal(startRevision, parked.stepId === undefined ? 0 : 4);
          return current();
        },
        parkDebugEntry(identity, selection, requestControl, publicationControl) {
          assert.equal(debugEntry, true); assert.equal(identity, request);
          assert.equal(selection.ref, ref); assert.equal(selection.expiresAt, debugEntryExpiresAt);
          assert.equal(selection.expectedRevision, 1); assert.equal(selection.current(), true);
          assert.equal(requestControl, moon); assert.equal(publicationControl, control);
          debugEvents.push('park-entry');
          entryParked.resolve();
          return {kind: 'parked', revision: 2, expiresAt: debugEntryExpiresAt, pausedAt: debugPausedAt};
        },
        acceptDebugEntryResume(original, {commandWire, current, capture, receiptOriginal}, publicationControl) {
          assert.equal(original, ref); assert.equal(publicationControl, control);
          assert.equal(commandWire, 'fixture-entry-command');
          if (current() !== true) throw new Error('FixtureEntryDenied');
          assert.strictEqual(receiptOriginal.runDefinition, runDefinition);
          assert.equal(receiptOriginal.logicalMapCid, 'sha256:' + 'a'.repeat(64));
          receiptOriginal.reserve(64);
          debugEvents.push('accept-entry');
          const receipt = {kind: 'resume_accepted', revision: 3, commandCid: debugCid, until: debugResumeUntil};
          capture(receipt);
          return receipt;
        },
      }, control, now: () => '2026-11-15T00:00:00.000Z',
    });
  const prepareSampleStart = installNodeRelationSampleStart(moon, () => account,
    hostConnection, 'installed-fixture-authority');
  const owner = installNodeClientDispatchOwner({moon,
    control,
    prepareSampleStart: sampleStartMissingReady ? (...args) => {prepareSampleStart(...args);} : prepareSampleStart,
    prepareDebugEntryResume(actual, owner, authority, sample, signal, mapCid, definition) {
      assert.equal(debugResumeUntil !== undefined, true);
      assert.strictEqual(actual, setup);
      assert.strictEqual(owner, run);
      assert.strictEqual(authority.ref, ref);
      assert.equal(sample, sampleStart ? checkedProfile : undefined);
      if (sample !== undefined) {
        assert.equal(mapCid, 'sha256:' + 'a'.repeat(64));
        installedDebug = prepareDebug(actual, owner, authority, sample, signal, mapCid, definition);
        return installedDebug;
      }
      debugEvents.push('prepare');
      return {current: () => !sampleStart || account === originalAccount, activate(witness) {
        assert.strictEqual(witness, debugWitness);
        debugEvents.push(witness.until);
      }, taskControl};
    },
    journal: {
      originalSubmittedIntent(identity, options, originalMoon, originalControl) {
        assert.equal(sampleStart, true, 'Normal dispatch must not open a Sample Journal view');
        assert.equal(identity, request);
        assert.equal(options.namespaceId, 'fixture-namespace');
        assert.equal(options.sampleRunRef, ref);
        assert.equal(originalMoon, moon);
        assert.equal(originalControl, control);
        sampleEvents.push('probe-original');
        options.reserveSampleRead(12345);
        sampleEvents.push('journal-original');
        return {checkSampleProfile(owner, definition, observation, evidence, limits) {
          assert.equal(owner, run);
          assert.equal(definition, runDefinition);
          assert.equal(observation, sampleObservation);
          assert.equal(evidence, profile);
          assert.ok(limits.maxWireBytes > 0);
          sampleEvents.push('check-profile');
          if (sampleProfileFailure) throw new Error('ClientRequestSubmittedIntentMismatch');
          return {profile: checkedProfile, startTicket, logicalMapCid: 'sha256:' + 'a'.repeat(64), withAdoption(prefix, current, consume) {
            assert.equal(prefix, committedPrefix);
            if (current() !== true) throw new Error('FixtureSamplePermissionDenied');
            sampleEvents.push('visit-prefix');
            assert.equal(consume(scopedTicket), undefined);
          }};
        }};
      },
      reservePhysicalStart(_request, options) {
        calls.physicalClaims++;
        if (debugResumeUntil !== undefined) {
          assert.equal(options.debugResume.commandCid, debugCid);
          assert.equal(options.debugResume.current(), true);
          debugEvents.push('claim');
          if (jointStart === 'unknown') {
            throw Object.assign(new Error('ClientRunPhysicalStartUnknown'), {code: 'ClientRunPhysicalStartUnknown', outcome: 'unknown'});
          }
          if (physicalStart && !debugReplyLost) options.debugResume.capture(debugWitness);
        } else assert.equal(Object.hasOwn(options, 'debugResume'), false);
        if (sampleStart && !sampleStartMissingReady) {
          const capture = options.captureSampleStart;
          assert.equal(capture.startTicket, startTicket);
          assert.equal(capture.program, prepared);
          assert.equal(capture.compiled, options.localExecutionOwner.compiled);
          sampleEvents.push('claim');
          if (physicalStart) {
            if (jointStart !== 'sample-missing') {
              capture.captureRevision(debugResumeUntil === undefined ? 2 : jointStart === 'different' ? 5 : 4);
            }
            if (replaceSampleAccountAtAck) account = {};
            if (!sampleWriterMissing) capture.captureAdoption(ticket => {
              assert.equal(ticket, scopedTicket);
              sampleEvents.push('journal-adopted');
              return originalReceipt;
            });
          }
        } else assert.equal(Object.hasOwn(options, 'captureSampleStart'), false);
        return physicalStart;
      },
      lookupRunDefinition: () => frame,
      lookupReconciliationState: () => undefined,
      markPreDispatchFailure(value) { assert.equal(value, ref); calls.preDispatchFailures++; },
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
    store: {confirmCommittedIndex: async () => !laterDebugPark && calls.computed === 1 ? {} : undefined},
    startRun: async () => ({kind: 'reserved', ref, revision: 1}),
    hostConnection,
    authorizeSampleCapture({ref: original, principalId}) {
      assert.equal(original, ref);
      assert.equal(principalId, 'owner');
      return allowsSampleCapture;
    },
    planFor: () => samplePlan ?? ({kind: source ? 'tasks' : 'values', compiled, runDefinition,
      publicationPreparation, requestIdentity: request, authoringContextOriginal, admission: {}, compiledPlan: {identity: 'fixture-compiled'},
      createdAt: '2026-11-15T00:00:00.000Z'}),
    sourceProfile: adapter,
    prepareAcquisition() { assert.fail('The same prepared Source must not be reacquired'); },
    observed(name, detail) { if (name === 'dispatch_failed') { failures.push(detail); failed(detail); } },
    async faultInjection(name) {
      if (physicalStart && name === 'physical_start_reserved') {
        if (sampleStart) sampleEvents.push('reservation-observed');
        entered(); await physicalBarrier;
      }
    },
    registry: 'registry', values: 'values', fragment: 'fragment', ordered: 'ordered',
    managedComputeRequired: true, retainedRelationOutput: retained,
    runPublished(actual, _publication, _config, _signal, _before, retain, _taskObservation,
      _preparationHolder, _beforePublication, sampleDriver, driverControl) {
      if (debugResumeUntil !== undefined) {
        assert.strictEqual(driverControl, installedDebug?.taskControl ?? taskControl);
        assert.equal(driverControl.phase(setup), 'runnable');
        debugEvents.push('compute');
      } else assert.equal(driverControl, undefined);
      calls.computed++;
      assert.equal(normalCompute, true, 'Refused physical start must not enter Compute');
      assert.equal(actual, setup);
      if (sampleStart) {
        assert.equal(sampleDriver.owner, run);
        assert.equal(sampleDriver.profile, checkedProfile);
        assert.equal(sampleDriver.current(), true);
        allowsSampleCapture = false;
        assert.throws(() => sampleDriver.adopt(committedPrefix), /ClientRunSampleStartOriginalUnavailable/u);
        allowsSampleCapture = true;
        assert.equal(sampleDriver.adopt(committedPrefix), undefined);
      } else assert.equal(sampleDriver, undefined);
      const completed = {
        close() {calls.closed++;},
        cleanup() {return !laterDebugPark || laterReady;},
        cleanupPending() {return laterDebugPark && !laterReady;},
      };
      if (laterDebugPark) {
        return (async () => {
          debugRunnable = false;
          atTaskBoundary.resolve();
          await continueToPark.promise;
          assert.equal(driverControl.phase(setup), 'paused');
          try {await driverControl.waitForResume(setup, _signal);}
          catch (cause) {
            retain(completed);
            throw new CapturedRunPublicationError(cause, completed);
          }
          assert.fail('Host shutdown cannot resume another task or publish its Result');
        })();
      }
      retain(completed);
      if (installedDebug !== undefined) {
        assert.equal(installedDebug.current(), false, 'Publication drops the live Debug aliases');
        assert.throws(() => driverControl.phase(setup), {message: 'ClientRunDebugEntryOriginalUnavailable'});
      }
      if (sampleStart) {
        assert.equal(sampleDriver.owner, undefined, 'publication may keep the port but the original is released');
        assert.equal(sampleDriver.current(), false);
        assert.throws(() => sampleDriver.adopt(committedPrefix), /ClientRunSampleStartOriginalUnavailable/u);
      }
      return completed;
    },
    namespaceId: 'fixture-namespace', authorityScopeCid: 'fixture-scope',
    now: () => '2026-11-15T00:00:00.000Z',
  });
  const held = {...(managed ? {managedRun: run} : {}),
    ...(sampleStart ? {sampleProfile: missingSampleProfile ? undefined : profile} : {}),
    ...(debugEntry ? {debugEntryExpiresAt} : debugResumeUntil === undefined ? {} : {debugResumeCid: debugCid}),
    ...(source ? {preparedSource, preparedSourceAccess: sourceAccess} : {})};
  return {owner, moon, calls, marker, failures, failure, ref, stops, physicalEntered, sampleEvents, debugEvents,
    entryParked: entryParked.promise, taskParked: taskParked.promise,
    atTaskBoundary: atTaskBoundary.promise, continueToPark: continueToPark.resolve,
    ready() { ready = laterReady = true; },
    resume,
    cancel() {
      frame = Object.freeze({...frame, revision: frame.revision + 1, cancellationRequested: true});
      owner.cancel(ref);
    },
    start() { return owner.start({preparedProgram: prepared, principalId: 'owner',
      connection: {}, requestId: 'fixture-request',
      ...(ordinaryDebug ? {executionProfile: 'debug'} : {})}, request,
    {ref, runDefinition: acceptedDefinition, dispatchReserved: false, cancellationRequested: false}, held); }};
}

const sampleProfileCheckEvents = ['reserve', 'observation', 'probe-original', 'reserve-original',
  'journal-original', 'check-profile', 'return-observation'];

test('Sample start revision reaches the pending managed setup before activity and only on a confirmed start', async () => {
  for (const physicalStart of [false, true]) {
    const f = originalDispatchFixture({sampleStart: true, physicalStart});
    assert.equal(await f.start(), physicalStart ? 'started' : 'not_started');
    if (physicalStart) {
      await f.physicalEntered;
      assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim', 'core', 'received', 'reservation-observed']);
      f.cancel();
      f.resume();
      await f.owner.operation(f.ref);
    } else assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim']);
    await f.owner.drain();
    assert.equal(f.calls.opened, 1);
    assert.equal(f.calls.returned, 1);
  }
});

test('selected dispatch uses only its acknowledged Journal writer during Compute', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, normalCompute: true});
  assert.equal(await f.start(), 'started');
  await f.physicalEntered;
  const operation = f.owner.operation(f.ref);
  f.resume();
  await operation;
  await f.owner.drain();
  assert.equal(f.calls.computed, 1);
  assert.equal(f.calls.returned, 1);
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim', 'core', 'received',
    'reservation-observed', 'visit-prefix', 'journal-adopted']);
});

test('durable Sample start without its writer closes the original setup before Compute', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, sampleWriterMissing: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'ClientRunSampleStartOriginalUnavailable');
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim']);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.stops, ['failed']);
});

test('refused Sample handoff after a durable start closes the same setup before Compute', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, sampleStartCoreFailure: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, f.marker.message);
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim', 'core']);
  assert.equal(f.calls.physicalClaims, 1);
  assert.equal(f.calls.opened, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.stops, ['failed']);
  assert.equal(f.owner.operation(f.ref), undefined);
});

test('replacement Account after the Sample start ACK cannot activate the installed controller', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, replaceSampleAccountAtAck: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'ClientRunSampleStartAuthorityLost');
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared', 'claim', 'core']);
  assert.equal(f.calls.physicalClaims, 1);
  assert.equal(f.calls.computed, 0);
  assert.deepEqual(f.stops, ['failed']);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('Sample start capacity refusal never calls the preparer or attempts the physical claim', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, sampleStartCapacityFailure: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, f.marker.message);
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, ['reserve']);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.opened, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.stops, []);
  assert.equal(f.owner.operation(f.ref), undefined);
});

test('selected Sample receiver without ready refuses before physical start and returns the original setup', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, sampleStartMissingReady: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'InvalidClientRunSampleStartReceiver');
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'prepared']);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.preDispatchFailures, 1);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.closed, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.stops, []);
  assert.equal(f.owner.operation(f.ref), undefined);
});

test('a selected Sample with stale Journal evidence never reaches its receiver or physical start', async () => {
  const f = originalDispatchFixture({sampleStart: true, sampleProfileFailure: true, physicalStart: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'ClientRequestSubmittedIntentMismatch');
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, sampleProfileCheckEvents);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.preDispatchFailures, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('selected Sample row capacity refusal leaves no original view or start claim', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, sampleReadCapacityFailure: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, f.marker.message);
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, ['reserve', 'observation', 'probe-original', 'reserve-original',
    'return-observation']);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('a selected Sample cannot start while returning its original Journal profile observation', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, cleanupReady: false});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'OriginalSampleObservationReturnPending');
  assert.equal(f.calls.leaseRetired, 0);
  f.ready();
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'return-observation', 'return-observation']);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('a selected Sample without admitted profile evidence refuses without opening a Journal view', async () => {
  const f = originalDispatchFixture({sampleStart: true, physicalStart: true, missingSampleProfile: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'ClientRunSampleStartOriginalUnavailable');
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, []);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.physicalClaims, 0);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('the Driver receives the exact acknowledged Debug interval and original controller', async () => {
  for (const until of ['step', 'terminal']) {
    const f = originalDispatchFixture({debugResumeUntil: until, physicalStart: true, normalCompute: true});
    assert.equal(await f.start(), 'started');
    await f.physicalEntered;
    assert.deepEqual(f.debugEvents, ['prepare', 'claim', until]);
    const operation = f.owner.operation(f.ref);
    f.resume();
    await operation;
    await f.owner.drain();
    assert.deepEqual(f.debugEvents, ['prepare', 'claim', until, 'compute']);
    assert.equal(f.calls.returned, 1);
  }
});

test('a physical start without the acknowledged Debug interval cannot activate its controller', async () => {
  const f = originalDispatchFixture({debugResumeUntil: 'step', physicalStart: true, debugReplyLost: true});
  assert.equal(await f.start(), 'not_started');
  assert.equal((await f.failure).code, 'ClientRunDebugEntryOriginalUnavailable');
  await f.owner.drain();
  assert.deepEqual(f.debugEvents, ['prepare', 'claim']);
  assert.equal(f.calls.computed, 0);
  assert.equal(f.calls.returned, 1);
});

test('one acknowledged Debug start gives the original Driver both its controller and its Sample writer', async () => {
  const f = originalDispatchFixture({debugResumeUntil: 'step', sampleStart: true, physicalStart: true, normalCompute: true});
  assert.equal(await f.start(), 'started');
  await f.physicalEntered;
  assert.deepEqual(f.debugEvents, ['prepare', 'claim', 'step']);
  assert.deepEqual(f.sampleEvents, [...sampleProfileCheckEvents, 'claim', 'core', 'debug-resume', 'reservation-observed']);
  const operation = f.owner.operation(f.ref);
  f.resume();
  await operation;
  await f.owner.drain();
  assert.deepEqual(f.debugEvents, ['prepare', 'claim', 'step', 'compute']);
  assert.deepEqual(f.sampleEvents.slice(-2), ['visit-prefix', 'journal-adopted']);
  assert.equal(f.calls.physicalClaims, 1);
  assert.equal(f.calls.returned, 1);
});

test('the live Dispatcher parks the same sampled setup before physical start and admits another authorized client', async () => {
  for (const cancel of [false, true]) {
    const f = originalDispatchFixture({debugEntry: true, debugResumeUntil: 'step', sampleStart: true,
      physicalStart: true, normalCompute: true});
    const start = f.start();
    await f.entryParked;
    assert.equal(f.calls.physicalClaims, 0);
    assert.equal(f.calls.computed, 0);
    const client = {principalId: 'owner', connection: {}, authorize: () => true,
      reserve: peak => assert.equal(peak, 64)};
    assert.equal(f.owner.observeDebugTask(f.ref, client).revision, 2);
    assert.equal(f.owner.observeDebugInspect(f.ref, client).logicalMapCid, 'sha256:' + 'a'.repeat(64));
    assert.equal(f.owner.observeDebugInspect(f.ref, client).startRevision, 0);
    assert.equal(f.owner.observeDebugTask(f.ref, {...client, authorize: () => false}), undefined);
    if (cancel) {
      f.cancel();
      assert.equal(await start, 'not_started');
      await f.owner.drain();
      assert.deepEqual(f.debugEvents, ['prepare', 'park-entry']);
      assert.equal(f.calls.physicalClaims, 0);
      assert.equal(f.calls.returned, 1);
    } else {
      assert.equal(f.owner.resumeDebugTask(f.ref, client, 'fixture-entry-command').revision, 3);
      assert.equal(await start, 'started');
      await f.physicalEntered;
      assert.deepEqual(f.debugEvents, ['prepare', 'park-entry', 'accept-entry', 'claim', 'step']);
      const finished = f.owner.operation(f.ref);
      f.resume();
      await finished;
      await f.owner.drain();
      assert.equal(f.calls.computed, 1);
      assert.equal(f.calls.returned, 1);
    }
  }
});

test('Host shutdown releases the first Debug waiter before physical start', async () => {
  for (const resumeBeforeClose of [false, true]) {
    const f = originalDispatchFixture({debugEntry: true, debugResumeUntil: 'step', sampleStart: true,
      physicalStart: true, normalCompute: true});
    const closes = [];
    const shutdown = installedHostShutdown({dispatchOwner: f.owner, retireTerminalEffects() {
      closes.push('effects');
    }, journal: {close() {closes.push('journal');}}, store: {close() {closes.push('store');}}});
    const start = f.start();
    await f.entryParked;
    const client = {principalId: 'owner', connection: {}, authorize: () => true,
      reserve: peak => assert.equal(peak, 64)};
    assert.equal(f.owner.observeDebugTask(f.ref, client).revision, 2);
    let drain;
    if (resumeBeforeClose) {
      assert.equal(f.owner.resumeDebugTask(f.ref, client, 'fixture-entry-command').revision, 3);
      // Enter the existing drain synchronously before the accepted wait resumes.
      drain = f.owner.drain();
    }
    const close = (drain === undefined ? shutdown.close() : drain.then(() => shutdown.close()))
      .then(() => 'closed');
    const nextTurn = new Promise(resolve => setImmediate(resolve, 'still waiting'));
    assert.equal(await Promise.race([close, nextTurn]), 'closed');
    assert.equal(await start, 'not_started');
    assert.equal(f.calls.physicalClaims, 0);
    assert.equal(f.calls.computed, 0);
    assert.equal(f.calls.preDispatchFailures, 0);
    assert.deepEqual(f.stops, []);
    assert.equal(f.calls.returned, 1);
    assert.equal(f.calls.leaseRetired, 1);
    assert.deepEqual(closes, ['effects', 'journal', 'store']);
    assert.deepEqual(f.debugEvents, resumeBeforeClose
      ? ['prepare', 'park-entry', 'accept-entry'] : ['prepare', 'park-entry']);
  }
});

test('Host shutdown joins the original started Step through the later Debug park', async () => {
  for (const closeBeforePark of [false, true]) {
    const f = originalDispatchFixture({debugEntry: true, debugResumeUntil: 'step', sampleStart: true,
      physicalStart: true, normalCompute: true, laterDebugPark: true, cleanupReady: closeBeforePark});
    const closes = [];
    const shutdown = installedHostShutdown({dispatchOwner: f.owner, retireTerminalEffects() {},
      journal: {close() {closes.push('journal');}}, store: {close() {closes.push('store');}}});
    const start = f.start();
    await f.entryParked;
    const client = {principalId: 'owner', connection: {}, authorize: () => true,
      reserve: peak => assert.equal(peak, 64)};
    f.owner.resumeDebugTask(f.ref, client, 'fixture-entry-command');
    assert.equal(await start, 'started');
    f.resume();
    const failedEarly = f.failure.then(detail => assert.fail(detail.primaryCode ?? detail.code));
    await Promise.race([f.atTaskBoundary, failedEarly]);
    if (!closeBeforePark) {
      f.continueToPark();
      await Promise.race([f.taskParked, failedEarly]);
      assert.equal(f.owner.observeDebugTask(f.ref, client).revision, 5);
    }
    const closing = shutdown.close();
    if (closeBeforePark) {
      await new Promise(resolve => setImmediate(resolve));
      f.continueToPark();
      await closing;
    } else {
      await assert.rejects(closing, {code: 'ClientDispatchCleanupPending'});
      assert.deepEqual(f.stops, [], 'unsettled physical cleanup cannot acknowledge a stop');
      assert.deepEqual(closes, []);
      assert.equal(f.calls.returned, 0);
      f.ready();
      await shutdown.close();
    }
    assert.equal((await f.failure).primaryCode, 'ClientRunDebugEntryHostClosing');
    assert.deepEqual(f.debugEvents, ['prepare', 'park-entry', 'accept-entry', 'claim', 'step',
      'compute', 'park-task']);
    assert.deepEqual(f.stops, [null], 'physical close is independent of the Run outcome');
    assert.equal(f.calls.computed, 1);
    assert.equal(f.calls.physicalClaims, 1);
    assert.equal(f.calls.returned, 1);
    assert.equal(f.calls.leaseRetired, 1);
    assert.deepEqual(closes, ['journal', 'store']);
  }
});

test('the selected Debug receiver waits on the original setup and detaches on abort or retirement', async () => {
  for (const abort of [true, false]) {
    const profile = {}, setup = {}, owner = {}, authority = {principalId: 'original'};
    const controller = new AbortController();
    let account = {}, isRunnable = true;
    const original = account;
    const prepare = installNodeRelationSampleDebugEntry({
      clientProgramAdvanceRelationSampleDebugEntry(actualProfile, actualOwner, actualSetup, admitted,
        principal, site, command, revision) {
        assert.equal(actualProfile, profile);
        assert.equal(actualOwner, owner);
        assert.equal(actualSetup, setup);
        assert.equal(admitted, original);
        assert.equal(principal, 'original');
        assert.equal(site, 'local');
        assert.equal(revision, command === 'prepare' ? 0 : 2);
        return {$tag: 1, _0: undefined};
      },
      clientProgramRelationSampleDebugEntryRunnable() {return {$tag: 1, _0: isRunnable};},
      clientProgramRelationSampleDebugTaskPause() {
        return {$tag: 1, _0: {_0: 2, _1: 'last-original-step', _2: '', _3: 1}};
      },
      clientProgramResumeRelationSampleDebugTask: assert.fail,
      clientProgramRelationSampleDebugResumeAllowed: assert.fail,
    }, () => account, selected => selected === authority, 'local', {
      journal: {
        parkDebugTask(_ref, {startRevision, expectedRevision, controlRevision, stepId, nextStepId: selectedNext, committedGeneration, current}) {
          assert.equal(startRevision, 2);
          assert.equal(expectedRevision, 2);
          assert.equal(current(), true);
          assert.equal(committedGeneration, 1);
          assert.equal(selectedNext, null);
          return {kind: 'parked', revision: 3, controlRevision, stepId, nextStepId: selectedNext, committedGeneration,
            expiresAt: Date.parse('2026-11-15T00:00:05.000Z'), pausedAt: Date.parse('2026-11-15T00:00:00.000Z')};
        },
        acceptDebugTaskResume: assert.fail,
        debugPauseCurrent(_ref, {parked, startRevision, current}) {
          assert.equal(startRevision, 2);
          assert.equal(parked.stepId, 'last-original-step');
          return current();
        },
      },
      now: () => '2026-11-15T00:00:00.000Z',
    });
    const entry = prepare(setup, owner, authority, profile, controller.signal);
    const {phase, waitForResume} = entry.taskControl;
    const unavailable = {message: 'ClientRunDebugEntryOriginalUnavailable'};
    assert.throws(() => phase(setup), unavailable);
    entry.activate({until: 'step', physicalStartRevision: 2});
    assert.equal(phase(setup), 'runnable');
    assert.throws(() => phase({}), unavailable);
    assert.throws(() => waitForResume(setup, new AbortController().signal), unavailable);
    isRunnable = false;
    account = {};
    assert.throws(() => phase(setup), {message: 'ClientRunDebugEntryDenied'});
    account = original;
    assert.equal(phase(setup), 'paused');
    const wait = waitForResume(setup, controller.signal);
    assert.equal(getEventListeners(controller.signal, 'abort').length, 1);
    assert.equal(entry.observePause(() => true).completedStepId, 'last-original-step');
    assert.equal(entry.observePause(() => true).pausedAt, Date.parse('2026-11-15T00:00:00.000Z'));
    assert.equal(Object.hasOwn(entry.observePause(() => true), 'nextStepId'), false);
    assert.throws(() => waitForResume(setup, controller.signal), unavailable);
    if (abort) {
      const reason = new Error('original AbortSignal');
      controller.abort(reason);
      await assert.rejects(wait, error => error === reason);
    } else {
      entry.close();
      await assert.rejects(wait, unavailable);
    }
    entry.close();
    assert.equal(entry.current(), false);
    assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
    assert.throws(() => phase(setup), unavailable);
  }
});

test('Debug and Sample cannot advance on a missing, foreign or unacknowledged start', async () => {
  for (const [jointStart, debugReplyLost, code] of [
    ['different', false, 'ClientRunSampleStartOriginalUnavailable'],
    ['sample-missing', false, 'ClientRunSampleStartOriginalUnavailable'],
    ['confirmed', true, 'ClientRunDebugEntryOriginalUnavailable'],
    ['unknown', false, 'ClientRunPhysicalStartUnknown'],
  ]) {
    const f = originalDispatchFixture({debugResumeUntil: 'step', sampleStart: true, physicalStart: true,
      debugReplyLost, jointStart});
    assert.equal(await f.start(), 'not_started');
    assert.equal((await f.failure).code, code);
    await f.owner.drain();
    assert.deepEqual(f.debugEvents, ['prepare', 'claim']);
    assert.deepEqual(f.sampleEvents, jointStart === 'unknown' ? sampleProfileCheckEvents : [...sampleProfileCheckEvents, 'claim']);
    assert.equal(f.calls.physicalClaims, 1);
    assert.equal(f.calls.computed, 0);
    assert.equal(f.calls.returned, 1);
    assert.equal(f.calls.leaseRetired, 1);
    assert.deepEqual(f.stops, jointStart === 'unknown' ? [] : ['failed']);
  }
});

test('ordinary Debug does not opt into the unattended Sample starter', async () => {
  const f = originalDispatchFixture({physicalStart: true, normalCompute: true, ordinaryDebug: true});
  assert.equal(await f.start(), 'started');
  await f.physicalEntered;
  assert.deepEqual(f.sampleEvents, []);
  const operation = f.owner.operation(f.ref);
  f.resume();
  await operation;
  await f.owner.drain();
  assert.deepEqual(f.sampleEvents, []);
  assert.equal(f.calls.physicalClaims, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
});

test('Normal dispatch without a Sample receiver starts and enters Compute with the same setup', async () => {
  const f = originalDispatchFixture({physicalStart: true, normalCompute: true});
  assert.equal(await f.start(), 'started');
  await f.physicalEntered;
  const operation = f.owner.operation(f.ref);
  f.resume();
  await operation;
  await f.owner.drain();
  assert.equal(f.calls.physicalClaims, 1);
  assert.equal(f.calls.preDispatchFailures, 0);
  assert.equal(f.calls.computed, 1);
  assert.equal(f.calls.closed, 1);
  assert.equal(f.calls.returned, 1);
  assert.equal(f.calls.leaseRetired, 1);
  assert.deepEqual(f.sampleEvents, []);
  assert.deepEqual(f.failures, []);
  assert.deepEqual(f.stops, [null]);
});

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

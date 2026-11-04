// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {runtimeField, runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan,
  acquiredKeyedTaskPublicationPlan, sourceFreePlanExecutionOwner} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {ordinarySourceDescriptors, verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installTaskObservation} from '../host-common/task-observation.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';
import {ledgerUsageDiagnostic, ledgerUsageHasPendingResources} from '../host-common/runtime-core.mjs';

// Diagnostics must not become a second owner of execution/cleanup capabilities.
// Read only inert own data; accessors and arbitrary thrown objects are not
// invoked, traversed or retained by the returned diagnostic receipt.
const dispatchFailureFields = Object.freeze(['primaryFailure', 'closeFailure',
  'cleanupFailure', 'finishFailure', 'releaseFailure', 'preparationRetirementFailure']);
function dispatchFailureSnapshot(error) {
  if (error === undefined) return undefined;
  const text = name => {
    try {
      const field = Object.getOwnPropertyDescriptor(error, name);
      return field !== undefined && Object.hasOwn(field, 'value') &&
        typeof field.value === 'string' ? field.value : undefined;
    } catch { return undefined; }
  };
  return Object.freeze({name: text('name') ?? 'Error', code: text('code'),
    message: typeof error === 'string' ? error : text('message')});
}

// One original Core holder covers the ordinary configured Host and its
// transitive outputs through confirmed cleanup. This is not a numeric grant.
function releaseDispatchPreparationHost(entry) {
  const holder = entry.preparationHostBorrow;
  if (holder === undefined) return;
  const release = entry.preparationHostReturn, runtime = entry.preparationHostRuntime;
  entry.preparationHostBorrow = entry.preparationHostReturn = entry.preparationHostRuntime = undefined;
  // A valid Core return consumes its token before any settlement failure;
  // the original retirement receipt retains a failed debit for cleanup retry.
  checked(Reflect.apply(release, runtime, [holder]));
}
function retainDispatchPreparationHost(entry, moon, managedRun, prepared, request, hasCustody) {
  const acquire = moon.clientProgramInstalledManagedPreparationBorrow;
  if (typeof acquire !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  if (entry.preparationHostBorrow !== undefined) throw new Error('DuplicatePreparationHostBorrow');
  const release = moon.clientProgramPreparationBorrowReturn, read = moon.clientProgramPreparationBorrowRead;
  if (typeof release !== 'function' || typeof read !== 'function') throw new Error('PreparationHostCustodyUnavailable');
  const holder = checked(Reflect.apply(acquire, moon, [managedRun, prepared, request]));
  if (holder === undefined) throw new Error('PreparationHostCustodyUnavailable');
  entry.preparationHostBorrow = holder;
  entry.preparationHostReturn = release;
  entry.preparationHostRuntime = moon;
  try {
    if (!hasCustody || Reflect.apply(read, moon, [holder]) !== prepared) {
      throw new Error('ForeignPreparationHostCustody');
    }
  } catch (error) {
    releaseDispatchPreparationHost(entry);
    throw error;
  }
}

// Terminal observation only, never a send or cancellation permission. The
// physical owner calls this after confirmed stop and temporary reclamation;
// restored observers use their persisted physical-close confirmation.
async function collectNodeRunStop({ref, journal, store,
  checkpoints, moon, control, cleanupConfirmed, physicalStopConfirmed = false}, originalFrame) {
  if (typeof journal?.lookupRunDefinition !== 'function' ||
      typeof journal?.lookupReconciliationState !== 'function') return {cancelled: false};
  const before = originalFrame ?? journal.lookupRunDefinition(ref, moon, control);
  if (before === undefined) return {cancelled: false};
  const runId = control.runDefinitionRunId(before.runDefinition);
  const model = checkpoints?.journal;
  const publicationCommitted = await store.confirmCommittedIndex(ref) !== undefined;
  // Publication inspection is asynchronous. A changed request observation
  // must be re-evaluated rather than sealed as a terminal cancellation.
  const after = journal.lookupRunDefinition(ref, moon, control, before);
  // Collect fresh synchronous facts after the await, then hand the terminal
  // decision to the same common Run owner for normal and restored execution.
  const cancelled = control.runCancellationConfirmed({
    cancellationRequested: after?.cancellationRequested === true,
    modelFenceRequired: (model?.discoverModelCallSets({runId, limit: 1}) ?? []).length !== 0,
    modelFenced: model?.modelCancellationFenced?.(runId, ref.runDefinitionCid) === true,
    unresolvedModelCalls: model?.hasUnresolvedModelCalls(runId) === true,
    unresolvedEffects: journal.lookupReconciliationState(ref) !== undefined,
    reconciliationRequired: model?.getRunState?.(runId)?.status === 'needs_reconciliation',
    publicationCommitted,
    physicalStopConfirmed: physicalStopConfirmed === true,
    cleanupConfirmed: cleanupConfirmed === true,
    revisionUnchanged: after === before,
  });
  return {cancelled, publicationCommitted, revisionUnchanged: after === before, frame: after};
}

export async function confirmNodeRunCancellation(facts) {
  return (await collectNodeRunStop(facts)).cancelled;
}

export async function cancelNodeRunContinuation({currentDispatchIdle, ...facts}) {
  if (typeof currentDispatchIdle !== 'function' || !currentDispatchIdle()) return false;
  const retained = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
  // A waiting Checkpoint may be visible before its producer has reclaimed
  // its temporary resources. Require the persisted stop receipt as well as
  // absence of a newer live or pending-cleanup owner; neither alone suffices.
  if (retained?.physicalCloseConfirmed !== true) return false;
  const observation=await collectNodeRunStop({...facts,physicalStopConfirmed:true,
    cleanupConfirmed:true},retained);
  if (!observation.cancelled || !currentDispatchIdle() ||
      facts.journal.lookupRunDefinition(facts.ref,facts.moon,facts.control,
        observation.frame)!==observation.frame) {
    return false;
  }
  return facts.checkpoints.cancelEffectContinuation(
    facts.control.runDefinitionRunId(retained.runDefinition), facts.ref.runDefinitionCid);
}

export async function observeNodeRestoredLocalStop(facts) {
  // Same-process original stop is an execution observation, not a cleanup
  // acknowledgement or proof that a requested cancellation was honored.
  // Publication/Carrier cleanup remains owned by its actual original APIs.
  for (let inspection = 0; inspection < 2; inspection++) {
    const before = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control);
    if (before === undefined || before.physicalCloseConfirmed === true ||
        facts.journal.observeStoppedLocalExecutionOwner?.(facts.ref, before) !== true) return;
    const committed = await facts.store.confirmCommittedIndex(facts.ref) !== undefined;
    const retained = facts.journal.lookupRunDefinition(facts.ref, facts.moon, facts.control, before);
    if (retained?.physicalCloseConfirmed === true) return;
    if (retained !== before) {
      if (inspection === 0 &&
          facts.journal.canReinspectRunStopAfterStatePublication?.(before, retained) === true) continue;
      throw new Error('ClientRunStopObservationChanged');
    }
    if (facts.journal.observeStoppedLocalExecutionOwner(facts.ref, retained) !== true ||
        facts.journal.lookupReconciliationState(facts.ref) !== undefined) return;
    facts.journal.markPhysicalClose(facts.ref, committed ? null : 'failed', retained);
    return;
  }
  throw new Error('ClientRunStopObservationChanged');
}

export async function observeNodeRestoredModelStop(facts) {
  return observeNodeRunStop(facts, {failureObserved: false});
}

export function recordNodeRunPhysicalStop({ref, journal, moon, control}, outcome) {
  const retained = journal.lookupRunDefinition(ref, moon, control);
  if (retained?.physicalCloseConfirmed === true) return;
  journal.markPhysicalClose(ref, outcome, retained);
}

async function observeNodeRunStop(facts, {failureObserved}) {
  if (facts.physicalStopConfirmed !== true || facts.cleanupConfirmed !== true) return;
  for(let inspection=0;inspection<2;inspection++){
    const before=facts.journal.lookupRunDefinition(facts.ref,facts.moon,facts.control);
    if(before?.physicalCloseConfirmed===true)return;
    if(before===undefined)throw new Error('ClientRunStopObservationChanged');
    const observation = await collectNodeRunStop(facts,before);
    // Preserve another confirmed observer's immutable physical-stop record,
    // including a nonterminal stop from an earlier phase of this same Run.
    const retained = observation.frame;
    if (retained?.physicalCloseConfirmed === true) return;
    if (observation.revisionUnchanged !== true) {
      // A real public observation may advance only its own metadata during
      // the Store await. The Journal's nominal frame comparison must prove
      // every immutable/control field unchanged before one full reinspection.
      if(inspection===0&&facts.journal.canReinspectRunStopAfterStatePublication?.(before,retained)===true) continue;
      throw new Error('ClientRunStopObservationChanged');
    }
    facts.journal.markPhysicalClose(facts.ref, observation.publicationCommitted ? null :
      observation.cancelled ? 'cancelled' : failureObserved && retained?.cancellationRequested !== true ? 'failed' : null,
    retained);
    return;
  }
  // Continued changes retain this same physical owner for later inspection.
  throw new Error('ClientRunStopObservationChanged');
}

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
  faultInjection, runInfer, runContent, computeConfigurations = {},
  observation, preparationCustody, beforePublication,
  managedComputeRequired = false,
  retainedRelationOutput = false,
  runPublished = runPublishedCapturedStrategy}) {
  const entries = new Map();
  const diagnostic = diagnosticObserver(observed);
  const step = async (name, detail) => {
    diagnostic(name, detail);
    await faultInjection?.(name, detail);
  };
  const keyOf = ref => ref.runDefinitionCid;
  const current = ref => entries.get(keyOf(ref));
  const resourceUsage = ledger => {
    const usage = moon.clientProgramMultiCapturedLedgerUsage(ledger);
    return ledgerUsageDiagnostic(usage);
  };
  const cancel = ref => current(ref)?.abort.abort(
    new Error('ClientRunCancellationRequested'));
  const live = ref => current(ref)?.settled === false;
  const operation = ref => current(ref)?.promise;

  async function acquireSource(entry, preparedProgram, preparedSource, sourceAccess,
    {captureOnly = false, originalEvidence = false, ledger, occurrence} = {}) {
    if (entry.sourceCapture !== undefined) {
      throw new TypeError('ClientSourceCaptureAlreadyRetained');
    }
    const installedSource = installedSourceFor(sourceProfile,
      preparedSource.checkedSource.sourceRef);
    const captureStartedAt = now();
    await step('acquisition_started', {ref: entry.ref,
      ...(preparedSource.selection === undefined ? {} :
        {selection: preparedSource.selection})});
    entry.physicalStarted = true;
    entry.physicalWorkMayHaveStarted = true;
    const acquisition = acquisitionEndHandoff();
    const measured = observation?.canMeasure('source') ? performance.now() : undefined;
    let returned = false;
    try {
      const open = captureOnly ? installedSource.openCapture : installedSource.open;
      if (typeof open !== 'function') throw new TypeError('InstalledSourceCaptureUnavailable');
      entry.sourceCapture = await open({preparedProgram,
        registry, values, fragment, ordered, sourceAccess,
        signal: entry.abort.signal, preparedSource,
        retainedRelationOutput, ledger,
        reportAcquisitionFailure: acquisition.retain,
        ...(entry.sourceOperationScope === undefined ? {} : {
          originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
            journal, store, preparedProgram, preparedSource, occurrence ?? {stage: 0, input: 0, task: 0}),
        })});
      returned = true;
    } catch (error) {
      const ended = acquisition.outcome(error);
      if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
        entry.stopObservationPending = true;
      } else if (ended.recovery !== undefined) {
        entry.cleanupOwner = ended.recovery;
      } else {
        entry.unresolvedCleanup = true;
      }
      throw error;
    } finally {
      if (measured !== undefined) observation.emit('source', 'acquisition_interval',
        {ref: entry.ref, outcome: returned ? 'confirmed' : 'failed'},
        {segment: 'source-acquisition', durationMs: performance.now() - measured});
    }
    const captureCompletedAt = now();
    await step('acquisition_completed', {ref: entry.ref,
      ...(entry.sourceCapture.acquisition === undefined ? {} :
        {acquisition: entry.sourceCapture.acquisition})});
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: entry.sourceCapture.checkedSource.sourceDataPolicyCid};
    let sourceEvidence, sourceEvidenceWire;
    if (originalEvidence) {
      await entry.sourceCapture.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(entry.sourceCapture.capture);
    } else sourceEvidenceWire = await entry.sourceCapture.issueSourceEvidence(evidenceOptions);
    return {captured: entry.sourceCapture, captureStartedAt, captureCompletedAt,
      sourceEvidence, sourceEvidenceWire};
  }

  async function acquireKeyedSources(entry, preparedProgram, selected, acquired, principalId) {
    const {directAdapter, keyedAdapter, preparedSource, directOccurrence,
      directAccess, keyedAccess, preparedKeyed, acquisition, capacity, ledger, capturedContent,
      managedRun, requestIdentity} = selected;
    // Retain the aggregate before the first await. Compute borrows these
    // inputs; its confirmed close must precede reclamation of either source.
    entry.borrowedSources = true;
    const children = [];
    const closed = new Set();
    entry.sourceCapture = Object.freeze({async close() {
      const failures = [];
      for (const child of [...children].reverse()) {
        if (closed.has(child)) continue;
        try {
          await child.close();
          if (typeof child.cleanup === 'function' &&
              (await child.cleanup() === false || child.cleanupPending() !== false)) {
            throw new Error('ClientSourceCleanupPending');
          }
          closed.add(child);
        } catch (error) {
          failures.push(error);
          // The lookup can still borrow its left capture while stopping.
          // Keep earlier children until that dependent custody is reclaimed.
          break;
        }
      }
      if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
    }});
    const open = async (kind, operation) => {
      let returned = false;
      entry.abort.signal.throwIfAborted();
      await step('acquisition_started', {ref: entry.ref, kind,
        resourceUsage: resourceUsage(ledger)});
      entry.physicalWorkMayHaveStarted = true;
      try {
        const child = await operation();
        children.push(child);
        returned = true;
        await step('acquisition_completed', {ref: entry.ref, kind,
          resourceUsage: resourceUsage(ledger)});
        return child;
      } catch (error) {
        if (returned) throw error;
        const ended = acquisitionEndHandoff().outcome(error);
        if (ended.outcome === 'unknown') {
          // A lookup's failed child is source custody, not an execution owner.
          // Keep it alongside the already acquired Direct input for retry.
          if (ended.recovery !== undefined) children.push(ended.recovery);
          else entry.unresolvedCleanup = true;
        }
        throw error;
      }
    };
    const captureStartedAt = now();
    const captured = await open('direct', () => directAdapter.openCapture({preparedProgram,
      registry, values, fragment, ordered, preparedSource,
      occurrence: directOccurrence, sourceAccess: directAccess,
      signal: entry.abort.signal, ledger}));
    const left = checked(moon.clientProgramKeyedCaptureLeftRead(acquisition,
      captured.capture.source()));
    const keyedContent = !capturedContent ? undefined : runContent.captureKeyed({
      preparedProgram, plan: acquired, acquisition, ledger, maxBytes: capacity.maxBytes, maxWork: capacity.maxWork,
      sourceBinding: keyedAdapter.keyedRecoveryBinding(preparedKeyed),
      store, principalId, signal: entry.abort.signal, retainExecution: child => children.push(child)});
    const lookup = await open('keyed', () => keyedAdapter.openKeyedLookup({preparedProgram,
      keyedAcquisition: acquisition, left, ledger, signal: entry.abort.signal,
      originalCapture: captured.capture, keyedContent,
      sourceAccess: keyedAccess, preparedKeyed, maxWork: capacity.maxWork}));
    const evidenceOptions = {authorityScopeCid,
      effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
    const contentOrInfer = acquired.serializationGraph !== undefined || acquired.kind === 'infer';
    let sourceEvidence, sourceEvidenceWire;
    if (contentOrInfer) sourceEvidenceWire = await captured.issueSourceEvidence(evidenceOptions);
    else {
      await captured.prepareSourceEvidenceOriginal(evidenceOptions);
      sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
    }
    const keyedObservation = await lookup.issueObservation({authorityScopeCid, observedAt: now()});
    const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
    if (effectiveDataPolicyCid === undefined) throw new Error('InstalledKeyedSourcePolicyUnavailable');
    if (contentOrInfer) {
      // Both acquisition children remain in this supervisor's custody. The
      // Content provider borrows their exact sealed inputs; cleanup stops that
      // dependent before closing lookup and its left capture in reverse order.
      return {plan: acquired, acquiredContent: {captured, ledger, sourceEvidenceWire,
        authorityScopeCid, captureStartedAt, captureCompletedAt: now(), keyedObservation,
        keyedLookup: await lookup.borrowSerializationInput(), keyedContent,
        sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}),
        keyedSourceEvidence: control.admitRunEvidence('source_evidence', keyedObservation.sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})}};
    }
    const plan = acquiredKeyedTaskPublicationPlan({moon, control, acquired,
      preparedProgram, captured, sourceEvidence, keyedObservation,
      authorityScopeCid, effectiveDataPolicyCid, captureStartedAt, captureCompletedAt: now(),
      namespaceId, storeAuthorityCid, now});
    const setup = await lookup.openHost({registry, values, fragment, ordered, retainedRelationOutput,
      managedRun, requestIdentity});
    entry.pendingSetup = setup;
    return {plan, setup};
  }

  function retire(entry) {
    if (entry.settled && entry.cleanupOwner === undefined &&
        entry.cleanupHandle === undefined && !entry.unresolvedCleanup &&
        entry.sourceCapture === undefined && entry.sourcePreparations === undefined &&
        entry.pendingSetup === undefined &&
        !entry.stopObservationPending &&
        !entry.failureObservationPending && !entry.finishPending &&
        !entry.releasePending &&
        (!entry.physicalStarted || entry.stopObserved ||
          !entry.physicalWorkMayHaveStarted)) {
      try {
        entry.retirePreparation?.();
      } catch (failure) {
        // Keep the original retirement capability and identity for drain.
        // A settled operation alone does not release preparation custody.
        entry.preparationRetirementFailure = failure;
        return;
      }
      entry.retirePreparation = undefined;
      entry.preparationRetirementFailure = undefined;
      const removed = entries.delete(keyOf(entry.ref));
      // This diagnostic describes the complete original owner, not just its
      // physical children. Preparation/finished and acquisition release have
      // now completed under the unchanged retirement predicate above.
      if (removed && entry.acquisitionLedger !== undefined) {
        try {diagnostic('dispatch_cleanup_completed', {ref: entry.ref,
          resourceUsage: resourceUsage(entry.acquisitionLedger)});}
        catch { /* Optional observation cannot restore or prevent retirement. */ }
      }
    }
  }

  async function observeStop(entry) {
    if (entry.terminalOutcome === 'cancelled' &&
        !await confirmNodeRunCancellation({ref: entry.ref, journal, store,
          checkpoints, moon, control, cleanupConfirmed: true, physicalStopConfirmed: true})) {
      entry.terminalOutcome = null;
    }
    if (entry.observeStopped !== undefined) {
      // An Effect continuation may stop its in-process Compute while its Run
      // waits for approval. Only that common Run owner can publish the
      // observed outcome; absence of a public index does not imply failure.
      await entry.observeStopped(entry.terminalOutcome ?? null);
      entry.stopObservationPending = false;
      entry.stopObserved = true;
      return;
    }
    await observeNodeRunStop({ref: entry.ref, journal, store, checkpoints,
      moon, control, cleanupConfirmed: true, physicalStopConfirmed: true},
    {failureObserved: !entry.abort.signal.aborted});
    entry.stopObservationPending = false;
    entry.stopObserved = true;
  }

  async function settleCleanupHandle(entry) {
    if (entry.cleanupHandle === undefined) return;
    const handle = entry.cleanupHandle;
    if (handle.status()?.pending === true) await handle.retry();
    if (handle.status()?.pending !== false) {
      throw new Error('ClientDispatchCleanupPending');
    }
    entry.cleanupHandle = undefined;
  }

  async function settleCleanup(entry) {
    const execution = entry.cleanupOwner;
    if (entry.borrowedSources && entry.sourceCapture !== undefined) {
      // Stop Compute before closing any borrowed native input. The same
      // NativePhysical issuer must confirm close before the DAG can release
      // its transferred holding. A failed close retains these exact owners.
      if (execution !== undefined) {
        try { await execution.close(); } catch (failure) { entry.closeFailure ??= failure; }
      }
      if (entry.pendingSetup !== undefined) moon.strategyHostStop(entry.pendingSetup);
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      if (!entry.computeStartAttempted && !entry.unresolvedCleanup) entry.stopObservationPending = true;
    }
    if (entry.pendingSetup !== undefined) {
      moon.strategyHostStop(entry.pendingSetup);
      moon.strategyHostCloseOutputs(entry.pendingSetup);
      if (ledgerUsageHasPendingResources(moon.strategyHostUsage(entry.pendingSetup)) &&
          !(entry.preparationHostBorrow !== undefined &&
            typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
            moon.clientProgramPreparationBorrowUsageIsolated(entry.preparationHostBorrow, moon.strategyHostRun(entry.pendingSetup)) === true)) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.pendingSetup = undefined;
      // This exact setup has stopped and returned its temporary resources.
      // An unentered Compute needs no execution-owner handoff; the existing
      // Run owner still decides the outcome from current durable facts.
      if (entry.physicalStarted && !entry.computeStartAttempted) {
        entry.stopObservationPending = true;
      }
    }
    if (execution !== undefined) {
      if (typeof execution.close !== 'function' ||
          typeof execution.cleanup !== 'function' ||
          typeof execution.cleanupPending !== 'function') {
        throw new Error('ClientDispatchCleanupOwnerInvalid');
      }
      // close may permanently retain its first rejected Promise. Recovery is
      // owned by cleanup, not by invoking close again or repeating Compute.
      try { await execution.close(); }
      catch (failure) { entry.closeFailure ??= failure; }
      // A failed Store consumer can still pin the completed output. Ask the
      // retained Store owner to settle before retrying the execution's
      // reclamation; cancellation alone still grants neither release.
      await settleCleanupHandle(entry);
      const recovered = await execution.cleanup();
      if (recovered === false || execution.cleanupPending() !== false) {
        throw new Error('ClientDispatchCleanupPending');
      }
      entry.cleanupOwner = undefined;
      entry.stopObservationPending = true;
    }
    if (entry.sourceCapture !== undefined) {
      await entry.sourceCapture.close();
      entry.sourceCapture = undefined;
      // Acquisition returned successfully, but evidence/plan preparation can
      // fail before Compute has an owner. Closing that exact capture confirms
      // this physical end; it does not confirm an unowned Compute attempt.
      if (!entry.computeStartAttempted) entry.stopObservationPending = true;
    }
    await settleCleanupHandle(entry);
    if (entry.unresolvedCleanup) {
      throw new Error('ClientDispatchCleanupOwnerMissing');
    }
    if (entry.sourcePreparations !== undefined) {
      for (const {source, prepared, retire} of entry.sourcePreparations) {
        Reflect.apply(retire, source, [prepared]);
      }
      entry.sourcePreparations = undefined;
    }
    if (entry.stopObservationPending) await observeStop(entry);
    if (entry.failureObservationPending) {
      journal.markPreDispatchFailure(entry.ref);
      entry.failureObservationPending = false;
    }
    if (entry.physicalStarted && !entry.stopObserved &&
        entry.physicalWorkMayHaveStarted) {
      throw new Error('ClientDispatchStopUnknown');
    }
    observation?.emit('cleanup', 'cleanup_completed', {ref: entry.ref,
      physicalStop: entry.stopObserved ? 'confirmed' : undefined});
  }

  async function finishRun(entry) {
    if (!entry.finishPending) return;
    await entry.finished?.();
    entry.finishPending = false;
  }

  function releaseAcquisition(entry) {
    if (!entry.releasePending) return;
    checkpoints.releaseAcquisition(entry.requestId);
    entry.releasePending = false;
  }

  const start = (submission, requested, accepted, held, finished, gate) => {
    const {principalId: actual, connection} = submission;
    const unstarted = accepted.dispatchReserved !== true ||
      accepted.physicalStartReserved === false &&
      !accepted.preDispatchFailureConfirmed;
    if (entries.has(keyOf(accepted.ref)) || !unstarted ||
        accepted.cancellationRequested) {
      return Promise.resolve('not_started');
    }
    // Held requests can start only from the Checkpoint's admitted resume.
    if (gate === undefined && checkpoints?.heldOrigin(submission.requestId)) {
      return Promise.resolve('not_started');
    }
    let preparationLease = preparationCustody?.begin(submission);
    let preparedProgram = preparationLease === undefined
      ? submission.preparedProgram : preparationLease.preparedProgram;
    let reached;
    const physical = new Promise(resolve => { reached = resolve; });
    const entry = {ref: accepted.ref, requestId: submission.requestId,
      finished, promise: undefined,
      reserved: false, settled: false, abort: new AbortController(),
      physicalStarted: false, physicalStartClaimAttempted: false,
      computeStartAttempted: false,
      failureObservationPending: false, stopObservationPending: false,
      stopObserved: false, physicalWorkMayHaveStarted: false,
      finishPending: false, releasePending: checkpoints !== undefined,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, sourceCapture: undefined};
    if (preparationLease !== undefined) {
      entry.retirePreparation = () => {
        // The complete retirement predicate has settled callbacks, physical
        // custody and acquisition release. No later drain needs these raw
        // aliases; discard them before the private owner returns its charge.
        preparedProgram = undefined;
        if (held !== undefined) held.plan = undefined;
        submission = requested = accepted = held = finished = gate = undefined;
        entry.finished = undefined;
        entry.observeStopped = undefined;
        for (const field of dispatchFailureFields) {
          entry[field] = dispatchFailureSnapshot(entry[field]);
        }
        releaseDispatchPreparationHost(entry);
        preparationLease.retire();
        preparationLease = undefined;
      };
    }
    entries.set(keyOf(accepted.ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      const claim = await startRun({identity: requested, namespaceId,
        principalId: actual, connection});
      if (claim.kind !== 'reserved' &&
          !(claim.kind === 'reconcile' &&
            accepted.dispatchReserved === true &&
            accepted.physicalStartReserved === false &&
            !accepted.preDispatchFailureConfirmed)) return;
      entry.reserved = true;
      await step('dispatch_reserved', {ref: claim.ref});
      if (beforeDispatch !== undefined) await beforeDispatch(claim.ref);
      if (entry.abort.signal.aborted) return;
      if (held.plan === undefined) {
        held.plan = planFor(submission, accepted.runDefinition.wire);
      }
      const acquiring = sourceProfile !== undefined &&
        moon.clientProgramAcquisitionCount(preparedProgram) > 0;
      const inferring = held.plan.kind === 'infer';
      const serializing = held.plan.kind === 'serialization';
      const generatingContent = held.plan.serializationGraph !== undefined;
      // Managed Compute publication cannot publish an acquisition Result.
      // Inspect the common checked graph before reserving physical custody or
      // capturing rows. Content and Infer have their own publication owners.
      if (!inferring && !serializing && !generatingContent) {
        if (held.managedRun !== undefined &&
            typeof moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication !== 'function') {
          throw new TypeError('InstalledManagedSourcePlanUnavailable');
        }
        const requiresAcquisitionResult = held.managedRun === undefined
          ? moon.clientProgramRequiresAcquisitionResultPublication(preparedProgram)
          : checked(moon.clientProgramInstalledManagedRequiresAcquisitionResultPublication(
            held.managedRun, preparedProgram, requested));
        if (requiresAcquisitionResult) throw new TypeError('InstalledAcquisitionResultPublicationUnsupported');
      }
      // A checked model barrier is not a Values task. The installed Model
      // connection must consume this exact plan and transfer physical custody
      // before advancing; this supervisor still owns the one Run-start claim.
      if (inferring && typeof runInfer !== 'function') {
        throw new Error('InstalledInferDispatchUnavailable');
      }
      if ((serializing || generatingContent) && typeof runContent !== 'function') {
        // Only the Host's installed physical composition may consume this
        // checked Content plan. Never execute it as dense Relation/Values.
        throw new Error('InstalledContentDispatchUnavailable');
      }
      const multiple = held.preparedSources?.length === 2;
      const keyedAcquisition = held.keyedSource?.acquisition ?? (typeof moon.clientProgramSelectSingleKeyedAcquisition === 'function'
        ? checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) : undefined);
      if (keyedAcquisition !== undefined && (multiple ||
          inferring && !generatingContent && typeof runInfer.prepareKeyedLedger !== 'function')) {
        throw new Error('InstalledKeyedSourceRunProfileUnsupported');
      }
      if (keyedAcquisition !== undefined && checkpoints !== undefined && held.keyedSource === undefined) {
        // A listing-only inventory must not authorize keyed content I/O.
        throw new Error('InstalledKeyedSourceAdmissionInventoryUnavailable');
      }
      if (inferring && multiple && typeof sourceProfile?.modelPreparation !== 'function') {
        throw new Error('InstalledInferMultiSourceUnsupported');
      }
      const installedSource = acquiring && !multiple
        ? installedSourceFor(sourceProfile, held.preparedSource.checkedSource.sourceRef) : undefined;
      if (retainedRelationOutput && !inferring && installedSource !== undefined &&
          installedSource.supportsRetainedRelationOutput !== true) {
        throw new TypeError('InstalledSourceRetainedOutputUnsupported');
      }
      let ledger;
      let keyedSelection;
      const selectedSources = [];
      if (keyedAcquisition !== undefined) {
        const coordinates = moon.clientProgramKeyedDirectAcquisitionCoordinates(keyedAcquisition);
        if (coordinates === undefined || installedSource === undefined) {
          throw new Error('InstalledKeyedSourcePreparationUnavailable');
        }
        const directOccurrence = {stage: runtimeField(coordinates, 0), input: runtimeField(coordinates, 1), task: runtimeField(coordinates, 2)};
        const directAccess = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess, {...directOccurrence,
            checkedSource: held.preparedSource.checkedSource,
            readTuple: held.preparedSource.readTuple,
            physicalBinding: held.preparedSource.physicalBinding,
            ...(held.keyedSource === undefined ? {} : {installationBinding: {
              connectorId: installedSource.connectorBindings[0].connectorId,
              connectorRegistration: installedSource.connectorRegistration,
              connectorRevision: installedSource.connectorRevision,
              bindingCid: installedSource.connectorBindings[0].bindingCid}})}) ?? installedSource.sourceAccess;
        const preparedSource = directAccess === held.preparedSourceAccess ? held.preparedSource :
          await prepareAcquisition(preparedProgram, directAccess, directOccurrence);
        const facts = checked(moon.clientProgramKeyedAcquisitionSourceEvidenceFacts(keyedAcquisition));
        const keyedAdapter = installedSourceFor(sourceProfile, facts[0]);
        if (typeof installedSource.openCapture !== 'function' ||
            typeof keyedAdapter.openKeyedLookup !== 'function' ||
            typeof keyedAdapter.keyedLedgerCapacity !== 'function') {
          throw new Error('InstalledKeyedSourceCapacityUnavailable');
        }
        const direct = installedSource.ledgerCapacity(preparedSource);
        const capacity = keyedAdapter.keyedLedgerCapacity(keyedAcquisition);
        const capturedContent = keyedAdapter.requiresRunContentCapture === true;
        if (capturedContent && typeof runContent?.captureKeyed !== 'function') {
          throw new Error('InstalledContentCaptureUnavailable');
        }
        const retainedKeyed = held.keyedSource;
        const keyedAccess = retainedKeyed === undefined ? keyedAdapter.sourceAccess
          : checkpoints?.acquisitionAccess(submission.requestId, keyedAdapter.sourceAccess,
            {...retainedKeyed.occurrence, checkedSource: retainedKeyed.prepared.checkedSource,
              readTuple: retainedKeyed.prepared.readTuple, physicalBinding: retainedKeyed.prepared.physicalBinding,
              installationBinding: {connectorId: keyedAdapter.connectorBindings[0].connectorId,
                connectorRegistration: keyedAdapter.connectorRegistration, connectorRevision: keyedAdapter.connectorRevision,
                bindingCid: keyedAdapter.connectorBindings[0].bindingCid}}) ?? keyedAdapter.sourceAccess;
        const preparedKeyed = retainedKeyed === undefined ? undefined :
          (await keyedAdapter.prepareKeyed({preparedProgram, keyedAcquisition,
            requestIdentity: retainedKeyed.requestIdentity, sourceAccess: keyedAccess})).prepared;
        // Captured Content must retain the admitted physical read binding.
        // Refuse missing custody before reserving a start or listing any rows;
        // acquisition rechecks that binding before issuing its Content frame.
        if (capturedContent) {
          if (typeof keyedAdapter.keyedRecoveryBinding !== 'function') {
            throw new Error('InstalledCapturedContentBindingUnavailable');
          }
          keyedAdapter.keyedRecoveryBinding(preparedKeyed);
        }
        const managedKeyed = !generatingContent && !inferring && direct.managedRun !== undefined;
        if (managedKeyed) {
          if (direct.managedRun !== held.managedRun ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledKeyedSourceOriginalRunUnavailable');
          }
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested,
            preparationLease !== undefined);
          // The retained Plan already owns Direct and Compute. Borrow its
          // SAME Ledger; each actual keyed RowRun/lookup admits and grows its
          // own demand there before use. A full budget is not another cost.
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            held.managedRun, preparedProgram, requested, [direct.capacity],
            [direct.transferBytes], [direct.executionBytes], registry, values, fragment, ordered));
        } else ledger = generatingContent ? runContent.prepareKeyedLedger({preparedProgram, plan: held.plan,
          direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          inferring ? runInfer.prepareKeyedLedger({preparedProgram, plan: held.plan,
            direct, acquisition: keyedAcquisition, capacity, capturedContent}) :
          moon.clientProgramPrepareKeyedCapturedLocalInstalledLedger(preparedProgram,
          direct.capacity, keyedAcquisition, capacity.capacity,
          [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
          capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered, capturedContent);
        if (ledger === undefined) throw new Error('InstalledKeyedSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
        keyedSelection = {directAdapter: installedSource, keyedAdapter, preparedSource,
          directOccurrence, directAccess, keyedAccess, preparedKeyed,
          acquisition: keyedAcquisition, capacity, ledger, capturedContent,
          ...(managedKeyed ? {managedRun: held.managedRun, requestIdentity: requested} : {})};
      }
      if (multiple) {
        // Preparation creates the whole original prefix before the first
        // physical read. Retain each existing preparation's retirement port
        // before a sibling can fail; started captures still close above first.
        entry.sourcePreparations = held.preparedSources.flatMap(source => {
          const retire = source.adapter.retirePreparedSource;
          if (retire === undefined) return [];
          if (typeof retire !== 'function') throw new TypeError('InstalledSourceCleanupUnavailable');
          return [{source: source.adapter, prepared: source.prepared, retire}];
        });
        // Read approvals retain their occurrence and physical target. Resolve
        // resumed access before selecting configurations and sizing the one
        // ledger; the exact preparations below also own the subsequent reads.
        const descriptors = ordinarySourceDescriptors(held.preparedSources);
        for (const [index, source] of held.preparedSources.entries()) {
          entry.abort.signal.throwIfAborted();
          const occurrence = descriptors[index];
          const access = checkpoints?.acquisitionAccess(submission.requestId,
            source.sourceAccess, occurrence) ?? source.sourceAccess;
          const preparedSource = access === source.sourceAccess ? source.prepared :
            await prepareAcquisition(preparedProgram, access, source.occurrence);
          if (occurrence.installationBinding !== undefined) {
            verifyOrdinarySourceBinding(source.adapter, preparedSource, occurrence.installationBinding);
          }
          selectedSources.push({...source, access, preparedSource});
        }
        const capacities = selectedSources.map(source => {
          if (retainedRelationOutput &&
              source.adapter.supportsRetainedRelationOutput !== true) {
            throw new TypeError('InstalledSourceRetainedOutputUnsupported');
          }
          if (typeof source.adapter.ledgerCapacity !== 'function') {
            throw new TypeError('InstalledMultiSourceCapacityUnavailable');
          }
          return source.adapter.ledgerCapacity(source.preparedSource);
        });
        const managedRun = capacities[0]?.managedRun;
        if (capacities.some(value => value.managedRun !== undefined)) {
          if (managedRun === undefined || capacities.some(value => value.managedRun !== managedRun) ||
              typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
            throw new Error('InstalledMultiSourceOriginalRunUnavailable');
          }
          // The original operational parent was admitted before preparation.
          // Do not replace it with the legacy scalar accounting constructor,
          // even when another Source has equal capacities or matching CIDs.
          if (inferring) {
            if (held.managedRun !== managedRun || typeof runInfer.prepareAcquiredLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            retainDispatchPreparationHost(entry, moon, managedRun, preparedProgram, requested, preparationLease !== undefined);
            ledger = runInfer.prepareAcquiredLedger({preparedProgram, plan: held.plan, sourceCapacities: capacities});
            entry.borrowedSources = true;
          } else {
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            managedRun, preparedProgram, requested,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered));
          }
        } else {
          ledger = moon.clientProgramPrepareMultiCapturedLocalInstalledLedger(preparedProgram,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      const requestModelAcquired = inferring && !generatingContent && acquiring && !multiple &&
        keyedSelection === undefined && held.managedRun !== undefined;
      if ((generatingContent || requestModelAcquired) && acquiring && keyedSelection === undefined) {
        if (multiple ||
            typeof (requestModelAcquired ? runInfer : runContent).prepareAcquiredLedger !== 'function' ||
            typeof installedSource?.ledgerCapacity !== 'function') {
          throw new Error('InstalledContentAcquiredDispatchUnavailable');
        }
        const access = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess) ?? installedSource.sourceAccess;
        if (held.preparedSourceAccess !== access) {
          held.preparedSource = await prepareAcquisition(preparedProgram, access);
          held.preparedSourceAccess = access;
        }
        if (requestModelAcquired) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          ledger = runInfer.prepareAcquiredLedger({preparedProgram, plan: held.plan,
            sourceCapacity: installedSource.ledgerCapacity(held.preparedSource)});
          entry.borrowedSources = true;
        } else ledger = runContent.prepareAcquiredLedger({preparedProgram, plan: held.plan,
          sourceCapacity: installedSource.ledgerCapacity(held.preparedSource)});
        entry.acquisitionLedger = ledger;
      }
      const singleAccounted = acquiring && !multiple && keyedSelection === undefined &&
        !inferring && !serializing;
      if (singleAccounted) {
        const access = checkpoints?.acquisitionAccess(submission.requestId,
          installedSource.sourceAccess) ?? installedSource.sourceAccess;
        if (held.preparedSourceAccess !== access) {
          held.preparedSource = await prepareAcquisition(preparedProgram, access);
          held.preparedSourceAccess = access;
        }
        if (typeof installedSource.ledgerCapacity !== 'function') {
          throw new Error('InstalledSingleSourceCapacityUnavailable');
        }
        const capacity = installedSource.ledgerCapacity(held.preparedSource);
        if (capacity.managedRun !== undefined) {
          if (capacity.managedRun !== held.managedRun) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          if (capacity.wholeInput === true) {
            if (typeof moon.clientProgramInstalledManagedWholeSourceLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourceLedger(
              capacity.managedRun, preparedProgram, requested,
              capacity.capacity, capacity.transferBytes, capacity.executionBytes));
          } else {
            if (typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
              throw new Error('InstalledSingleSourceOriginalRunUnavailable');
            }
            // One Source uses the same operational parent as the checked
            // capture prefix. Equal scalar capacity is not a replacement Run.
            ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
              capacity.managedRun, preparedProgram, requested,
              [capacity.capacity], [capacity.transferBytes], [capacity.executionBytes],
              registry, values, fragment, ordered));
          }
        } else {
          if (capacity.wholeInput === true || held.managedRun !== undefined) {
            throw new Error('InstalledSingleSourceOriginalRunUnavailable');
          }
          ledger = moon.clientProgramPrepareSingleCapturedLocalInstalledLedger(preparedProgram,
            capacity.capacity, capacity.transferBytes, capacity.executionBytes,
            registry, values, fragment, ordered);
        }
        if (ledger === undefined) throw new Error('InstalledSingleSourceLedgerUnavailable');
        entry.acquisitionLedger = ledger;
      }
      let setup;
      let acquiredInfer;
      let acquiredContent;
      if (!acquiring && !inferring && !serializing) {
        if (managedComputeRequired && held.managedRun === undefined) {
          throw new Error('InstalledManagedComputeRunUnavailable');
        }
        if (held.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedSourceFreeHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          // This opaque Run already owns the original operational Ledger.
          // Missing/foreign/parked originals cannot fall back to accounting.
          setup = checked(moon.clientProgramOpenInstalledManagedSourceFreeHost(
            held.managedRun, preparedProgram, requested, registry, values,
            fragment, ordered, retainedRelationOutput));
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenSourceFreeLocalRetainedHost
            : moon.clientProgramOpenSourceFreeLocalHost;
          setup = open(
            preparedProgram, registry, values, 1n, 0n, 0n, 0n,
            fragment, ordered);
        }
        if (setup === undefined) throw new Error('ClientProgramNeedsInputs');
        // Retain before the reservation/fault boundary: cancellation can
        // arrive there before runPublished transfers execution custody.
        entry.pendingSetup = setup;
      }
      // The resumed admission and physical start reservation are adjacent.
      if (gate !== undefined) {
        try { gate.beforePhysicalStart(); }
        catch (error) {
          reached({refused: error});
          await settleCleanup(entry);
          return;
        }
      }
      entry.physicalStartClaimAttempted = true;
      if (!journal.reservePhysicalStart(requested, {
        namespaceId, ref: accepted.ref,
        currentAuthorization: hostConnection({principalId: actual,
          connection, ref: accepted.ref}),
        ...(!acquiring && !inferring && !serializing && !generatingContent ? {
          localExecutionOwner: sourceFreePlanExecutionOwner(held.plan),
        } : {}),
        ...(acquiring && journal.sourceOperationConfigured === true ? {
          captureSourceOperation: {program: preparedProgram, compiled: held.plan.compiled, store,
            capture(scope) {entry.sourceOperationScope = scope;}},
        } : {}),
      }, moon, control)) {
        await settleCleanup(entry);
        return;
      }
      entry.physicalStarted = true;
      entry.finishPending = true;
      gate?.started();
      reached('started');
      await step('physical_start_reserved', {ref: accepted.ref});
      const sourceAccess = checkpoints?.acquisitionAccess(
        submission.requestId, installedSource?.sourceAccess) ??
        installedSource?.sourceAccess;
      if (keyedSelection !== undefined) {
        const keyed = await acquireKeyedSources(entry, preparedProgram, keyedSelection, held.plan, actual);
        held.plan = keyed.plan;
        setup = keyed.setup;
        acquiredContent = keyed.acquiredContent;
      } else if (multiple) {
        entry.borrowedSources = true;
        const captures = [];
        const closed = new Set();
        entry.sourceCapture = Object.freeze({async close() {
          const failures = [];
          for (const capture of captures) {
            if (closed.has(capture)) continue;
            try {
              await step('acquisition_cleanup_started', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
              await capture.close();
              closed.add(capture);
              diagnostic('acquisition_cleanup_completed', {ref: accepted.ref,
                task: capture.occurrence.task, resourceUsage: resourceUsage(ledger)});
            }
            catch (error) { failures.push(error); }
          }
          if (failures.length) throw new AggregateError(failures, 'ClientSourceCleanupPending');
        }});
        const captureStartedAt = now();
        const sources = [];
        for (const source of selectedSources) {
          entry.abort.signal.throwIfAborted();
          const {access, preparedSource} = source;
          await step('acquisition_started', {ref: accepted.ref, task: source.occurrence.task,
            selection: preparedSource.selection,
            resourceUsage: resourceUsage(ledger)});
          entry.physicalWorkMayHaveStarted = true;
          const acquisition = acquisitionEndHandoff();
          const measured = observation?.canMeasure('source') ? performance.now() : undefined;
          let captured;
          let returned = false;
          try {
            captured = await source.adapter.open({preparedProgram, registry, values,
              fragment, ordered, sourceAccess: access, signal: entry.abort.signal,
              preparedSource, occurrence: source.occurrence, ledger,
              reportAcquisitionFailure: acquisition.retain,
              ...(entry.sourceOperationScope === undefined ? {} : {
                originalOperationScope: bindClientSourceOperation(entry.sourceOperationScope,
                  journal, store, preparedProgram, preparedSource, source.occurrence),
              })});
            returned = true;
          } catch (error) {
            const ended = acquisition.outcome(error);
            if (ended.outcome === 'not_started' || ended.outcome === 'stopped') {
              entry.stopObservationPending = true;
            } else if (ended.recovery !== undefined) {
              entry.cleanupOwner = ended.recovery;
            } else {
              // Earlier captures settling proves nothing about an unknown
              // current acquisition that handed back no physical owner.
              entry.unresolvedCleanup = true;
            }
            throw error;
          } finally {
            if (measured !== undefined) observation.emit('source', 'acquisition_interval',
              {ref: accepted.ref, task: source.occurrence.task,
                outcome: returned ? 'confirmed' : 'failed'},
              {segment: 'source-acquisition', durationMs: performance.now() - measured});
          }
          captures.push(captured);
          await step('acquisition_completed', {ref: accepted.ref, task: source.occurrence.task,
            acquisition: captured.acquisition,
            resourceUsage: resourceUsage(ledger)});
          const evidenceOptions = {authorityScopeCid,
            effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
          await captured.prepareSourceEvidenceOriginal(evidenceOptions);
          const sourceEvidence = control.takeSourceEvidenceOriginal(captured.capture);
          sources.push({...source, captured, sourceEvidence,
            ...(inferring ? {sourceEvidenceWire: sourceEvidence.wire} : {})});
        }
        const captureCompletedAt = now();
        const effectiveDataPolicyCid = moon.clientProgramPublicationDataPolicyCid(preparedProgram);
        if (effectiveDataPolicyCid === undefined) throw new Error('InstalledMultiSourcePolicyUnavailable');
        if (inferring) {
          acquiredInfer = {sources, ledger, managedRun: held.managedRun, captureStartedAt, captureCompletedAt,
            sourceEvidence: sources.map(source => source.sourceEvidence)};
        } else {
        held.plan = acquiredMultiTaskPublicationPlan({moon, control, acquired: held.plan,
          preparedProgram, sources, authorityScopeCid, effectiveDataPolicyCid,
          captureStartedAt, captureCompletedAt, namespaceId, storeAuthorityCid, now});
        if (held.managedRun !== undefined) {
          retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
          if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
            throw new Error('InstalledManagedComputeHostUnavailable');
          }
          setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
            held.managedRun, preparedProgram, requested, captures.map(value => value.capture.source())));
        } else {
          const open = retainedRelationOutput
            ? moon.clientProgramOpenMultiCapturedLocalRetainedHost
            : moon.clientProgramOpenMultiCapturedLocalHost;
          setup = open(preparedProgram,
            captures.map(value => value.capture.source()), ledger, registry, values, fragment, ordered);
        }
        if (setup === undefined) throw new Error('InstalledMultiSourceHostUnavailable');
        entry.pendingSetup = setup;
        const dag = moon.strategyHostRun(setup);
        for (const [task, captured] of captures.entries()) captured.capture.retainTask(dag, task);
        }
      } else if (acquiring) {
        if (held.preparedSourceAccess !== sourceAccess) {
          held.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess);
          held.preparedSourceAccess = sourceAccess;
        }
        const {captureStartedAt, captureCompletedAt, sourceEvidence, sourceEvidenceWire} =
          await acquireSource(entry, preparedProgram, held.preparedSource, sourceAccess,
            {captureOnly: generatingContent || requestModelAcquired, originalEvidence: singleAccounted || inferring && !generatingContent,
              ledger: generatingContent || singleAccounted || requestModelAcquired ? ledger : undefined,
              occurrence: inferring ? runInfer.sourceOccurrence?.(preparedProgram, 0) : undefined});
        if (generatingContent) {
          acquiredContent = {captured: entry.sourceCapture, ledger, sourceEvidenceWire,
            authorityScopeCid, captureStartedAt, captureCompletedAt,
            sourceEvidence: control.admitRunEvidence('source_evidence', sourceEvidenceWire,
              {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
        } else if (inferring) {
          const captured = entry.sourceCapture;
          const input = requestModelAcquired || captured.composedInfer ? undefined : control.admitInferCapturedInput(
            preparedProgram, captured, sourceEvidence, authorityScopeCid,
            captured.checkedSource.sourceDataPolicyCid, captureStartedAt, captureCompletedAt);
          acquiredInfer = {input, captured, preparedSource: held.preparedSource, sourceAccess,
            occurrence: runInfer.sourceOccurrence?.(preparedProgram, 0),
            ...(requestModelAcquired ? {ledger, managedRun: held.managedRun} : {}),
            sourceEvidenceWire: sourceEvidence.wire, captureStartedAt, captureCompletedAt, sourceEvidence};
        } else {
          held.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held.plan, preparedProgram,
          captured: entry.sourceCapture, sourceEvidence,
          authorityScopeCid,
          effectiveDataPolicyCid: moon.clientProgramPublicationDataPolicyCid(preparedProgram),
          captureStartedAt, captureCompletedAt, namespaceId,
          requestId: submission.requestId, storeAuthorityCid, now});
        }
        if (singleAccounted) {
          // Reuse the existing borrowed-input cleanup order: stop Compute,
          // close its original physical input, then reclaim DAG outputs.
          entry.borrowedSources = true;
          const capture = entry.sourceCapture.capture;
          if (held.managedRun !== undefined) {
            retainDispatchPreparationHost(entry, moon, held.managedRun, preparedProgram, requested, preparationLease !== undefined);
            if (typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
              throw new Error('InstalledManagedComputeHostUnavailable');
            }
            setup = checked(moon.clientProgramOpenInstalledManagedCaptureHost(
              held.managedRun, preparedProgram, requested, [capture.source()]));
          } else {
            setup = moon.clientProgramOpenSingleCapturedLocalHost(preparedProgram,
              capture.source(), ledger, registry, values, fragment, ordered, retainedRelationOutput);
          }
          if (setup === undefined) throw new Error('InstalledSingleSourceHostUnavailable');
          // Retain before binding the borrow: a failed binding still leaves
          // this same Compute owner in child-first cleanup custody.
          entry.pendingSetup = setup;
          capture.retainTask(moon.strategyHostRun(setup), 0);
        } else setup = entry.sourceCapture.setup;
      }
      entry.abort.signal.throwIfAborted();
      entry.physicalWorkMayHaveStarted = true;
      entry.computeStartAttempted = true;
      if (serializing) {
        await runContent({preparedProgram, plan: held.plan, store,
          principalId: actual, signal: entry.abort.signal, acquiredContent,
          retainExecution(execution) {
            if (entry.cleanupOwner !== undefined && entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        // A byte writer or private capture alone is not a public Result. The
        // same committed Store index and physical-close owner govern success.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledContentPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      if (inferring) {
        const result = await runInfer({preparedProgram, plan: held.plan, store,
          preparationHolder: entry.preparationHostBorrow,
          acquiredInfer, acquiredContent,
          ...(acquiredInfer?.sources === undefined ? {} : {
            originalPreparation: sourceProfile.modelPreparation(preparedProgram, held.plan)}),
          submission: Object.fromEntries(['requestId', 'principalId', 'connection',
            'kind', 'input', 'parameters'].filter(key => Object.hasOwn(submission, key))
            .map(key => [key, submission[key]])),
          principalId: actual, signal: entry.abort.signal,
          retainExecution(execution) {
            if (entry.cleanupOwner !== undefined &&
                entry.cleanupOwner !== execution) {
              throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
            }
            if (typeof execution?.close !== 'function' ||
                typeof execution?.cleanup !== 'function' ||
                typeof execution?.cleanupPending !== 'function') {
              throw new TypeError('ClientDispatchCleanupOwnerInvalid');
            }
            entry.cleanupOwner = execution;
          }});
        if (result?.status === 'waiting_checkpoint') {
          const checkpoint = checkpoints?.journal.inspect(result.checkpoint?.checkpointCid);
          if (entry.cleanupOwner === undefined || checkpoint?.kind !== 'model_invocation' ||
              checkpoint.prepareAttemptId !== null ||
              checkpoint.runDefinitionCid !== accepted.ref.runDefinitionCid ||
              checkpoint.runId !== control.runDefinitionRunId(accepted.runDefinition)) {
            throw new Error('InstalledInferWaitingNotCommitted');
          }
          // The fixed input and continuation have reached durable custody.
          // Stopping this physical owner is not a failed or cancelled Run;
          // the Checkpoint lifecycle remains authoritative for its next step.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_waiting_checkpoint', {ref: accepted.ref,
            checkpointCid: checkpoint.checkpointCid});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        if (result?.status === 'needs_reconciliation') {
          const runId = control.runDefinitionRunId(accepted.runDefinition);
          if (entry.cleanupOwner === undefined ||
              checkpoints?.journal.hasUnresolvedModelCalls(runId) !== true) {
            throw new Error('InstalledInferUnknownNotRecorded');
          }
          // The owner made all permitted progress and retained an entered
          // call without a saved response. Physical stop is not an ordinary
          // failure and cannot turn that call into a completed barrier.
          entry.observeStopped = () => recordNodeRunPhysicalStop({ref: entry.ref,
            journal, moon, control}, null);
          await step('infer_needs_reconciliation', {ref: accepted.ref});
          await settleCleanup(entry);
          await finishRun(entry);
          return;
        }
        // Success is the existing Store's committed index, not merely a
        // returned model value or a completed private capture.
        if (entry.cleanupOwner === undefined ||
            await store.confirmCommittedIndex(entry.ref) === undefined) {
          throw new Error('InstalledInferPublicationIncomplete');
        }
        entry.publicationCommitted = true;
        await step('computed', {ref: accepted.ref});
        await settleCleanup(entry);
        await finishRun(entry);
        return;
      }
      const published = await runPublished(setup,
        {store, plan: held.plan},
        { ...computeConfigurations,
          ...(sourceAccess === undefined ? {} :
            {authorization: sourceAccess.authorization}) },
        entry.abort.signal, undefined, owner => {
          // One synchronous transfer consumes this exact pending setup before
          // either the preflight or completed-execution owner may close it.
          if (entry.cleanupOwner !== undefined ||
              entry.pendingSetup !== undefined && entry.pendingSetup !== setup) {
            throw new Error('ClientDispatchCleanupOwnerAlreadyRetained');
          }
          entry.cleanupOwner = owner;
          entry.pendingSetup = undefined;
        }, observation === undefined ? undefined : installTaskObservation(({event, task, durationMs}) =>
          observation.emit('compute', event, {ref: accepted.ref, task}, {durationMs})), entry.preparationHostBorrow,
        entry.preparationHostBorrow === undefined ? undefined : () => {
          if (typeof beforePublication !== 'function') throw new Error('PreparationPublicationUnavailable');
          return beforePublication(preparedProgram);
        });
      entry.cleanupOwner = published;
      entry.publicationCommitted = true;
      await step('computed', {ref: accepted.ref,
        outputRepresentations: (published.execution?.completed ?? [])
          .map(task => ({task:task.task,
            representation:task.outputRepresentation})),
        carrierSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.snapshot !== undefined)
          .map(task => ({task:task.task,...task.snapshot})),
        relationSnapshots: (published.execution?.completed ?? [])
          .filter(task => task.relationSnapshot !== undefined)
          .map(task => ({task:task.task,...task.relationSnapshot}))});
      await settleCleanup(entry);
      await finishRun(entry);
    }).catch(async cause => {
      entry.primaryFailure = cause;
      try {
        const primaryFailure = cause instanceof CapturedRunPublicationError
          ? cause.primaryFailure : cause;
        diagnostic('dispatch_failed', {ref: accepted.ref,
          code: cause?.code ?? cause?.message ?? 'ClientDispatchFailed',
          primaryCode: primaryFailure?.code,
          issueTag: runtimeTag(primaryFailure?.cause),
          nestedIssueTag: runtimeTag(runtimeOptionalField(primaryFailure?.cause, 0))});
      } catch { /* Optional diagnostics cannot interrupt cleanup. */ }
      const failedExecution = cause instanceof CapturedRunPublicationError
        ? cause.execution : undefined;
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (failedExecution === undefined && entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      if (entry.reserved && !entry.physicalStartClaimAttempted &&
          !entry.abort.signal.aborted) {
        entry.failureObservationPending = true;
      }
      if (failedExecution !== undefined) entry.cleanupOwner = failedExecution;
      if (entry.physicalStarted && entry.cleanupOwner !== undefined) {
        entry.stopObservationPending = true;
      }
      try { await settleCleanup(entry); }
      catch (cleanupFailure) { entry.cleanupFailure = cleanupFailure; }
      try { await finishRun(entry); }
      catch (failure) { entry.finishFailure = failure; }
    }).finally(() => {
      entry.settled = true;
      reached('not_started');
      try { releaseAcquisition(entry); }
      catch (failure) { entry.releaseFailure = failure; }
      retire(entry);
    });
    // Retain only the originating optional observation, not a new operation
    // or a release receipt. The physical-start barrier remains independent.
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return physical;
  };

  // The installed Effect Run owner supplies the already-admitted operation.
  // This is the same physical supervisor as ordinary dispatch, not another
  // Run-start or Effect retry engine. It never invokes run again during drain.
  // The callback must transfer cleanup custody before any fallible operation
  // that can retain resources. Its common Run observer records the stop
  // independently from waiting, failed, unknown or published outcome.
  const track = (ref, {run, observeStopped,
    barrierFailureOutcome = null}) => {
    if (typeof ref?.runDefinitionCid !== 'string' ||
        typeof run !== 'function' || typeof observeStopped !== 'function') {
      throw new TypeError('InvalidClientOwnedDispatch');
    }
    const existing = current(ref);
    if (existing !== undefined) return existing.promise;
    const entry = {ref: Object.freeze({...ref}), settled: false,
      abort: new AbortController(), observeStopped,
      // The original Run-start claim does not prove that this continuation
      // began physical work. The installed Site marks that boundary itself.
      physicalStarted: false, physicalWorkMayHaveStarted: false,
      stopObserved: false, stopObservationPending: false,
      cleanupOwner: undefined, cleanupHandle: undefined,
      unresolvedCleanup: false, runInvoked: false};
    entries.set(keyOf(ref), entry);
    entry.promise = Promise.resolve().then(async () => {
      if (beforeDispatch !== undefined) await beforeDispatch(ref);
      entry.abort.signal.throwIfAborted();
      entry.runInvoked = true;
      return run(Object.freeze({
      signal: entry.abort.signal,
      acquireSource({preparedProgram, preparedSource, sourceAccess}) {
        return acquireSource(entry, preparedProgram, preparedSource, sourceAccess, {originalEvidence: true});
      },
      beginPhysicalWork() {
        entry.physicalStarted = true;
        entry.physicalWorkMayHaveStarted = true;
      },
      observePreEffectFailure() {
        // Only the installed opening boundary can assert this: acquisition
        // or Compute failed before the Effect adapter was invoked. This is
        // an outcome observation, not a physical stop or cleanup exemption.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : 'failed';
      },
      retainExecution(execution) {
        if (entry.cleanupOwner !== undefined &&
            entry.cleanupOwner !== execution) {
          throw new TypeError('ClientDispatchCleanupOwnerAlreadyRetained');
        }
        if (typeof execution?.close !== 'function' ||
            typeof execution?.cleanup !== 'function' ||
            typeof execution?.cleanupPending !== 'function') {
          throw new TypeError('ClientDispatchCleanupOwnerInvalid');
        }
        entry.cleanupOwner = execution;
      },
      }));
    }).then(async result => {
      // A trusted installed Site may confirm that a pre-Preview refusal
      // performed no external Effect dispatch. Record that observation only
      // after its physical owner has stopped and cleanup has completed.
      if (result?.status === 'failed_without_effect_dispatch' ||
          result?.status === 'failed_effect_set') {
        entry.terminalOutcome = 'failed';
      }
      await settleCleanup(entry);
      return result;
    }).catch(async cause => {
      entry.primaryFailure = cause;
      if (!entry.runInvoked) {
        // A refused execution barrier ran no Site callback. This is a
        // positive no-start observation, not an inferred physical stop.
        entry.terminalOutcome = entry.abort.signal.aborted
          ? 'cancelled' : barrierFailureOutcome;
        entry.stopObservationPending = true;
      }
      if (cause?.cleanupPending === true) {
        if (typeof cause.cleanupHandle?.status === 'function' &&
            typeof cause.cleanupHandle?.retry === 'function') {
          entry.cleanupHandle = cause.cleanupHandle;
        } else if (entry.cleanupOwner === undefined) {
          entry.unresolvedCleanup = true;
        }
      }
      try { await settleCleanup(entry); }
      catch (failure) { entry.cleanupFailure = failure; }
      throw cause;
    }).finally(() => {
      entry.settled = true;
      retire(entry);
    });
    // submit returns its durable RunRef before the owned operation settles.
    // Observation remains available through operation(), without an unhandled
    // rejection when a Client disconnects or never calls wait().
    entry.promise.catch(() => {});
    try {observation?.retainOperation?.(entry.promise);} catch { /* Optional metadata. */ }
    return entry.promise;
  };

  const drain = async () => {
    for (;;) {
      const running = [...entries.values()].filter(entry => !entry.settled);
      if (running.length === 0) break;
      await Promise.allSettled(running.map(entry => entry.promise));
    }
    for (const entry of [...entries.values()]) {
      try {
        await settleCleanup(entry);
        await finishRun(entry);
        releaseAcquisition(entry);
      }
      catch (failure) { entry.cleanupFailure = failure; }
      retire(entry);
    }
    if (entries.size > 0) {
      throw Object.assign(new Error('ClientDispatchCleanupPending'), {
        code: 'ClientDispatchCleanupPending',
        pendingRefs: [...entries.values()].map(entry => entry.ref),
        failures: [...entries.values()].map(entry => ({ref: entry.ref,
          primary: dispatchFailureSnapshot(entry.primaryFailure),
          close: dispatchFailureSnapshot(entry.closeFailure),
          cleanup: dispatchFailureSnapshot(entry.cleanupFailure),
          finish: dispatchFailureSnapshot(entry.finishFailure),
          release: dispatchFailureSnapshot(entry.releaseFailure),
          preparation: dispatchFailureSnapshot(entry.preparationRetirementFailure)})),
      });
    }
  };
  return Object.freeze({start, track, cancel, live, operation, drain});
}

import {dispatchFailureSnapshot, dispatchFailureCodeSite, publicBudgetFailureMessage} from './client-dispatch-diagnostic.mjs';
// One installed Host owner for an admitted Run's physical dispatch, stop
// observation, and recoverable cleanup. The journal and MoonBit control keep
// their existing authority; this owner does not decide whether to retry.
import {types as nodeTypes} from 'node:util';
import {runtimeField, runtimeOptionalField, runtimeTag} from '../host-common/compiler-binding.generated.mjs';
import {CapturedRunPublicationError,
  runPublishedCapturedStrategy} from './entry.mjs';
import {acquiredTaskPublicationPlan, acquiredMultiTaskPublicationPlan,
  sourceFreePlanExecutionOwner} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
import {ordinarySourceDescriptors, verifyOrdinarySourceBinding} from './ordinary-source-binding.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installTaskObservation} from '../host-common/task-observation.mjs';
import {prepareInstalledLogicalObservation} from './logical-task-observation.mjs';
import {bindClientSourceOperation} from './client-source-operation.mjs';
import {ledgerUsageDiagnostic} from '../host-common/runtime-core.mjs';
import {isModelCredentialRefusal} from './infer-operation.mjs';
import {createClientDispatchCleanup, releaseDispatchPreparationHost, retainDispatchPreparationHost}
  from './client-dispatch-cleanup.mjs';
import {createClientDispatchTracking} from './client-dispatch-tracking.mjs';
import {createClientDispatchKeyedAcquisition, createClientDispatchSourceAcquisition} from './client-dispatch-source-acquisition.mjs';
import {confirmNodeRunCancellation, observeNodeRunStop, recordNodeRunPhysicalStop}
  from './client-dispatch-stop.mjs';
export {cancelNodeRunContinuation, confirmNodeRunCancellation, observeNodeRestoredLocalStop,
  observeNodeRestoredModelStop, observeNodeRunCancellation, recordNodeRunPhysicalStop}
  from './client-dispatch-stop.mjs';


// Diagnostics must not become a second owner of execution/cleanup capabilities.
// Read only inert own data, including one existing primaryFailure diagnostic
// slot. Accessors and error/cause chains are not invoked or traversed, and the
// returned receipt retains no thrown object or cleanup capability.
const dispatchFailureFields = Object.freeze(['primaryFailure', 'closeFailure',
  'cleanupFailure', 'finishFailure', 'releaseFailure', 'preparationRetirementFailure']);


// This message extends the existing failed Run observation, not its status,
// authority or cleanup evidence. Never format arbitrary exception text.


// Only diagnostic custody moves here. An Unknown result keeps its outcome,
// physical owner and current gates; a later cleanup refusal is not its cause.
function retainDispatchPrimaryFailure(entry, result) {
  try {
    const primary = Object.getOwnPropertyDescriptor(result, 'primaryFailure');
    if (!Object.hasOwn(entry, 'primaryFailure') &&
        primary !== undefined && Object.hasOwn(primary, 'value')) {
      entry.primaryFailure = primary.value;
    }
  } catch { /* Optional failure DATA cannot interrupt the original cleanup. */ }
}

export function installNodeClientDispatchOwner({moon, control, journal,
  store, checkpoints, startRun, hostConnection, beforeDispatch, observed,
  prepareAcquisition, planFor, sourceProfile, registry, values, fragment,
  ordered, namespaceId, authorityScopeCid, storeAuthorityCid, now,
  faultInjection, runInfer, runContent, computeConfigurations = {},
  observation, preparationCustody, beforePublication, authorizeLogicalObservation,
  managedComputeRequired = false,
  retainedRelationOutput = false,
  runPublished = runPublishedCapturedStrategy}) {
  const entries = new Map();
  const capturedRun = moon?.strategyHostRun;
  const diagnostic = diagnosticObserver(observed);
  const diagnosticErrorType = Error;
  const diagnosticStackFormatter = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace')?.value;
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
  const credentialRefusalPending = ref => {
    const entry = current(ref);
    return entry?.requestId !== undefined && entry.settled &&
      entry.ref.namespaceId === ref.namespaceId && entry.ref.authorityScopeCid === ref.authorityScopeCid &&
      !entry.stopObserved && isModelCredentialRefusal(entry.primaryFailure);
  };
  const failureMessage = ref => {
    const entry = current(ref);
    return entry === undefined ? undefined : publicBudgetFailureMessage(
      entry.primaryFailure, control?.executionFailureExplanation);
  };

  const acquireSource = createClientDispatchSourceAcquisition({
    sourceProfile, now, step, observation, registry, values, fragment, ordered, store,
    journal, retainedRelationOutput, authorityScopeCid, control,
  });

  const acquireKeyedSources = createClientDispatchKeyedAcquisition({
    moon, control, runContent, store, registry, values, fragment, ordered,
    step, resourceUsage, now, authorityScopeCid, namespaceId, storeAuthorityCid, retainedRelationOutput,
  });

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

  const {retire, settleCleanup, finishRun, releaseAcquisition, settleRetainedEntry} = createClientDispatchCleanup({
    entries, keyOf, moon, journal, control, now, checkpoints, observation, observeStop,
    resourceUsage, diagnostic,
  });

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
        // A settled Run is not an observation-delivery ACK. The same original
        // Request stays owned while any queue/callback still holds its loan.
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.close();
          entry.logicalObservation = undefined;
        }
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
      // Request preparation can already own unentered Source reads. Keep
      // their original retirement ports before a start or authorization
      // refusal; started captures still complete their physical cleanup first.
      const preparedSources = held.preparedSources ?? (held.preparedSource === undefined ? [] : [{
        adapter: installedSourceFor(sourceProfile, held.preparedSource.checkedSource.sourceRef),
        prepared: held.preparedSource,
      }]);
      for (const source of preparedSources) {
        const retire = source.adapter.retirePreparedSource;
        if (retire === undefined) continue;
        if (typeof retire !== 'function') throw new TypeError('InstalledSourceCleanupUnavailable');
        entry.sourcePreparations ??= [];
        entry.sourcePreparations.push({source: source.adapter, prepared: source.prepared, retire});
      }
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
        held.plan = planFor(submission, accepted.runDefinition.wire, requested);
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
          await prepareAcquisition(preparedProgram, directAccess, directOccurrence,
            held.managedRun === undefined ? undefined : held.preparedSource);
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
          if (capacities.some(value => value.wholeInput === true)) {
            if (capacities.some(value => value.wholeInput !== true) ||
                typeof moon.clientProgramInstalledManagedWholeSourcesLedger !== 'function') {
              throw new Error('InstalledMultiSourceOriginalRunUnavailable');
            }
            ledger = checked(moon.clientProgramInstalledManagedWholeSourcesLedger(
              managedRun, preparedProgram, requested, capacities.map(value => value.capacity),
              capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes)));
          } else {
          ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(
            managedRun, preparedProgram, requested,
            capacities.map(value => value.capacity),
            capacities.map(value => value.transferBytes),
            capacities.map(value => value.executionBytes),
            registry, values, fragment, ordered));
          }
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
          held.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held.managedRun === undefined ? undefined : held.preparedSource);
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
          held.preparedSource = await prepareAcquisition(preparedProgram, access, undefined,
            held.managedRun === undefined ? undefined : held.preparedSource);
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
          if (!generatingContent && preparationLease !== undefined &&
              typeof capturedRun === 'function' && typeof authorizeLogicalObservation === 'function') {
            const logical = prepareInstalledLogicalObservation(moon, control,
              held.managedRun, sourceFreePlanExecutionOwner(held.plan), held.plan.runDefinition, observation);
            if (logical !== undefined) entry.logicalObservation = logical;
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
        if (entry.logicalObservation !== undefined) {
          entry.logicalObservation.attach(Reflect.apply(capturedRun, moon, [setup]),
            accepted.ref, actual, operation => authorizeLogicalObservation(operation, connection),
            control.runDefinitionRunId(accepted.runDefinition));
        }
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
          entry.abort.signal.throwIfAborted();
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
          publicationOriginal: held.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held.managedRun},
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
        for (const [slot, captured] of captures.entries()) {
          const occurrence = selectedSources[slot].occurrence;
          captured.capture.retainTask(dag, occurrence.computeTask ?? occurrence.task);
        }
        }
      } else if (acquiring) {
        if (held.preparedSourceAccess !== sourceAccess) {
          held.preparedSource = await prepareAcquisition(preparedProgram,
            sourceAccess, undefined, held.managedRun === undefined ? undefined : held.preparedSource);
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
          acquiredInfer = {input, captured, adapter: installedSource, preparedSource: held.preparedSource, sourceAccess,
            occurrence: runInfer.sourceOccurrence?.(preparedProgram, 0),
            ...(requestModelAcquired ? {ledger, managedRun: held.managedRun} : {}),
            sourceEvidenceWire: sourceEvidence.wire, captureStartedAt, captureCompletedAt, sourceEvidence};
        } else {
          held.plan = acquiredTaskPublicationPlan({moon, control,
          acquired: held.plan, preparedProgram,
          publicationOriginal: held.managedRun === undefined ? undefined
            : {kind: 'installed_run', value: held.managedRun},
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
          retainDispatchPrimaryFailure(entry, result);
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
          observation.emit('compute', event, {ref: accepted.ref, task}, {durationMs}),
          entry.logicalObservation === undefined ? undefined
            : (phase, task) => entry.logicalObservation.project(phase, task)), entry.preparationHostBorrow,
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
      if (!Object.hasOwn(entry, 'primaryFailure')) entry.primaryFailure = cause;
      try {
        const original = entry.primaryFailure;
        const primaryFailure = original instanceof CapturedRunPublicationError
          ? original.primaryFailure : original;
        const issue = primaryFailure?.cause;
        const issueTag = runtimeTag(issue);
        const nestedIssue = runtimeOptionalField(issue, 0);
        const nestedTag = runtimeTag(nestedIssue);
        const leafIssue = runtimeOptionalField(nestedIssue, 0);
        const leafTag = runtimeTag(leafIssue);
        diagnostic('dispatch_failed', {ref: accepted.ref,
          code: cause?.code ?? cause?.message ?? 'ClientDispatchFailed',
          primaryCode: primaryFailure?.code,
          primaryDiagnostic: dispatchFailureSnapshot(primaryFailure)?.primaryDiagnostic ??
            dispatchFailureCodeSite(primaryFailure, diagnosticErrorType, diagnosticStackFormatter),
          cleanupDiagnostic: dispatchFailureSnapshot(primaryFailure)?.cleanupDiagnostic,
          issueTag: issueTag === undefined && Number.isSafeInteger(issue) &&
            issue >= 0 && issue <= 65535 ? issue : issueTag,
          nestedIssueTag: nestedTag === undefined && Number.isSafeInteger(nestedIssue) &&
            nestedIssue >= 0 && nestedIssue <= 65535 ? nestedIssue : nestedTag,
          leafIssueTag: leafTag === undefined && Number.isSafeInteger(leafIssue) &&
            leafIssue >= 0 && leafIssue <= 65535 ? leafIssue
            : Number.isSafeInteger(leafTag) && leafTag >= 0 && leafTag <= 65535 ? leafTag : undefined});
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

  const {track, settleCredentialRefusal, drain} = createClientDispatchTracking({
    entries, keyOf, current, beforeDispatch, acquireSource, retainDispatchPrimaryFailure,
    settleCleanup, settleRetainedEntry, retire, credentialRefusalPending, diagnostic,
    diagnosticErrorType, diagnosticStackFormatter, observation,
  });
  return Object.freeze({start, track, cancel, live, operation, failureMessage, drain,
    credentialRefusalPending, settleCredentialRefusal});
}

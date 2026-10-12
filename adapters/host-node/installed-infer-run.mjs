// Installed physical composition of the checked Infer, original per-call
// journal/custody and publication owners. No JS slot scheduler is introduced.
import {projectInferEvidence} from './infer-evaluation-evidence.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';
import {createInferIoNotification} from './infer-io-notification.mjs';

export function installNodeInferRun({moon, core, registry, values, fragment, ordered, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection, modelController, inferEvidence,
  checkpoints, prepareAcquisition, sourceAccessFor,
  computeConfigurations = {}}) {
  const control = core.publicationControl;
  return async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, acquiredInfer, replay = false, beginPhysicalWork = () => {},
    submission, existingModel, modelClaim, assertCurrent, originalPreparation}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    // Installation-only original custody. Public request data and restored
    // inputs cannot mint a fresh read or replace its original scope/Ledger.
    if (originalPreparation !== undefined &&
        (originalPreparation === null || typeof originalPreparation !== 'object' ||
          originalPreparation.control !== control ||
          originalPreparation.compiled !== plan.compiled ||
          originalPreparation.runDefinition !== plan.runDefinition ||
          originalPreparation.scope === undefined || originalPreparation.read === undefined ||
          !Object.hasOwn(originalPreparation, 'nodeInstallation') ||
          ['close', 'cleanup', 'cleanupPending'].some(name =>
            typeof originalPreparation.physicalCustody?.[name] !== 'function') ||
          ['stopCheckedClientInferOriginalReadPreparation',
            'settleCheckedClientInferOriginalReadPreparation',
            'finishCheckedClientInferOriginalReadScope'].some(name =>
            typeof control[name] !== 'function') ||
          acquiredInfer !== undefined || replay || selected.components !== undefined)) {
      throw new TypeError('InvalidInstalledInferOriginalPreparation');
    }
    if (selected.components !== undefined) {
      return runInstalledComposedInfers({moon, control, preparedProgram, plan, selected,
        store, principalId, signal, retainExecution, acquiredInfer, replay,
        beginPhysicalWork, submission, existingModel, modelClaim, assertCurrent,
        modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor,
        namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
        registry, values, fragment, ordered, computeConfigurations});
    }
    if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
    const runId = JSON.parse(plan.runDefinition.wire).run_id;
    const taskIndex = moon.clientProgramInferPlanBoundary(selected.graph)._0;
    existingModel ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
    if (replay && existingModel === undefined) throw new Error('InstalledInferOriginalInventoryMissing');
    if (originalPreparation !== undefined && existingModel !== undefined) {
      throw new TypeError('RestoredInferOriginalPreparationUnavailable');
    }
    const token = existingModel === undefined ? undefined : await modelController.prime(existingModel);
    let restoredInput, sources;
    try {
      restoredInput = token === undefined ? undefined : {token, snapshot: token.snapshot,
        sendMask: modelController.state(existingModel.inventory).slots.map(slot => slot.state === 'Unsent'),
        savedScope: modelController.savedScope(plan, preparedProgram, selected, token)};
      sources = restoredInput === undefined
        ? acquiredInfer === undefined ? [] : [acquiredInfer.sourceEvidence]
        : JSON.parse(token.snapshot.callScopeSnapshotWire).sources.map(source =>
          control.admitRunEvidence('source_evidence', source.source_evidence_wire,
            {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}));
    } catch (error) { modelController.release(token); throw error; }
    let operation, captureOwner, continuation, evidenceCopy;
    let captureCloseAttempted = false, captureReleased = false;
    let continuationCloseAttempted = false, continuationReleased = false;
    // These are phases of the same existing retained custody, not another
    // cleanup Owner. A failed physical close keeps this exact original record.
    let originalReadStopped = false, originalReadCloseAttempted = false;
    let originalReadPhysicalReleased = originalPreparation === undefined;
    let originalReadSettled = originalPreparation === undefined;
    let originalScopeReleased = originalPreparation === undefined;
    let originalCleanupFlight;
    const cleanupPending = () => evidenceCopy?.cleanupPending() === true || !captureReleased ||
      continuation !== undefined && !continuationReleased || !originalReadSettled ||
      !originalScopeReleased;
    const cleanupOwned = async () => {
      // Optional projection is a child of this already-retained INFER custody.
      // Keep its originals alive until the copy handoff and release settle.
      if (evidenceCopy !== undefined) {
        if (await evidenceCopy.cleanup() === false || evidenceCopy.cleanupPending()) return false;
        evidenceCopy = undefined;
      }
      let failure;
      if (!captureReleased) {
        const recover = captureCloseAttempted;
        captureCloseAttempted = true;
        try {
          const child = captureOwner?.custody ?? operation;
          const result = child === undefined ? true : await (recover ? child.cleanup() : child.close());
          captureReleased = result !== false && (child === undefined || child.cleanupPending() === false);
        } catch (error) { failure = error; }
      }
      if (continuation !== undefined && !continuationReleased) {
        const recover = continuationCloseAttempted;
        continuationCloseAttempted = true;
        try {
          const result = await (recover ? continuation.cleanup() : continuation.close());
          continuationReleased = result !== false && continuation.cleanupPending() === false;
        } catch (error) { failure ??= error; }
      }
      if (captureReleased && continuation === undefined) modelController.release(token);
      if (failure !== undefined) throw failure;
      if (originalPreparation !== undefined && captureReleased &&
          (continuation === undefined || continuationReleased)) {
        if (!originalReadStopped) {
          control.stopCheckedClientInferOriginalReadPreparation(plan.compiled,
            plan.runDefinition, selected.graph, originalPreparation.scope,
            originalPreparation.read);
          originalReadStopped = true;
        }
        if (!originalReadPhysicalReleased) {
          const child = originalPreparation.physicalCustody;
          const recover = originalReadCloseAttempted;
          originalReadCloseAttempted = true;
          const result = await (recover ? child.cleanup() : child.close());
          originalReadPhysicalReleased = result !== false && child.cleanupPending() === false;
          if (!originalReadPhysicalReleased) return false;
        }
        if (!originalReadSettled) {
          control.settleCheckedClientInferOriginalReadPreparation(plan.compiled,
            plan.runDefinition, selected.graph, originalPreparation.read, true);
          originalReadSettled = true;
        }
        // All actual children of this fresh single-component custody have
        // acknowledged cleanup. The original Core census still refuses any
        // other live child; read settlement alone cannot release bootstrap.
        originalScopeReleased = control.finishCheckedClientInferOriginalReadScope(
          plan.compiled, plan.runDefinition, selected.graph,
          originalPreparation.scope, true) === true;
        if (originalScopeReleased) originalPreparation = undefined;
      }
      return !cleanupPending();
    };
    const cleanup = () => {
      // An original cleanup flight belongs to this same retained custody.
      // Concurrent close/retry callers must not overlap physical close or
      // settle its read twice. The former route is otherwise unchanged.
      if (originalReadStopped && originalScopeReleased) return originalCleanupFlight;
      if (originalPreparation === undefined) return cleanupOwned();
      if (originalCleanupFlight === undefined) {
        originalCleanupFlight = cleanupOwned();
        originalCleanupFlight.then(complete => {
          if (complete !== true) originalCleanupFlight = undefined;
        }, () => { originalCleanupFlight = undefined; });
      }
      return originalCleanupFlight;
    };
    const custody = Object.freeze({cleanupPending, cleanup, close: cleanup});
    try { retainExecution(custody); }
    catch (error) { modelController.release(token); throw error; }
    operation = openNodeInferOperation({moon, preparedProgram,
      step: selected.step, graph: selected.graph, registry, values, fragment, ordered, signal,
      acquiredInput: restoredInput === undefined ? acquiredInfer?.input : undefined,
      restoredInput, durableCalls: true, computeSuffix: selected.computeSuffix,
      observeProgress: () => faultInjection?.('infer_execution_advanced', {}),
      provider: selected.provider, quantityCapacity: selected.quantityCapacity,
      physicalPreflight: selected.physicalPreflight, egressAdmission: selected.egressAdmission,
      originalPreparation,
      ioNotification: selected.entryPersistence === 'async' ? createInferIoNotification() : undefined,
      retainOperation(value) { operation = value; }});
    captureOwner = openNodeInferCaptureCustody({moon, control, operation,
      plan, store, storeAuthorityCid, replay: false, durableCalls: true, faultInjection,
      sourceEvidence: sources,
      publicationFor: ({issuance, modelEvidence}) => inferTaskPublicationPlan({
        moon, control, preparedProgram, admitted: plan, operation, issuance,
        modelEvidence, namespaceId, sourceEvidence: sources,
        authorityScopeCid, storeAuthorityCid, now})});
    beginPhysicalWork();
    operation.bindRun(control, plan);
    const declaredResults = Array.from({length: moon.clientProgramResultCount(preparedProgram)},
      (_, index) => moon.clientProgramResultName(preparedProgram, index));
    async function settle(settlement) {
      const slot = operation.settlementSlot(settlement);
      const entry = continuation?.entry(slot);
      if (entry === undefined) throw new Error('InferSettlementEntryMissing');
      await captureOwner.persistSettlement(settlement, entry);
    }
    try {
      for (;;) {
        const boundary = await operation.run();
        if (boundary?.status === 'waiting') {
          if (continuation === undefined) {
            continuation = await modelController.open({operation, preparedCallSet: boundary.preparedCallSet,
              plan, selected, principalId, declaredResults, submission, signal,
              existing: existingModel, inputToken: token, claim: modelClaim});
            captureOwner.configureModelJournal({observe: continuation.observe, entry: continuation.entry});
            // Saved/unknown records first re-enter the same normal owner without
            // any fresh permission. A still-unsent slot yields Waiting again.
            if (existingModel !== undefined) continue;
          }
          const decision = await continuation.authorize();
          if (decision.status === 'waiting_checkpoint') return decision;
          continue;
        }
        if (boundary?.status === 'settling') { await settle(boundary.settlement); continue; }
        break;
      }
    } catch (error) {
      const settlement = operation.pendingSettlement();
      if (settlement !== undefined && continuation !== undefined) await settle(settlement);
      if (operation.physicalStopped()) await captureOwner.persistStoppedAttempts();
      if (modelController.unresolved(runId)) {
        return Object.freeze({status: 'needs_reconciliation'});
      }
      throw error;
    }
    captureOwner.retainCompleted();
    const publication = await captureOwner.persist();
    await faultInjection?.('infer_capture_committed', {});
    signal.throwIfAborted();
    const execution = inferPublicationExecution({moon, core, operation,
      binding: publication.binding, compiled: plan.compiled, preparedProgram});
    await publishCompletedEffectFreeRun({...publication.plan, execution, store, control, signal});
    await projectInferEvidence({configuration: inferEvidence, moon, control, preparedProgram,
      plan, selected, operation, captureOwner, continuation, authorityScopeCid,
      retainCopy(copy) {
        if (evidenceCopy !== undefined) throw new TypeError('InferEvidenceCopyAlreadyRetained');
        evidenceCopy = copy;
      }});
  };
}

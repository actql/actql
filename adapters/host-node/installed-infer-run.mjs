// Installed physical composition of the checked Infer, original per-call
// journal/custody and publication owners. No JS slot scheduler is introduced.
import {checked} from '../host-common/runtime-result.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';

export function installNodeInferRun({moon, core, registry, values, fragment, ordered, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection, modelController}) {
  const control = core.publicationControl;
  return async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, acquiredInfer, replay = false, beginPhysicalWork = () => {},
    submission, existingModel, modelClaim}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
    const runId = JSON.parse(plan.runDefinition.wire).run_id;
    const taskIndex = moon.clientProgramInferPlanBoundary(selected.graph)._0;
    existingModel ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
    if (replay && existingModel === undefined) throw new Error('InstalledInferOriginalInventoryMissing');
    const token = existingModel === undefined ? undefined : await modelController.prime(existingModel);
    const restoredInput = token === undefined ? undefined : {token, snapshot: token.snapshot,
      sendMask: modelController.state(existingModel.inventory).slots.map(slot => slot.state === 'Unsent'),
      savedScope: modelController.savedScope(plan, preparedProgram, selected, token)};
    const sources = restoredInput === undefined
      ? acquiredInfer === undefined ? [] : [acquiredInfer.sourceEvidence]
      : JSON.parse(token.snapshot.callScopeSnapshotWire).sources.map(source =>
        control.admitRunEvidence('source_evidence', source.source_evidence_wire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}));
    const operation = openNodeInferOperation({moon, preparedProgram,
      step: selected.step, graph: selected.graph, registry, values, fragment, ordered, signal,
      acquiredInput: restoredInput === undefined ? acquiredInfer?.input : undefined,
      restoredInput, durableCalls: true, computeSuffix: selected.computeSuffix,
      observeProgress: () => faultInjection?.('infer_execution_advanced', {}),
      provider: selected.provider, quantityCapacity: selected.quantityCapacity,
      physicalPreflight: selected.physicalPreflight, egressAdmission: selected.egressAdmission});
    const captureOwner = openNodeInferCaptureCustody({moon, control, operation,
      plan, store, storeAuthorityCid, replay: false, durableCalls: true, faultInjection,
      sourceEvidence: sources,
      publicationFor: ({issuance, modelEvidence}) => inferTaskPublicationPlan({
        moon, control, preparedProgram, admitted: plan, operation, issuance,
        modelEvidence, namespaceId, sourceEvidence: sources,
        authorityScopeCid, storeAuthorityCid, now})});
    let continuation;
    let captureCloseAttempted = false, captureReleased = false;
    let continuationCloseAttempted = false, continuationReleased = false;
    const cleanupPending = () => !captureReleased ||
      continuation !== undefined && !continuationReleased;
    const cleanup = async () => {
      let failure;
      if (!captureReleased) {
        const recover = captureCloseAttempted;
        captureCloseAttempted = true;
        try {
          const result = await (recover ? captureOwner.custody.cleanup() : captureOwner.custody.close());
          captureReleased = result !== false && captureOwner.custody.cleanupPending() === false;
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
      if (failure !== undefined) throw failure;
      return !cleanupPending();
    };
    const custody = Object.freeze({cleanupPending, cleanup, close: cleanup});
    retainExecution(custody);
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
              existing: existingModel, claim: modelClaim});
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
  };
}

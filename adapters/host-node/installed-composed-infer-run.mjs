// Assemble checked Model components into the existing Local task driver.
// Local owns scheduling; the original Model journal owns each physical send.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';
import {runCapturedStrategy} from './entry.mjs';
import {withLocalExecutionPauseHandler} from '../local-node/retained-store.mjs';
import {openNodeComposedInferProvider, startCompleteInferObservation} from './infer-operation.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {preparePrivatePublicationHolding} from '../host-common/private-publication-holding.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {projectInferEvidence} from './infer-evaluation-evidence.mjs';

export async function runInstalledComposedInfers({moon, control, preparedProgram, plan, selected,
  store, principalId, signal, retainExecution, acquiredInfer, replay, beginPhysicalWork,
  submission, modelController, inferEvidence, namespaceId, authorityScopeCid,
  storeAuthorityCid, now, faultInjection, registry, values, fragment, ordered, computeConfigurations}) {
  // Evidence restoration reads the user sink, never this fresh-send assembly.
  // A historical physical start must use its durable Model restoration owner.
  if (replay || modelController === undefined || acquiredInfer?.captured === undefined) {
    throw new Error('InstalledComposedInferInputUnavailable');
  }
  const runId = JSON.parse(plan.runDefinition.wire).run_id;
  if (modelController.discover(runId).length !== 0) {
    throw new Error('InstalledComposedInferOriginalInventoryRequiresRestore');
  }
  const {captured, sourceEvidenceWire, captureStartedAt, captureCompletedAt} = acquiredInfer;
  const sourceEvidence = [acquiredInfer.sourceEvidence];
  const children = selected.components.map(selection => ({selection}));
  let execution, pendingSetup, issuance, publication, holding;
  let issuanceComplete = false, closeAttempted = false, released = false;
  async function cleanup() {
    if (released) return true;
    // Installation can fail before the asynchronous driver returns an owner.
    // Retain that exact setup until its stopped outputs and reservations close.
    if (pendingSetup !== undefined) {
      moon.strategyHostStop(pendingSetup);
      moon.strategyHostCloseOutputs(pendingSetup);
      if (moon.strategyHostUsage(pendingSetup).slice(4).some(value => value !== 0n)) {
        return false;
      }
      pendingSetup = undefined;
    }
    // Copies must finish their handoff before original capture custody ends.
    for (const child of children) {
      if (child.copy !== undefined) {
        if (!await child.copy.cleanup() || child.copy.cleanupPending()) return false;
        child.copy = undefined;
      }
    }
    if (holding !== undefined) {await holding.commit(); holding = undefined;}
    if (publication !== undefined) {
      moon.clientProgramReleaseInferInvocationBinding(publication.binding);
      publication = undefined;
    }
    if (issuance !== undefined) {
      if (moon.clientProgramCancelInferObservationIssuance(issuance)) {
        checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1));
      }
      if (!checked(moon.clientProgramCleanupInferObservationIssuance(issuance))) return false;
      issuance = undefined;
    }
    let pending = false;
    for (const child of children) {
      if (child.capture !== undefined && !child.captureReleased) {
        const retry = child.captureCloseAttempted === true;
        child.captureCloseAttempted = true;
        const result = await (retry ? child.capture.custody.cleanup() : child.capture.custody.close());
        child.captureReleased = result !== false && !child.capture.custody.cleanupPending();
        pending ||= !child.captureReleased;
      }
      if (child.continuation !== undefined && !child.continuationReleased) {
        const retry = child.continuationCloseAttempted === true;
        child.continuationCloseAttempted = true;
        const result = await (retry ? child.continuation.cleanup() : child.continuation.close());
        child.continuationReleased = result !== false && !child.continuation.cleanupPending();
        pending ||= !child.continuationReleased;
      }
    }
    if (pending) return false;
    if (execution !== undefined) {
      if (!closeAttempted) {
        // The driver may retain its first rejected close Promise. Recovery uses
        // its cleanup handle rather than calling that close a second time.
        closeAttempted = true;
        if (await execution.close() === false) return false;
      }
      if (await execution.cleanup() === false || execution.cleanupPending()) return false;
    }
    released = true;
    return true;
  }
  retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !released}));
  const declaredResults = Array.from({length: moon.clientProgramResultCount(preparedProgram)},
    (_, index) => moon.clientProgramResultName(preparedProgram, index));
  for (const child of children) {
    const sources = checked(moon.clientProgramAdmitComposedInferSources(child.selection.occurrence,
      [captured.capture.source()], [captured.identity], [captured.requirement],
      [moon.strategyRunEvidenceJson(captured.logicalInput)], [sourceEvidenceWire], authorityScopeCid,
      captureStartedAt, captureCompletedAt));
    child.component = openNodeComposedInferProvider({moon, selected: child.selection, sources,
      control, plan, principalId, now, signal, durableCalls: true,
      retainOperation(operation) {
        child.operation = operation;
        child.capture = openNodeInferCaptureCustody({moon, control, operation, plan, store,
          storeAuthorityCid, sourceEvidence, faultInjection, durableCalls: true, captureOnly: true});
      }, retainCompleted: () => child.capture.retainCompleted()});
  }
  const setup = moon.clientProgramOpenCapturedComposedInferHost(preparedProgram,
    captured.capture.source(), registry, values, fragment, ordered,
    children.map(child => child.component.provider));
  if (setup === undefined) throw new Error('InstalledComposedInferHostUnavailable');
  pendingSetup = setup;
  // The existing single-Source dispatch owner retains this capture until
  // all Compute custody has settled. It is not a multi-capture ledger lease.
  const local = withLocalExecutionPauseHandler(computeConfigurations.local, async boundary => {
    const child = children.find(value => moon.clientProgramInferPlanBoundary(value.selection.graph)._0 === boundary.task);
    if (child?.operation === undefined || child.capture === undefined) throw new Error('ModelPauseOwnerMissing');
    if (boundary.status === 'settling') {
      const settlement = child.operation.pendingSettlement();
      const slot = child.operation.settlementSlot(settlement);
      const entry = child.continuation?.entry(slot);
      if (entry === undefined || slot !== boundary.slot) throw new Error('ModelPauseSettlementMismatch');
      await child.capture.persistSettlement(settlement, entry);
      return {action: 'resume'};
    }
    if (boundary.status !== 'waiting') throw new Error('InvalidModelPause');
    if (child.continuation === undefined) {
      const preparedCallSet = child.operation.preparedCallSet();
      if (preparedCallSet === undefined) throw new Error('ModelPausePreparedOwnerMissing');
      child.continuation = await modelController.open({operation: child.operation, preparedCallSet,
        plan, selected: child.selection, principalId, declaredResults, submission, signal});
      child.capture.configureModelJournal({observe: child.continuation.observe, entry: child.continuation.entry});
    }
    const decision = await child.continuation.authorize();
    if (decision.status === 'dispatch') return {action: 'resume'};
    if (decision.status !== 'waiting_checkpoint') throw new Error('InvalidModelPauseDecision');
    return {action: 'waiting_checkpoint', checkpoint: decision.checkpoint,
      cleanupPending: true, cleanupHandle: {status: () => ({pending: !released}), retry: cleanup}};
  });
  beginPhysicalWork();
  execution = await runCapturedStrategy(setup, {...computeConfigurations, local}, signal);
  pendingSetup = undefined;
  if (execution.status === 'host-tasks-waiting') {
    return Object.freeze({status: 'waiting_checkpoint', checkpoint: execution.checkpoint});
  }
  if (execution.status !== 'host-tasks-completed') {
    for (const child of children) {
      if (child.operation?.physicalStopped()) await child.capture.persistStoppedAttempts();
    }
    if (modelController.unresolved(runId)) return Object.freeze({status: 'needs_reconciliation'});
    throw children.find(child => child.component.failure() !== undefined)?.component.failure() ??
      execution.failure ?? new Error('InstalledComposedInferComputationFailed');
  }
  for (const child of children) await child.capture.persist();
  const calls = children.reduce((sum, child) => sum + child.capture.evaluationBundle().count, 0);
  issuance = startCompleteInferObservation({moon, operations: children.map(child => child.operation),
    ledger: checked(moon.clientProgramInferPublicationLedger(262144n + BigInt(calls * 128 + (children.length - 1) * 256), calls + 2)),
    maxSlots: calls, maxWireBytes: 16384, maxWork: calls + 2});
  while (!issuanceComplete) {
    issuanceComplete = checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1))._0;
    if (!issuanceComplete) await yieldEventLoop();
  }
  publication = inferTaskPublicationPlan({moon, control, preparedProgram, admitted: plan,
    operation: children[0].operation, issuance,
    modelEvidence: children.flatMap(child => child.capture.modelEvidence()), sourceEvidence,
    authorityScopeCid, namespaceId, storeAuthorityCid, now});
  for (const original of [publication.observation, publication.invocation]) {
    holding = preparePrivatePublicationHolding(store, {name: original.name, wire: original.wire,
      semanticCid: original.identity,
      holdingCid: control.modelPrivateHoldingCid(plan.runDefinition, storeAuthorityCid, original.name, -1)});
    await holding.commit(); holding = undefined;
  }
  signal.throwIfAborted();
  await publishCompletedEffectFreeRun({...publication.plan, execution, store, control, signal});
  for (const child of children) {
    await projectInferEvidence({configuration: inferEvidence, moon, control, preparedProgram, plan,
      selected: child.selection, operation: child.operation, captureOwner: child.capture,
      continuation: child.continuation, authorityScopeCid,
      retainCopy(copy) {if (child.copy !== undefined) throw new Error('InferEvidenceCopyAlreadyRetained'); child.copy = copy;}});
  }
}

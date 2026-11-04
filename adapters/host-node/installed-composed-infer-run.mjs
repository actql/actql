// Assemble checked Model components into the existing Local task driver.
// Local owns scheduling; the original Model journal owns each physical send.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
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
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {ledgerUsageHasPendingResources} from '../host-common/runtime-core.mjs';

export async function runInstalledComposedInfers({moon, control, preparedProgram, plan, selected,
  store, principalId, signal, retainExecution, acquiredInfer, replay, beginPhysicalWork,
  submission, existingModel, modelClaim, assertCurrent = () => {},
  modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor, namespaceId, authorityScopeCid,
  storeAuthorityCid, now, faultInjection, registry, values, fragment, ordered, computeConfigurations,
  originalPreparation}) {
  if (modelController === undefined) {
    throw new Error('InstalledComposedInferInputUnavailable');
  }
  const runId = JSON.parse(plan.runDefinition.wire).run_id;
  const records = modelController.discover(runId);
  if (replay && records.length === 0 || existingModel !== undefined &&
      !records.some(record => record.inventory.scopeCid === existingModel.inventory.scopeCid)) {
    throw new Error('InstalledComposedInferOriginalInventoryMissing');
  }
  const multiple = acquiredInfer?.sources?.length === 2;
  const originalComponents = originalPreparation?.components;
  const completeOriginal = Array.isArray(originalComponents) && originalComponents.length === selected.components.length &&
    originalComponents.every((original, index) => original.selection === selected.components[index]);
  const sourceFree = originalPreparation !== undefined && acquiredInfer === undefined &&
    (completeOriginal || selected.components.length === 1 &&
      (selected.components[0].localMock === true || originalPreparation.selection === selected.components[0])) &&
    typeof originalPreparation.openSourceFreeHost === 'function' &&
    moon.clientProgramAcquisitionCount(preparedProgram) === 0;
  if (records.length === 0 && acquiredInfer?.captured === undefined && !multiple && !sourceFree) {
    throw new Error('InstalledComposedInferInputUnavailable');
  }
  const children = selected.components.map(selection => ({selection}));
  const installedCaptured = originalPreparation !== undefined &&
    typeof originalPreparation.openCapturedHost === 'function';
  const installedSourceFree = sourceFree && (completeOriginal || selected.components[0].localMock !== true);
  const installedComponent = installedCaptured || installedSourceFree;
  if (installedComponent && (completeOriginal
      ? originalComponents.some(original => typeof original.component?.bindOriginal !== 'function')
      : children.length !== 1 || originalPreparation.selection !== children[0].selection ||
        typeof originalPreparation.component?.bindOriginal !== 'function')) {
    throw new TypeError('InvalidInstalledRequestModelPreparation');
  }
  let execution, pendingSetup, issuance, publication, holding, sourceContinuation, restoredSource, preflightCleanup;
  let issuanceComplete = false, closeAttempted = false, released = false, publicationOwner;
  function retainCompleted(child) {
    // The first actual completed original retains this Run's complete
    // publication envelope. Later captures reuse that same operation/borrow;
    // completion order never changes the compiler's ordered owner inventory.
    if (completeOriginal) publicationOwner ??= child.operation;
    if (!child.capture.retainCompleted(completeOriginal ? publicationOwner : child.operation)) return false;
    if (originalPreparation === undefined || issuanceComplete) return true;
    if (!children.includes(child)) {
      throw new Error('InstalledComposedInferOriginalObservationUnavailable');
    }
    child.completed = true;
    // Each earlier original capture/output and publication borrow stays live.
    // Seal the complete compiler inventory at the LAST original completion,
    // before Local can transfer that component's completed output ownership.
    if (children.some(original => original.completed !== true)) return true;
    let calls = 0;
    for (const original of children) {
      const count = original.capture.completedCallCount();
      if (!Number.isSafeInteger(count) || count < 0 || count > 128 - calls) {
        throw new Error('InstalledComposedInferOriginalObservationUnavailable');
      }
      calls += count;
    }
    // Seal this Model's actual observation while its original input tokens
    // still precede Local's legitimate completed-output ownership transfer.
    // Store persistence and public Result publication still follow the DAG.
    issuance ??= startCompleteInferObservation({moon, operations: children.map(original => original.operation),
      maxSlots: calls, maxWireBytes: 16384, maxWork: calls + 2});
    for (let step = 0; step < calls + 2 && !issuanceComplete; step++) {
      issuanceComplete = runtimeField(checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1)), 0);
    }
    if (!issuanceComplete) throw new Error('InstalledComposedInferOriginalObservationUnavailable');
    return true;
  }
  async function cleanup() {
    if (released) return true;
    if (preflightCleanup !== undefined) {
      if (preflightCleanup.status()?.pending === true) await preflightCleanup.retry();
      if (preflightCleanup.status()?.pending !== false) return false;
      preflightCleanup = undefined;
    }
    // Installation can fail before the asynchronous driver returns an owner.
    // Retain that exact setup until its stopped outputs and reservations close.
    if (pendingSetup !== undefined) {
      moon.strategyHostStop(pendingSetup);
      moon.strategyHostCloseOutputs(pendingSetup);
      // The same parent can still own the original Model Scope/bootstrap.
      // Drain its real children below before testing whole-parent quiescence;
      // otherwise this setup would wait on cleanup it itself prevents.
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
    if (completeOriginal && publicationOwner !== undefined) {
      // Stop is only a request. Every actual capture must finish its accepted
      // Store work and sever publication aliases BEFORE this one borrow ends.
      // Otherwise retiring its owner first would unback a sibling's metadata.
      for (const child of children) {
        if (child.operation !== undefined && !child.operation.physicalStopped()) await child.operation.stop();
      }
      for (const child of children) {
        if (child.capture !== undefined && !await child.capture.custody.retirePublication()) pending = true;
      }
      if (pending || !publicationOwner.releaseOriginalPublicationCapacity()) return false;
      publicationOwner = undefined;
    }
    for (const child of children) {
      const physical = child.capture?.custody ?? child.operation;
      if (physical !== undefined && !child.captureReleased) {
        if (child.operation?.publicationCapacityPending?.()) {
          // Real publication child/alias retirement precedes release of this
          // exact borrow. Parent Model cleanup is pinned until both settle.
          if (!await child.capture.custody.retirePublication() ||
              !child.operation.releaseOriginalPublicationCapacity()) {
            pending = true;
            continue;
          }
        }
        const retry = child.captureCloseAttempted === true;
        child.captureCloseAttempted = true;
        const result = await (retry ? physical.cleanup() : physical.close());
        child.captureReleased = result !== false && !physical.cleanupPending();
        pending ||= !child.captureReleased;
      }
      if (child.continuation !== undefined && !child.continuationReleased) {
        const retry = child.continuationCloseAttempted === true;
        child.continuationCloseAttempted = true;
        const result = await (retry ? child.continuation.cleanup() : child.continuation.close());
        child.continuationReleased = result !== false && !child.continuation.cleanupPending();
        pending ||= !child.continuationReleased;
      }
      if (child.continuation === undefined && child.token !== undefined &&
          (child.operation === undefined || child.captureReleased)) {
        modelController.release(child.token);
        child.token = undefined;
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
    if (restoredSource !== undefined) {await restoredSource.close(); restoredSource = undefined;}
    if (sourceContinuation !== undefined) {await sourceContinuation.close(); sourceContinuation = undefined;}
    if (originalPreparation !== undefined && await originalPreparation.retire() !== true) return false;
    if (pendingSetup !== undefined) {
      if (ledgerUsageHasPendingResources(moon.strategyHostUsage(pendingSetup)) &&
          !(originalPreparation?.preparationHolder !== undefined &&
            typeof moon.clientProgramPreparationBorrowUsageIsolated === 'function' &&
            moon.clientProgramPreparationBorrowUsageIsolated(originalPreparation.preparationHolder,
              moon.strategyHostRun(pendingSetup)) === true)) return false;
      pendingSetup = undefined;
    }
    released = true;
    return true;
  }
  retainExecution(Object.freeze({close: cleanup, cleanup, cleanupPending: () => !released}));
  if (originalPreparation !== undefined) originalPreparation.retain();
  const declaredResults = Array.from({length: moon.clientProgramResultCount(preparedProgram)},
    (_, index) => moon.clientProgramResultName(preparedProgram, index));
  const matched = new Set();
  for (const child of children) {
    const task = runtimeField(moon.clientProgramInferPlanBoundary(child.selection.graph), 0);
    const candidates = records.filter(record => record.inventory.taskIndex === task);
    if (candidates.length > 1) throw new Error('ModelResumeScopeAmbiguous');
    if (candidates.length === 0) continue;
    child.record = candidates[0];
    matched.add(child.record.inventory.scopeCid);
    child.token = await modelController.prime(child.record);
    assertCurrent();
    child.restoredInput = {token: child.token, snapshot: child.token.snapshot,
      sendMask: modelController.state(child.record.inventory).slots.map(slot => slot.state === 'Unsent'),
      savedScope: modelController.savedScope(plan, preparedProgram, child.selection, child.token)};
  }
  if (matched.size !== records.length) throw new Error('ModelResumeForeignInventory');
  let input = acquiredInfer;
  const historical = children.find(child => child.token !== undefined);
  if (multiple && checkpoints !== undefined) {
    // Retain both original approved request/response prefixes. A last ticket,
    // matching array or a single Source's closure cannot stand in for them.
    if (historical !== undefined) throw new Error('ModelMultiSourceClosureCustodyUnavailable');
    sourceContinuation = acquiredEffectContinuation({checkpoints, moon,
      acquired: {kind: 'infer', prepared: preparedProgram, runDefinition: plan.runDefinition, control},
      submission, declaredResults, principalId, unitId: 'composed-source-input', signal,
      currentRun: () => {try {assertCurrent(); return !signal.aborted;} catch {return false;}}});
    const originals = input.sources.map(source => ({occurrence: source.occurrence,
      preparedSource: source.preparedSource, adapter: source.adapter}));
    for (const source of input.sources) sourceContinuation.accessFor(source.access, source.occurrence);
    await sourceContinuation.prepared(originals);
    for (const [index, source] of input.sources.entries()) {
      await sourceContinuation.captured(originals[index], source.captured, source.sourceEvidenceWire,
        input.captureStartedAt, input.captureCompletedAt);
    }
  } else if (!sourceFree && checkpoints !== undefined && prepareAcquisition !== undefined) {
    const coordinates = originalPreparation?.sourceCoordinates?.[0];
    const occurrence = coordinates === undefined ? {stage: 0, input: 0, task: 0}
      : Object.freeze({stage: coordinates[0], input: coordinates[1], task: coordinates[2]});
    const preparedSource = input?.preparedSource ?? await prepareAcquisition(preparedProgram);
    assertCurrent();
    const saved = historical?.token.snapshot.sourceContinuation;
    if (historical !== undefined && saved === undefined) throw new Error('ModelSourceClosureCustodyUnavailable');
    for (const child of children) {
      if (child.token !== undefined && canonicalJson(child.token.snapshot.sourceContinuation) !== canonicalJson(saved)) {
        throw new Error('ModelSourceClosureMismatch');
      }
    }
    sourceContinuation = acquiredEffectContinuation({checkpoints, moon,
      acquired: {kind: 'infer', prepared: preparedProgram, runDefinition: plan.runDefinition, control},
      submission, declaredResults, principalId, unitId: 'composed-source-input', signal,
      currentRun: () => {try {assertCurrent(); return !signal.aborted;} catch {return false;}},
      ...(saved === undefined ? {} : {restore: {
        view: {kind: 'model_invocation', prepareAttemptId: null, runId,
          runDefinitionCid: plan.runDefinition.identity}, continuation: saved}})});
    // Preparation is an authorization check, never an upstream acquisition.
    // The selected adapter's access owner revalidates retained consumption.
    const access = input?.sourceAccess ?? sourceAccessFor(preparedSource);
    sourceContinuation.accessFor(access, occurrence);
    const source = {occurrence, preparedSource};
    await sourceContinuation.prepared([source]);
    if (historical === undefined) {
      await sourceContinuation.captured(source, input.captured, input.sourceEvidenceWire,
        input.captureStartedAt, input.captureCompletedAt);
    } else {
      const retained = await sourceContinuation.beforeRead(source);
      assertCurrent();
      if (retained.retained === undefined) throw new Error('ModelSourceClosureCustodyUnavailable');
      const restored = sourceContinuation.restore(source, retained.retained, undefined);
      restoredSource = restored.captured;
      input = {...restored, ...sourceContinuation.times(),
        sourceEvidence: control.admitRunEvidence('source_evidence', restored.sourceEvidenceWire,
          {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})};
    }
  } else if (historical !== undefined) throw new Error('ModelSourceClosureCustodyUnavailable');
  const {captured, captureStartedAt, captureCompletedAt} = input ?? {};
  const captures = sourceFree ? [] : multiple ? input.sources.map(source => source.captured) : [captured];
  const sourceEvidence = sourceFree ? [] : multiple ? input.sourceEvidence : [input.sourceEvidence];
  for (const [index, child] of children.entries()) {
    const childOriginal = completeOriginal ? originalComponents[index] : originalPreparation;
    const sources = child.restoredInput === undefined && !sourceFree ? control.admitComposedInferSources(
      child.selection.occurrence, captures, sourceEvidence, authorityScopeCid,
      captureStartedAt, captureCompletedAt) : undefined;
    const context = {moon, selected: child.selection, sources,
      control, plan, principalId, now, signal, durableCalls: true, restoredInput: child.restoredInput,
      originalPreparation: childOriginal, assertRuntimeCurrent: childOriginal?.assertRuntimeCurrent,
      retainOperation(operation) {
        child.operation = operation;
        childOriginal?.retainOperation?.(operation);
        child.capture = openNodeInferCaptureCustody({moon, control, operation, plan, store,
          storeAuthorityCid, sourceEvidence, faultInjection, durableCalls: true, captureOnly: true});
      }, retainCompleted: () => retainCompleted(child)};
    if (installedComponent) {
      child.component = childOriginal.component;
      child.component.bindOriginal(context);
    } else child.component = openNodeComposedInferProvider(context);
  }
  const setup = installedCaptured ? originalPreparation.openCapturedHost(captures)
    : sourceFree ? originalPreparation.openSourceFreeHost(registry, values, fragment, ordered,
    children.map(child => child.component.provider)) : multiple ? moon.clientProgramOpenMultiCapturedComposedInferHost(preparedProgram,
    captures.map(value => value.capture.source()), input.ledger, registry, values, fragment, ordered,
    children.map(child => child.component.provider)) : moon.clientProgramOpenCapturedComposedInferHost(preparedProgram,
    captured.capture.source(), registry, values, fragment, ordered,
    children.map(child => child.component.provider));
  if (setup === undefined) throw new Error('InstalledComposedInferHostUnavailable');
  pendingSetup = setup;
  if (multiple || installedCaptured) {
    const dag = moon.strategyHostRun(setup);
    for (const [task, original] of captures.entries()) original.capture.retainTask(dag, task);
  }
  // The existing single-Source dispatch owner retains this capture until
  // all Compute custody has settled. It is not a multi-capture ledger lease.
  const local = withLocalExecutionPauseHandler(computeConfigurations.local, async boundary => {
    const child = children.find(value => runtimeField(moon.clientProgramInferPlanBoundary(value.selection.graph), 0) === boundary.task);
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
        plan, selected: child.selection, principalId, declaredResults, submission, signal,
        originalPreparation,
        retainEvidenceCopy(copy) {
          if (child.copy?.cleanupPending()) throw new Error('InferEvidenceCopyAlreadyRetained');
          child.copy = copy;
        },
        existing: child.record, inputToken: child.token,
        ...(child.record?.inventory.scopeCid === existingModel?.inventory.scopeCid ? {claim: modelClaim} : {}),
        ...(sourceContinuation === undefined ? {} : {sourceContinuation: await sourceContinuation.retainAll()})});
      child.capture.configureModelJournal({observe: child.continuation.observe, entry: child.continuation.entry});
      // Restore saved/unknown slots through Core before considering new send
      // permission. The Local component pauses again for any unsent work.
      if (child.record !== undefined && !child.continuation.hasResponseReconciliation) return {action: 'resume'};
    }
    const decision = await child.continuation.authorize();
    if (decision.status === 'dispatch') return {action: 'resume'};
    if (decision.status !== 'waiting_checkpoint') throw new Error('InvalidModelPauseDecision');
    // Local retains its task's physical cleanup handle. Feeding the parent
    // driver's cleanup back into that handle creates recursive reclamation.
    // The installed Run retains the separate capture/continuation custody.
    return {action: 'waiting_checkpoint', checkpoint: decision.checkpoint};
  });
  beginPhysicalWork();
  execution = await runCapturedStrategy(setup, {...computeConfigurations, local}, signal, undefined,
    installedCaptured ? {preparationHolder: originalPreparation.preparationHolder,
      retainPreflightCleanup(owner) {
        if (preflightCleanup !== undefined || pendingSetup !== setup) {
          throw new TypeError('InstalledComposedInferPreflightCleanupUnavailable');
        }
        // Keep even a malformed original partial carrier before reporting a
        // protocol failure. That is pending custody, never a cleanup ACK.
        preflightCleanup = owner;
        if (typeof owner?.status !== 'function' || typeof owner?.retry !== 'function') {
          throw new TypeError('InstalledComposedInferPreflightCleanupUnavailable');
        }
        // Existing entry supplies this exact refused setup/partial Site owner
        // before stopping it. Transfer the slot, never wrap or replace it.
        pendingSetup = undefined;
      }} : undefined);
  pendingSetup = undefined;
  if (execution.status === 'host-tasks-waiting') {
    return Object.freeze({status: 'waiting_checkpoint', checkpoint: execution.checkpoint});
  }
  if (execution.status !== 'host-tasks-completed') {
    for (const child of children) {
      if (child.operation?.physicalStopped()) await child.capture.persistStoppedAttempts();
    }
    if (modelController.unresolved(runId)) {
      // A partial Run has no complete ObservationSet or Named Result. Reuse
      // authenticated individual Store originals without inventing either.
      for (const child of children) {
        await projectInferEvidence({configuration: inferEvidence, moon, control, preparedProgram, plan,
          selected: child.selection, operation: child.operation, captureOwner: child.capture,
          continuation: child.continuation, authorityScopeCid, partial: true,
          retainCopy(copy) {if (child.copy?.cleanupPending()) throw new Error('InferEvidenceCopyAlreadyRetained'); child.copy = copy;}});
      }
      return Object.freeze({status: 'needs_reconciliation'});
    }
    const failed = children.find(child => child.component.hasFailure?.() === true ||
      child.component.failure() !== undefined);
    if (failed !== undefined) throw failed.component.failure();
    if (Object.hasOwn(execution, 'failure')) throw execution.failure;
    throw new Error('InstalledComposedInferComputationFailed');
  }
  for (const child of children) await child.capture.persist();
  const calls = children.reduce((sum, child) => sum + child.capture.evaluationBundle().count, 0);
  if (originalPreparation === undefined) {
    issuance = startCompleteInferObservation({moon, operations: children.map(child => child.operation),
      ledger: checked(moon.clientProgramInferPublicationLedger(262144n + BigInt(calls * 128 + (children.length - 1) * 256), calls + 2)),
      maxSlots: calls, maxWireBytes: 16384, maxWork: calls + 2});
  } else if (issuance === undefined || !issuanceComplete) {
    throw new Error('InstalledComposedInferOriginalObservationUnavailable');
  }
  while (!issuanceComplete) {
    issuanceComplete = runtimeField(checked(moon.clientProgramAdvanceInferObservationIssuance(issuance, 1)), 0);
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
  // Match the existing single-Model durable capture boundary: every capture
  // and its Observation/Invocation holdings committed before publication.
  await faultInjection?.('infer_capture_committed', {});
  signal.throwIfAborted();
  await publishCompletedEffectFreeRun({...publication.plan, execution, store, control, signal});
  for (const child of children) {
    await projectInferEvidence({configuration: inferEvidence, moon, control, preparedProgram, plan,
      selected: child.selection, operation: child.operation, captureOwner: child.capture,
      continuation: child.continuation, authorityScopeCid,
      retainCopy(copy) {if (child.copy?.cleanupPending()) throw new Error('InferEvidenceCopyAlreadyRetained'); child.copy = copy;}});
  }
}

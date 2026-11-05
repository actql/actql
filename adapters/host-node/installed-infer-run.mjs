// Installed physical composition of the checked Infer, original per-call
// journal/custody and publication owners. No JS slot scheduler is introduced.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {projectInferEvidence} from './infer-evaluation-evidence.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation, retireNodeInferOriginalRead, finishNodeInferOriginalReadScopes} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';
import {createInferIoNotification} from './infer-io-notification.mjs';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {selectedInferOriginalCurrentStateCodec,
  selectedInferOriginalPublicationCapacity} from './infer-original-installation.mjs';

// Borrow the existing Request's Model Plan and Scope. This is the
// same installed Run; configured providers keep their current/claim/stop owner.
function sourceFreeModelPreparation(moon, control, prepared, plan, selected, model, acquired) {
  const group = model?.group;
  const managed = model?.managed, scope = model?.scope, component = model?.component;
  const original = managed?.value, request = managed?.request, graph = selected.graph,
    compiled = plan.compiled, definition = plan.runDefinition, budget = model?.budget,
    publication = model?.publicationCapacity;
  const sourceLedger = acquired?.ledger, captured = acquired?.captured;
  const current = () => {
    if (model === null || typeof model !== 'object' || model.closed || model.scopeFinished ||
        model.prepared !== prepared || model.selection !== selected || model.graph !== graph || selected.graph !== graph ||
        model.control !== control || model.compiled !== compiled || plan.compiled !== compiled ||
        model.runDefinition !== definition || plan.runDefinition !== definition ||
        scope === undefined || model.scope !== scope || model.budget !== budget ||
        component === undefined || model.component !== component ||
        typeof component.bindOriginal !== 'function' ||
        typeof publication !== 'function' || model.publicationCapacity !== publication ||
        model.originalReadInstallation !== undefined || model.managed !== managed ||
        managed?.closed || managed?.model !== (group ?? model) ||
        group !== undefined && (!Array.isArray(group.components) || !group.components.includes(model) ||
          group.closed || group.scopeFinished) || original === undefined ||
        managed.value !== original || managed.request !== request ||
        managed.runtime !== moon || managed.prepared !== prepared ||
        acquired !== undefined && (moon.clientProgramAcquisitionCount(prepared) !== 1 ||
          managed.value !== acquired.managedRun || acquired.ledger !== sourceLedger ||
          model.sourceLedger !== sourceLedger || acquired.captured !== captured)) {
      throw new TypeError('InvalidInstalledRequestModelPreparation');
    }
  };
  current();
  if (model.taken || model.readAttempted || model.read !== undefined) {
    throw new TypeError('InvalidInstalledRequestModelPreparation');
  }
  const publicationCapacity = () => {
    current();
    return Reflect.apply(publication, model, []);
  };
  return Object.freeze({selection: selected, control, compiled: plan.compiled, component,
    assertRuntimeCurrent: current,
    runDefinition: plan.runDefinition, scope, publicationCapacity,
    readRetainedBytes: model.budget.readRetainedBytes, readExecutionBytes: model.budget.readExecutionBytes,
    modelRetainedBytes: model.budget.modelRetainedBytes, modelExecutionBytes: model.budget.modelExecutionBytes,
    retain() {
      current();
      if (model.taken || model.readAttempted) throw new TypeError('InvalidInstalledRequestModelPreparation');
      model.taken = true;
    },
    openSourceFreeHost(registry, values, fragment, ordered, providers) {
      current();
      if (!model.taken || model.hostAttempted || moon.clientProgramAcquisitionCount(prepared) !== 0) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
        original, prepared, request, registry, values, fragment, ordered, providers));
    },
    ...(acquired === undefined ? {} : {openCapturedHost(captures) {
      current();
      if (!model.taken || model.hostAttempted || !Array.isArray(captures) ||
          captures.length !== 1 || captures[0] !== captured ||
          typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
        throw new TypeError('InstalledComposedInferHostUnavailable');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedCaptureHost(original,
        prepared, request, captures.map(value => value.capture.source())));
    }}),
    prepareRead() {
      current();
      if (model.readAttempted && Object.hasOwn(model, 'readFailure')) throw model.readFailure;
      if (!model.taken || model.readAttempted) throw new TypeError('InvalidInstalledRequestModelPreparation');
      model.readAttempted = true;
      try {
        model.read = control.prepareCheckedClientInferOriginalRead(plan.compiled,
          plan.runDefinition, selected.graph, scope, model.budget);
        return Object.freeze({control, compiled: plan.compiled, runDefinition: plan.runDefinition,
          scope, read: model.read, publicationCapacity,
          readRetainedBytes: model.budget.readRetainedBytes, readExecutionBytes: model.budget.readExecutionBytes,
          modelRetainedBytes: model.budget.modelRetainedBytes, modelExecutionBytes: model.budget.modelExecutionBytes});
      } catch (cause) {model.readFailure = cause; throw cause;}
    },
    async retire() {
      if (model.closed && model.scopeFinished) return true;
      current();
      retireNodeInferOriginalRead(model);
      model.read = undefined;
      if (control.finishCheckedClientInferOriginalReadScope(plan.compiled,
        plan.runDefinition, selected.graph, scope, true) !== true) return false;
      model.scopeFinished = true;
      // The existing Host registry still owns Run/parent retirement and alias
      // severing. Finishing this Scope does not report whole-Host cleanup.
      model.closed = true;
      return true;
    }});
}

// One original group view on the same installed Run. All component reads and
// scopes retire before its existing Request/Host cleanup; the first pending
// scope never prevents cleanup from reaching the remaining actual children.
function sourceFreeModelsPreparation(moon, control, prepared, plan, selected, model, acquired, preparationHolder) {
  const members = model?.components, scopes = model?.scopes, managed = model?.managed;
  const current = () => {
    if (!Array.isArray(members) || !Object.isFrozen(members) || members.length < 2 ||
        model.components !== members || model.selection !== selected || model.closed || model.scopeFinished ||
        !Array.isArray(scopes) || model.scopes !== scopes || scopes.length !== members.length ||
        model.graph !== selected.graph || model.control !== control || model.compiled !== plan.compiled ||
        model.runDefinition !== plan.runDefinition || managed?.model !== model || managed.closed ||
        model.managed !== managed || managed.value === undefined || managed.prepared !== prepared ||
        acquired !== undefined && (managed.value !== acquired.managedRun || model.sourceLedger !== acquired.ledger) ||
        members.some((member, index) => member.group !== model || member.managed !== managed ||
          member.selection !== selected.components[index] || member.graph !== selected.graph[index] ||
          member.scope !== scopes[index])) throw new TypeError('InvalidInstalledRequestModelPreparation');
  };
  current();
  const originals = Object.freeze(members.map((member, index) =>
    sourceFreeModelPreparation(moon, control, prepared, plan, selected.components[index], member)));
  return Object.freeze({control, compiled: plan.compiled, runDefinition: plan.runDefinition,
    selection: selected, components: originals, preparationHolder, sourceCoordinates: selected.sourceCoordinates,
    retain() {current(); for (const original of originals) original.retain(); model.taken = true;},
    ...(acquired === undefined ? {
    openSourceFreeHost(registry, values, fragment, ordered, providers) {
      current();
      if (!model.taken || model.hostAttempted || moon.clientProgramAcquisitionCount(prepared) !== 0 ||
          !Array.isArray(providers) || providers.length !== members.length ||
          providers.some((provider, index) => provider !== members[index].component.provider)) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedSourceFreeComposedInferHost(
        managed.value, prepared, managed.request, registry, values, fragment, ordered, providers));
    },
    } : {openCapturedHost(captures) {
      current();
      if (!model.taken || model.hostAttempted || !Array.isArray(captures) ||
          captures.length !== moon.clientProgramAcquisitionCount(prepared) ||
          typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
        throw new TypeError('InstalledComposedInferHostUnavailable');
      }
      model.hostAttempted = true;
      return checked(moon.clientProgramOpenInstalledManagedCaptureHost(managed.value,
        prepared, managed.request, captures.map(value => value.capture.source())));
    }}),
    async retire() {
      if (model.closed && model.scopeFinished) return true;
      current();
      for (const member of members) {retireNodeInferOriginalRead(member); member.read = undefined;}
      if (finishNodeInferOriginalReadScopes(model) !== true) return false;
      model.scopeFinished = true; model.closed = true;
      return true;
    }});
}

export function installNodeInferRun({moon, core, registry, values, fragment, ordered, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection, modelController, inferEvidence,
  checkpoints, prepareAcquisition, sourceAccessFor, sourceAdapterFor, runContent, prepareKeyedRecovery,
  prepareOriginalMockRun, prepareOriginalModelRun, prepareModelRecoveryPlan,
  computeConfigurations = {}}) {
  const control = core.publicationControl;
  const run = async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, acquiredInfer, acquiredContent, replay = false, beginPhysicalWork = () => {},
    submission, existingModel, modelClaim, assertCurrent, originalPreparation, preparationHolder}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    if (selected.restoredRun === undefined && selected.components !== undefined &&
        typeof prepareOriginalModelRun === 'function') {
      const sourceCount = moon.clientProgramAcquisitionCount(preparedProgram);
      if (originalPreparation !== undefined || replay || sourceCount > 0 &&
          (acquiredInfer?.managedRun === undefined || preparationHolder === undefined) ||
          sourceCount === 0 && acquiredInfer !== undefined) throw new TypeError('InvalidInstalledRequestModelPreparation');
      const model = prepareOriginalModelRun(preparedProgram, plan, selected);
      const original = sourceFreeModelsPreparation(moon, control, preparedProgram, plan, selected, model, acquiredInfer, preparationHolder);
      return runInstalledComposedInfers({moon, control, preparedProgram, plan, selected,
        store, principalId, signal, retainExecution, acquiredInfer, replay, beginPhysicalWork, submission,
        existingModel, modelClaim, assertCurrent, modelController, inferEvidence, checkpoints,
        prepareAcquisition, sourceAccessFor, sourceAdapterFor, namespaceId, authorityScopeCid, storeAuthorityCid,
        now, faultInjection, registry, values, fragment, ordered, computeConfigurations,
        originalPreparation: original});
    }
    let directRequestModel, restoredRequestModel;
    const configuredModel = selected.restoredRun === undefined && !selected.localMock && selected.originalReadInstallation === undefined &&
      selected.occurrence !== undefined && selected.components === undefined &&
      selected.serializationGraph === undefined && moon.clientProgramAcquisitionCount(preparedProgram) <= 1;
    if (selected.localMock || configuredModel) {
      const sourceFree = moon.clientProgramAcquisitionCount(preparedProgram) === 0;
      if (configuredModel) {
        if (originalPreparation !== undefined ||
            (sourceFree ? acquiredInfer !== undefined : acquiredInfer?.captured === undefined || preparationHolder === undefined) ||
            typeof prepareOriginalModelRun !== 'function') {
          throw new TypeError('InvalidInstalledRequestModelPreparation');
        }
        originalPreparation = sourceFreeModelPreparation(moon, control, preparedProgram, plan, selected,
          prepareOriginalModelRun(preparedProgram, plan, selected), acquiredInfer);
      } else if (sourceFree && originalPreparation === undefined &&
          typeof prepareOriginalMockRun === 'function') {
        originalPreparation = prepareOriginalMockRun(preparedProgram, plan);
      }
      if (originalPreparation?.control !== control || originalPreparation.compiled !== plan.compiled ||
          originalPreparation.runDefinition !== plan.runDefinition ||
          (sourceFree ? acquiredInfer !== undefined || typeof originalPreparation.openSourceFreeHost !== 'function'
            : configuredModel ? acquiredInfer?.captured === undefined : acquiredInfer?.sources?.length !== 2)) {
        throw new TypeError('InvalidInstalledMockModelPreparation');
      }
      if (!sourceFree) {
        if (preparationHolder === undefined || originalPreparation.selection !== selected ||
            typeof originalPreparation.component?.bindOriginal !== 'function' ||
            typeof originalPreparation.openCapturedHost !== 'function') {
          throw new TypeError('InvalidInstalledMockModelPreparation');
        }
        originalPreparation = Object.freeze({...originalPreparation, preparationHolder});
      }
      // A captured task is already complete in the DAG. When the original
      // checked Program has just that one task, its terminal Model still runs
      // through the original kernel/publication owner, not a captured Result.
      if (configuredModel && !sourceFree && moon.clientProgramTaskCount(preparedProgram) === 1) {
        directRequestModel = originalPreparation;
        originalPreparation = undefined;
      } else {
        return runInstalledComposedInfers({moon, control, preparedProgram, plan,
          selected: {components: [selected]}, store, principalId, signal, retainExecution,
          acquiredInfer, replay, beginPhysicalWork, submission, existingModel, modelClaim, assertCurrent,
          modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor, sourceAdapterFor,
          namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
          registry, values, fragment, ordered, computeConfigurations, originalPreparation});
      }
    }
    if (selected.restoredRun !== undefined) {
      // The restored typed owner is the same Journal-selected compilation,
      // not a fresh ordinary Request module or an unbacked legacy admission.
      control.checkRestoredClientInferRunOwner(selected.restoredRun, preparedProgram);
      if (selected.restoredRun.compiled !== plan.compiled || selected.restoredRun.graph !== selected.graph ||
          selected.restoredRun.runDefinition !== plan.runDefinition || existingModel === undefined) {
        throw new TypeError('ForeignRestoredInferOriginal');
      }
      if (originalPreparation !== undefined || typeof prepareModelRecoveryPlan !== 'function') {
        throw new TypeError('InstalledModelRecoveryPreparationUnavailable');
      }
      restoredRequestModel = prepareModelRecoveryPlan(preparedProgram, plan, selected);
      if (restoredRequestModel?.control !== control || restoredRequestModel.compiled !== plan.compiled ||
          restoredRequestModel.runDefinition !== plan.runDefinition || restoredRequestModel.selection !== selected ||
          ['retain', 'retire', 'assertRuntimeCurrent'].some(name => typeof restoredRequestModel[name] !== 'function')) {
        throw new TypeError('ForeignRestoredInferOriginalPreparation');
      }
      if (selected.components !== undefined || moon.clientProgramTaskCount(preparedProgram) !== 1) {
        return runInstalledComposedInfers({moon, control, preparedProgram, plan,
          selected: selected.components === undefined ? {...selected, components: [selected]} : selected,
          store, principalId, signal, retainExecution, acquiredInfer, replay, beginPhysicalWork, submission,
          existingModel, modelClaim, assertCurrent, modelController, inferEvidence, checkpoints,
          prepareAcquisition, sourceAccessFor, sourceAdapterFor, namespaceId, authorityScopeCid, storeAuthorityCid,
          now, faultInjection, registry, values, fragment, ordered, computeConfigurations,
          originalPreparation: restoredRequestModel});
      }
    }
    const originalInstallation = restoredRequestModel === undefined ? selected.originalReadInstallation : undefined;
    const requestComposed = originalInstallation !== undefined && acquiredInfer !== undefined &&
      selected.occurrence !== undefined && selected.serializationGraph === undefined &&
      selected.components === undefined && !replay && typeof prepareOriginalModelRun === 'function';
    let runtimeBorrow, requestModel;
    const assertOriginalRuntime = () => {
      if (originalInstallation === undefined) return;
      if (originalScopeReleased) throw new TypeError('InstalledInferOriginalPreparationRetired');
      if (typeof selected.assertTrustedRuntime !== 'function' ||
          typeof selected.currentProvider !== 'function' || !selected.currentProvider()) {
        throw new TypeError('InferTrustedRuntimeViewUnavailable');
      }
      if (runtimeBorrow === undefined) {
        if (typeof selected.assertNewTrustedRuntime !== 'function') {
          throw new TypeError('InferTrustedRuntimeViewUnavailable');
        }
        if (requestModel === undefined) selected.assertNewTrustedRuntime();
        else {
          selected.assertTrustedRuntime();
          if (!control.checkedClientInferOriginalReadScopeLive(plan.compiled,
            plan.runDefinition, selected.graph, requestModel.scope)) {
            throw new TypeError('InferTrustedRuntimeScopeUnavailable');
          }
        }
      } else {
        selected.assertTrustedRuntimeScope(originalPreparation.scope, runtimeBorrow,
          plan.compiled, plan.runDefinition, selected.graph);
      }
    };
    if (originalInstallation!==undefined) {
      // Known missing selection refuses before creating the original child.
      // This finite DATA role supplies no normal numerical funding or grant.
      selectedInferOriginalCurrentStateCodec(originalInstallation,originalInstallation.nodeInstallation);
      selectedInferOriginalPublicationCapacity(originalInstallation,originalInstallation.nodeInstallation);
    }
    if (originalInstallation !== undefined &&
        (originalPreparation !== undefined || acquiredInfer !== undefined && !requestComposed || replay ||
          selected.components !== undefined)) {
      throw new TypeError('InstalledInferOriginalReadInstallationUnavailable');
    }
    if (originalInstallation !== undefined &&
        [...(prepareOriginalModelRun === undefined ? ['beginCheckedClientInferOriginalReadScope'] : []),
          'prepareCheckedClientInferNodeReadLayout',
          'claimCheckedClientInferNodePreparationLayout', 'startCheckedClientInferOriginalPreparation',
          'stopCheckedClientInferOriginalReadPreparation', 'settleCheckedClientInferOriginalReadPreparation',
          'finishCheckedClientInferOriginalReadScope',
          'checkedClientInferOriginalReadScopeLive'].some(name => typeof control[name] !== 'function') ||
        originalInstallation !== undefined && ['bindTrustedRuntimeScope',
          'assertTrustedRuntimeScope','finishTrustedRuntimeScope']
          .some(name=>typeof selected[name]!=='function')) {
      throw new TypeError('InstalledInferOriginalReadRuntimeUnavailable');
    }
    if (originalInstallation !== undefined && prepareOriginalModelRun !== undefined) {
      if (typeof prepareOriginalModelRun !== 'function') throw new TypeError('InstalledInferOriginalReadRuntimeUnavailable');
      requestModel = prepareOriginalModelRun(preparedProgram, plan, selected);
      if (requestModel === null || typeof requestModel !== 'object' ||
          requestModel.prepared !== preparedProgram || requestModel.control !== control ||
          requestModel.compiled !== plan.compiled || requestModel.runDefinition !== plan.runDefinition ||
          requestModel.graph !== selected.graph || requestModel.originalReadInstallation !== originalInstallation ||
          requestModel.scope === undefined || requestModel.scopeFinished || requestModel.closed ||
          requestModel.taken || requestModel.readAttempted || requestModel.read !== undefined ||
          requestComposed && (preparationHolder === undefined || requestModel.component === undefined ||
            typeof requestModel.component.bindOriginal !== 'function' ||
            requestModel.managed?.closed || requestModel.managed?.value === undefined ||
            requestModel.managed.value !== acquiredInfer.managedRun ||
            requestModel.sourceLedger !== acquiredInfer.ledger)) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
    }
    // Installation-only original custody. Public request data and restored
    // inputs cannot mint a fresh read or replace its original scope/Ledger.
    if (originalPreparation !== undefined &&
        (originalPreparation === null || typeof originalPreparation !== 'object' ||
          Object.keys(originalPreparation).filter(name => name !== 'metadataInstallation').sort().join(',') !==
            'compiled,control,modelExecutionBytes,modelRetainedBytes,nodeInstallation,physicalCustody,read,readExecutionBytes,readRetainedBytes,runDefinition,scope' ||
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
    if (originalPreparation !== undefined) {
      // Capture these already-owned references once before any await. The
      // installation's full preparation envelope must fund this record and
      // its overlap with the caller's input; no late grant is inferred here.
      originalPreparation = Object.freeze({...originalPreparation});
    }
    if (selected.components !== undefined) {
      return runInstalledComposedInfers({moon, control, preparedProgram, plan, selected,
        store, principalId, signal, retainExecution, acquiredInfer, replay,
        beginPhysicalWork, submission, existingModel, modelClaim, assertCurrent,
        modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor, sourceAdapterFor,
        namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
        registry, values, fragment, ordered, computeConfigurations});
    }
    const keyed = directRequestModel === undefined && !requestComposed && selected.occurrence !== undefined && selected.serializationGraph === undefined &&
      checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) !== undefined;
    // The current installed read/layout supplier has no adopted Content overlap.
    // Refuse before generation/recovery or keyed input construction; support
    // checks and a visible child Ledger are not original funding authority.
    if (keyed || acquiredContent !== undefined && (requestModel === undefined ||
          requestModel.contentPreparation?.managed === undefined || selected.serializationGraph === undefined) ||
        selected.serializationGraph !== undefined && (requestModel === undefined ||
          requestModel.serializationGraph !== selected.serializationGraph || requestModel.contentPreparation?.managed === undefined)) {
      throw new TypeError('InstalledInferContentOriginalPreparationUnavailable');
    }
    if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
    const runId = JSON.parse(plan.runDefinition.wire).run_id;
    const taskIndex = runtimeField(moon.clientProgramInferPlanBoundary(selected.graph), 0);
    existingModel ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
    if (replay && existingModel === undefined) throw new Error('InstalledInferOriginalInventoryMissing');
    if ((originalPreparation !== undefined || originalInstallation !== undefined) &&
        existingModel !== undefined) {
      throw new TypeError('RestoredInferOriginalPreparationUnavailable');
    }
    const token = existingModel === undefined ? undefined : await modelController.prime(existingModel);
    let restoredInput, sources;
    try {
      // A fresh original installation cannot have a restored token. Its
      // current check stays after custody transfer and before Scope issuance:
      // late refusal must not strand an already admitted dispatch without
      // the same cleanup Owner. Restored input owns its existing token here.
      restoredInput = token === undefined ? undefined : {token, snapshot: token.snapshot,
        capturedContent: modelController.capturedContent(token, plan.runDefinition.identity),
        capturedContentBinding: modelController.capturedContentBinding(token, plan.runDefinition.identity),
        sendMask: modelController.state(existingModel.inventory).slots.map(slot => slot.state === 'Unsent'),
        savedScope: modelController.savedScope(plan, preparedProgram, selected, token)};
      sources = restoredInput === undefined
        ? keyed ? [acquiredContent?.sourceEvidence, acquiredContent?.keyedSourceEvidence]
          : acquiredInfer === undefined ? [] : [acquiredInfer.sourceEvidence]
        : JSON.parse(token.snapshot.callScopeSnapshotWire).sources.map(source =>
          control.admitRunEvidence('source_evidence', source.source_evidence_wire,
            {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100}));
    } catch (error) { modelController.release(token); throw error; }
    let operation, captureOwner, continuation, sourceContinuation, evidenceCopy, contentChild, keyedContentChild, composedExecution,
      serializedInput, restoredReferenceIssuer, keyedInput, receivingKeyed, prepareDeferredOriginalRead, composedInput;
    let captureCloseAttempted = false, captureReleased = false;
    let continuationCloseAttempted = false, continuationReleased = false;
    // These are phases of the same existing retained custody, not another
    // cleanup Owner. A failed physical close keeps this exact original record.
    let originalReadStopped = false, originalReadCloseAttempted = false;
    let originalReadPhysicalReleased = directRequestModel === undefined && restoredRequestModel === undefined &&
      originalPreparation === undefined && originalInstallation === undefined;
    let originalReadSettled = originalReadPhysicalReleased;
    let originalScopeReleased = originalReadPhysicalReleased;
    let originalCleanupFlight;
    const cleanupPending = () => evidenceCopy?.cleanupPending() === true || !captureReleased ||
      continuation !== undefined && !continuationReleased ||
      sourceContinuation !== undefined ||
      contentChild?.cleanupPending() === true || keyedContentChild?.cleanupPending() === true ||
      !originalReadSettled || !originalScopeReleased || originalPreparation !== undefined ||
      directRequestModel !== undefined || restoredRequestModel !== undefined;
    // The same original read/Scope duty is shared by the single-stage and
    // adopted composed drivers. Neither child calls the outer cleanup owner.
    const retireOriginalPreparation = async () => {
      if (restoredRequestModel !== undefined) {
        if (await restoredRequestModel.retire() !== true) return false;
        restoredRequestModel = undefined;
        originalPreparation = undefined;
        originalReadStopped = originalReadPhysicalReleased = originalReadSettled = originalScopeReleased = true;
        return true;
      }
      if (directRequestModel !== undefined) {
        if (!await directRequestModel.retire()) return false;
        directRequestModel = undefined;
        originalPreparation = undefined;
        originalReadStopped = originalReadPhysicalReleased = originalReadSettled = originalScopeReleased = true;
        return true;
      }
      if (originalPreparation === undefined) return true;
      const original = originalPreparation, model = requestModel, scope = original.scope, read = original.read;
      const sameOriginal = () => {
        if (originalPreparation !== original || original.scope !== scope || original.read !== read ||
            requestModel !== model || model !== undefined &&
              (model.closed || model.scopeFinished || model.scope !== scope ||
                model.control !== control || model.compiled !== plan.compiled ||
                model.runDefinition !== plan.runDefinition || model.graph !== selected.graph ||
                model.read !== (originalReadSettled ? undefined : read))) {
          throw new TypeError('InvalidInstalledRequestModelPreparation');
        }
      };
      sameOriginal();
      // Cleanup wins over a prefix still unwinding. It cannot later issue
      // a read or start a Model from the same retired Scope.
      prepareDeferredOriginalRead = undefined;
      if (originalPreparation.read === undefined) {
        // The original scope was issued, but read admission refused before
        // an Execution/physical child existed. Only the original census can
        // finish this scope; no synthetic read or physical ACK is issued.
        originalReadStopped = true;
        originalReadPhysicalReleased = true;
        originalReadSettled = true;
      } else if (!originalReadStopped) {
        control.stopCheckedClientInferOriginalReadPreparation(plan.compiled,
          plan.runDefinition, selected.graph, originalPreparation.scope,
          originalPreparation.read);
        sameOriginal();
        originalReadStopped = true;
      }
      if (!originalReadPhysicalReleased) {
        const child = originalPreparation.physicalCustody;
        const recover = originalReadCloseAttempted;
        originalReadCloseAttempted = true;
        const result = await (recover ? child.cleanup() : child.close());
        const complete = result !== false && child.cleanupPending() === false;
        sameOriginal();
        originalReadPhysicalReleased = complete;
        if (!originalReadPhysicalReleased) return false;
      }
      if (!originalReadSettled) {
        control.settleCheckedClientInferOriginalReadPreparation(plan.compiled,
          plan.runDefinition, selected.graph, originalPreparation.read, true);
        sameOriginal();
        originalReadSettled = true;
        if (requestModel !== undefined) requestModel.read = undefined;
      }
      // All actual children of this fresh single-component custody have
      // acknowledged cleanup. The original Core census still refuses any
      // other live child; read settlement alone cannot release bootstrap.
      if (!originalScopeReleased) originalScopeReleased = (runtimeBorrow === undefined
        ? control.finishCheckedClientInferOriginalReadScope(plan.compiled,
          plan.runDefinition, selected.graph, originalPreparation.scope, true)
        : selected.finishTrustedRuntimeScope(originalPreparation.scope, runtimeBorrow,
          plan.compiled, plan.runDefinition, selected.graph)) === true;
      sameOriginal();
      if (originalScopeReleased) {
        if (requestModel !== undefined) {
          requestModel.scopeFinished = true;
          requestModel.read = undefined;
          requestModel = undefined;
        }
        runtimeBorrow = undefined;
        originalPreparation = undefined;
      }
      return originalReadSettled && originalScopeReleased;
    };
    const cleanupOwned = async () => {
      // Optional projection is a child of this already-retained INFER custody.
      // Keep its originals alive until the copy handoff and release settle.
      if (evidenceCopy !== undefined) {
        if (await evidenceCopy.cleanup() === false || evidenceCopy.cleanupPending()) return false;
        evidenceCopy = undefined;
      }
      let failure, failureObserved = false;
      if (!captureReleased) {
        const recover = captureCloseAttempted;
        captureCloseAttempted = true;
        try {
          if (operation?.publicationCapacityPending?.()) {
            // Physical child/alias retirement is observed by its existing
            // custody. Release this operation's exact original byte borrow,
            // not a Bool-derived grant, before the pinned parent Model cleanup.
            if (!await captureOwner.custody.retirePublication()) return false;
            if (!operation.releaseOriginalPublicationCapacity()) return false;
          }
          const child = composedExecution ?? captureOwner?.custody ?? operation;
          const result = child === undefined ? true : await (recover ? child.cleanup() : child.close());
          captureReleased = result !== false && (child === undefined || child.cleanupPending() === false);
        } catch (error) { failure = error; failureObserved = true; }
      }
      if (continuation !== undefined && !continuationReleased) {
        const recover = continuationCloseAttempted;
        continuationCloseAttempted = true;
        try {
          const result = await (recover ? continuation.cleanup() : continuation.close());
          continuationReleased = result !== false && continuation.cleanupPending() === false;
        } catch (error) { if (!failureObserved) {failure = error; failureObserved = true;} }
      }
      if (captureReleased && continuation === undefined) modelController.release(token);
      if (failureObserved) throw failure;
      // Reclaim Model/input borrowers before their producer's prefix. The
      // Content Store's committed private generation remains durable custody,
      // independently of this temporary execution or a public Result index.
      if (!captureReleased || continuation !== undefined && !continuationReleased) return false;
      if (contentChild !== undefined) {
        if (await contentChild.cleanup() === false || contentChild.cleanupPending() !== false) return false;
        contentChild = undefined;
      }
      if (keyedContentChild !== undefined) {
        if (await keyedContentChild.cleanup() === false || keyedContentChild.cleanupPending() !== false) return false;
        keyedContentChild = undefined;
      }
      if (sourceContinuation !== undefined) {
        if (await sourceContinuation.close() === false) return false;
        sourceContinuation = undefined;
      }
      if ((originalPreparation !== undefined || directRequestModel !== undefined || restoredRequestModel !== undefined) && captureReleased &&
          (continuation === undefined || continuationReleased)) {
        if (!await retireOriginalPreparation()) return false;
      }
      return !cleanupPending();
    };
    const cleanup = () => {
      // An original cleanup flight belongs to this same retained custody.
      // Concurrent close/retry callers must not overlap physical close or
      // settle its read twice. The former route is otherwise unchanged.
      if (originalReadStopped && originalScopeReleased && originalPreparation === undefined) return originalCleanupFlight;
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
    catch (error) {
      if (originalInstallation !== undefined) {
        originalReadPhysicalReleased = true;
        originalReadSettled = true;
        originalScopeReleased = true;
      }
      modelController.release(token); throw error;
    }
    if (restoredRequestModel !== undefined) {
      restoredRequestModel.retain();
      const sourceCount = moon.clientProgramAcquisitionCount(preparedProgram);
      if (sourceCount !== 0) {
        const coordinates = restoredRequestModel.sourceCoordinates;
        const saved = restoredInput?.snapshot.sourceContinuation;
        if (sourceCount !== 1 || !Array.isArray(coordinates) || coordinates.length !== 1 ||
            !Array.isArray(coordinates[0]) || coordinates[0].length !== 3 ||
            coordinates[0].some(part => !Number.isSafeInteger(part) || part < 0) ||
            saved === undefined || checkpoints === undefined ||
            typeof prepareAcquisition !== 'function' || typeof sourceAccessFor !== 'function' ||
            typeof sourceAdapterFor !== 'function') {
          throw new Error('ModelSourceClosureCustodyUnavailable');
        }
        const [stage, input, task] = coordinates[0];
        const occurrence = Object.freeze({stage, input, task});
        const current = () => {
          assertCurrent?.();
          restoredRequestModel.assertRuntimeCurrent();
          signal.throwIfAborted();
        };
        current();
        const declaredResults = Array.from({length: moon.clientProgramResultCount(preparedProgram)},
          (_, index) => moon.clientProgramResultName(preparedProgram, index));
        // Keep the exact continuation in the retained cleanup custody before
        // any asynchronous authorization/preparation can fail. SavedInputScope
        // already owns this Model input; consuming it still needs current
        // permission for its original installed Source.
        sourceContinuation = acquiredEffectContinuation({checkpoints, moon,
          acquired: {kind: 'infer', prepared: preparedProgram, runDefinition: plan.runDefinition, control},
          submission, declaredResults, principalId, unitId: 'composed-source-input', signal,
          currentRun: () => {try {current(); return true;} catch {return false;}},
          restore: {view: {kind: 'model_invocation', prepareAttemptId: null, runId,
            runDefinitionCid: plan.runDefinition.identity}, continuation: saved}});
        const preparedSource = await prepareAcquisition(preparedProgram, undefined, occurrence);
        current();
        const adapter = sourceAdapterFor(preparedSource);
        if (adapter === undefined) throw new Error('InstalledComposedInferSourceOwnerUnavailable');
        const source = {occurrence, preparedSource, adapter};
        sourceContinuation.accessFor(sourceAccessFor(preparedSource), occurrence);
        await sourceContinuation.prepared([source]);
        current();
        const retained = await sourceContinuation.beforeRead(source);
        current();
        if (retained.retained === undefined) throw new Error('ModelSourceClosureCustodyUnavailable');
        // Authorization consumes retained custody only. Do not restore a
        // second Source capture, parse its rows or borrow another Ledger.
      }
      composedInput = {occurrence: selected.occurrence, prefix: selected.computePrefix, inputs: []};
      originalPreparation = restoredRequestModel.restoreRead(restoredInput);
    } else if (directRequestModel !== undefined) {
      // Retained cleanup precedes the original Source admission and read. A
      // refusal keeps this same Scope; there is no unowned/standalone fallback.
      directRequestModel.retain();
      const occurrence = acquiredInfer.occurrence ?? acquiredInfer.preparedSource?.occurrence;
      if (checkpoints === undefined || acquiredInfer.preparedSource === undefined || acquiredInfer.adapter === undefined ||
          occurrence === undefined || ['stage', 'input', 'task'].some(name =>
            !Number.isSafeInteger(occurrence[name]) || occurrence[name] < 0)) {
        throw new Error('ModelSourceClosureCustodyUnavailable');
      }
      const current = () => {
        assertCurrent?.();
        directRequestModel.assertRuntimeCurrent();
        signal.throwIfAborted();
      };
      current();
      const declaredResults = Array.from({length: moon.clientProgramResultCount(preparedProgram)},
        (_, index) => moon.clientProgramResultName(preparedProgram, index));
      // Retain this SAME already captured Source before the Model checkpoint
      // stores its input. No acquisition, replacement capture or new grant.
      sourceContinuation = acquiredEffectContinuation({checkpoints, moon,
        acquired: {kind: 'infer', prepared: preparedProgram, runDefinition: plan.runDefinition, control},
        submission, declaredResults, principalId, unitId: 'composed-source-input', signal,
        currentRun: () => {try {current();return true;} catch {return false;}}});
      const source = {occurrence, preparedSource: acquiredInfer.preparedSource, adapter: acquiredInfer.adapter};
      sourceContinuation.accessFor(acquiredInfer.sourceAccess, occurrence);
      await sourceContinuation.prepared([source]);
      current();
      const approvalOriginal = acquiredInfer.sourceAccess?.originalCheckpointApproval;
      if (approvalOriginal !== undefined && typeof approvalOriginal !== 'function') {
        throw new Error('ModelSourceClosureCustodyUnavailable');
      }
      await sourceContinuation.captured(source, acquiredInfer.captured, acquiredInfer.sourceEvidenceWire,
        acquiredInfer.captureStartedAt, acquiredInfer.captureCompletedAt,
        approvalOriginal === undefined ? undefined : Reflect.apply(approvalOriginal, acquiredInfer.sourceAccess, []));
      current();
      const admitted = control.admitComposedInferSources(selected.occurrence,
        [acquiredInfer.captured], [acquiredInfer.sourceEvidence], authorityScopeCid,
        acquiredInfer.captureStartedAt, acquiredInfer.captureCompletedAt);
      directRequestModel.assertRuntimeCurrent();
      // The module compiled this prefix once before adoption. Read its SAME
      // native Run/Request original; the early selection intentionally has no
      // independently prepared segments. No Plan alias is recreated in JS.
      composedInput = {occurrence: selected.occurrence,
        prefix: checked(moon.clientProgramInstalledManagedRunModelInputPrefix(
          acquiredInfer.managedRun, preparedProgram)), inputs: [], sources: admitted};
      originalPreparation = directRequestModel.prepareRead();
    }
    if (originalInstallation !== undefined) {
      // Custody exists before the first issuer. A failed issuer is atomic;
      // once scope is returned, record it before read construction can fail.
      // These fixed installation values must have the reviewed initial/full
      // phase basis. Presence or passing Common support checks is not proof.
      let scope;
      if (requestModel !== undefined) {
        // The existing Host bag retained/adopted this SAME Scope before
        // dispatch. Taking it creates no Scope or independent Run admission.
        scope = requestModel.scope;
        if (!requestComposed) requestModel.taken = true;
      } else {
        try {
          assertOriginalRuntime();
          scope = control.beginCheckedClientInferOriginalReadScope(plan.compiled,
            plan.runDefinition, selected.graph,
            {...originalInstallation.bootstrap, quantityCapacity: selected.quantityCapacity});
        } catch (error) {
          originalReadPhysicalReleased = true;
          originalReadSettled = true;
          originalScopeReleased = true;
          throw error;
        }
      }
      originalPreparation = {compiled: plan.compiled, runDefinition: plan.runDefinition,
        control, scope, read: undefined,
        nodeInstallation: originalInstallation.nodeInstallation,
        metadataInstallation: originalInstallation,
        readRetainedBytes: originalInstallation.nodeInstallation.layout.retained_bytes,
        readExecutionBytes: originalInstallation.nodeInstallation.layout.execution_bytes,
        modelRetainedBytes: originalInstallation.modelRetainedBytes,
        modelExecutionBytes: originalInstallation.modelExecutionBytes,
        // A projection of this SAME existing Execution, not another physical
        // cleanup owner or a stop Boolean. Constructor refusal creates no child.
        physicalCustody: Object.freeze({
          close: () => operation === undefined ? true : operation.close(),
          cleanup: () => operation === undefined ? true : operation.cleanup(),
          cleanupPending: () => operation?.cleanupPending() ?? false})};
      const prepareRead = () => {
        try {
          if (originalScopeReleased || originalReadStopped || originalPreparation === undefined) {
            throw new TypeError('InstalledInferOriginalPreparationRetired');
          }
          assertOriginalRuntime();
          if (requestModel !== undefined) requestModel.readAttempted = true;
          originalPreparation.read = control.prepareCheckedClientInferNodeReadLayout(
            plan.compiled, plan.runDefinition, selected.graph, scope,
            originalInstallation.nodeInstallation);
          if (requestModel !== undefined) {
            requestModel.read = originalPreparation.read;
            assertOriginalRuntime();
            if (requestModel.scope !== scope || requestModel.compiled !== plan.compiled ||
                requestModel.runDefinition !== plan.runDefinition || requestModel.graph !== selected.graph ||
                requestModel.read !== originalPreparation.read || requestModel.scopeFinished || requestModel.closed) {
              throw new TypeError('InvalidInstalledRequestModelPreparation');
            }
          }
        } catch (cause) {
          if (requestModel !== undefined) requestModel.readFailure = cause;
          throw cause;
        } finally {if (originalPreparation !== undefined) Object.freeze(originalPreparation);}
      };
      try {
        // Retain this SAME Scope before runtime binding. The read snapshot
        // must follow an overlapping Content prefix's Ledger changes.
        if (requestModel !== undefined) assertOriginalRuntime();
        runtimeBorrow = selected.bindTrustedRuntimeScope(scope, plan.compiled,
          plan.runDefinition, selected.graph);
        assertOriginalRuntime();
        if (requestModel !== undefined && (selected.serializationGraph !== undefined || requestComposed)) {
          prepareDeferredOriginalRead = prepareRead;
        } else prepareRead();
      } catch (cause) {
        if (requestModel !== undefined) requestModel.readFailure = cause;
        Object.freeze(originalPreparation);
        throw cause;
      }
    }
    if (requestComposed) {
      const model = requestModel, managed = model.managed;
      const liveModel = () => {
        assertOriginalRuntime();
        if (requestModel !== model || model.closed || model.scopeFinished ||
            model.managed !== managed || managed.closed || managed.value !== acquiredInfer.managedRun ||
            model.graph !== selected.graph || model.scope !== originalPreparation?.scope) {
          throw new TypeError('InvalidInstalledRequestModelPreparation');
        }
      };
      const original = Object.freeze({...originalPreparation, preparationHolder, selection: selected,
        component: model.component, assertRuntimeCurrent: assertOriginalRuntime,
        retain() {
          liveModel();
          if (model.taken || model.readAttempted) throw new TypeError('InstalledInferOriginalPreparationRetired');
          model.taken = true;
        },
        prepareRead() {
          liveModel();
          if (!model.taken || prepareDeferredOriginalRead === undefined) {
            throw new TypeError('InstalledInferOriginalPreparationRetired');
          }
          const prepare = prepareDeferredOriginalRead;
          prepareDeferredOriginalRead = undefined;
          prepare();
          return originalPreparation;
        },
        retainOperation(value) {
          liveModel();
          if (operation !== undefined || model.component.operation() !== value) {
            throw new TypeError('ForeignComposedInferCompletion');
          }
          operation = value;
        },
        openCapturedHost(captures) {
          liveModel();
          if (!model.taken || model.hostAttempted || captures.length !== 1 ||
              typeof moon.clientProgramOpenInstalledManagedCaptureHost !== 'function') {
            throw new TypeError('InstalledComposedInferHostUnavailable');
          }
          model.hostAttempted = true;
          return checked(moon.clientProgramOpenInstalledManagedCaptureHost(managed.value,
            preparedProgram, managed.request, [captures[0].capture.source()]));
        },
        retire: retireOriginalPreparation});
      return runInstalledComposedInfers({moon, control, preparedProgram, plan,
        selected: {components: [selected]}, store, principalId, signal,
        retainExecution(value) {
          if (composedExecution !== undefined) throw new TypeError('InstalledComposedInferAlreadyRetained');
          composedExecution = value;
        }, acquiredInfer, replay, beginPhysicalWork, submission, existingModel, modelClaim,
        assertCurrent: () => {assertCurrent?.(); assertOriginalRuntime();}, modelController,
        inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor, sourceAdapterFor,
        namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
        registry, values, fragment, ordered, computeConfigurations, originalPreparation: original});
    }
    if (restoredInput?.capturedContent !== undefined) {
      if (typeof prepareKeyedRecovery !== 'function' || typeof runContent?.recoverKeyed !== 'function') {
        throw new Error('InstalledCapturedContentRecoveryUnavailable');
      }
      receivingKeyed = await prepareKeyedRecovery({preparedProgram, plan, submission});
      const frame = await runContent.recoverKeyed({...receivingKeyed, preparedProgram, plan, store,
        principalId, signal, modelController, inputToken: token, retainExecution(child) {
          if (keyedContentChild !== undefined) throw new TypeError('KeyedContentChildAlreadyRetained');
          keyedContentChild = child;
        }});
      if (selected.serializationGraph === undefined) restoredReferenceIssuer = frame.referenceIssuer;
    }
    if (keyed) {
      if (restoredInput !== undefined) {
        receivingKeyed ??= await prepareKeyedRecovery({preparedProgram, plan, submission});
        keyedInput = {occurrence: selected.occurrence, prefix: selected.computePrefix,
          ledger: receivingKeyed.ledger};
      } else {
        if (acquiredContent?.keyedObservation === undefined || acquiredContent.keyedLookup === undefined ||
            acquiredContent.ledger === undefined || acquiredInfer !== undefined) {
          throw new Error('InstalledKeyedInferInputUnavailable');
        }
        const {captured, keyedObservation} = acquiredContent;
        const sources = checked(moon.clientProgramAdmitComposedInferSources(selected.occurrence,
          [captured.capture.source()], [captured.identity], [captured.requirement],
          [moon.strategyRunEvidenceJson(captured.logicalInput)], [acquiredContent.sourceEvidenceWire],
          acquiredContent.authorityScopeCid, acquiredContent.captureStartedAt,
          acquiredContent.captureCompletedAt, keyedObservation.observation));
        keyedInput = {occurrence: selected.occurrence, prefix: selected.computePrefix,
          sources, ledger: acquiredContent.ledger,
          capturedRecovery: acquiredContent.keyedContent?.recoveryInventory(),
          capturedBinding: acquiredContent.keyedContent?.sourceBinding};
      }
    }
    if (selected.serializationGraph !== undefined) {
      const method = restoredInput === undefined ? 'generate' : 'recover';
      if (typeof runContent?.[method] !== 'function' || acquiredInfer !== undefined) {
        throw new Error('InstalledGeneratedContentInputUnavailable');
      }
      const generated = await runContent[method]({preparedProgram, plan, store,
        principalId, signal, acquiredContent, restoredInput, retainExecution(child) {
          if (contentChild !== undefined) throw new TypeError('ContentChildAlreadyRetained');
          contentChild = child;
        }});
      if (restoredInput === undefined) sources = generated.sourceEvidence;
      serializedInput = {control, compiled: plan.compiled, definition: plan.runDefinition,
        generation: generated.generation,
        capturedRecovery: generated.capturedContentRecovery,
        capturedBinding: generated.capturedContentBinding,
        recovery: generated.recovery};
    }
    if (originalInstallation !== undefined && (originalScopeReleased || originalReadStopped ||
        originalPreparation === undefined)) throw new TypeError('InstalledInferOriginalPreparationRetired');
    if (prepareDeferredOriginalRead !== undefined) {
      const prepareRead = prepareDeferredOriginalRead;
      prepareDeferredOriginalRead = undefined;
      prepareRead();
    }
    operation = openNodeInferOperation({moon, preparedProgram,
      step: selected.step, graph: selected.graph, registry, values, fragment, ordered, signal,
      acquiredInput: restoredInput === undefined && directRequestModel === undefined ? acquiredInfer?.input : undefined,
      composedInput,
      restoredInput, serializedInput, restoredReferenceIssuer, keyedInput,
      durableCalls: true, computeSuffix: selected.computeSuffix,
      observeProgress: () => faultInjection?.('infer_execution_advanced', {}),
      provider: selected.provider, quantityCapacity: selected.quantityCapacity,
      physicalPreflight: selected.physicalPreflight, egressAdmission: selected.egressAdmission,
      assertRuntimeCurrent: restoredRequestModel?.assertRuntimeCurrent ?? directRequestModel?.assertRuntimeCurrent ??
        (originalInstallation === undefined ? undefined : assertOriginalRuntime),
      originalPreparation: restoredRequestModel === undefined ? originalPreparation : undefined,
      restoredPreparation: restoredRequestModel === undefined ? undefined : originalPreparation,
      ioNotification: (composedInput === undefined || directRequestModel !== undefined || restoredRequestModel !== undefined) &&
        selected.entryPersistence === 'async' ? createInferIoNotification() : undefined,
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
        assertOriginalRuntime();
        const boundary = await operation.run();
        assertOriginalRuntime();
        if (boundary?.status === 'waiting') {
          if (continuation === undefined) {
            continuation = await modelController.open({operation, preparedCallSet: boundary.preparedCallSet,
              plan, selected, principalId, declaredResults, submission, signal,
              existing: existingModel, inputToken: token, claim: modelClaim,
              originalPreparation,
              ...(sourceContinuation === undefined || restoredInput !== undefined ? {}
                : {sourceContinuation: await sourceContinuation.retainAll()})});
            captureOwner.configureModelJournal({observe: continuation.observe, entry: continuation.entry});
            // Saved/unknown records first re-enter the same normal owner without
            // any fresh permission. A still-unsent slot yields Waiting again.
            if (existingModel !== undefined) continue;
          }
          const decision = await continuation.authorize();
          assertOriginalRuntime();
          if (decision.status === 'waiting_checkpoint') return decision;
          if (originalPreparation!==undefined) {
            // Same actual journal now has the original CallSet. Complete its
            // saved Resource cut and nominal fence removal before next advance
            // can create an Entry. Authorization and physical send stay separate.
            await continuation.prepareOriginalResourcesForDispatch();
            assertOriginalRuntime();
          }
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
  run.sourceOccurrence = (prepared, index) => {
    const coordinates = selections.get(prepared)?.sourceCoordinates?.[index];
    return coordinates === undefined ? undefined
      : Object.freeze({stage: coordinates[0], input: coordinates[1], task: coordinates[2]});
  };
  run.prepareAcquiredLedger = ({preparedProgram, plan, sourceCapacity, sourceCapacities}) => {
    control.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const selected = selections.get(preparedProgram);
    const complete = Array.isArray(selected?.components);
    const capacities = sourceCapacities ?? [sourceCapacity];
    if (selected?.localMock) {
      if (selected.graph !== plan.inferGraph || typeof prepareOriginalMockRun !== 'function') {
        throw new TypeError('InstalledModelSourcePreparationUnavailable');
      }
      const original = prepareOriginalMockRun(preparedProgram, plan);
      if (original?.control !== control || original.compiled !== plan.compiled ||
          original.runDefinition !== plan.runDefinition || typeof original.prepareAcquiredLedger !== 'function') {
        throw new TypeError('InvalidInstalledMockModelPreparation');
      }
      return original.prepareAcquiredLedger(capacities, registry, values, fragment, ordered);
    }
    if (selected?.graph !== plan.inferGraph || !complete && selected.occurrence === undefined || selected.serializationGraph !== undefined ||
        !Array.isArray(capacities) || capacities.length !== moon.clientProgramAcquisitionCount(preparedProgram) ||
        capacities.length < 1 || capacities.length > 2 ||
        typeof prepareOriginalModelRun !== 'function' ||
        typeof moon.clientProgramInstalledManagedRunPrepareLedger !== 'function') {
      throw new TypeError('InstalledModelSourcePreparationUnavailable');
    }
    const model = prepareOriginalModelRun(preparedProgram, plan, selected), managed = model?.managed;
    if (model?.closed || model?.scopeFinished || model?.taken || model?.readAttempted ||
        model?.selection !== selected || (complete ? model?.components?.some(member =>
          member.component === undefined || member.taken || member.readAttempted || member.read !== undefined) : model?.component === undefined) ||
        model?.graph !== selected.graph || model?.compiled !== plan.compiled ||
        model?.runDefinition !== plan.runDefinition ||
        managed?.closed || managed?.value === undefined || capacities.some(value => value?.managedRun !== managed.value)) {
      throw new TypeError('InvalidInstalledRequestModelPreparation');
    }
    if (model.sourceLedgerAttempted) {
      if (Object.hasOwn(model, 'sourceLedgerFailure')) throw model.sourceLedgerFailure;
      throw new TypeError('InstalledModelSourceLedgerAlreadyBorrowed');
    }
    const original = managed.value, request = managed.request;
    model.sourceLedgerAttempted = true;
    try {
      const ledger = checked(moon.clientProgramInstalledManagedRunPrepareLedger(original,
        preparedProgram, request, capacities.map(value => value.capacity), capacities.map(value => value.transferBytes),
        capacities.map(value => value.executionBytes), registry, values, fragment, ordered));
      // This is the original parent's Ledger getter, with no new child. A
      // callback that retires/replaces its record cannot resurrect that alias.
      if (model.closed || model.scopeFinished || model.managed !== managed || managed.closed ||
          managed.value !== original || managed.request !== request || model.selection !== selected ||
          model.compiled !== plan.compiled || model.runDefinition !== plan.runDefinition) {
        throw new TypeError('InvalidInstalledRequestModelPreparation');
      }
      model.sourceLedger = ledger;
      return ledger;
    } catch (cause) {
      if (!model.closed && model.managed === managed) model.sourceLedgerFailure = cause;
      throw cause;
    }
  };
  run.prepareKeyedLedger = ({preparedProgram, plan, direct, acquisition, capacity, capturedContent = false}) => {
    control.checkClientCompiledRunOwner(plan.compiled, preparedProgram);
    const selected = selections.get(preparedProgram);
    if (selected?.graph !== plan.inferGraph || selected.occurrence === undefined ||
        selected.serializationGraph !== undefined || selected.components !== undefined) {
      throw new TypeError('InstalledKeyedInferSelectionMissing');
    }
    const ledger = moon.clientProgramPrepareKeyedInferCapturedLedger(preparedProgram,
      selected.occurrence, direct.capacity, acquisition, capacity.capacity,
      [direct.transferBytes, capacity.transferBytes], [direct.executionBytes, capacity.executionBytes],
      capacity.maxBytes, capacity.maxWork, registry, values, fragment, ordered, capturedContent);
    if (ledger === undefined) throw new TypeError('InstalledKeyedInferCapacityUnavailable');
    return ledger;
  };
  return run;
}

// Installed physical composition of the checked Infer, original per-call
// journal/custody and publication owners. No JS slot scheduler is introduced.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {projectInferEvidence} from './infer-evaluation-evidence.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {publishCompletedEffectFreeRun} from '../host-common/completed-run-publication.mjs';
import {openNodeInferOperation} from './infer-operation.mjs';
import {inferTaskPublicationPlan} from './local-values-plan.mjs';
import {inferPublicationExecution} from './infer-result-publication.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';
import {createInferIoNotification} from './infer-io-notification.mjs';
import {selectedInferOriginalCurrentStateCodec,
  selectedInferOriginalPublicationCapacity} from './infer-original-installation.mjs';

export function installNodeInferRun({moon, core, registry, values, fragment, ordered, selections,
  namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection, modelController, inferEvidence,
  checkpoints, prepareAcquisition, sourceAccessFor, runContent, prepareKeyedRecovery,
  prepareOriginalMockRun, prepareOriginalModelRun,
  computeConfigurations = {}}) {
  const control = core.publicationControl;
  const run = async ({preparedProgram, plan, store, principalId, signal,
    retainExecution, acquiredInfer, acquiredContent, replay = false, beginPhysicalWork = () => {},
    submission, existingModel, modelClaim, assertCurrent, originalPreparation}) => {
    const selected = selections.get(preparedProgram);
    if (selected === undefined || selected.graph !== plan.inferGraph) {
      throw new Error('InstalledInferSelectionMissing');
    }
    if (selected.localMock) {
      const sourceFree = moon.clientProgramAcquisitionCount(preparedProgram) === 0;
      if (sourceFree && originalPreparation === undefined &&
          typeof prepareOriginalMockRun === 'function') {
        originalPreparation = prepareOriginalMockRun(preparedProgram, plan);
      }
      if (originalPreparation?.control !== control || originalPreparation.compiled !== plan.compiled ||
          originalPreparation.runDefinition !== plan.runDefinition ||
          (sourceFree ? acquiredInfer !== undefined || typeof originalPreparation.openSourceFreeHost !== 'function'
            : acquiredInfer?.sources?.length !== 2)) {
        throw new TypeError('InvalidInstalledMockModelPreparation');
      }
      return runInstalledComposedInfers({moon, control, preparedProgram, plan,
        selected: {components: [selected]}, store, principalId, signal, retainExecution,
        acquiredInfer, replay, beginPhysicalWork, submission, existingModel, modelClaim, assertCurrent,
        modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor,
        namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
        registry, values, fragment, ordered, computeConfigurations, originalPreparation});
    }
    const originalInstallation = selected.originalReadInstallation;
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
        (originalPreparation !== undefined || acquiredInfer !== undefined || replay ||
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
          requestModel.taken || requestModel.readAttempted || requestModel.read !== undefined) {
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
        modelController, inferEvidence, checkpoints, prepareAcquisition, sourceAccessFor,
        namespaceId, authorityScopeCid, storeAuthorityCid, now, faultInjection,
        registry, values, fragment, ordered, computeConfigurations});
    }
    const keyed = selected.occurrence !== undefined && selected.serializationGraph === undefined &&
      checked(moon.clientProgramSelectSingleKeyedAcquisition(preparedProgram)) !== undefined;
    // The current installed read/layout supplier has no adopted Content overlap.
    // Refuse before generation/recovery or keyed input construction; support
    // checks and a visible child Ledger are not original funding authority.
    if (keyed || acquiredContent !== undefined ||
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
    let operation, captureOwner, continuation, evidenceCopy, contentChild, keyedContentChild,
      serializedInput, restoredReferenceIssuer, keyedInput, receivingKeyed, prepareDeferredOriginalRead;
    let captureCloseAttempted = false, captureReleased = false;
    let continuationCloseAttempted = false, continuationReleased = false;
    // These are phases of the same existing retained custody, not another
    // cleanup Owner. A failed physical close keeps this exact original record.
    let originalReadStopped = false, originalReadCloseAttempted = false;
    let originalReadPhysicalReleased = originalPreparation === undefined && originalInstallation === undefined;
    let originalReadSettled = originalReadPhysicalReleased;
    let originalScopeReleased = originalReadPhysicalReleased;
    let originalCleanupFlight;
    const cleanupPending = () => evidenceCopy?.cleanupPending() === true || !captureReleased ||
      continuation !== undefined && !continuationReleased ||
      contentChild?.cleanupPending() === true || keyedContentChild?.cleanupPending() === true ||
      !originalReadSettled || !originalScopeReleased;
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
          if (operation?.publicationCapacityPending?.()) {
            // Physical child/alias retirement is observed by its existing
            // custody. Release this operation's exact original byte borrow,
            // not a Bool-derived grant, before the pinned parent Model cleanup.
            if (!await captureOwner.custody.retirePublication()) return false;
            if (!operation.releaseOriginalPublicationCapacity()) return false;
          }
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
      if (originalPreparation !== undefined && captureReleased &&
          (continuation === undefined || continuationReleased)) {
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
          if (requestModel !== undefined) requestModel.read = undefined;
        }
        // All actual children of this fresh single-component custody have
        // acknowledged cleanup. The original Core census still refuses any
        // other live child; read settlement alone cannot release bootstrap.
        originalScopeReleased = (runtimeBorrow === undefined
          ? control.finishCheckedClientInferOriginalReadScope(plan.compiled,
            plan.runDefinition, selected.graph, originalPreparation.scope, true)
          : selected.finishTrustedRuntimeScope(originalPreparation.scope, runtimeBorrow,
            plan.compiled, plan.runDefinition, selected.graph)) === true;
        if (originalScopeReleased) {
          if (requestModel !== undefined) {
            requestModel.scopeFinished = true;
            requestModel.read = undefined;
            requestModel = undefined;
          }
          runtimeBorrow = undefined;
          originalPreparation = undefined;
        }
      }
      return !cleanupPending();
    };
    const cleanup = () => {
      // An original cleanup flight belongs to this same retained custody.
      // Concurrent close/retry callers must not overlap physical close or
      // settle its read twice. The former route is otherwise unchanged.
      if (originalReadStopped && originalScopeReleased) return originalCleanupFlight;
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
        requestModel.taken = true;
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
        if (requestModel !== undefined && selected.serializationGraph !== undefined) {
          prepareDeferredOriginalRead = prepareRead;
        } else prepareRead();
      } catch (cause) {
        if (requestModel !== undefined) requestModel.readFailure = cause;
        Object.freeze(originalPreparation);
        throw cause;
      }
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
      acquiredInput: restoredInput === undefined ? acquiredInfer?.input : undefined,
      restoredInput, serializedInput, restoredReferenceIssuer, keyedInput,
      durableCalls: true, computeSuffix: selected.computeSuffix,
      observeProgress: () => faultInjection?.('infer_execution_advanced', {}),
      provider: selected.provider, quantityCapacity: selected.quantityCapacity,
      physicalPreflight: selected.physicalPreflight, egressAdmission: selected.egressAdmission,
      assertRuntimeCurrent: originalInstallation === undefined ? undefined : assertOriginalRuntime,
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
        assertOriginalRuntime();
        const boundary = await operation.run();
        assertOriginalRuntime();
        if (boundary?.status === 'waiting') {
          if (continuation === undefined) {
            continuation = await modelController.open({operation, preparedCallSet: boundary.preparedCallSet,
              plan, selected, principalId, declaredResults, submission, signal,
              existing: existingModel, inputToken: token, claim: modelClaim,
              originalPreparation});
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

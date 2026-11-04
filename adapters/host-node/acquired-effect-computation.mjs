// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {runtimeField} from '../host-common/compiler-binding.generated.mjs';
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan,
  acquiredInferEffectPublicationPlan, sourceFreeInferEffectPublicationPlan,
  sourceFreeContentEffectPublicationPlan} from './local-values-plan.mjs';
import {selectAcquiredEffectSources} from './acquired-effect-sources.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openNodeComposedInferProvider} from './infer-operation.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';
import {refusedEffectPreparation} from '../host-common/effect-preparation-result.mjs';
import {ledgerUsageDiagnostic} from '../host-common/runtime-core.mjs';

export async function openAcquiredEffectComputation({moon, owner, acquired, managedRun,
  sourceProfile, registry, values, fragment, ordered, sourceAccess,
  signal, now, retainComputationOwner, infer, store, principalId, faultInjection,
  observe, sourceContinuation, computeConfigurations = {}, withComputePauseHandler, modelController,
  submission, existingModel, modelClaim, parentResume, modelJournalPort, contentRun,
  assertUpdateSelectionCurrent, assertContinuationCurrent, originalPreparation, originalModelPlan,
  originalModelComponent, originalModelSelection, originalContent}) {
  const preparedOriginal = acquired.prepared, requestOriginal = acquired.requestIdentity;
  const count = moon?.clientProgramEffectAcquisitionCount?.(acquired.prepared);
  const sourceFree = count === 0;
  const multiple = count === 2;
  const serializations = moon?.clientProgramEffectSerializationOccurrences?.(acquired.prepared) ?? [];
  if (typeof retainComputationOwner !== 'function' ||
      ![0, 1, 2].includes(count) ||
      sourceFree && infer === undefined && serializations.length === 0 ||
      !sourceFree && sourceProfile === undefined) {
    throw new TypeError('InvalidAcquiredEffectComputationPort');
  }
  const captures = [];
  let execution;
  let checkedHost;
  let recovery;
  let inferCapture;
  let inferOperation;
  let modelContinuation;
  let modelToken;
  let modelPlan = originalModelPlan;
  let modelRecord = existingModel;
  let ledger;
  let contentFamily, contentFamilyCleanup, contentPlan, contentRecovery, restoredModelInput;
  const diagnostic = diagnosticObserver(observe);
  const observeUsage = (name, facts = {}) => {
    const usage = ledger === undefined ? checkedHost === undefined ? undefined
      : moon.strategyHostUsage(moon.clientProgramLocalEffectHostRuntime(checkedHost))
      : moon.clientProgramMultiCapturedLedgerUsage(ledger);
    if (usage === undefined) return;
    diagnostic(name, {...facts, resourceUsage: ledgerUsageDiagnostic(usage)});
  };
  let unresolved = false;
  let pending = true;
  let settled = false;
  let closed = false;
  let originalPreparationRetained = false;
  const originalCurrent = () => {
    signal?.throwIfAborted();
    if (closed) throw Object.assign(new Error('ClientRunCancellationRequested'),
      {code: 'ClientRunCancellationRequested'});
    if (assertUpdateSelectionCurrent === undefined) return;
    const changed = () => { throw refusedEffectPreparation(Object.assign(
      new Error('InstalledEffectOriginalSelectionChanged'),
      {code: 'InstalledEffectOriginalSelectionChanged'})); };
    if (typeof assertUpdateSelectionCurrent !== 'function') changed();
    const result = assertUpdateSelectionCurrent();
    if (typeof result?.then === 'function') {
      void Promise.resolve(result).catch(() => {});
      changed();
    }
  };
  const current = () => {
    originalCurrent();
    assertContinuationCurrent?.();
  };
  let inferCloseAttempted = false, inferReleased = false;
  let modelCloseAttempted = false, modelReleased = false;
  const inferCleanupPending = () => (inferCapture !== undefined || inferOperation !== undefined) && !inferReleased ||
    modelContinuation !== undefined && !modelReleased;
  const cleanupInfer = async (includeContinuation = true) => {
    let failure, failed = false;
    if ((inferCapture !== undefined || inferOperation !== undefined) && !inferReleased) {
      const recover = inferCloseAttempted;
      inferCloseAttempted = true;
      try {
        const child = inferCapture?.custody ?? inferOperation;
        if (originalPreparation !== undefined && inferOperation?.publicationCapacityPending?.()) {
          if (!await inferCapture.custody.retirePublication() ||
              !inferOperation.releaseOriginalPublicationCapacity()) return false;
        }
        const result = await (recover ? child.cleanup() : child.close());
        inferReleased = result !== false && child.cleanupPending() === false;
      } catch (error) { failure = error; failed = true; }
    }
    if (includeContinuation && modelContinuation !== undefined && !modelReleased) {
      const recover = modelCloseAttempted;
      modelCloseAttempted = true;
      try {
        const result = await (recover ? modelContinuation.cleanup() : modelContinuation.close());
        modelReleased = result !== false && modelContinuation.cleanupPending() === false;
      } catch (error) { if (!failed) { failure = error; failed = true; } }
    }
    if (failed) throw failure;
    return ((inferCapture === undefined && inferOperation === undefined) || inferReleased) &&
      (!includeContinuation || modelContinuation === undefined || modelReleased);
  };
  const custody = Object.freeze({
    async close() {
      closed = true;
      // A physical owner's cleanup, not another Compute call, recovers a
      // failed close. Retain the captured source until consumers are gone.
      let failure;
      try { await (execution ?? recovery)?.close(); }
      catch (error) { failure = error; }
      try { if (settled) await cleanupInfer(); }
      catch (error) { failure ??= error; }
      try { if (settled) await (contentFamilyCleanup ?? contentFamily)?.close(); }
      catch (error) { failure ??= error; }
      try { if (settled) await contentRecovery?.close(); }
      catch (error) { failure ??= error; }
      if (failure !== undefined) observeUsage('effect_computation_cleanup_pending');
      if (failure !== undefined) throw failure;
    },
    async cleanup() {
      if (!pending) return true;
      if (!closed || !settled || unresolved) return false;
      if (!await cleanupInfer()) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      const familyCleanup = contentFamilyCleanup ?? contentFamily;
      if (familyCleanup !== undefined && (!await familyCleanup.cleanup() ||
          familyCleanup.cleanupPending())) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      if (contentRecovery !== undefined && (!await contentRecovery.cleanup() ||
          contentRecovery.cleanupPending())) return false;
      const physical = execution ?? recovery;
      if (physical !== undefined) {
        if (await physical.cleanup() === false ||
            physical.cleanupPending() !== false) {
          observeUsage('effect_computation_cleanup_pending');
          return false;
        }
      }
      while (captures.length > 0) {
        await captures[0].close();
        captures.shift();
      }
      if (originalPreparationRetained) {
        if (await originalPreparation.retire() !== true) return false;
        originalPreparationRetained = false;
      }
      if (checkedHost !== undefined &&
          !moon.clientProgramRefreshAcquiredEffectCleanup(checkedHost)) {
        observeUsage('effect_computation_cleanup_pending');
        return false;
      }
      execution = undefined;
      recovery = undefined;
      await sourceContinuation?.close();
      if (modelToken !== undefined) modelController.release(modelToken);
      pending = false;
      observeUsage('effect_computation_cleanup_completed');
      return true;
    },
    cleanupPending: () => pending,
  });
  // Even preparation can fail. The dispatch owner receives custody before
  // the first asynchronous boundary or provider operation.
  retainComputationOwner(custody);
  try {
    if (originalPreparation !== undefined) {
      originalPreparation.retain();
      originalPreparationRetained = true;
    }
    current();
    const readPlan = moon.clientProgramInstalledEffectManagedOperationPlan;
    if (managedRun === undefined || typeof readPlan !== 'function' ||
        typeof moon.clientProgramInstalledEffectManagedHostOpen !== 'function') {
      throw new Error('InstalledEffectPlanUnavailable');
    }
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    const operationPlan = checked(Reflect.apply(readPlan, moon,
      [managedRun, preparedOriginal, requestOriginal]));
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    current();
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    if (acquired.queryTimePreparation !== undefined) {
      if (typeof moon.clientProgramEffectRunQueryTimeMatches !== 'function' ||
          typeof moon.clientProgramEffectRunQueryTimeMatches !== 'function' ||
          moon.clientProgramEffectRunQueryTimeMatches(owner,
            acquired.queryTimePreparation, acquired.requestIdentity) !== true) {
        throw new Error('OriginalQueryTimeUnavailable');
      }
    }
    if (assertUpdateSelectionCurrent !== undefined && infer !== undefined) {
      const originalInfer = infer;
      if (typeof originalInfer.observeAccount !== 'function') {
        throw new Error('InstalledInferAuthorityUnavailable');
      }
      // The same dispatch admission re-observes this actual account at its
      // final send gate, including after Entry persistence. Preserve its
      // original result; the installed selection assertion adds no permit.
      infer = Object.freeze({...originalInfer, observeAccount() {
        current();
        const account = originalInfer.observeAccount();
        current();
        return account;
      }});
    }
    const selectedSources = selectAcquiredEffectSources({moon,
      preparedEffect: acquired.prepared, sourceProfile, registry, values, fragment, ordered,
      queryTimePreparation: acquired.queryTimePreparation, requestIdentity: acquired.requestIdentity,
      managedPlan: operationPlan, managedRun});
    const singleSourceAccess = sourceAccess ?? selectedSources[0]?.adapter.sourceAccess;
    if (infer !== undefined) {
      if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
      const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
      const taskIndex = runtimeField(moon.clientProgramInferPlanBoundary(infer.graph), 0);
      modelRecord ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
      if (modelRecord !== undefined) {
        current();
        modelToken = await modelController.prime(modelRecord);
        current();
        if (!sourceFree && sourceContinuation?.restoringModel !== true) {
          throw new Error('ModelSourceCaptureRestoreRequired');
        }
      }
    }
    const sources = [];
    for (const {adapter, occurrence} of selectedSources) {
      current();
      const baseAccess = multiple ? adapter.sourceAccess : singleSourceAccess;
      const access = sourceContinuation?.accessFor(baseAccess, occurrence) ?? baseAccess;
      current();
      const preparedSource = await adapter.prepare({
        preparedEffect: acquired.prepared, registry, values, fragment, ordered,
        queryTimePreparation: acquired.queryTimePreparation, requestIdentity: acquired.requestIdentity,
        sourceAccess: access, occurrence, managedRun});
      current();
      sources.push({adapter, access, preparedSource, occurrence});
    }
    await sourceContinuation?.prepared(sources);
    current();
    const captureStartedAt = sourceContinuation?.times().captureStartedAt ?? now();
    let captureCompletedAt;
    const evidence = [];
    let component;
    if (serializations.length > 0 && originalContent !== undefined) {
      if (multiple || serializations.length !== 1 ||
          infer !== undefined && (modelPlan === undefined || originalContent.plan?.compiled !== modelPlan.compiled)) {
        throw new TypeError('UnsupportedInstalledContentEffectClosure');
      }
      contentPlan = originalContent.plan;
      contentFamily = originalContent.family;
      contentFamilyCleanup = contentFamily;
      contentFamily.bindExecution({prepared: acquired.prepared, plan: contentPlan, store, principalId, signal});
    } else if (serializations.length > 0) {
      if (multiple || serializations.length !== 1 ||
          typeof contentRun?.effectFamily !== 'function' ||
          !sourceFree && typeof sources[0]?.adapter.ledgerCapacity !== 'function') {
        throw new TypeError('UnsupportedInstalledContentEffectClosure');
      }
      // Both children borrow this exact compiled Run, not two independently
      // reconstructed wrappers with merely equal wire identities.
      const compiled = infer === undefined
        ? acquired.control.adoptCheckedClientEffectSerializationRun(acquired.allowed, acquired.runDefinition)
        : acquired.control.adoptCheckedClientEffectInferRun(acquired.allowed, acquired.runDefinition,
          acquired.resultDataPolicy, acquired.resultDataPolicyLimits);
      if (infer !== undefined) {
        modelPlan = {compiled, runDefinition: acquired.runDefinition};
      }
      contentPlan = {kind: 'effect', compiled, runDefinition: acquired.runDefinition,
        inferGraph: infer?.graph,
        serializationGraph: acquired.control.compiledSerializationGraph(compiled)};
      let restored;
      if (modelToken !== undefined) {
        restoredModelInput = {
          token: modelToken, snapshot: modelToken.snapshot,
          sendMask: modelController.state(modelRecord.inventory).slots.map(slot => slot.state === 'Unsent'),
          savedScope: modelController.savedScope(modelPlan, acquired.prepared, infer, modelToken),
        };
        current();
        restored = await contentRun.recover({preparedEffect: acquired.prepared,
          plan: contentPlan, store, principalId, signal, restoredInput: restoredModelInput,
          retainExecution(value) { contentRecovery = value; }});
        current();
      }
      contentFamily = contentRun.effectFamily({prepared: acquired.prepared,
        plan: contentPlan, store, principalId, signal, restored,
        retainCleanup(value) {contentFamilyCleanup = value;}});
    }
    const prepareInferComponent = () => {
      current();
      if (infer === undefined) return undefined;
      if (!multiple && !sourceFree && contentFamily === undefined) {
        throw new TypeError('UnsupportedComposedInferSourceClosure');
      }
      const sourceEvidence = evidence.map(value => value.sourceEvidence);
      const admittedSources = sourceFree || contentFamily !== undefined ? undefined
        : acquired.control.admitComposedInferSources(
          infer.occurrence, captures, sourceEvidence, acquired.authorityScopeCid,
          captureStartedAt, captureCompletedAt);
      const compiled = modelPlan?.compiled ?? acquired.control.adoptCheckedClientEffectInferRun(
        acquired.allowed, acquired.runDefinition, acquired.resultDataPolicy,
        acquired.resultDataPolicyLimits);
      const plan = modelPlan ?? {compiled, runDefinition: acquired.runDefinition};
      modelPlan = plan;
      const restoredInput = restoredModelInput ?? (modelToken === undefined ? undefined : {
        token: modelToken, snapshot: modelToken.snapshot,
        sendMask: modelController.state(modelRecord.inventory).slots.map(slot => slot.state === 'Unsent'),
        savedScope: modelController.savedScope(plan, acquired.prepared, infer, modelToken),
      });
      const context = {moon, selected: originalModelSelection ?? infer, sources: admittedSources,
        originalPreparation,
        assertRuntimeCurrent: originalPreparation?.assertRuntimeCurrent,
        ...(contentFamily === undefined ? {} : {generatedInput: {
          generation: () => contentFamily.generation(),
          recovery: () => contentFamily.recovery(),
        }}),
        control: acquired.control, plan, principalId, signal, now, durableCalls: true, restoredInput,
        retainOperation(operation) {
          inferOperation = operation;
          inferCapture = openNodeInferCaptureCustody({moon, control: acquired.control,
            operation, plan, store, storeAuthorityCid: acquired.storeAuthorityCid, durableCalls: true,
            sourceEvidence,
            faultInjection,
            publicationFor: ({issuance, modelEvidence}) =>
              sourceFree ? sourceFreeInferEffectPublicationPlan({acquired,
                compiled, operation, issuance, modelEvidence}) :
              acquiredInferEffectPublicationPlan({acquired, sources: evidence,
                compiled, operation, issuance, modelEvidence,
                captureStartedAt, captureCompletedAt})});
        },
        retainCompleted: () => inferCapture.retainCompleted()};
      return originalModelComponent === undefined ? openNodeComposedInferProvider(context)
        : originalModelComponent.bindOriginal(context);
    };
    // The original plan already selected its configuration/Source capacities.
    // A provider family requiring a different scope cannot acquire a scalar
    // replacement here. Its full plan must have been admitted before capture.
    if (contentFamily !== undefined) component = prepareInferComponent();
    if (!sourceFree) {
      const capacities = sources.map(source => source.adapter.ledgerCapacity(source.preparedSource));
      if (capacities.some(value => value?.managedRun !== managedRun) ||
          typeof moon.clientProgramInstalledEffectManagedRunPrepareLedger !== 'function') {
        throw new Error('ForeignInstalledEffectManagedRun');
      }
      ledger = checked(moon.clientProgramInstalledEffectManagedRunPrepareLedger(managedRun,
        acquired.prepared, acquired.requestIdentity, capacities.map(value => value.capacity),
        capacities.map(value => value.transferBytes), capacities.map(value => value.executionBytes),
        registry, values, fragment, ordered));
    }
    for (const source of sources) {
      current();
      const capacity = source.adapter.ledgerCapacity(source.preparedSource);
      if (capacity?.managedRun !== managedRun) throw new Error('ForeignInstalledEffectManagedRun');
      const acquisition = acquisitionEndHandoff();
      let captured;
      current();
      const admission = await sourceContinuation?.beforeRead(source);
      if (admission?.waiting !== undefined) {
        originalCurrent();
        return Object.freeze({status: 'waiting_checkpoint',
          checkpoint: admission.waiting, cleanupOwner: custody});
      }
      current();
      if (admission?.retained !== undefined) {
        const restored = sourceContinuation.restore(source, admission.retained, ledger);
        captures.push(restored.captured);
        evidence.push(restored);
        continue;
      }
      // A refused fence proves this attempt has not called the adapter.
      // Do not feed it into the adapter's unknown physical-outcome path.
      admission?.enter();
      current();
      try {
        // Only this original adapter call starts a new Source attempt. A
        // retained capture or a refused admission must not invent another.
        diagnostic('acquisition_started', {task: source.occurrence.task,
          selection: source.preparedSource.selection});
        captured = await source.adapter.open({preparedEffect: acquired.prepared,
          registry, values, fragment, ordered, sourceAccess: source.access, signal,
          preparedSource: source.preparedSource, occurrence: source.occurrence,
          ledger, reportAcquisitionFailure: acquisition.retain});
      } catch (error) {
        const ended = acquisition.outcome(error);
        recovery = ended.recovery;
        unresolved = ended.outcome === 'unknown' && recovery === undefined;
        throw error;
      }
      captures.push(captured);
      // Retain physical custody before a post-await refusal. It must still
      // close this acquired source even if its installed owner changed.
      current();
      diagnostic('acquisition_completed', {task: source.occurrence.task,
        acquisition: captured.acquisition});
      current();
      const sourceEvidenceOptions = {
        authorityScopeCid: acquired.authorityScopeCid,
        effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid};
      let sourceEvidence, sourceEvidenceWire;
      if (infer === undefined) {
        sourceEvidenceWire = await captured.issueSourceEvidence(sourceEvidenceOptions);
      } else {
        await captured.prepareSourceEvidenceOriginal(sourceEvidenceOptions);
        current();
        sourceEvidence = acquired.control.takeSourceEvidenceOriginal(captured.capture);
        sourceEvidenceWire = sourceEvidence.wire;
      }
      current();
      evidence.push({captured, sourceEvidenceWire,
        ...(sourceEvidence === undefined ? {} : {sourceEvidence})});
      await sourceContinuation?.captured(source, captured, sourceEvidenceWire,
        captureStartedAt, now());
      current();
    }
    captureCompletedAt = sourceContinuation?.times().captureCompletedAt ?? now();
    if (!sourceFree) contentFamily?.bindCapture(captures[0], {...evidence[0],
      authorityScopeCid: acquired.authorityScopeCid, captureStartedAt, captureCompletedAt});
    // A completed Source does not close a Run containing a generation barrier.
    // Its original Content evidence must be issued by the selected component
    // before publication is prepared; never fill that inventory with [] or
    // claim a Source-only Invocation for the same checked Template.
    let publicationPlan = infer === undefined && serializations.length === 0 ? multiple
      ? acquiredMultiEffectPublicationPlan({acquired, sources: evidence,
        captureStartedAt, captureCompletedAt})
      : acquiredEffectPublicationPlan({acquired, ...evidence[0],
        captureStartedAt, captureCompletedAt}) : undefined;
    if (component === undefined && infer !== undefined) component = prepareInferComponent();
    current();
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    const currentPlan = checked(Reflect.apply(readPlan, moon,
      [managedRun, preparedOriginal, requestOriginal]));
    assertAcquiredEffectOriginal(acquired, preparedOriginal, requestOriginal);
    if (currentPlan !== operationPlan) throw new Error('ForeignInstalledEffectManagedRun');
    checkedHost = checked(moon.clientProgramInstalledEffectManagedHostOpen(managedRun,
      owner, captures.map(value => value.capture.source())));
    if (checkedHost === undefined) {
      throw new Error('InstalledEffectProgramUnsupported');
    }
    // Without a returned Compute owner an exception cannot prove a stop.
    // Keep the responsibility rather than relabeling it as released.
    unresolved = true;
    if (multiple || contentFamily !== undefined) {
      const dag = moon.strategyHostRun(moon.clientProgramLocalEffectHostRuntime(checkedHost));
      for (const [task, captured] of captures.entries()) captured.capture.retainTask(dag, task);
    }
    if ((component !== undefined || contentFamily !== undefined) && typeof withComputePauseHandler !== 'function') {
      throw new TypeError('PhysicalPauseConfigurationMissing');
    }
    const handleModelPause = async boundary => {
        current();
        const operation = component.operation();
        if (operation === undefined || inferCapture === undefined) throw new Error('ModelPauseOwnerMissing');
        if (boundary.status === 'settling') {
          const settlement = operation.pendingSettlement();
          const slot = operation.settlementSlot(settlement);
          const entry = modelContinuation?.entry(slot);
          if (entry === undefined || slot !== boundary.slot) throw new Error('ModelPauseSettlementMismatch');
          current();
          await inferCapture.persistSettlement(settlement, entry);
          current();
          return {action: 'resume'};
        }
        if (boundary.status !== 'waiting') throw new Error('InvalidModelPause');
        if (modelContinuation === undefined) {
          const preparedCallSet = operation.preparedCallSet();
          if (preparedCallSet === undefined) throw new Error('ModelPausePreparedOwnerMissing');
          current();
          const sourceClosure = await sourceContinuation?.retainAll();
          current();
          modelContinuation = await modelController.open({operation, preparedCallSet,
            plan: modelPlan, selected: infer, principalId,
            declaredResults: moon.clientProgramEffectCompilationResultNames(acquired.compilation),
            submission, signal, existing: modelRecord, inputToken: modelToken, claim: modelClaim, parentResume,
            journalPort: modelJournalPort, sourceContinuation: sourceClosure});
          current();
          inferCapture.configureModelJournal({observe: modelContinuation.observe, entry: modelContinuation.entry});
          if (modelRecord !== undefined) return {action: 'resume'};
        }
        current();
        const decision = await modelContinuation.authorize();
        if (decision.status === 'dispatch') {
          current();
          return {action: 'resume'};
        }
        originalCurrent();
        if (decision.status !== 'waiting_checkpoint') throw new Error('InvalidModelPauseDecision');
        // Stop/cleanup the retained Model owner before Local settles its
        // reservation. This handle never calls operation.run or a provider.
        const cleanupHandle = Object.freeze({
          status: () => ({pending: inferCleanupPending()}),
          retry: cleanupInfer,
        });
        return {action: 'waiting_checkpoint', checkpoint: decision.checkpoint,
          cleanupPending: true, cleanupHandle};
      };
    const configurations = component === undefined && contentFamily === undefined ? computeConfigurations
      : withComputePauseHandler(computeConfigurations, async boundary => {
        current();
        // Slots are local to each child. A shared numerical slot must not
        // route a Model settlement into the already-completed Content owner.
        if (contentFamily !== undefined && contentFamily.generation() === undefined) {
          const decision = await contentFamily.handlePause(boundary);
          current();
          return decision;
        }
        if (component !== undefined) return handleModelPause(boundary);
        throw new Error('PhysicalPauseOwnerMissing');
      });
    current();
    execution = await runCapturedEffectComputation(checkedHost,
      {...configurations,
        authorization: multiple ? undefined : singleSourceAccess?.authorization}, signal);
    unresolved = false;
    if (execution.status === 'host-tasks-waiting') {
      originalCurrent();
      return Object.freeze({status: 'waiting_checkpoint', checkpoint: execution.checkpoint,
        execution, checkedHost, cleanupOwner: custody});
    }
    current();
    if (execution.status !== 'host-tasks-completed' && component?.operation()?.physicalStopped()) {
      current();
      await inferCapture.persistStoppedAttempts();
      current();
    }
    if (execution.status !== 'host-tasks-completed' && component !== undefined &&
        modelController.unresolved(acquired.control.runDefinitionRunId(acquired.runDefinition))) {
      return Object.freeze({status: 'needs_reconciliation', modelUnknown: true,
        execution, checkedHost, cleanupOwner: custody});
    }
    if (execution.status !== 'host-tasks-completed') {
      throw component?.failure() ?? execution.failure ?? new Error('InstalledEffectComputationFailed');
    }
    observeUsage('effect_computation_completed', {
      carrierSnapshots: (execution.completed ?? [])
        .filter(task => task.snapshot !== undefined)
        .map(task => ({task: task.task, ...task.snapshot})),
      relationSnapshots: (execution.completed ?? [])
        .filter(task => task.relationSnapshot !== undefined)
        .map(task => ({task: task.task, ...task.relationSnapshot})),
    });
    if (component !== undefined) {
      if (inferCapture === undefined) throw component.failure() ?? new Error('InstalledInferCaptureUnavailable');
      current();
      publicationPlan = (await inferCapture.persist()).plan;
      current();
      if (originalPreparation !== undefined) {
        // The complete immutable publication plan and Store capture now own
        // their evidence. Retire only the original Model aliases/borrow first;
        // Content and the same journal continuation retain their own lifetime.
        const refreshScratch = execution.refreshCompletedScratch;
        if (typeof refreshScratch !== 'function') {
          throw new TypeError('InstalledEffectCompletedScratchUnavailable');
        }
        if (!await cleanupInfer(false)) {
          throw Object.assign(new Error('ClientDispatchCleanupPending'),
            {code: 'ClientDispatchCleanupPending'});
        }
        current();
        // This reconciles actual stopped-provider scratch while preserving
        // successful output/holding custody. It grants no physical close ACK.
        await Reflect.apply(refreshScratch, execution, []);
        current();
      }
      await faultInjection?.('infer_capture_committed', {});
      current();
    }
    if (contentFamily !== undefined && component === undefined) {
      const generation = contentFamily.generation();
      if (generation === undefined) throw new Error('InstalledContentGenerationEvidenceUnavailable');
      publicationPlan = sourceFree
        ? sourceFreeContentEffectPublicationPlan({acquired,compiled:contentPlan.compiled,generation})
        : acquiredEffectPublicationPlan({acquired, ...evidence[0],
          captureStartedAt, captureCompletedAt, content: {...contentPlan, generation}});
    }
    if (publicationPlan === undefined) {
      throw new Error('InstalledContentGenerationEvidenceUnavailable');
    }
    current();
    return Object.freeze({execution, checkedHost, publicationPlan,
      // The original family owns both the issued Reference and its Store
      // bytes through approval. Do not reconstruct a consumer from saved CIDs.
      ...(contentFamily === undefined ? {} : {contentOwner: contentFamily}),
      cleanupOwner: custody});
  } finally {
    settled = true;
  }
}

// The original acquisition/dispatch boundary keeps the same prepared/request
// across the bound getter and its existing outer current callback.
function assertAcquiredEffectOriginal(acquired, prepared, request) {
  if (acquired.prepared !== prepared || acquired.requestIdentity !== request) {
    throw Object.assign(new Error('ForeignInstalledEffectManagedRun'),
      {code: 'ForeignInstalledEffectManagedRun'});
  }
}

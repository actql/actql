// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan,
  acquiredInferEffectPublicationPlan, sourceFreeInferEffectPublicationPlan} from './local-values-plan.mjs';
import {selectAcquiredEffectSources, prepareInstalledAcquiredEffectLedger} from './acquired-effect-sources.mjs';
import {capturedDuckDBConfiguration, capturedDuckDBPhysicalCapacity,
  capturedDuckDBPendingCapacity} from './captured-duckdb-source.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runCapturedEffectComputation} from './entry.mjs';
import {openNodeComposedInferProvider} from './infer-operation.mjs';
import {openNodeInferCaptureCustody} from './infer-capture-custody.mjs';
import {diagnosticObserver} from '../host-common/diagnostic-observer.mjs';

export async function openAcquiredEffectComputation({moon, owner, acquired,
  sourceProfile, registry, values, fragment, ordered, sourceAccess,
  signal, now, retainComputationOwner, infer, store, principalId, faultInjection,
  observe, sourceContinuation, computeConfigurations = {}, withComputePauseHandler, modelController,
  submission, existingModel, modelClaim, parentResume, modelJournalPort, contentRun}) {
  const count = moon?.clientProgramEffectAcquisitionCount?.(acquired.prepared);
  const sourceFree = count === 0;
  const multiple = count === 2;
  if (typeof retainComputationOwner !== 'function' ||
      ![0, 1, 2].includes(count) ||
      sourceFree && infer === undefined ||
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
  let modelPlan;
  let modelRecord = existingModel;
  let ledger;
  let contentFamily, contentPlan, contentRecovery, restoredModelInput;
  const diagnostic = diagnosticObserver(observe);
  const observeUsage = (name, facts = {}) => {
    const usage = ledger === undefined ? checkedHost === undefined ? undefined
      : moon.strategyHostUsage(moon.clientProgramLocalEffectHostRuntime(checkedHost))
      : moon.clientProgramMultiCapturedLedgerUsage(ledger);
    if (usage === undefined) return;
    diagnostic(name, {...facts, resourceUsage: Object.fromEntries([
      'planningWork', 'attempts', 'holdings', 'transferredBytes',
      'reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes',
      'reservedExecutionBytes', 'uncertainTransferBytes',
    ].slice(0, usage.length).map((field, index) => [field, usage[index].toString()]))});
  };
  let unresolved = false;
  let pending = true;
  let settled = false;
  let closed = false;
  let inferCloseAttempted = false, inferReleased = false;
  let modelCloseAttempted = false, modelReleased = false;
  const inferCleanupPending = () => (inferCapture !== undefined || inferOperation !== undefined) && !inferReleased ||
    modelContinuation !== undefined && !modelReleased;
  const cleanupInfer = async () => {
    let failure;
    if ((inferCapture !== undefined || inferOperation !== undefined) && !inferReleased) {
      const recover = inferCloseAttempted;
      inferCloseAttempted = true;
      try {
        const child = inferCapture?.custody ?? inferOperation;
        const result = await (recover ? child.cleanup() : child.close());
        inferReleased = result !== false && child.cleanupPending() === false;
      } catch (error) { failure = error; }
    }
    if (modelContinuation !== undefined && !modelReleased) {
      const recover = modelCloseAttempted;
      modelCloseAttempted = true;
      try {
        const result = await (recover ? modelContinuation.cleanup() : modelContinuation.close());
        modelReleased = result !== false && modelContinuation.cleanupPending() === false;
      } catch (error) { failure ??= error; }
    }
    if (failure !== undefined) throw failure;
    return !inferCleanupPending();
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
      try { if (settled) await contentFamily?.close(); }
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
      if (contentFamily !== undefined && (!await contentFamily.cleanup() ||
          contentFamily.cleanupPending())) {
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
    signal?.throwIfAborted();
    const selectedSources = selectAcquiredEffectSources({moon,
      preparedEffect: acquired.prepared, sourceProfile, registry, values, fragment, ordered});
    const singleSourceAccess = sourceAccess ?? selectedSources[0]?.adapter.sourceAccess;
    if (infer !== undefined) {
      if (modelController === undefined) throw new Error('InstalledModelJournalRequired');
      const runId = acquired.control.runDefinitionRunId(acquired.runDefinition);
      const taskIndex = moon.clientProgramInferPlanBoundary(infer.graph)._0;
      modelRecord ??= modelController.discover(runId).find(record => record.inventory.taskIndex === taskIndex);
      if (modelRecord !== undefined) {
        modelToken = await modelController.prime(modelRecord);
        if (!sourceFree && sourceContinuation?.restoringModel !== true) {
          throw new Error('ModelSourceCaptureRestoreRequired');
        }
      }
    }
    const sources = [];
    for (const {adapter, occurrence} of selectedSources) {
      const baseAccess = multiple ? adapter.sourceAccess : singleSourceAccess;
      const access = sourceContinuation?.accessFor(baseAccess, occurrence) ?? baseAccess;
      const preparedSource = await adapter.prepare({
        preparedEffect: acquired.prepared, registry, values, fragment, ordered,
        sourceAccess: access, occurrence});
      sources.push({adapter, access, preparedSource, occurrence});
      signal?.throwIfAborted();
    }
    await sourceContinuation?.prepared(sources);
    const serializations = moon.clientProgramEffectSerializationOccurrences(acquired.prepared);
    const captureStartedAt = sourceContinuation?.times().captureStartedAt ?? now();
    let captureCompletedAt;
    const evidence = [];
    let component;
    if (serializations.length > 0) {
      if (multiple || sourceFree || serializations.length !== 1 ||
          typeof contentRun?.effectFamily !== 'function' ||
          typeof sources[0]?.adapter.ledgerCapacity !== 'function') {
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
        restored = await contentRun.recover({preparedEffect: acquired.prepared,
          plan: contentPlan, store, principalId, signal, restoredInput: restoredModelInput,
          retainExecution(value) { contentRecovery = value; }});
      }
      contentFamily = contentRun.effectFamily({prepared: acquired.prepared,
        plan: contentPlan, store, principalId, signal, restored});
    }
    const prepareInferComponent = () => {
      if (infer === undefined) return undefined;
      if (!multiple && !sourceFree && contentFamily === undefined) {
        throw new TypeError('UnsupportedComposedInferSourceClosure');
      }
      const admittedSources = sourceFree || contentFamily !== undefined ? undefined
        : checked(moon.clientProgramAdmitComposedInferSources(
          infer.occurrence, captures.map(value => value.capture.source()),
          captures.map(value => value.identity), captures.map(value => value.requirement),
          captures.map(value => moon.strategyRunEvidenceJson(value.logicalInput)),
          evidence.map(value => value.sourceEvidenceWire), acquired.authorityScopeCid,
          captureStartedAt, captureCompletedAt));
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
      return openNodeComposedInferProvider({moon, selected: infer, sources: admittedSources,
        ...(contentFamily === undefined ? {} : {generatedInput: {
          generation: () => contentFamily.generation(),
          recovery: () => contentFamily.recovery(),
        }}),
        control: acquired.control, plan, principalId, signal, now, durableCalls: true, restoredInput,
        retainOperation(operation) {
          inferOperation = operation;
          inferCapture = openNodeInferCaptureCustody({moon, control: acquired.control,
            operation, plan, store, storeAuthorityCid: acquired.storeAuthorityCid, durableCalls: true,
            sourceEvidence: evidence.map(source => acquired.control.admitRunEvidence(
              'source_evidence', source.sourceEvidenceWire,
              {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 100})),
            faultInjection,
            publicationFor: ({issuance, modelEvidence}) =>
              sourceFree ? sourceFreeInferEffectPublicationPlan({acquired,
                compiled, operation, issuance, modelEvidence}) :
              acquiredInferEffectPublicationPlan({acquired, sources: evidence,
                compiled, operation, issuance, modelEvidence,
                captureStartedAt, captureCompletedAt})});
        },
        retainCompleted: () => inferCapture.retainCompleted()});
    };
    if (contentFamily !== undefined) {
      component = prepareInferComponent();
      // Resolve every registered family on the original Source ledger before
      // any adapter read; Model opens only when Local binds its completed edge.
      ledger = contentFamily.prepareLedger(sources[0].adapter.ledgerCapacity(sources[0].preparedSource),
        component === undefined ? [] : [component.provider]);
    }
    if (multiple) {
      if (sources.some(source => source.adapter.realizationKey !== 'duckdb-acquired')) {
        ledger = prepareInstalledAcquiredEffectLedger({moon, preparedEffect: acquired.prepared,
          sources, registry, values, fragment, ordered});
      } else {
        const capacities = sources.map(value => capturedDuckDBPhysicalCapacity(value.preparedSource));
        const pendingSelection = sources.some(value => value.preparedSource.selection === undefined);
        ledger = (pendingSelection
          ? moon.clientProgramPrepareMultiCapturedEffectCapacityLedger
          : moon.clientProgramPrepareMultiCapturedEffectAcquisitionLedger)(acquired.prepared,
          sources.map(value => (pendingSelection ? capturedDuckDBPendingCapacity
            : capturedDuckDBConfiguration)(value.preparedSource)),
          capacities.map(value => value.transferBytes),
          capacities.map(value => value.executionBytes), registry, values, fragment, ordered);
        if (ledger === undefined) throw new Error('InstalledMultiSourceLedgerUnavailable');
      }
    }
    for (const source of sources) {
      signal?.throwIfAborted();
      diagnostic('acquisition_started', {task: source.occurrence.task,
        selection: source.preparedSource.selection});
      const acquisition = acquisitionEndHandoff();
      let captured;
      const admission = await sourceContinuation?.beforeRead(source);
      if (admission?.waiting !== undefined) {
        return Object.freeze({status: 'waiting_checkpoint',
          checkpoint: admission.waiting, cleanupOwner: custody});
      }
      if (admission?.retained !== undefined) {
        const restored = sourceContinuation.restore(source, admission.retained, ledger);
        captures.push(restored.captured);
        evidence.push(restored);
        continue;
      }
      // A refused fence proves this attempt has not called the adapter.
      // Do not feed it into the adapter's unknown physical-outcome path.
      admission?.enter();
      try {
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
      diagnostic('acquisition_completed', {task: source.occurrence.task,
        acquisition: captured.acquisition});
      const sourceEvidenceWire = await captured.issueSourceEvidence({
        authorityScopeCid: acquired.authorityScopeCid,
        effectiveDataPolicyCid: captured.checkedSource.sourceDataPolicyCid});
      evidence.push({captured, sourceEvidenceWire});
      await sourceContinuation?.captured(source, captured, sourceEvidenceWire,
        captureStartedAt, now());
    }
    captureCompletedAt = sourceContinuation?.times().captureCompletedAt ?? now();
    contentFamily?.bindCapture(captures[0], {...evidence[0],
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
    signal?.throwIfAborted();
    checkedHost = sourceFree
      ? moon.clientProgramOpenSourceFreeInferEffectHost(owner,
        registry, values, fragment, ordered, component.provider)
      : multiple
      ? component === undefined ? moon.clientProgramOpenMultiCapturedLocalEffectHost(owner,
        captures.map(value => value.capture.source()), ledger,
        registry, values, fragment, ordered) :
        moon.clientProgramOpenMultiCapturedInferEffectHost(owner,
          captures.map(value => value.capture.source()), ledger,
          registry, values, fragment, ordered, component.provider)
      : contentFamily !== undefined
      ? moon.clientProgramOpenCapturedFamilyEffectHost(owner,
        captures[0].capture.source(), ledger, registry, values, fragment, ordered,
        component === undefined ? [contentFamily.provider] : [contentFamily.provider, component.provider])
      : moon.clientProgramOpenCapturedLocalEffectHost(owner,
        captures[0].capture.source(), registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
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
        const operation = component.operation();
        if (operation === undefined || inferCapture === undefined) throw new Error('ModelPauseOwnerMissing');
        if (boundary.status === 'settling') {
          const settlement = operation.pendingSettlement();
          const slot = operation.settlementSlot(settlement);
          const entry = modelContinuation?.entry(slot);
          if (entry === undefined || slot !== boundary.slot) throw new Error('ModelPauseSettlementMismatch');
          await inferCapture.persistSettlement(settlement, entry);
          return {action: 'resume'};
        }
        if (boundary.status !== 'waiting') throw new Error('InvalidModelPause');
        if (modelContinuation === undefined) {
          const preparedCallSet = operation.preparedCallSet();
          if (preparedCallSet === undefined) throw new Error('ModelPausePreparedOwnerMissing');
          const sourceClosure = await sourceContinuation?.retainAll();
          modelContinuation = await modelController.open({operation, preparedCallSet,
            plan: modelPlan, selected: infer, principalId,
            declaredResults: moon.clientProgramEffectCompilationResultNames(acquired.compilation),
            submission, signal, existing: modelRecord, inputToken: modelToken, claim: modelClaim, parentResume,
            journalPort: modelJournalPort, sourceContinuation: sourceClosure});
          inferCapture.configureModelJournal({observe: modelContinuation.observe, entry: modelContinuation.entry});
          if (modelRecord !== undefined) return {action: 'resume'};
        }
        const decision = await modelContinuation.authorize();
        if (decision.status === 'dispatch') return {action: 'resume'};
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
      : withComputePauseHandler(computeConfigurations, boundary => {
        // Slots are local to each child. A shared numerical slot must not
        // route a Model settlement into the already-completed Content owner.
        if (contentFamily !== undefined && contentFamily.generation() === undefined) {
          return contentFamily.handlePause(boundary);
        }
        if (component !== undefined) return handleModelPause(boundary);
        throw new Error('PhysicalPauseOwnerMissing');
      });
    execution = await runCapturedEffectComputation(checkedHost,
      {...configurations,
        authorization: multiple ? undefined : singleSourceAccess?.authorization}, signal);
    unresolved = false;
    if (execution.status === 'host-tasks-waiting') {
      return Object.freeze({status: 'waiting_checkpoint', checkpoint: execution.checkpoint,
        execution, checkedHost, cleanupOwner: custody});
    }
    if (execution.status !== 'host-tasks-completed' && component?.operation()?.physicalStopped()) {
      await inferCapture.persistStoppedAttempts();
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
      publicationPlan = (await inferCapture.persist()).plan;
      await faultInjection?.('infer_capture_committed', {});
    }
    if (contentFamily !== undefined && component === undefined) {
      const generation = contentFamily.generation();
      if (generation === undefined) throw new Error('InstalledContentGenerationEvidenceUnavailable');
      publicationPlan = acquiredEffectPublicationPlan({acquired, ...evidence[0],
        captureStartedAt, captureCompletedAt, content: {...contentPlan, generation}});
    }
    if (publicationPlan === undefined) {
      throw new Error('InstalledContentGenerationEvidenceUnavailable');
    }
    return Object.freeze({execution, checkedHost, publicationPlan,
      cleanupOwner: custody});
  } finally {
    settled = true;
  }
}

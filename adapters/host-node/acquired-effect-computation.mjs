// Physical custody while one admitted Effect Run acquires its source and
// computes. This does not retry acquisition, Compute, or an Effect dispatch.
import {acquisitionEndHandoff} from '../host-common/acquisition-outcome.mjs';
import {acquiredEffectPublicationPlan, acquiredMultiEffectPublicationPlan,
  acquiredInferEffectPublicationPlan, sourceFreeInferEffectPublicationPlan} from './local-values-plan.mjs';
import {installedSourceFor} from './installed-source.mjs';
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
  observe, sourceContinuation, computeConfigurations = {}}) {
  const count = moon?.clientProgramEffectAcquisitionCount?.(acquired.prepared);
  const sourceFree = count === 0;
  const multiple = count === 2;
  if (typeof retainComputationOwner !== 'function' ||
      ![0, 1, 2].includes(count) ||
      sourceFree && infer === undefined ||
      !sourceFree &&
      (multiple ? sourceProfile?.sources?.length !== 2 :
        typeof sourceProfile?.prepare !== 'function' ||
        typeof sourceProfile?.open !== 'function')) {
    throw new TypeError('InvalidAcquiredEffectComputationPort');
  }
  const captures = [];
  let execution;
  let checkedHost;
  let recovery;
  let inferCapture;
  let ledger;
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
  const custody = Object.freeze({
    async close() {
      closed = true;
      // A physical owner's cleanup, not another Compute call, recovers a
      // failed close. Retain the captured source until consumers are gone.
      let failure;
      try { await (execution ?? recovery)?.close(); }
      catch (error) { failure = error; }
      try { if (settled) await inferCapture?.custody.close(); }
      catch (error) { failure ??= error; }
      if (failure !== undefined) observeUsage('effect_computation_cleanup_pending');
      if (failure !== undefined) throw failure;
    },
    async cleanup() {
      if (!pending) return true;
      if (!closed || !settled || unresolved) return false;
      if (inferCapture !== undefined) {
        if (!await inferCapture.custody.cleanup()) {
          observeUsage('effect_computation_cleanup_pending');
          return false;
        }
      }
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
    const sources = [];
    for (let task = 0; task < count; task++) {
      const occurrence = {stage: task, input: 0, task};
      const requirement = multiple ? checked(
        moon.clientProgramEffectPrepareLocalQueryRequirement(acquired.prepared,
          task, 0, registry, values, fragment, ordered)) : undefined;
      const adapter = multiple ? installedSourceFor(sourceProfile,
        moon.clientProgramQueryRequirementSourceRef(requirement)) : sourceProfile;
      if (multiple && adapter.realizationKey !== 'duckdb-acquired') {
        throw new TypeError('UnsupportedEffectSourceRealization');
      }
      const baseAccess = multiple ? adapter.sourceAccess : sourceAccess;
      const access = sourceContinuation?.accessFor(baseAccess, occurrence) ?? baseAccess;
      const preparedSource = await adapter.prepare({
        preparedEffect: acquired.prepared, registry, values, fragment, ordered,
        sourceAccess: access, occurrence});
      sources.push({adapter, access, preparedSource, occurrence});
      signal?.throwIfAborted();
    }
    await sourceContinuation?.prepared(sources);
    if (multiple) {
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
    const captureStartedAt = sourceContinuation?.times().captureStartedAt ?? now();
    const evidence = [];
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
    const captureCompletedAt = sourceContinuation?.times().captureCompletedAt ?? now();
    let publicationPlan = infer === undefined ? multiple
      ? acquiredMultiEffectPublicationPlan({acquired, sources: evidence,
        captureStartedAt, captureCompletedAt})
      : acquiredEffectPublicationPlan({acquired, ...evidence[0],
        captureStartedAt, captureCompletedAt}) : undefined;
    let component;
    if (infer !== undefined) {
      if (!multiple && !sourceFree) throw new TypeError('UnsupportedComposedInferSourceClosure');
      const sources = sourceFree ? undefined : checked(moon.clientProgramAdmitComposedInferSources(
        infer.occurrence, captures.map(value => value.capture.source()),
        captures.map(value => value.identity), captures.map(value => value.requirement),
        captures.map(value => moon.strategyRunEvidenceJson(value.logicalInput)),
        evidence.map(value => value.sourceEvidenceWire), acquired.authorityScopeCid,
        captureStartedAt, captureCompletedAt));
      const compiled = acquired.control.adoptCheckedClientEffectInferRun(
        acquired.allowed, acquired.runDefinition, acquired.resultDataPolicy,
        acquired.resultDataPolicyLimits);
      const plan = {compiled, runDefinition: acquired.runDefinition};
      component = openNodeComposedInferProvider({moon, selected: infer, sources,
        control: acquired.control, plan, principalId, signal, now,
        retainOperation(operation) {
          inferCapture = openNodeInferCaptureCustody({moon, control: acquired.control,
            operation, plan, store, storeAuthorityCid: acquired.storeAuthorityCid,
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
    }
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
      : moon.clientProgramOpenCapturedLocalEffectHost(owner,
        captures[0].capture.source(), registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (checkedHost === undefined) {
      throw new Error('InstalledEffectProgramUnsupported');
    }
    // Without a returned Compute owner an exception cannot prove a stop.
    // Keep the responsibility rather than relabeling it as released.
    unresolved = true;
    if (multiple) {
      const dag = moon.strategyHostRun(moon.clientProgramLocalEffectHostRuntime(checkedHost));
      for (const [task, captured] of captures.entries()) captured.capture.retainTask(dag, task);
    }
    execution = await runCapturedEffectComputation(checkedHost,
      {...computeConfigurations,
        authorization: multiple ? undefined : sourceAccess?.authorization}, signal);
    unresolved = false;
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
    return Object.freeze({execution, checkedHost, publicationPlan,
      cleanupOwner: custody});
  } finally {
    settled = true;
  }
}

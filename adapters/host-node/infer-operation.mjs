// Physical stepping and custody for the existing MoonBit inference owner.
// Run admission, model policy and private Store confirmation precede opening;
// this adapter does not authorize dispatch or issue a public Run outcome.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});
const activeOperations = new WeakMap();

// Called by the installed Run's dispatch callback. The caller transfers this
// object to client-dispatch-owner before calling run, hence before any advance.
// Exactly one physical provider or already Store-confirmed saved read is used.
export function openNodeInferOperation({moon, preparedProgram, step, graph,
  registry, values, fragment, ordered, provider, savedCapture, savedSlots, quantityCapacity,
  physicalPreflight, egressAdmission, computeSuffix, acquiredInput, composedInput,
  signal, quantum = 256, observeProgress, durableCalls = false, restoredInput, retainOperation}) {
  if (retainOperation !== undefined && typeof retainOperation !== 'function') {
    throw new TypeError('InvalidInferOperationCustody');
  }
  if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      [provider, savedCapture, savedSlots].filter(value => value !== undefined)
        .length !== 1) {
    throw new TypeError('InvalidInstalledInferOperation');
  }
  if (physicalPreflight !== undefined &&
      (typeof physicalPreflight !== 'function' || provider === undefined ||
        quantityCapacity === undefined)) {
    throw new TypeError('InvalidInstalledInferPhysicalPreflight');
  }
  if (egressAdmission !== undefined && provider === undefined) {
    throw new TypeError('InvalidInstalledInferEgress');
  }
  if (quantityCapacity !== undefined && (provider === undefined ||
      quantityCapacity === null ||
      typeof quantityCapacity !== 'object' ||
      Object.keys(quantityCapacity).sort().join(',') !== 'limits,perAttempt' ||
      ['limits', 'perAttempt'].some(scope => {
        const value = quantityCapacity[scope];
        return value === null || typeof value !== 'object' ||
          Object.keys(value).sort().join(',') !==
            'costUnits,durationMs,tokens' ||
          Object.values(value).some(amount => typeof amount !== 'bigint' ||
            amount < 0n || amount > BigInt(Number.MAX_SAFE_INTEGER));
      }))) {
    throw new TypeError('InvalidInstalledInferQuantityCapacity');
  }
  signal?.throwIfAborted();
  if (acquiredInput !== undefined && savedCapture !== undefined) {
    throw new TypeError('AcquiredInferReplayNotConnected');
  }
  if (composedInput !== undefined && (provider === undefined ||
      acquiredInput !== undefined || savedSlots !== undefined ||
      savedCapture !== undefined)) {
    throw new TypeError('InvalidComposedInferOperation');
  }
  if (restoredInput !== undefined && (provider === undefined || acquiredInput !== undefined ||
      savedCapture !== undefined || savedSlots !== undefined)) {
    throw new TypeError('InvalidRestoredInferInput');
  }
  const active = checked(restoredInput !== undefined && composedInput !== undefined
    ? moon.clientProgramStartRestoredComposedInferInput(composedInput.occurrence, graph,
      composedInput.prefix, provider, restoredInput.snapshot.binding,
      restoredInput.snapshot.descriptorWire, restoredInput.snapshot.rows,
      () => restoredInput.token.available, restoredInput.savedScope)
    : restoredInput !== undefined
    ? moon.clientProgramStartRestoredInferInput(preparedProgram, step, graph, registry,
      values, provider, restoredInput.snapshot.binding, restoredInput.snapshot.descriptorWire,
      restoredInput.snapshot.rows, () => restoredInput.token.available, restoredInput.savedScope,
      fragment, ordered)
    : composedInput !== undefined
    ? moon.clientProgramStartComposedInferExecution(composedInput.occurrence,
      graph, composedInput.prefix, composedInput.inputs, provider,
      composedInput.sources)
    : savedSlots !== undefined
    ? acquiredInput === undefined
      ? moon.clientProgramStartRestoredInferSlotReplay(preparedProgram, step,
        graph, registry, values, savedSlots, fragment, ordered)
      : moon.clientProgramStartAcquiredInferSlotReplay(preparedProgram, step,
        graph, registry, values, savedSlots, acquiredInput, fragment, ordered)
    : savedCapture === undefined
      ? acquiredInput === undefined
        ? moon.clientProgramStartScopedInferExecution(preparedProgram, step,
          graph, registry, values, provider, fragment, ordered)
        : moon.clientProgramStartAcquiredInferExecution(preparedProgram, step,
          graph, registry, values, provider, acquiredInput, fragment, ordered)
      : moon.clientProgramStartRestoredInferReplay(preparedProgram, step,
        graph, registry, values, savedCapture, fragment, ordered));
  const requestStop = () => moon.clientProgramCancelInferExecution(active);
  signal?.addEventListener('abort', requestStop, {once: true});
  let flight;
  let closeFlight;
  let reclaimed = false;
  let closing = false;
  let cleanupSettlement;

  function cleanup() {
    if (reclaimed) return true;
    // Cancellation delivery alone never permits releasing the execution.
    if (!moon.clientProgramInferExecutionStopped(active)) return false;
    reclaimed = checked(moon.clientProgramCleanupInferExecution(active));
    if (reclaimed) signal?.removeEventListener('abort', requestStop);
    return reclaimed;
  }

  async function drive() {
    for (;;) {
      if (closing || signal?.aborted) requestStop();
      const poll = checked(moon.clientProgramAdvanceInferExecution(active,
        quantum));
      const kind = moon.clientProgramInferExecutionPollKind(poll);
      if (kind === 'waiting') {
        const preparedCallSet = moon.clientProgramInferPreparedCallSet(active);
        if (preparedCallSet === undefined) throw new Error('InferPreparedOwnerUnavailable');
        return Object.freeze({status: 'waiting', preparedCallSet});
      }
      if (kind === 'settling') {
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw new Error('InferSettlementOwnerUnavailable');
        return Object.freeze({status: 'settling', settlement});
      }
      if (kind === 'complete') {
        return moon.clientProgramInferExecutionOutput(poll);
      }
      if (kind === 'failed') {
        // Preserve the existing typed cause without a new public classifier.
        checked({$tag: 0, _0: moon.clientProgramInferExecutionPollIssue(poll)});
      }
      if (kind === 'stopped') {
        if (signal?.aborted) signal.throwIfAborted();
        throw Object.assign(new Error('InferExecutionStopped'),
          {code: 'InferExecutionStopped'});
      }
      if (kind !== 'continue') throw new Error('InvalidInferExecutionPoll');
      await observeProgress?.();
      // A macrotask delivers timer/I/O cancellation; a resolved Promise does
      // not. MoonBit owns work, progress, phase changes and safe stop checks.
      await yieldEventLoop();
    }
  }

  function run() {
    if (composedInput !== undefined) {
      return Promise.reject(new Error('InferComponentDrivenByLocal'));
    }
    if (closing || reclaimed) {
      return Promise.reject(new Error('InferOperationClosed'));
    }
    if (flight === undefined) {
      flight = drive().then(result => {
        if (result?.status === 'waiting' || result?.status === 'settling') flight = undefined;
        return result;
      });
      // The supervisor observes this promise even if its Client disconnects.
      // Retaining the rejection here prevents an unhandled detached failure.
      flight.catch(() => {});
    }
    return flight;
  }

  async function stop() {
    closing = true;
    requestStop();
    if (flight !== undefined) await flight.catch(() => {});
    // Finish only bounded observation/custody already owned by an entered
    // attempt. requestStop is sticky, so this cannot dispatch another slot.
    while (!moon.clientProgramInferExecutionStopped(active)) {
      requestStop();
      const poll = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      const kind = moon.clientProgramInferExecutionPollKind(poll);
      if (kind === 'settling') {
        if (typeof cleanupSettlement !== 'function') throw pending();
        const settlement = moon.clientProgramInferCallSettlement(active);
        if (settlement === undefined) throw pending();
        await cleanupSettlement(settlement);
      } else if (kind === 'continue') {
        await yieldEventLoop();
      } else if (!moon.clientProgramInferExecutionStopped(active)) {
        throw pending();
      }
    }
  }

  function close() {
    if (reclaimed) return Promise.resolve();
    if (closeFlight === undefined) {
      closing = true;
      closeFlight = (async () => {
        await stop();
        if (!cleanup()) throw pending();
      })();
      closeFlight.catch(() => {});
    }
    return closeFlight;
  }

  const operation = Object.freeze({run, stop, close, cleanup,
    installSettlementCleanup(callback) {
      if (cleanupSettlement !== undefined || typeof callback !== 'function') {
        throw new TypeError('InvalidInferSettlementCleanup');
      }
      cleanupSettlement = callback;
    },
    cleanupPending: () => !reclaimed,
    cleanupProgress: () => moon.clientProgramInferCleanupProgress?.(active),
    physicalStopped: () => moon.clientProgramInferExecutionStopped(active),
    quantityUsage: () => moon.clientProgramInferQuantityUsage(active),
    stoppedAttemptCount: () => moon.clientProgramInferStoppedAttemptCount(active),
    stoppedAttemptSlot: index => moon.clientProgramInferStoppedAttemptSlot(active, index),
    hasUnknownCalls: () => moon.clientProgramInferHasUnknownCalls(active),
    acquireOutput: () => moon.clientProgramAcquireInferOutput(active),
    acquireCapture: () => moon.clientProgramAcquireInferCapture(active),
    acquireOutcomes: () => moon.clientProgramAcquireInferOutcomes(active),
    invocationEvidence: slot => moon.clientProgramInferInvocationEvidence(active,
      slot),
    // The ordinary publication control owns compilation and contract tokens.
    // It passes the original owner to MoonBit, never recompiling this Program.
    bindRun: (control, {compiled, runDefinition}) =>
      control.bindCheckedClientInferRun(compiled, active, runDefinition),
    bindDispatch: (control, {compiled, runDefinition, ...observation}) =>
      control.bindCheckedClientInferDispatch(compiled, active, runDefinition,
        observation),
    preparedCallSet: () => moon.clientProgramInferPreparedCallSet(active),
    pendingSettlement: () => moon.clientProgramInferCallSettlement(active),
    exportPreparedInput: (preparedCallSet, binding) => {
      const exported = checked(moon.clientProgramExportInferPreparedInput(active, preparedCallSet, binding));
      return Object.freeze({owner: exported,
        descriptorWire: moon.clientProgramInferPreparedInputExportDescriptor(exported),
        rows: Object.freeze(moon.clientProgramInferPreparedInputExportRows(exported)),
        current: () => moon.clientProgramInferPreparedInputExportMatches(active, preparedCallSet, exported)});
    },
    preparedFacts: preparedCallSet => {
      const count = moon.clientProgramInferPreparedCallCount(preparedCallSet);
      const input = moon.clientProgramInferPreparedInput(preparedCallSet);
      const artifact = moon.clientProgramInferPreparedInputArtifact(preparedCallSet);
      const ids = moon.clientProgramInferPreparedIdentities(preparedCallSet);
      if (!Number.isSafeInteger(count) || count < 0 || count > 128 ||
          input === undefined || artifact === undefined || ids === undefined) {
        throw new Error('InferPreparedOwnerUnavailable');
      }
      const slotWires = Array.from({length: count}, (_, slot) => {
        const call = moon.clientProgramInferPreparedCallAt(preparedCallSet, slot);
        if (call === undefined) throw new Error('InferPreparedCallUnavailable');
        return moon.strategyRunEvidenceJson(call);
      });
      return Object.freeze({preparedCallSet, input,
        inputArtifactWire: moon.strategyRunEvidenceJson(artifact),
        slotWires: Object.freeze(slotWires), providerId: ids._0,
        modelTaskCid: ids._1, fixedRequestCid: ids._2,
        unitId: moon.clientProgramInferCallScopeUnitId(active),
        callScopeSnapshotWire: checked(moon.clientProgramInferCallScopeSnapshot(active))});
    },
    bindModelScope: (control, plan, preparedCallSet, originals) =>
      control.bindCheckedClientInferModelScope(plan.compiled, active,
        plan.runDefinition, preparedCallSet, originals),
    bindModelDispatch: (control, plan, preparedCallSet, scope, observation) =>
      control.bindCheckedClientInferModelDispatch(plan.compiled, active,
        plan.runDefinition, preparedCallSet, scope, {...observation,
          enterCall: entry => {
            const originals = moon.clientProgramInferCallEntryOriginals(entry);
            if (originals === undefined) return false;
            return observation.enterCall(Object.freeze({entry,
              slot: originals._0, callWire: originals._1,
              attemptWire: originals._2, authorityWire: originals._3})) === true;
          }}),
    entryCurrent: (entry, preparedCallSet) =>
      moon.clientProgramInferCallEntryCurrent(entry, preparedCallSet),
    restoreCall: (preparedCallSet, slot, record, proof, bundle) => checked(
      moon.clientProgramRestoreInferPreparedCall(preparedCallSet, slot, record, proof, bundle)),
    restoreUnknown: (preparedCallSet, slot, attempt, authority) => checked(
      moon.clientProgramRestoreInferPreparedUnknown(preparedCallSet, slot, attempt, authority)),
    settlementSlot: settlement => moon.clientProgramInferCallSettlementSlot(settlement),
    acknowledgeSettlement: settlement => {
      if (!moon.clientProgramAcknowledgeInferCallSettlement(settlement)) {
        throw new Error('InferSettlementAcknowledgementRejected');
      }
    },
    attemptEvidence: slot => checked(moon.clientProgramInferAttemptEvidence(
      active, slot)),
    issuedSlotCapture: slot => checked(moon.clientProgramIssueInferSlotCapture(
      active, slot)),
    bindInvocation: (control, {compiled, runDefinition, verification,
      invocation, dataPolicyCid}) => control.bindCheckedClientInferInvocation(
      compiled, active, runDefinition, verification, invocation, dataPolicyCid),
    startObservation: ({ledger, maxSlots, maxWireBytes, maxWork}) => checked(
      moon.clientProgramStartInferObservationIssuance(active, ledger,
        maxSlots, maxWireBytes, maxWork)),
    bindIssuedInvocation: (control, {compiled, runDefinition, issued}) =>
      control.bindIssuedClientInferInvocation(compiled, active, runDefinition,
        issued),
    // Store use is awaited to settlement before releasing the common Result
    // owner. Aborting a writer is not physical stop confirmation.
    withResult: (binding, result, consume, resultSignal = signal) =>
      withNodeInferResult({moon, binding, result, consume,
        signal: resultSignal, quantum}),
  });
  activeOperations.set(operation, active);
  try {
    // Input construction already owns Core resources. Transfer that exact
    // owner before any fallible binding, without granting permission to run.
    retainOperation?.(operation);
    if (durableCalls) checked(moon.clientProgramRequireInferCallEntry(active));
    if (restoredInput !== undefined) checked(moon.clientProgramRestrictInferSendSlots(active,
      restoredInput.sendMask));
    if (quantityCapacity !== undefined) {
      const {limits, perAttempt} = quantityCapacity;
      checked(moon.clientProgramBindInferQuantityCapacity(active,
        limits.tokens, limits.costUnits, limits.durationMs,
        perAttempt.tokens, perAttempt.costUnits, perAttempt.durationMs));
    }
    if (computeSuffix !== undefined) checked(moon.clientProgramBindInferComputeSuffix(active, computeSuffix));
    if (physicalPreflight !== undefined) checked(moon.clientProgramBindInferPhysicalPreflight(active, physicalPreflight));
    if (egressAdmission !== undefined) checked(moon.clientProgramBindInferEgress(active, egressAdmission));
  } catch (error) {
    // Preserve the admission failure even when stop/cleanup cannot finish.
    // The receiving parent retries this owner, never construction or dispatch.
    closing = true;
    try {
      requestStop();
      const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(stopped) === 'stopped' &&
          retainOperation === undefined) cleanup();
    } catch { /* The original failure and pending owner remain authoritative. */ }
    if (!reclaimed && error !== null && typeof error === 'object' &&
        Object.isExtensible(error) && !Object.hasOwn(error, 'cleanupOwner')) {
      Object.defineProperty(error, 'cleanupOwner', {value: operation});
    }
    throw error;
  }
  return operation;
}

// One original Model component is opened by the common Local task driver,
// after it has bound actual producer reads. Local alone advances it. The
// installing Run retains physical custody before binding current admissions.
export function openNodeComposedInferProvider({moon, selected, sources,
  control, plan, principalId, now, signal, retainOperation, retainCompleted,
  durableCalls = false, restoredInput}) {
  if (selected?.occurrence === undefined ||
      typeof retainOperation !== 'function') {
    throw new TypeError('InvalidComposedInferProvider');
  }
  let operation;
  let failure;
  const provider = moon.clientProgramComposedInferLocalProvider(
    selected.occurrence, inputs => {
      try {
        if (operation !== undefined) throw new Error('ComposedInferAlreadyOpened');
        operation = openNodeInferOperation({moon, graph: selected.graph,
          composedInput: {occurrence: selected.occurrence,
            prefix: selected.computePrefix, inputs, sources},
          computeSuffix: selected.computeSuffix, provider: selected.provider,
          quantityCapacity: selected.quantityCapacity,
          physicalPreflight: selected.physicalPreflight,
          egressAdmission: selected.egressAdmission, signal, durableCalls, restoredInput,
          retainOperation(value) { operation = value; retainOperation(value); }});
        operation.bindRun(control, plan);
        if (!durableCalls) operation.bindDispatch(control, {...plan, account: selected.account,
          principalId, at: now(), observeAccount: selected.observeAccount,
          observeAt: now});
        return activeOperations.get(operation);
      } catch (error) {
        failure = error;
        return undefined;
      }
    }, issue => {
      failure ??= Object.assign(new Error('ComposedInferComponentFailed'),
        {code: 'MoonBitHostFailure', cause: issue});
    }, active => {
      try {
        if (operation === undefined || activeOperations.get(operation) !== active) {
          throw new Error('ForeignComposedInferCompletion');
        }
        return retainCompleted?.(operation) !== false;
      } catch (error) {
        failure = error;
        return false;
      }
    }, active => operation !== undefined &&
      activeOperations.get(operation) === active &&
      operation.cleanupPending() === false);
  return Object.freeze({provider, operation: () => operation,
    failure: () => failure});
}

// This is physical stepping of the existing checked Result transformer, not
// another publisher or an adapter-authored publication inventory. The Store
// callback receives the common selection and ordinary opaque output exporter.
export async function withNodeInferResult({moon, binding, result, consume,
  signal, quantum = 256}) {
  if (typeof consume !== 'function' || !Number.isSafeInteger(result) ||
      result < 0 || !Number.isSafeInteger(quantum) || quantum < 1 ||
      quantum > 2147483647) {
    throw new TypeError('InvalidInstalledInferResult');
  }
  signal?.throwIfAborted();
  const owner = checked(moon.clientProgramInferPublicationBegin(binding,
    result));
  const cancel = () => moon.clientProgramInferPublicationCancel(owner);
  signal?.addEventListener('abort', cancel, {once: true});
  let custodyTransferred = false;
  try {
    for (;;) {
      signal?.throwIfAborted();
      const progress = checked(moon.clientProgramInferPublicationAdvance(owner,
        quantum));
      if (progress._0) break;
      await yieldEventLoop();
    }
    signal?.throwIfAborted();
    const selection = moon.clientProgramInferPublicationSelection(owner);
    const exported = checked(moon.clientProgramInferPublicationFinish(owner));
    // Do not race this against abort: a rejected/aborted consumer must first
    // settle its physical I/O and retain any unresolved cleanup responsibility.
    return await consume({selection, exported, signal,
      storeExport: () => checked(
        moon.clientProgramInferPublicationStoreExport(owner))});
  } catch (failure) {
    if (failure?.cleanupPending === true) {
      // The existing dispatch supervisor retries this exact Store cleanup
      // handle. Keep the Result pinned until that handle confirms settlement;
      // a rejected consumer Promise alone cannot confirm physical stop.
      const original = failure.cleanupHandle;
      custodyTransferred = true;
      const retained = Object.freeze({
        status: () => ({pending: custodyTransferred}),
        async retry() {
          if (!custodyTransferred) return false;
          if (typeof original?.retry !== 'function' ||
              typeof original?.status !== 'function') throw pending();
          if (original.status()?.pending === true) await original.retry();
          if (original.status()?.pending !== false) throw pending();
          moon.clientProgramInferPublicationRelease(owner);
          custodyTransferred = false;
          return true;
        },
      });
      // Preserve the original typed cause even when its Error is immutable.
      const held = new Error(failure.message, {cause: failure});
      held.code = failure.code;
      held.cleanupPending = true;
      held.cleanupHandle = retained;
      throw held;
    }
    throw failure;
  } finally {
    signal?.removeEventListener('abort', cancel);
    if (!custodyTransferred) moon.clientProgramInferPublicationRelease(owner);
  }
}

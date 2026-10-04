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
  signal, quantum = 256, observeProgress, deferDispatch = false, enterCall}) {
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
  if (typeof deferDispatch !== 'boolean' ||
      (deferDispatch && (provider === undefined || composedInput !== undefined ||
        typeof enterCall !== 'function')) ||
      (enterCall !== undefined && (typeof enterCall !== 'function' ||
        provider === undefined || composedInput !== undefined))) {
    throw new TypeError('InvalidInstalledInferEntry');
  }
  let entryFailure;
  let entryFlight;
  const enterOriginal = entry => {
    try {
      const originals = moon.clientProgramInferCallEntryOriginals(entry);
      const result = enterCall(Object.freeze({slot: originals._0,
        callWire: originals._1, attemptWire: originals._2,
        authorityWire: originals._3}));
      if (result !== null && typeof result === 'object' &&
          typeof result.then === 'function') {
        entryFailure = new TypeError('AsyncInferAttemptEntry');
        const flight = Promise.resolve(result);
        entryFlight = flight;
        flight.catch(() => {}).finally(() => {
          if (entryFlight === flight) entryFlight = undefined;
        }).catch(() => {});
        return false;
      }
      return result === true;
    } catch (error) {
      // The journal may have committed before its acknowledgement was lost.
      // Core retains this attempt as unknown; never invoke or silently retry.
      entryFailure = error;
      return false;
    }
  };
  const active = checked(composedInput !== undefined
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
        ? enterCall === undefined
          ? moon.clientProgramStartScopedInferExecution(preparedProgram, step,
            graph, registry, values, provider, fragment, ordered)
          : moon.clientProgramStartScopedEnteredInferExecution(preparedProgram,
            step, graph, registry, values, provider, fragment, ordered,
            enterOriginal, deferDispatch)
        : enterCall === undefined
          ? moon.clientProgramStartAcquiredInferExecution(preparedProgram, step,
            graph, registry, values, provider, acquiredInput, fragment, ordered)
          : moon.clientProgramStartAcquiredEnteredInferExecution(preparedProgram,
            step, graph, registry, values, provider, acquiredInput, fragment,
            ordered, enterOriginal, deferDispatch)
      : moon.clientProgramStartRestoredInferReplay(preparedProgram, step,
        graph, registry, values, savedCapture, fragment, ordered));
  const requestStop = () => moon.clientProgramCancelInferExecution(active);
  if (quantityCapacity !== undefined) {
    const {limits, perAttempt} = quantityCapacity;
    const bound = moon.clientProgramBindInferQuantityCapacity(active,
      limits.tokens, limits.costUnits, limits.durationMs,
      perAttempt.tokens, perAttempt.costUnits, perAttempt.durationMs);
    if (bound?.$tag !== 1) {
      // This is still the bounded, pre-dispatch Input phase. Confirm stop and
      // cleanup before propagating the original typed refusal; never run.
      requestStop();
      const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(stopped) !== 'stopped' ||
          checked(moon.clientProgramCleanupInferExecution(active)) !== true) {
        throw pending();
      }
      checked(bound);
    }
  }
  for (const bind of [
    ...(computeSuffix === undefined ? [] :
      [() => moon.clientProgramBindInferComputeSuffix(active, computeSuffix)]),
    ...(physicalPreflight === undefined ? [] :
      [() => moon.clientProgramBindInferPhysicalPreflight(active, physicalPreflight)]),
    ...(egressAdmission === undefined ? [] :
      [() => moon.clientProgramBindInferEgress(active, egressAdmission)]),
  ]) {
    const bound = bind();
    if (bound?.$tag !== 1) {
      requestStop();
      const stopped = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(stopped) !== 'stopped' ||
          checked(moon.clientProgramCleanupInferExecution(active)) !== true) {
        throw pending();
      }
      checked(bound);
    }
  }
  signal?.addEventListener('abort', requestStop, {once: true});
  let flight;
  let closeFlight;
  let reclaimed = false;
  let closing = false;
  let waiting = false;
  let retainedCallSet;

  function preparedCallSet() {
    if (!waiting || closing || reclaimed) return undefined;
    if (retainedCallSet !== undefined) return retainedCallSet;
    const set = moon.clientProgramInferPreparedCallSet(active);
    const count = set === undefined ? undefined :
      moon.clientProgramInferPreparedCallCount(set);
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new Error('InferPreparedCallSetUnavailable');
    }
    const inputWire = moon.clientProgramInferPreparedInputWire(set);
    if (typeof inputWire !== 'string') {
      throw new Error('InferPreparedCallSetUnavailable');
    }
    retainedCallSet = Object.freeze({inputWire, count,
      slotWire(index) {
        if (!waiting || closing || reclaimed || !Number.isSafeInteger(index) ||
            index < 0 || index >= count) {
          throw new Error('InferPreparedCallSetUnavailable');
        }
        const wire = moon.clientProgramInferPreparedSlotWire(set, index);
        if (typeof wire !== 'string') {
          throw new Error('InferPreparedCallSetUnavailable');
        }
        return wire;
      }});
    return retainedCallSet;
  }

  async function materializeCallSet({quantum: step = 256,
    signal: readSignal = signal} = {}) {
    if (!Number.isSafeInteger(step) || step < 1) {
      throw new TypeError('InvalidInferCallInventoryQuantum');
    }
    const set = preparedCallSet();
    if (set === undefined) throw new Error('InferPreparedCallSetUnavailable');
    const slotWires = [];
    for (let index = 0; index < set.count; index++) {
      readSignal?.throwIfAborted();
      slotWires.push(set.slotWire(index));
      if ((index + 1) % step === 0) await yieldEventLoop();
    }
    readSignal?.throwIfAborted();
    return Object.freeze({inputWire: set.inputWire,
      slotWires: Object.freeze(slotWires)});
  }

  function cleanup() {
    if (reclaimed) return true;
    // Cancellation delivery alone never permits releasing the execution.
    if (!moon.clientProgramInferExecutionStopped(active) ||
        entryFlight !== undefined) return false;
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
      if (kind === 'complete') {
        return moon.clientProgramInferExecutionOutput(poll);
      }
      if (kind === 'waiting') {
        if (!deferDispatch) throw new Error('UnexpectedInferApprovalWait');
        waiting = true;
        return Object.freeze({kind: 'waiting', callSet: preparedCallSet()});
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
      flight = drive();
      // The supervisor observes this promise even if its Client disconnects.
      // Retaining the rejection here prevents an unhandled detached failure.
      flight.catch(() => {});
    }
    return flight;
  }

  function resumeApproved({grant, admission, now, current}) {
    if (!waiting || closing || reclaimed || typeof now !== 'function' ||
        typeof current !== 'function') {
      return Promise.reject(new Error('InferApprovalResumeUnavailable'));
    }
    try {
      checked(moon.clientProgramResumeApprovedInferExecution(active, grant,
        admission, now, current));
    } catch (error) { return Promise.reject(error); }
    waiting = false;
    retainedCallSet = undefined;
    flight = undefined;
    return run();
  }

  function resumeApprovedFromReadback({requestWire, checkpointWire,
    verifiedWire, admission, now, current, immediate = false}) {
    if (!waiting || closing || reclaimed ||
        [requestWire, checkpointWire, verifiedWire].some(value =>
          typeof value !== 'string' || value.length === 0) ||
        typeof now !== 'function' || typeof current !== 'function' ||
        typeof immediate !== 'boolean') {
      return Promise.reject(new Error('InferApprovalReadbackUnavailable'));
    }
    let grant;
    try {
      grant = checked(moon.clientProgramModelInvocationGrantHandle(
        requestWire, checkpointWire, verifiedWire, now(), immediate));
    } catch (error) { return Promise.reject(error); }
    return resumeApproved({grant, admission, now, current});
  }

  async function stop() {
    closing = true;
    requestStop();
    if (flight !== undefined) await flight.catch(() => {});
    if (entryFlight !== undefined) {
      const pendingEntry = entryFlight;
      await pendingEntry.catch(() => {});
      if (entryFlight === pendingEntry) entryFlight = undefined;
    }
    if (!moon.clientProgramInferExecutionStopped(active)) {
      const poll = checked(moon.clientProgramAdvanceInferExecution(active, 1));
      if (moon.clientProgramInferExecutionPollKind(poll) !== 'stopped' ||
          !moon.clientProgramInferExecutionStopped(active)) throw pending();
    }
  }

  function close() {
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

  const operation = Object.freeze({run, resumeApproved,
    resumeApprovedFromReadback, preparedCallSet,
    materializeCallSet,
    entryFailure: () => entryFailure, stop, close, cleanup,
    cleanupPending: () => !reclaimed,
    physicalStopped: () => entryFlight === undefined &&
      moon.clientProgramInferExecutionStopped(active),
    quantityUsage: () => moon.clientProgramInferQuantityUsage(active),
    stoppedAttemptCount: () => moon.clientProgramInferStoppedAttemptCount(active),
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
    issueDispatch: (control, {compiled, runDefinition, ...observation}) =>
      control.issueCheckedClientInferDispatch(compiled, runDefinition,
        observation),
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
  return operation;
}

// One original Model component is opened by the common Local task driver,
// after it has bound actual producer reads. Local alone advances it. The
// installing Run retains physical custody before binding current admissions.
export function openNodeComposedInferProvider({moon, selected, sources,
  control, plan, principalId, now, signal, retainOperation, retainCompleted}) {
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
          egressAdmission: selected.egressAdmission, signal});
        retainOperation(operation);
        operation.bindRun(control, plan);
        operation.bindDispatch(control, {...plan, account: selected.account,
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

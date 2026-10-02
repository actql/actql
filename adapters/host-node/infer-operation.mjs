// Physical stepping and custody for the existing MoonBit inference owner.
// Run admission, model policy and private Store confirmation precede opening;
// this adapter does not authorize dispatch or issue a public Run outcome.
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {checked} from '../host-common/runtime-result.mjs';

const pending = () => Object.assign(new Error('ClientDispatchCleanupPending'),
  {code: 'ClientDispatchCleanupPending'});

// Called by the installed Run's dispatch callback. The caller transfers this
// object to client-dispatch-owner before calling run, hence before any advance.
// Exactly one physical provider or already Store-confirmed saved read is used.
export function openNodeInferOperation({moon, preparedProgram, step, graph,
  registry, values, provider, savedCapture, savedSlots, quantityCapacity,
  physicalPreflight, egressAdmission, computeSuffix, signal, quantum = 256, observeProgress}) {
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
  const active = checked(savedSlots !== undefined
    ? moon.clientProgramStartRestoredInferSlotReplay(preparedProgram, step,
      graph, registry, values, savedSlots)
    : savedCapture === undefined
      ? moon.clientProgramStartScopedInferExecution(preparedProgram, step,
        graph, registry, values, provider)
      : moon.clientProgramStartRestoredInferReplay(preparedProgram, step,
        graph, registry, values, savedCapture));
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

  async function stop() {
    closing = true;
    requestStop();
    if (flight !== undefined) await flight.catch(() => {});
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

  return Object.freeze({run, stop, close, cleanup,
    cleanupPending: () => !reclaimed,
    physicalStopped: () => moon.clientProgramInferExecutionStopped(active),
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

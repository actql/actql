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
  registry, values, provider, savedCapture, savedSlots, signal, quantum = 256}) {
  if (!Number.isSafeInteger(quantum) || quantum < 1 || quantum > 2147483647 ||
      [provider, savedCapture, savedSlots].filter(value => value !== undefined)
        .length !== 1) {
    throw new TypeError('InvalidInstalledInferOperation');
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

  function close() {
    if (closeFlight === undefined) {
      closing = true;
      closeFlight = (async () => {
        requestStop();
        if (flight !== undefined) {
          // A primary Compute failure is not a cleanup failure. Retain its
          // original rejected promise; never invoke run again during cleanup.
          await flight.catch(() => {});
        }
        if (!moon.clientProgramInferExecutionStopped(active)) {
          const poll = checked(moon.clientProgramAdvanceInferExecution(active, 1));
          if (moon.clientProgramInferExecutionPollKind(poll) !== 'stopped' ||
              !moon.clientProgramInferExecutionStopped(active)) throw pending();
        }
        if (!cleanup()) throw pending();
      })();
      closeFlight.catch(() => {});
    }
    return closeFlight;
  }

  return Object.freeze({run, close, cleanup,
    cleanupPending: () => !reclaimed,
    physicalStopped: () => moon.clientProgramInferExecutionStopped(active),
    acquireOutput: () => moon.clientProgramAcquireInferOutput(active),
    acquireCapture: () => moon.clientProgramAcquireInferCapture(active),
    acquireOutcomes: () => moon.clientProgramAcquireInferOutcomes(active),
    invocationEvidence: slot => moon.clientProgramInferInvocationEvidence(active,
      slot),
  });
}

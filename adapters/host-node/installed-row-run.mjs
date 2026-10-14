// Private plumbing shared by installed row adapters. The adapter keeps its
// provider protocol, page admission and current authority; the existing
// RowRun remains the sole acquisition, capture and release owner.
import {checked} from '../host-common/runtime-result.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';

const fail = code => { throw Object.assign(new Error(code), {code}); };

export function startInstalledRowRun({moon, acquisition, nonce, ledger,
  capacity, keyed = false}) {
  if (keyed && ledger === undefined) fail('InstalledKeyedSourceLedgerRequired');
  const reportCapacity = capacity?.listingReport;
  if (reportCapacity !== undefined) {
    if (keyed) fail('InstalledListingSourceProgramMismatch');
    if (ledger === undefined) fail('InstalledListingSourceLedgerRequired');
    if (typeof moon.clientProgramRowSourceStartListingAccounted !== 'function') {
      fail('InstalledListingSourceUnavailable');
    }
  }
  const settled = new Set();
  let transportStopped = false;
  let transportRecovery;
  const run = checked(keyed
    ? moon.clientProgramKeyedRowStartAccounted(acquisition, nonce,
      attempt => settled.has(attempt), ledger, capacity.transferBytes,
      capacity.executionBytes, () => transportStopped)
    : reportCapacity !== undefined
    ? moon.clientProgramRowSourceStartListingAccounted(acquisition,
      reportCapacity, nonce, attempt => settled.has(attempt), ledger,
      capacity.transferBytes, capacity.executionBytes)
    : ledger === undefined
    ? moon.clientProgramRowSourceStart(acquisition, nonce,
      attempt => settled.has(attempt))
    : moon.clientProgramRowSourceStartAccounted(acquisition, nonce,
      attempt => settled.has(attempt), ledger, capacity.transferBytes,
      capacity.executionBytes));
  let closed = false;
  const close = () => {
    if (closed) return;
    if (ledger === undefined) moon.clientProgramRowSourceClose(run);
    else checked(moon.clientProgramRowSourceCloseAccounted(run));
    if (!checked(moon.clientProgramRowSourceCaptureCleanup(run))) {
      fail('InstalledSourceCleanupPending');
    }
    closed = true;
  };

  // Called only after the adapter has awaited its complete Site transport.
  async function capture({currentRead, signal}) {
    if (typeof currentRead !== 'function') fail('InstalledSourceReadUnavailable');
    signal?.throwIfAborted();
    await currentRead();
    signal?.throwIfAborted();
    if (closed) fail('InstalledSourceClosed');
    if (keyed && !transportStopped) fail('InstalledSourceTransportUnconfirmed');
    checked(moon.clientProgramRowSourceFinish(run));
    settled.add(moon.clientProgramRowSourceAttempt(run));
    if (keyed) return checked(moon.clientProgramKeyedRowRetain(run));
    checked(moon.clientProgramRowSourceCaptureBegin(run));
    while (true) {
      signal?.throwIfAborted();
      await currentRead();
      signal?.throwIfAborted();
      if (closed) fail('InstalledSourceClosed');
      const {_0: complete} = checked(
        moon.clientProgramRowSourceCaptureAdvance(run, 64));
      if (complete) break;
      await yieldEventLoop();
    }
    // Current authority may have changed during the bounded child resumes.
    await currentRead();
    signal?.throwIfAborted();
    if (closed) fail('InstalledSourceClosed');
    return checked(moon.clientProgramRowSourceCapture(run));
  }

  async function complete({owner, prepared, registry, values, fragment, ordered,
    retainedRelationOutput, currentRead, signal, captureOnly = false}) {
    if (keyed) fail('InstalledSourceProgramMismatch');
    const captured = await capture({currentRead, signal});
    const source = () => checked(
      moon.clientProgramRowSourceCaptureSource(captured));
    const capturedSource = source();
    const {checkedOwner, effectful, occurrence} = owner;
    if ((effectful
      ? occurrence.task === 0
        ? moon.clientProgramEffectCapturedSourceMatches(checkedOwner, capturedSource)
        : moon.clientProgramEffectCapturedSourceMatchesAt(checkedOwner,
          capturedSource, occurrence.task)
      : moon.clientProgramCapturedTaskSourceMatches(checkedOwner,
        capturedSource, occurrence.task)) !== true) {
      fail('InstalledSourceProgramMismatch');
    }
    const identity = checked(effectful
      ? moon.clientProgramIdentifyCapturedEffectSourceRelation(capturedSource)
      : moon.clientProgramIdentifyCapturedSourceRelation(capturedSource));
    const logicalInput = checked(effectful
      ? occurrence.task === 0
        ? moon.clientProgramEffectIssueCapturedSourceLogical(checkedOwner,
          capturedSource, identity, owner.requirement)
        : moon.clientProgramEffectIssueCapturedSourceLogicalAt(checkedOwner,
          capturedSource, identity, owner.requirement, occurrence.task)
      : moon.clientProgramIssueCapturedTaskSourceLogical(checkedOwner,
        capturedSource, identity, owner.requirement, occurrence.task));
    // The checked graph selects the Model boundary. Carry the original
    // acquisition tuple to that owner instead of opening a pure Compute Run.
    const inferStep = effectful || ledger !== undefined ? undefined :
      moon.clientProgramSelectedInferStep(checkedOwner);
    const inferInventory = effectful || ledger !== undefined ? undefined :
      moon.clientProgramComposedInferOccurrences(checkedOwner);
    const composedInfer = inferInventory?.$tag === 1 && inferInventory._0.length > 1;
    // Accounted and Effect computation is opened later by the common Host.
    const openHost = retainedRelationOutput
      ? moon.clientProgramOpenCapturedLocalRetainedHost
      : moon.clientProgramOpenCapturedLocalHost;
    const setup = captureOnly || effectful || ledger !== undefined ||
      inferStep !== undefined || composedInfer ? undefined :
      openHost(checkedOwner, capturedSource, registry, values, 1n, 0n, 0n, 0n,
        fragment, ordered);
    if (!captureOnly && !effectful && ledger === undefined &&
        inferStep === undefined && !composedInfer && setup === undefined) {
      fail('InstalledSourceHostUnavailable');
    }
    return Object.freeze({checkedSource: prepared.checkedSource, identity,
      logicalInput, requirement: owner.requirement, setup, occurrence,
      capturedSource, inferStep, composedInfer,
      capture: Object.freeze({source,
        originalRead: () => {
          if (closed) fail('InstalledSourceClosed');
          return moon.clientProgramRowSourceOriginalRead(captured);
        },
        ...(ledger === undefined ? {} : {retainTask: (dag, task) => checked(
          moon.clientProgramRowSourceRetainCapturedTask(captured, dag, task))})}),
      issueSourceEvidence: async ({authorityScopeCid, effectiveDataPolicyCid}) => {
        await currentRead();
        return checked(moon.clientProgramRowSourceIssueSourceEvidence(
          acquisition, captured, identity, logicalInput, authorityScopeCid,
          effectiveDataPolicyCid, new Date().toISOString()));
      },
      close});
  }

  // This admission follows an awaited Site page, rechecking current authority
  // around bounded resumes. Values never escape as an unowned row array.
  async function consumeKeyedPage(body, {charge, currentRead, signal}) {
    if (!keyed) fail('InstalledSourceProgramMismatch');
    signal?.throwIfAborted();
    await currentRead();
    signal?.throwIfAborted();
    if (closed) fail('InstalledSourceClosed');
    checked(charge === undefined
      ? moon.clientProgramKeyedRowBeginPage(run, body)
      : moon.clientProgramKeyedRowBeginChargedPage(run, charge, body));
    while (true) {
      signal?.throwIfAborted();
      await currentRead();
      signal?.throwIfAborted();
      if (closed) fail('InstalledSourceClosed');
      const [status, rows] = checked(
        moon.clientProgramKeyedRowAdvancePage(run, 64));
      if (status === 1) return rows;
      if (status !== 0) fail('InvalidHostRuntimeResult');
      await yieldEventLoop();
    }
  }

  async function cleanup() {
    if (closed) return true;
    if (keyed && !transportStopped) {
      if (transportRecovery === undefined) return false;
      const finished = await transportRecovery.cleanup();
      if (finished === false || transportRecovery.cleanupPending()) return false;
      transportStopped = true;
    }
    // Recovery owns this same RowRun after close failed/pended. The common
    // retry refuses any run not already closed, and advances only its stop.
    if (!checked(moon.clientProgramRowSourceCaptureCleanupAdvance(run, 64))) {
      await yieldEventLoop();
      return false;
    }
    close();
    return true;
  }

  function closeAfterFailure(state, recovery) {
    if (keyed) transportRecovery = recovery;
    try { close(); }
    catch {
      state.closeFailed = true;
      state.recovery = Object.freeze({
        close() {},
        cleanup,
        cleanupPending: () => !closed,
      });
    }
  }
  return Object.freeze({run, close, capture, complete, cleanup, closeAfterFailure,
    consumeKeyedPage,
    // Only the installed adapter's transport boundary calls this observation.
    // It authorizes cleanup, never response evidence or successful retention.
    confirmTransportStopped() { transportStopped = true; }});
}

// Private plumbing shared by installed row adapters. The adapter keeps its
// provider protocol, page admission and current authority; the existing
// RowRun remains the sole acquisition, capture and release owner.
import {runtimeField, runtimeIsOk} from '../host-common/compiler-binding.generated.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {setImmediate as yieldEventLoop} from 'node:timers/promises';
import {types as nodeTypes} from 'node:util';

const fail = code => { throw Object.assign(new Error(code), {code}); };

export function startInstalledRowRun({moon, acquisition, nonce, ledger,
  capacity, keyed = false, originalRead, originalKeyedRead, wholeInput = false}) {
  if (wholeInput && (keyed || originalRead === undefined || ledger === undefined ||
      capacity?.provider === undefined || capacity?.listingReport !== undefined)) {
    fail('InstalledWholeSourceReadUnavailable');
  }
  if (keyed && ledger === undefined) fail('InstalledKeyedSourceLedgerRequired');
  const reportCapacity = capacity?.listingReport;
  const providerCapacity = capacity?.provider;
  if (originalKeyedRead !== undefined) {
    if (!keyed || ledger === undefined || originalRead !== undefined ||
        reportCapacity !== undefined || providerCapacity !== undefined) {
      fail('InstalledKeyedSourceRunLedgerRequired');
    }
    if (['clientProgramInstalledKeyedSourceReadCheckLedger',
      'clientProgramInstalledKeyedSourceReadStartRows',
      'clientProgramInstalledKeyedSourceReadRetire']
      .some(name => typeof moon[name] !== 'function')) fail('InstalledKeyedSourceReadUnavailable');
    checked(moon.clientProgramInstalledKeyedSourceReadCheckLedger(originalKeyedRead, ledger));
  }
  if (originalRead !== undefined) {
    if (ledger === undefined || keyed || reportCapacity !== undefined) {
      fail('InstalledSourceRunLedgerRequired');
    }
    if (['clientProgramInstalledSourceReadCheckLedger',
      wholeInput ? 'clientProgramInstalledWholeSourceReadStartRows'
      : providerCapacity === undefined ? 'clientProgramInstalledSourceReadStartRows'
        : 'clientProgramInstalledSourceReadStartProviderRows',
      'clientProgramInstalledSourceReadRetire']
      .some(name => typeof moon[name] !== 'function')) fail('InstalledSourceReadUnavailable');
    // The Source-only child's limits cannot stand in for the original Run.
    // Check actual nominal accounting before any RowRun or physical read.
    checked(moon.clientProgramInstalledSourceReadCheckLedger(originalRead, ledger));
  }
  if (providerCapacity !== undefined) {
    if (keyed || reportCapacity !== undefined) fail('InstalledProviderSourceProgramMismatch');
    if (ledger === undefined) fail('InstalledProviderSourceLedgerRequired');
    if ([wholeInput ? 'clientProgramInstalledWholeSourceReadStartRows'
      : originalRead === undefined ? 'clientProgramRowSourceStartProviderAccounted'
      : 'clientProgramInstalledSourceReadStartProviderRows',
      wholeInput ? 'clientProgramWholeSourceBorrowResponses' : 'clientProgramRowSourceBorrowResponses',
      'clientProgramRowSourceBindResponseCleanup',
      ...(!wholeInput ? ['clientProgramRowSourceRetireResponseWorkspace'] : [])]
      .some(name => typeof moon[name] !== 'function')) fail('InstalledProviderSourceUnavailable');
  }
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
  const run = checked(wholeInput
    ? moon.clientProgramInstalledWholeSourceReadStartRows(originalRead, acquisition,
      nonce, attempt => settled.has(attempt), capacity.transferBytes, capacity.executionBytes)
    : originalKeyedRead !== undefined
    ? moon.clientProgramInstalledKeyedSourceReadStartRows(originalKeyedRead, acquisition,
      nonce, attempt => settled.has(attempt), capacity.transferBytes,
      capacity.executionBytes, () => transportStopped)
    : keyed
    ? moon.clientProgramKeyedRowStartAccounted(acquisition, nonce,
      attempt => settled.has(attempt), ledger, capacity.transferBytes,
      capacity.executionBytes, () => transportStopped)
    : reportCapacity !== undefined
    ? moon.clientProgramRowSourceStartListingAccounted(acquisition,
      reportCapacity, nonce, attempt => settled.has(attempt), ledger,
      capacity.transferBytes, capacity.executionBytes)
    : providerCapacity !== undefined && originalRead !== undefined
    ? moon.clientProgramInstalledSourceReadStartProviderRows(originalRead, acquisition,
      providerCapacity, nonce, attempt => settled.has(attempt),
      capacity.transferBytes, capacity.executionBytes)
    : providerCapacity !== undefined
    ? moon.clientProgramRowSourceStartProviderAccounted(acquisition,
      providerCapacity, nonce, attempt => settled.has(attempt), ledger,
      capacity.transferBytes, capacity.executionBytes)
    : originalRead !== undefined
    ? moon.clientProgramInstalledSourceReadStartRows(originalRead, acquisition,
      nonce, attempt => settled.has(attempt), capacity.transferBytes, capacity.executionBytes)
    : ledger === undefined
    ? moon.clientProgramRowSourceStart(acquisition, nonce,
      attempt => settled.has(attempt))
    : moon.clientProgramRowSourceStartAccounted(acquisition, nonce,
      attempt => settled.has(attempt), ledger, capacity.transferBytes,
      capacity.executionBytes));
  let closed = false;
  let sourceEvidenceOriginal, sourceEvidenceCapture;
  let sourceEvidencePreparing = false;
  let nativeRecoveryCleanup, nativeRecoveryPending, nativeRecoveryFlight;
  let readerPrepared = false, readerStarted = false, readerReadPending = false;
  let readerStopRequested = false;
  let reader, readerRead, readerStop, readerObserve, readerRetry;
  let readerStopPending = false, readerStopFailure;
  const readerRetired = () => {
    if (readerReadPending || readerStopPending) return false;
    if (readerObserve === undefined) {
      // A refusing factory/getter may have supplied only its early original
      // preparation. Reuse the existing reader/retire slots; its own method
      // closes any partial child and retires managed aliases, not this RowRun.
      if (reader === undefined || readerRetry === undefined) return false;
      const original = reader, retire = readerRetry;
      let synchronous = true;
      readerStopPending = true;
      try {
        const retired = Reflect.apply(retire, original, []);
        if (nodeTypes.isPromise(retired)) {
          // Invalid async retirement is never an ACK. Keep this same flight
          // before permitting another attempt, and handle its rejection.
          synchronous = false; readerStopPending = retired;
          Promise.prototype.then.call(retired,
            () => {if (readerStopPending === retired) readerStopPending = false;},
            cause => {if (readerStopPending === retired) {
              readerStopFailure = cause; readerStopPending = false;
            }});
          return false;
        }
        return reader === original && readerRetry === retire &&
          readerObserve === undefined && readerRead === undefined && retired === true;
      } finally {if (synchronous) readerStopPending = false;}
    }
    // This is the same trusted reader's observation, not a packet Bool, the
    // read Promise's settlement, or the credential Site's close result.
    return Reflect.apply(readerObserve, reader, [])?.cleanupConfirmed === true;
  };
  const stopReader = () => {
    if (readerStop === undefined || readerStopPending) return;
    const retrying = readerStopRequested;
    if (retrying && readerRetry === undefined) return;
    readerStopRequested = true;
    try {
      const stopping = Reflect.apply(retrying ? readerRetry : readerStop, reader, []);
      if (stopping !== undefined) {
        // A pending stop/cancel request is not retirement. Handle its original
        // rejection without blocking cleanup forever or issuing another stop.
        readerStopPending = true;
        Promise.resolve(stopping).then(() => { readerStopPending = false; },
          error => { readerStopFailure = error; readerStopPending = false; });
      }
    } catch (error) { readerStopFailure = error; }
  };
  const close = () => {
    if (closed) return;
    if (!keyed && transportRecovery !== undefined && !transportStopped) fail('InstalledSourceCleanupPending');
    if (providerCapacity !== undefined) stopReader();
    if (ledger === undefined) moon.clientProgramRowSourceClose(run);
    else checked(moon.clientProgramRowSourceCloseAccounted(run));
    if (!checked(moon.clientProgramRowSourceCaptureCleanup(run))) {
      fail('InstalledSourceCleanupPending');
    }
    if (originalRead !== undefined) checked(moon.clientProgramInstalledSourceReadRetire(originalRead));
    if (originalKeyedRead !== undefined) checked(moon.clientProgramInstalledKeyedSourceReadRetire(originalKeyedRead));
    closed = true;
    sourceEvidenceOriginal = sourceEvidenceCapture = undefined;
    reader = readerRead = readerStop = readerObserve = readerRetry = undefined;
    readerPrepared = false;
    if (!keyed) {
      // Only after external ACK and Core capture/read retirement. A closed
      // cleanup handle keeps terminal state, not the original native owner.
      transportRecovery = nativeRecoveryCleanup = nativeRecoveryPending = nativeRecoveryFlight = undefined;
    }
    if (readerStopFailure !== undefined) throw readerStopFailure;
  };

  // The trusted installation supplies a pure reader preparer, never a public
  // Run packet. Install the same-acquisition Core borrow before entering it;
  // even a throwing factory/getter leaves that original reservation pending.
  async function readProvider({prepare, receiver, options}) {
    const verifyRead = options?.verifyRead, signal = options?.signal;
    if (providerCapacity === undefined || typeof prepare !== 'function' ||
        typeof verifyRead !== 'function') {
      fail('InstalledProviderSourceUnavailable');
    }
    if (closed || readerPrepared) fail('InstalledSourceReaderAlreadyPrepared');
    readerPrepared = true;
    const borrow = checked(wholeInput ? moon.clientProgramWholeSourceBorrowResponses(run, acquisition)
      : moon.clientProgramRowSourceBorrowResponses(run, acquisition));
    // Replace the existing one-shot preparation flag with its SAME original
    // borrow; no extra retained carrier or second reader owner is introduced.
    readerPrepared = borrow;
    checked(moon.clientProgramRowSourceBindResponseCleanup(borrow, readerRetired));
    const grow = moon.clientProgramRowSourceGrowResponseCapacity;
    const growConstruction = moon.clientProgramRowSourceGrowResponseConstructionCapacity;
    const reserveResponseCapacity = typeof grow !== 'function' ? undefined
      : (capacity, phase) => {
        if (closed || !readerReadPending || readerStopRequested) fail('InstalledSourceClosed');
        signal?.throwIfAborted();
        // IPC announces bytes before a received page exists. It must reserve
        // against this SAME original before Buffer/JSON construction; only the
        // existing one-argument path consumes a live page's charged entrance.
        const selected = phase === undefined ? grow
          : phase === 'announced-body' ? growConstruction : undefined;
        if (typeof selected !== 'function') fail('InstalledSourceResponseConstructionUnavailable');
        checked(Reflect.apply(selected, moon, [borrow, capacity]));
        // The original Resource callback already checked currentness. Reentry
        // still cannot use a closed reader after that same checked mutation.
        if (closed || !readerReadPending || readerStopRequested) fail('InstalledSourceClosed');
        signal?.throwIfAborted();
      };
    // Keep the original options object and every original callback receiver.
    // The separate private constructor argument supplies only this SAME
    // RowRun's growth function and SAME bound response borrow, never a copied
    // selection, reconstructed input or another issuer.
    const retainPreparation = original => {
      if (closed || reader !== undefined) fail('InstalledSourcePreparationAlreadyRetained');
      // Retain the original before descriptor validation can fail or reenter.
      reader = original;
      if (original === null || typeof original !== 'object' || nodeTypes.isProxy(original)) {
        fail('InvalidInstalledSourcePreparation');
      }
      const retire = Object.getOwnPropertyDescriptor(original, 'retire');
      if (!retire || !Object.hasOwn(retire, 'value') || typeof retire.value !== 'function' ||
          nodeTypes.isProxy(retire.value) || nodeTypes.isAsyncFunction(retire.value)) {
        fail('InvalidInstalledSourcePreparation');
      }
      readerRetry = retire.value;
    };
    const preparedReader = Reflect.apply(prepare, receiver,
      [options, retainPreparation, reserveResponseCapacity, borrow]);
    // Suppliers without the early port keep their old conservative custody.
    // An early original must survive every fallible returned-method getter.
    if (reader === undefined) reader = preparedReader;
    if (typeof preparedReader?.then === 'function') {
      // Preparation must be synchronous and I/O-free. An accidental async
      // factory is never adopted later, but its rejection must still be handled.
      Promise.resolve(preparedReader).catch(error => { readerStopFailure = error; });
      fail('InvalidInstalledSourceReader');
    }
    const read = preparedReader?.read, stop = preparedReader?.requestStop;
    const observe = preparedReader?.observe, retry = preparedReader?.retry;
    if ([read, stop, observe].some(method => typeof method !== 'function')) {
      fail('InvalidInstalledSourceReader');
    }
    if (retry !== undefined && typeof retry !== 'function') fail('InvalidInstalledSourceReader');
    if (closed || readerStopRequested) fail('InstalledSourceClosed');
    reader = preparedReader;
    readerRead = read; readerStop = stop; readerObserve = observe; readerRetry = retry;
    // Methods and receiver are captured once before the first physical read.
    readerReadPending = true;
    try {
      signal?.throwIfAborted();
      await Reflect.apply(verifyRead, options, []);
      signal?.throwIfAborted();
      if (closed || readerStopRequested) fail('InstalledSourceClosed');
      readerStarted = true;
      return await Reflect.apply(readerRead, reader, []);
    }
    finally { readerReadPending = false; }
  }

  // Called only after the adapter has awaited its complete Site transport.
  async function capture({currentRead, signal}) {
    if (typeof currentRead !== 'function') fail('InstalledSourceReadUnavailable');
    signal?.throwIfAborted();
    await currentRead();
    signal?.throwIfAborted();
    if (closed) fail('InstalledSourceClosed');
    if (keyed && !transportStopped) fail('InstalledSourceTransportUnconfirmed');
    if (providerCapacity !== undefined && (!readerStarted || readerReadPending)) {
      fail('InstalledSourceReaderUnavailable');
    }
    checked(moon.clientProgramRowSourceFinish(run));
    settled.add(moon.clientProgramRowSourceAttempt(run));
    if (keyed) return checked(moon.clientProgramKeyedRowRetain(run));
    checked(moon.clientProgramRowSourceCaptureBegin(run));
    while (true) {
      signal?.throwIfAborted();
      await currentRead();
      signal?.throwIfAborted();
      if (closed) fail('InstalledSourceClosed');
      let compilerTuple1 = checked(
        moon.clientProgramRowSourceCaptureAdvance(run, 64));
      const complete = runtimeField(compilerTuple1, 0);
      compilerTuple1 = undefined;
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
    if (providerCapacity !== undefined && !wholeInput) {
      // This SAME reader must actually retire its response/decode workspace
      // before Source/Compute/Effect consumers may use that phase allowance.
      // Keep its observer and receiver for final Row cleanup, including a
      // pending/throwing retirement; stopping alone never returns bytes.
      stopReader();
      // Core invokes the SAME bound observer once for this cut. Do not first
      // observe it here and then repeat that external observation in Core.
      checked(moon.clientProgramRowSourceRetireResponseWorkspace(readerPrepared));
      signal?.throwIfAborted();
      if (closed) fail('InstalledSourceClosed');
    }
    const source = () => checked(
      moon.clientProgramRowSourceCaptureSource(captured));
    const capturedSource = source();
    const {checkedOwner, effectful, occurrence} = owner;
    if (!(effectful && wholeInput) && (effectful
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
    const logicalInput = checked(wholeInput
      ? effectful
        ? moon.clientProgramIssueEffectWholeSourceInputLogical(checkedOwner,
          capturedSource, identity, owner.providerCaptureCapacity)
        : moon.clientProgramIssueWholeSourceInputLogical(checkedOwner,
          capturedSource, identity, owner.providerCaptureCapacity)
      : effectful
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
    const composedInfer = runtimeIsOk(inferInventory) && runtimeField(inferInventory, 0).length > 1;
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
    const evidenceIssuer = wholeInput ? moon.clientProgramWholeSourceIssueSourceEvidenceOriginal
      : moon.clientProgramRowSourceIssueSourceEvidenceOriginal;
    const captureAccess = Object.freeze({source,
      ...(wholeInput ? {originalWholeInput() {
        if (this !== captureAccess || closed) fail('ForeignInstalledSourceCapture');
        // The same native capture owns its Run association and live input.
        // This private view cannot create a Source observation or permission.
        source();
        return captured;
      }} : {}),
      ...(!wholeInput ? {originalRowCapture() {
        if (this !== captureAccess || closed) fail('ForeignInstalledSourceCapture');
        // This is the SAME accounted capture retained above, not a second
        // capture, permission, Source observation or cleanup acknowledgement.
        source();
        return captured;
      }} : {}),
      originalRead: () => {
        if (closed) fail('InstalledSourceClosed');
        return moon.clientProgramRowSourceOriginalRead(captured);
      },
      takeSourceEvidenceOriginal() {
        if (this !== captureAccess) fail('ForeignInstalledSourceCapture');
        if (closed) fail('InstalledSourceClosed');
        if (sourceEvidenceCapture !== captured || sourceEvidenceOriginal === undefined) {
          fail('InstalledSourceEvidenceUnavailable');
        }
        const original = sourceEvidenceOriginal;
        sourceEvidenceOriginal = sourceEvidenceCapture = undefined;
        return original;
      },
      ...(ledger === undefined ? {} : {retainTask: (dag, task) => checked(
        wholeInput ? moon.clientProgramWholeSourceCheckComputeBinding(captured, dag, task)
          : moon.clientProgramRowSourceRetainCapturedTask(captured, dag, task))})});
    return Object.freeze({checkedSource: prepared.checkedSource, identity,
      logicalInput, ...(wholeInput ? {} : {requirement: owner.requirement}), setup, occurrence,
      capturedSource, inferStep, composedInfer,
      capture: captureAccess,
      prepareSourceEvidenceOriginal: async ({authorityScopeCid, effectiveDataPolicyCid}) => {
        if (closed) fail('InstalledSourceClosed');
        if (typeof evidenceIssuer !== 'function') fail('InstalledSourceEvidenceUnavailable');
        if (sourceEvidencePreparing || sourceEvidenceOriginal !== undefined) {
          fail('InstalledSourceEvidencePending');
        }
        sourceEvidencePreparing = true;
        try {
          await currentRead();
          if (closed) fail('InstalledSourceClosed');
          const original = checked(Reflect.apply(evidenceIssuer, moon,
            [acquisition, captured, identity, logicalInput, authorityScopeCid,
              effectiveDataPolicyCid, new Date().toISOString()]));
          if (closed) fail('InstalledSourceClosed');
          if (original === undefined) fail('InstalledSourceEvidenceUnavailable');
          sourceEvidenceOriginal = original;
          sourceEvidenceCapture = captured;
        } finally { sourceEvidencePreparing = false; }
      },
      issueSourceEvidence: async ({authorityScopeCid, effectiveDataPolicyCid}) => {
        await currentRead();
        const issuer = wholeInput ? moon.clientProgramWholeSourceIssueSourceEvidence
          : moon.clientProgramRowSourceIssueSourceEvidence;
        return checked(Reflect.apply(issuer, moon, [
          acquisition, captured, identity, logicalInput, authorityScopeCid,
          effectiveDataPolicyCid, new Date().toISOString()]));
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
    if (!keyed && transportRecovery !== undefined && !transportStopped) {
      if (typeof nativeRecoveryCleanup !== 'function' || typeof nativeRecoveryPending !== 'function') return false;
      if (nativeRecoveryFlight === undefined) {
        // Keep the same operation before invoking an external cleanup. Other
        // callers await it; a later retry is possible only after it settles.
        nativeRecoveryFlight = Promise.resolve().then(async () => {
          const stopped = await Reflect.apply(nativeRecoveryCleanup, transportRecovery, []);
          if (stopped !== true || Reflect.apply(nativeRecoveryPending, transportRecovery, []) !== false) return false;
          transportStopped = true; return true;
        });
      }
      const work = nativeRecoveryFlight;
      try {if (await work !== true) return false;}
      finally {if (nativeRecoveryFlight === work) nativeRecoveryFlight = undefined;}
      if (closed) return true;
    }
    if (providerCapacity !== undefined) {
      stopReader();
      if (!readerRetired()) return false;
    }
    if (keyed && !transportStopped) {
      if (transportRecovery === undefined) return false;
      const finished = await transportRecovery.cleanup();
      if (finished === false || transportRecovery.cleanupPending()) return false;
      transportStopped = true;
    }
    // Advance only this original RowRun's stopped child. A prior close may
    // have failed before the common Owner closed the run; that refusal is not
    // a release ACK. Retry the same close, which must itself confirm cleanup.
    let ready;
    try {
      ready = checked(moon.clientProgramRowSourceCaptureCleanupAdvance(run, 64));
    } catch {
      close();
      return true;
    }
    if (!ready) {
      await yieldEventLoop();
      return false;
    }
    close();
    return true;
  }

  function closeAfterFailure(state, recovery) {
    if (keyed) transportRecovery = recovery;
    else if (recovery !== undefined && transportRecovery === undefined) {
      // The same RowRun owns the recovery and its Core retirement. Retain the
      // original receiver before method getters can throw or reenter.
      transportRecovery = recovery; transportStopped = false;
      try {
        nativeRecoveryCleanup = recovery.cleanup;
        nativeRecoveryPending = recovery.cleanupPending;
      } catch {
        nativeRecoveryCleanup = nativeRecoveryPending = undefined;
      }
    }
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
  return Object.freeze({run, close, capture, complete, cleanup, closeAfterFailure, readProvider,
    consumeKeyedPage,
    // Only the installed adapter's transport boundary calls this observation.
    // It authorizes cleanup, never response evidence or successful retention.
    confirmTransportStopped() { transportStopped = true; }});
}

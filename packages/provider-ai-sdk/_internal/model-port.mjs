import {pollSdkPreparation, sdkPreparedRequest, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  cancelSdkPreparation, cleanupSdkPreparation,
  retireSdkDecodedResult} from './intercepted-request.mjs';

// Private source integration only: not an exported package installation API.
// All records, SDK/request/response buffers and Promise overlaps must be funded
// by the original Run Ledger before this port is installed. No budget, grant,
// execution state or scheduler is inferred here. Common owns every transition.
export function createSdkModelPreflight({moon, request, preparation, profile,
  installation, quantities, fetch, responseLimits, persistRaw, notify, checked,
  observeAt, cleanupRaw, preparationProgress, rawCaptureBinder}) {
  const deferredRaw = rawCaptureBinder !== undefined;
  if (typeof fetch !== 'function' ||
      (deferredRaw ? typeof rawCaptureBinder !== 'function' ||
        persistRaw !== undefined || cleanupRaw !== undefined ||
        preparation !== undefined || preparationProgress === undefined
        : typeof persistRaw !== 'function' || typeof cleanupRaw !== 'function') ||
      typeof notify !== 'function' || typeof checked !== 'function' ||
      typeof observeAt !== 'function' ||
      preparationProgress !== undefined && (preparation !== undefined ||
        typeof preparationProgress?.advance !== 'function' ||
        typeof preparationProgress?.cleanup !== 'function')) {
    throw new TypeError('InvalidSdkModelPort');
  }
  let plan;
  let call;
  let response;
  let saving;
  let reconciling;
  let reconciliationPending = false;
  let reconciled;
  let saveStarted = false;
  let failure;
  let startUnknown = false;
  let preparationTerminal = false;
  let retired = false;
  let rawBound = !deferredRaw;
  const wake = () => {
    try { notify(); } catch { /* Wake is not execution or persistence evidence. */ }
  };
  const poll = () => {
    // Only the unused SDK projection is dropped. Saved/raw observations and
    // the same Store/Entry cleanup obligation remain owned independently.
    if (!retired && preparation !== undefined) retireSdkDecodedResult(preparation);
    if (response !== undefined) return moon.clientProgramModelPhysicalSavedChat(response);
    if (failure !== undefined || startUnknown) return moon.clientProgramModelPhysicalUnknown();
    if (retired) {
      throw Object.assign(new TypeError('ForeignSdkPreparation'), {code: 'ForeignSdkPreparation'});
    }
    const observed = pollSdkTransport(preparation);
    const raw = sdkTransportRawObservation(preparation);
    if (raw !== undefined && !saveStarted) {
      saveStarted = true;
      // The installed persistence port must use this exact original call and
      // raw backing, reconfirm Store bytes, and return its nominal saved view.
      // No SDK decoded defaults supply Common's answer or usage observations.
      saving = Promise.resolve().then(() => persistRaw(call, raw)).then(saved => {
        response = saved.response;
        if (response === undefined) throw new TypeError('MissingSavedRawChat');
      }).catch(error => {
        failure = error;
      }).finally(() => { saving = undefined; wake(); });
    }
    if (saveStarted) return moon.clientProgramModelPhysicalPending();
    return observed.kind === 'unknown'
      ? moon.clientProgramModelPhysicalUnknown()
      : moon.clientProgramModelPhysicalPending();
  };
  const cancel = () => {
    if (retired) {
      throw Object.assign(new TypeError('ForeignSdkPreparation'), {code: 'ForeignSdkPreparation'});
    }
    if (preparation !== undefined) cancelSdkPreparation(preparation);
  };
  const cleanup = () => {
    if (retired) return true;
    if (preparation !== undefined) retireSdkDecodedResult(preparation);
    if (saving !== undefined || reconciliationPending) return false;
    // Every attempted raw save retains its original port until cleanup,
    // including a successful save's local aliases. This does not erase the
    // parent's durable receipt/custody. Failed commit/cleanup stays pending.
    if (saveStarted || failure !== undefined || deferredRaw && rawBound) {
      try {
        if (cleanupRaw(call) !== true) return false;
      } catch { return false; }
    }
    if (preparation !== undefined && !cleanupSdkPreparation(preparation)) return false;
    if (preparationProgress !== undefined) {
      try { if (preparationProgress.cleanup() !== true) return false; }
      catch { return false; }
    }
    response = undefined;
    reconciled = undefined;
    reconciling = undefined;
    call = undefined;
    plan = undefined;
    // Escaped preflight/call closures must not keep the factory's original
    // input or installed callbacks after both original owners acknowledge
    // cleanup. Pending/failed cleanup retains them unchanged for retry.
    // Escaped immutable views and the primary failure retain their own
    // responsibility; clearing these aliases does not mutate those originals.
    request = undefined;
    preparation = undefined;
    preparationProgress = undefined;
    profile = undefined;
    installation = undefined;
    quantities = undefined;
    fetch = undefined;
    responseLimits = undefined;
    persistRaw = undefined;
    notify = undefined;
    checked = undefined;
    observeAt = undefined;
    cleanupRaw = undefined;
    retired = true;
    return true;
  };
  const start = entry => {
    // Missing installation custody is not send permission. Core keeps an
    // already entered attempt's unknown responsibility when no call starts.
    // This is a local data check, with no callback or await at the final gate.
    if (retired || call !== undefined || startUnknown) return undefined;
    if (!rawBound) { startUnknown = true; return undefined; }
    call = moon.clientProgramModelPhysicalCallForRequest(entry, request, poll, cancel, cleanup);
    if (call === undefined) { startUnknown = true; return undefined; }
    // Exact fixed transport only, immediately after Common's final gate. No
    // await, notification, user callback or request rebuilding occurs here.
    try { startSdkTransport(preparation); }
    catch { startUnknown = true; }
    return call;
  };
  const advance = () => {
    if (retired) return [true, undefined];
    if (plan !== undefined) return [true, plan];
    if (preparationTerminal) return [true, undefined];
    if (preparation===undefined && preparationProgress!==undefined) {
      try {
        const projected=preparationProgress.advance();
        if (projected.kind==='pending') return [false,undefined];
        if (projected.kind!=='ready' || projected.preparation===undefined) {
          preparationTerminal=true;
          return [true,undefined];
        }
        preparation=projected.preparation;
      } catch {
        preparationTerminal=true;
        return [true,undefined];
      }
      // SDK async readiness is a later advance, never another Common poll in
      // this same bounded physical-preflight transition.
      return [false,undefined];
    }
    const preparationState = pollSdkPreparation(preparation);
    if (preparationState.kind === 'pending') return [false, undefined];
    if (preparationState.kind !== 'ready') return [true, undefined];
    const original = sdkPreparedRequest(preparation);
    // Freeze fetch/init/bounds before Common consumes its one-shot Entry.
    preparationTerminal = true;
    try {
      prepareSdkTransport(preparation, {fetch, responseLimits, observeAt});
      plan = checked(moon.clientProgramModelAsyncPhysicalRequestPlan(request,
        BigInt(original.requestBytes), quantities.tokens, quantities.costUnits,
        quantities.durationMs, profile, installation, start));
    } catch { return [true, undefined]; }
    return [true, plan];
  };
  if (deferredRaw) {
    // The same original operation retains this private binder before its
    // Common preflight cursor is issued. Only its installed continuation
    // supplies the actual Store port after nominal raw registration.
    const bound = rawCaptureBinder((registration, persistence) => {
      if (retired || rawBound || registration === undefined ||
          typeof persistence !== 'function' || typeof persistence.cleanup !== 'function') {
        throw new TypeError('OriginalSdkRawBindingUnavailable');
      }
      persistRaw = persistence;
      cleanupRaw = persistence.cleanup;
      rawBound = true;
    });
    if (bound !== undefined) throw new TypeError('OriginalSdkRawBinderUnavailable');
    rawCaptureBinder = undefined;
  }
  // The pinned MoonBit JS tuple ABI is a field record, not a JS Array.
  const preflight = moon.clientProgramModelRequestPreflight(() => {
    const [terminal, physicalPlan] = advance();
    return {_0: terminal, _1: physicalPlan};
  }, cleanup);
  return Object.freeze({preflight,
    reconcileRaw(original) {
      // An explicit parent request only. Reuse the same observed transport
      // backing and persistence port, never re-enter the physical operation.
      // The saved view is returned for Common's reconciliation/usage reader;
      // it does not replace a terminal Unknown or issue answer/send authority.
      if (retired || call === undefined || original !== call ||
          !saveStarted || failure === undefined || saving !== undefined) {
        return Promise.reject(new TypeError('OriginalRawReconciliationUnavailable'));
      }
      if (reconciling !== undefined) return reconciling;
      const raw = sdkTransportRawObservation(preparation);
      if (raw === undefined) {
        return Promise.reject(new TypeError('MissingOriginalRawObservation'));
      }
      // This private initial physical shape owns one stable reconfirmation
      // Promise/view, including failure. Further recovery requires an explicit
      // owner-funded token/lifetime; it is not a language-level retry ban.
      reconciliationPending = true;
      reconciling = Promise.resolve().then(() => persistRaw(call, raw))
        .then(saved => {
          if (saved?.response === undefined) throw new TypeError('MissingSavedRawChat');
          reconciled = saved.response;
          return saved;
        }).finally(() => { reconciliationPending = false; wake(); });
      return reconciling;
    },
    readReconciledUsage(original, quantum) {
      if (retired || original !== call || reconciled === undefined ||
          !Number.isInteger(quantum) || quantum < 1 || quantum > 2_147_483_647) {
        throw new TypeError('OriginalRawUsageUnavailable');
      }
      return checked(moon.clientProgramReadReconciledInferRawUsage(
        original, reconciled, quantum));
    },
    // Private retained responsibility for the parent owner, never a public
    // success/result or authority. A failed save is not automatically retried.
    rawFailure: () => failure,
  });
}

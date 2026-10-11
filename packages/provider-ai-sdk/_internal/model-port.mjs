import {pollSdkPreparation, sdkPreparedRequest, prepareSdkTransport,
  startSdkTransport, pollSdkTransport, sdkTransportRawObservation,
  cancelSdkPreparation, cleanupSdkPreparation} from './intercepted-request.mjs';

// Private source integration only: not an exported package installation API.
// All records, SDK/request/response buffers and Promise overlaps must be funded
// by the original Run Ledger before this port is installed. No budget, grant,
// execution state or scheduler is inferred here. Common owns every transition.
export function createSdkModelPreflight({moon, request, preparation, profile,
  installation, quantities, fetch, responseLimits, persistRaw, notify, checked,
  observeAt, cleanupRaw}) {
  if (typeof fetch !== 'function' || typeof persistRaw !== 'function' ||
      typeof notify !== 'function' || typeof checked !== 'function' ||
      typeof observeAt !== 'function' || typeof cleanupRaw !== 'function') {
    throw new TypeError('InvalidSdkModelPort');
  }
  let prepared;
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
  const wake = () => {
    try { notify(); } catch { /* Wake is not execution or persistence evidence. */ }
  };
  const poll = () => {
    if (response !== undefined) return moon.clientProgramModelPhysicalSavedChat(response);
    if (failure !== undefined || startUnknown) return moon.clientProgramModelPhysicalUnknown();
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
  const cancel = () => cancelSdkPreparation(preparation);
  const cleanup = () => {
    if (retired) return true;
    if (saving !== undefined || reconciliationPending) return false;
    // Every attempted raw save retains its original port until cleanup,
    // including a successful save's local aliases. This does not erase the
    // parent's durable receipt/custody. Failed commit/cleanup stays pending.
    if (saveStarted || failure !== undefined) {
      try {
        if (cleanupRaw(call) !== true) return false;
      } catch { return false; }
    }
    if (!cleanupSdkPreparation(preparation)) return false;
    response = undefined;
    reconciled = undefined;
    reconciling = undefined;
    call = undefined;
    prepared = undefined;
    plan = undefined;
    retired = true;
    return true;
  };
  const start = entry => {
    if (retired || prepared === undefined || call !== undefined) return undefined;
    call = moon.clientProgramModelPhysicalCall(entry, prepared, poll, cancel, cleanup);
    if (call === undefined) return undefined;
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
  const preflight = moon.clientProgramModelRequestPreflight(advance, cleanup);
  return Object.freeze({preflight,
    bindPrepared(original) {
      if (retired || prepared !== undefined) throw new TypeError('SdkPreparedAlreadyBound');
      prepared = original;
    },
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

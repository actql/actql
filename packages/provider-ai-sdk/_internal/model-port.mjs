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
    if (saving !== undefined) return false;
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
    // Private retained responsibility for the parent owner, never a public
    // success/result or authority. A failed save is not automatically retried.
    rawFailure: () => failure,
  });
}

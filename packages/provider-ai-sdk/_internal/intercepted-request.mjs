// Physical SDK preparation only, outside atomic Entry/publication boundaries.
// The existing Model Owner supplies identity, admission, accounting and gates.
// This module performs no network I/O and cannot issue execution evidence.
const preparations = new WeakMap();
const positive = value => Number.isSafeInteger(value) && value > 0 &&
  value <= 2_147_483_647;
const issue = code => Object.assign(new TypeError(code), {code});
const record = handle => {
  const value = preparations.get(handle);
  if (value === undefined || value.retired) throw issue('ForeignSdkPreparation');
  return value;
};

// runSdk belongs to a verified private builder, not an arbitrary public model.
// Before invocation, the installed caller must fund the complete SDK input,
// body/header copies, Promise/record and eventual decoder/response holdings.
export function interceptSdkRequest({runSdk, endpoint, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify}) {
  if (typeof runSdk !== 'function' || typeof endpoint !== 'string' ||
      !positive(maxRequestBytes) || !positive(maxHeaderBytes) ||
      !positive(maxHeaders) || maxHeaders > 64 ||
      typeof notify !== 'function' ||
      (signal !== undefined && !(signal instanceof AbortSignal))) {
    throw issue('InvalidSdkPreparation');
  }
  const url = new URL(endpoint);
  if (url.href !== endpoint || url.username || url.password || url.hash ||
      url.search || !['https:', 'http:'].includes(url.protocol)) {
    throw issue('InvalidSdkPreparation');
  }
  const handle = Object.freeze({});
  const controller = new AbortController();
  const state = {controller, settled: false, retired: false, stopped: false,
    fetchCount: 0, delivered: false, violation: undefined, failure: undefined,
    request: undefined, responseResolve: undefined, responseReject: undefined,
    decoded: undefined, taken: false, notify, signal, abort: undefined};
  preparations.set(handle, state);
  const wake = () => {
    try { state.notify?.(); } catch { /* Wake is neither permission nor fact. */ }
  };
  const reject = code => {
    state.violation ??= code;
    state.responseReject?.(issue(code));
    wake();
    return Promise.reject(issue(code));
  };
  const fetch = (input, init) => {
    if (state.retired) return Promise.reject(issue('ForeignSdkPreparation'));
    if (++state.fetchCount !== 1) return reject('SdkAdditionalRequestRefused');
    if (state.stopped || controller.signal.aborted) {
      return reject('SdkPreparationCancelled');
    }
    // The verified SDK produces a URL plus init, not an arbitrary Request,
    // streaming body, custom dispatcher or a getter-controlled object.
    if (typeof input !== 'string' || input !== endpoint ||
        init?.method !== 'POST' || typeof init.body !== 'string' ||
        init.body.length > maxRequestBytes ||
        Buffer.byteLength(init.body) > maxRequestBytes ||
        init.redirect !== undefined && init.redirect !== 'error') {
      return reject('SdkRequestBindingRefused');
    }
    let headers;
    try { headers = [...new Headers(init.headers)]; }
    catch { return reject('SdkRequestHeadersRefused'); }
    let bytes = 0;
    for (const [name, value] of headers) {
      bytes += Buffer.byteLength(name) + Buffer.byteLength(value);
      if (bytes > maxHeaderBytes) return reject('SdkRequestHeadersRefused');
    }
    if (headers.length > maxHeaders) return reject('SdkRequestHeadersRefused');
    // Header values may contain current secrets. They stay in this private
    // record and are never part of a poll result, log or public preimage.
    state.request = {url: input, method: 'POST', body: init.body,
      headers: Object.freeze(headers.map(pair => Object.freeze(pair))),
      requestBytes: Buffer.byteLength(init.body), headerBytes: bytes};
    const waiting = new Promise((resolve, rejectResponse) => {
      state.responseResolve = resolve;
      state.responseReject = rejectResponse;
    });
    // Even an invalid SDK that discards fetch's returned Promise cannot leave
    // an unhandled rejection. Such an SDK still fails preparation below.
    waiting.catch(() => {});
    wake();
    return waiting;
  };
  state.abort = () => {
    if (state.stopped) return;
    state.stopped = true;
    controller.abort();
    state.responseReject?.(issue('SdkPreparationCancelled'));
    wake();
  };
  signal?.addEventListener('abort', state.abort, {once: true});
  if (signal?.aborted) {
    state.abort();
    state.settled = true;
    state.failure = 'SdkPreparationCancelled';
    return handle;
  }
  let operation;
  try { operation = runSdk(fetch, controller.signal); }
  catch {
    state.settled = true;
    state.failure = 'SdkPreparationRejected';
    state.responseReject?.(issue('SdkPreparationRejected'));
    state.responseResolve = undefined;
    state.responseReject = undefined;
    wake();
    return handle;
  }
  Promise.resolve(operation).then(value => {
    if (!state.delivered || state.fetchCount !== 1 || state.violation) {
      state.failure = state.violation ?? 'SdkReturnedBeforeResponse';
      state.responseReject?.(issue(state.failure));
    } else {
      // A complete SDK decode remains an observation even if cancellation
      // arrived meanwhile. Core decides adoption from its original facts;
      // this does not prove remote stop or authorize Result publication.
      state.decoded = value;
    }
  }, () => {
    state.failure = state.violation ?? (state.stopped
      ? 'SdkPreparationCancelled' : 'SdkPreparationRejected');
  }).finally(() => {
    state.settled = true;
    state.responseResolve = undefined;
    state.responseReject = undefined;
    wake();
  });
  return handle;
}

export function pollSdkPreparation(handle) {
  const state = record(handle);
  if (state.failure || state.violation) return Object.freeze({kind: 'rejected',
    issue: state.failure ?? state.violation});
  if (state.stopped) return Object.freeze({kind: 'rejected',
    issue: 'SdkPreparationCancelled'});
  if (state.request === undefined) return Object.freeze({kind: 'pending'});
  return Object.freeze({kind: 'ready'});
}

// Physical original for Common's rendered-request binding. This private body
// is not a public diagnostic and contains exactly the SDK-produced wire.
export function sdkPreparedRequest(handle) {
  const state = record(handle);
  if (pollSdkPreparation(handle).kind !== 'ready') return undefined;
  const {url, method, body, requestBytes, headerBytes} = state.request;
  return Object.freeze({url, method, body, requestBytes, headerBytes});
}

// Feed an already bounded owned response to the same suspended SDK invocation.
// This does not send, authorize, validate completeness or issue a success token.
// The transport/raw-response Owner must retain its independent original bytes.
export function deliverSdkResponse(handle, response) {
  const state = record(handle);
  if (pollSdkPreparation(handle).kind !== 'ready' || state.delivered ||
      state.settled || !(response instanceof Response)) {
    throw issue('SdkResponseDeliveryRefused');
  }
  state.delivered = true;
  state.responseResolve(response);
  state.responseResolve = undefined;
  state.responseReject = undefined;
}

export function pollSdkDecode(handle) {
  const state = record(handle);
  if (state.failure || state.violation) return Object.freeze({kind: 'rejected',
    issue: state.failure ?? state.violation});
  return Object.freeze({kind: state.settled ? 'ready' : 'pending'});
}

// A one-time physical transfer, not a Common output/capture admission.
export function takeSdkDecodedResult(handle) {
  const state = record(handle);
  if (pollSdkDecode(handle).kind !== 'ready' || state.taken) {
    throw issue('SdkDecodedResultUnavailable');
  }
  state.taken = true;
  const value = state.decoded;
  state.decoded = undefined;
  return value;
}

export function cancelSdkPreparation(handle) {
  const state = record(handle);
  state.abort();
}

export function cleanupSdkPreparation(handle) {
  const state = preparations.get(handle);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  if (state.retired) return true;
  if (!state.settled) {
    state.abort();
    return false;
  }
  state.signal?.removeEventListener('abort', state.abort);
  state.request = undefined;
  state.decoded = undefined;
  state.responseResolve = undefined;
  state.responseReject = undefined;
  state.notify = undefined;
  state.signal = undefined;
  state.abort = undefined;
  state.controller = undefined;
  state.retired = true;
  // Same physical handle retries are idempotent. Escaped caller originals and
  // a transferred decoded result are not claimed to have been retired here.
  return true;
}

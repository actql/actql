// Physical SDK preparation only, outside atomic Entry/publication boundaries.
// The existing Model Owner supplies identity, admission, accounting and gates.
// Only its explicitly installed transport can perform network I/O. Neither
// physical preparation nor transport can issue execution evidence.
import {fixedInferResponseLimits, readBoundedInferResponse} from './bounded-response.mjs';
import {prepareOriginalUndiciFetch} from './original-undici-transport.mjs';

const preparations = new WeakMap();
// Internal SDK consumer retirement, not Provider failure or a response fact.
// The owned transport mode records why its already intercepted wait ends;
// the existing rejection handlers still wait for actual SDK settlement.
const rawConsumerRetired = Symbol('ActQLSdkRawConsumerRetired');
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
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest}) {
  if (typeof runSdk !== 'function' || typeof endpoint !== 'string' ||
      !positive(maxRequestBytes) || !positive(maxHeaderBytes) ||
      !positive(maxHeaders) || maxHeaders > 64 ||
      typeof notify !== 'function' ||
      (signal !== undefined && !(signal instanceof AbortSignal)) ||
      (verifyRequest !== undefined && typeof verifyRequest !== 'function')) {
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
    decoded: undefined, taken: false, notify, signal, abort: undefined,
    transport: undefined};
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
    // Installed verification is preparation before Entry admission, never a
    // callback between the final one-shot consume and transport start.
    if (verifyRequest !== undefined) {
      try {
        if (verifyRequest(init.body) !== true) return reject('SdkOriginalRequestMismatch');
      } catch { return reject('SdkOriginalRequestMismatch'); }
    }
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
    if (state.transport?.responseMode === 'raw-only-retiring') {
      state.taken = true;
      state.decoded = undefined;
    } else if (!state.delivered || state.fetchCount !== 1 || state.violation) {
      state.failure = state.violation ?? 'SdkReturnedBeforeResponse';
      state.responseReject?.(issue(state.failure));
    } else {
      // A complete SDK decode remains an observation even if cancellation
      // arrived meanwhile. Core decides adoption from its original facts;
      // this does not prove remote stop or authorize Result publication.
      state.decoded = value;
    }
  }, () => {
    if (state.transport?.responseMode === 'raw-only-retiring') {
      // SDK error wrapping cannot turn this private, intentionally ended
      // consumer into Provider failure/Unknown. Common adopts only raw facts.
      state.taken = true;
      state.decoded = undefined;
    } else {
      state.failure = state.violation ?? (state.stopped
        ? 'SdkPreparationCancelled' : 'SdkPreparationRejected');
    }
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

// Only a verified installed caller supplies this physical fetch primitive.
// There is no ambient fetch, endpoint override or authority in this API.
// The complete request/init, limits and closure are fixed BEFORE Core consumes
// its original one-shot send gate. Their holdings must already be funded.
export function prepareSdkTransport(handle, {fetch, responseLimits, observeAt,
  responseMode = 'sdk'}) {
  const state = record(handle);
  if (pollSdkPreparation(handle).kind !== 'ready' ||
      state.transport !== undefined || state.delivered || state.settled ||
      typeof fetch !== 'function' ||
      !['sdk', 'raw-only'].includes(responseMode) ||
      (observeAt !== undefined && typeof observeAt !== 'function')) {
    throw issue('SdkTransportPreparationRefused');
  }
  const limits = fixedInferResponseLimits(responseLimits);
  const original = state.request;
  const init = Object.freeze({method: original.method, body: original.body,
    headers: original.headers, redirect: 'error', signal: state.controller.signal});
  // Selected per-call Client/options are fixed in preparation before Entry.
  // Generic/native transports retain their original fetch behavior.
  const physical = prepareOriginalUndiciFetch(fetch, original.url, init, limits);
  state.transport = {invoke: physical?.invoke ?? (() => fetch(original.url, init)),
    physicalCleanup: physical?.cleanup, physicalRetired: physical === undefined,
    physicalRetiring: false, limits, observeAt,
    observedAt: undefined, rawObservation: undefined, responseMode,
    started: false, settled: false, raw: undefined, failure: undefined,
    readerRetired: false, retiring: false, unreadResponse: undefined};
}

// Original fixed transport start only. The caller must first cross Common's
// durable Entry ACK and final current/stop/authority/egress/reservation gate.
// No await, notification or request construction precedes the actual invoke.
// A throw/lost response is unknown responsibility, not proof of non-send.
export function startSdkTransport(handle) {
  const state = record(handle);
  const transport = state.transport;
  if (transport === undefined || transport.started ||
      state.failure || state.violation || state.stopped ||
      state.delivered || state.settled || state.request === undefined) {
    throw issue('SdkTransportStartRefused');
  }
  transport.started = true;
  let operation;
  try { operation = transport.invoke(); }
  catch { operation = Promise.reject(issue('SdkTransportUnknown')); }
  transport.invoke = undefined;
  const wake = () => {
    try { state.notify?.(); } catch { /* Notification is not a Run fact. */ }
  };
  Promise.resolve(operation).then(response => {
    // A header/reader validation throw must not abandon an unread body.
    transport.unreadResponse = response;
    // Original Host clock observation at actual response receipt, before
    // body reading or Store awaits. It is not a provider-reported timestamp.
    transport.observedAt = transport.observeAt?.();
    transport.observeAt = undefined;
    return readBoundedInferResponse(response, transport.limits, state.controller.signal);
  }).then(raw => {
    transport.raw = raw;
    // The retained raw view now carries the same reader's retirement duty.
    transport.unreadResponse = undefined;
    raw.readerRetirement.then(retired => {
      transport.readerRetired = retired;
      wake();
    });
    if (!raw.transportComplete || raw.issue !== undefined) {
      transport.failure = raw.issue ?? 'SdkTransportIncomplete';
      state.responseReject?.(issue('SdkTransportIncomplete'));
      return;
    }
    if (transport.responseMode === 'raw-only') {
      // Chat's original raw/Store/Common codec owns response interpretation.
      // Do not allocate an unused SDK Response copy or decoder tree. This is
      // not raw persistence or reader retirement: those original obligations
      // remain held, independently of the SDK Promise's later settlement.
      transport.responseMode = 'raw-only-retiring';
      state.responseReject?.(rawConsumerRetired);
      return;
    }
    // This is a separately funded physical copy for the same suspended SDK.
    // It is not a raw Artifact CID, Common answer or completion observation.
    const body = [204, 205, 304].includes(raw.status) ? null : raw.body;
    deliverOriginalSdkResponse(state, new Response(body, {
      status: raw.status, headers: raw.headers,
    }));
  }).catch(() => {
    transport.failure ??= 'SdkTransportUnknown';
    state.responseReject?.(issue('SdkTransportUnknown'));
  }).finally(() => {
    transport.settled = true;
    wake();
  });
}

export function pollSdkTransport(handle) {
  const transport = record(handle).transport;
  if (transport === undefined) throw issue('ForeignSdkTransport');
  if (!transport.started) return Object.freeze({kind: 'not-started'});
  if (!transport.settled) return Object.freeze({kind: 'pending'});
  if (transport.raw !== undefined) return Object.freeze({kind: 'response',
    issue: transport.failure});
  return Object.freeze({kind: 'unknown', issue: transport.failure});
}

// A private original physical view, not a serializer or public diagnostic.
// The original Artifact/capture owner must admit and retain these bytes; SDK
// defaults or a complete transport are not a verified endpoint completion.
export function sdkTransportResponse(handle) {
  const state = record(handle);
  if (pollSdkTransport(handle).kind !== 'response') return undefined;
  return state.transport.raw;
}

// Retain an actually observed partial/error body as well as a complete body.
// This does not turn an incomplete transport into a successful response. The
// original capture caller must preserve its exact bytes and EOF separately.
export function sdkTransportRawObservation(handle) {
  const transport = record(handle).transport;
  if (transport === undefined) throw issue('ForeignSdkTransport');
  if (!transport.settled || transport.raw === undefined) return undefined;
  transport.rawObservation ??= Object.freeze({...transport.raw,
    observedAt: transport.observedAt});
  return transport.rawObservation;
}

// Feed an already bounded owned response to the same suspended SDK invocation.
// This does not send, authorize, validate completeness or issue a success token.
// The transport/raw-response Owner must retain its independent original bytes.
export function deliverSdkResponse(handle, response) {
  const state = record(handle);
  if (state.transport !== undefined) throw issue('SdkResponseDeliveryRefused');
  deliverOriginalSdkResponse(state, response);
}

function deliverOriginalSdkResponse(state, response) {
  if (state.failure || state.violation || state.stopped ||
      state.request === undefined || state.delivered || state.settled ||
      !(response instanceof Response)) {
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
  if (state.settled && state.transport?.responseMode === 'raw-only-retiring') {
    return Object.freeze({kind: 'retired'});
  }
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

// The Chat physical caller validates its answer/observations from original raw
// custody, not this SDK-normalized projection. Retire that unused local alias
// after SDK settlement even when raw Store cleanup is still pending. Reuse the
// original one-time-transfer bit; do not mutate an escaped value or retire raw,
// transport, request, reader, Promise or entered-call responsibility. This is
// not physical GC, saved response, remote stop or capacity-release evidence.
export function retireSdkDecodedResult(handle) {
  const state = preparations.get(handle);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  // Original preparation cleanup may finish before its parent Owner retires.
  if (state.retired) return true;
  if (!state.settled) return false;
  state.taken = true;
  state.decoded = undefined;
  return true;
}

export function cancelSdkPreparation(handle) {
  const state = record(handle);
  state.abort();
}

export function cleanupSdkPreparation(handle) {
  const state = preparations.get(handle);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  if (state.retired) return true;
  const transport = state.transport;
  if (transport?.physicalCleanup !== undefined && !transport.physicalRetired) {
    if (!transport.physicalRetiring) {
      transport.physicalRetiring = true;
      transport.physicalCleanup().then(retired => {
        transport.physicalRetired = retired === true;
      }, () => { /* Preserve the same original physical cleanup duty. */ }).finally(() => {
        transport.physicalRetiring = false;
        try { state.notify?.(); } catch { /* Close acknowledgement is not Run release. */ }
      });
    }
    // Preserve request/Client/body/SDK/raw holdings until actual settlement.
    state.abort();
    return false;
  }
  if (transport?.started) {
    if (!transport.settled) {
      state.abort();
      return false;
    }
    if (transport.unreadResponse !== undefined) {
      if (!transport.retiring) {
        transport.retiring = true;
        const response = transport.unreadResponse;
        let retirement;
        try {
          if (response === null || typeof response !== 'object' ||
              response.body === undefined) {
            // An invalid transport return supplied no usable response body.
            retirement = Promise.resolve();
          } else {
            retirement = response.body === null ? Promise.resolve() : response.body.cancel();
          }
        } catch { retirement = Promise.reject(issue('SdkUnreadResponseCleanupFailed')); }
        Promise.resolve(retirement).then(() => {
          transport.unreadResponse = undefined;
        }, () => {}).finally(() => {
          transport.retiring = false;
          try { state.notify?.(); } catch { /* Reader release is not Run release. */ }
        });
      }
      return false;
    }
    if (transport.raw !== undefined && !transport.readerRetired) {
      if (!transport.retiring) {
        transport.retiring = true;
        transport.raw.retryReaderRetirement().then(retired => {
          transport.readerRetired = retired;
        }).finally(() => {
          transport.retiring = false;
          try { state.notify?.(); } catch { /* A retry wake is not release. */ }
        });
      }
      return false;
    }
  }
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
  state.transport = undefined;
  state.retired = true;
  // Same physical handle retries are idempotent. Escaped caller originals and
  // a transferred decoded result are not claimed to have been retired here.
  return true;
}

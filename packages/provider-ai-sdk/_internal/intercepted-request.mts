// Physical SDK preparation only, outside atomic Entry/publication boundaries.
// The existing Model Owner supplies identity, admission, accounting and gates.
// Only its explicitly installed transport can perform network I/O. Neither
// physical preparation nor transport can issue execution evidence.
import type {LanguageModelV4, LanguageModelV4CallOptions} from '@ai-sdk/provider';
import {createHash} from 'node:crypto';
import {fixedInferResponseLimits, readBoundedInferResponse} from './bounded-response.mjs';
import {originalLocalModelHttpTransport} from './local-model-http-transport.mjs';

type ResponseLimits = Parameters<typeof fixedInferResponseLimits>[0];
type FixedResponseLimits = ReturnType<typeof fixedInferResponseLimits>;
type PhysicalResponse = Parameters<typeof readBoundedInferResponse>[0];
type RawResponse = Awaited<ReturnType<typeof readBoundedInferResponse>>;
type SavedSdkResponse = Readonly<{receipt?: unknown; bytes?: Uint8Array}>;
// Each selected SDK has its own V4 result surface. The transport retains
// that original as opaque until the separately checked decoder consumes it.
type SdkLanguageModel = Pick<LanguageModelV4, 'specificationVersion' | 'provider' | 'modelId'> & {
  doGenerate(options: LanguageModelV4CallOptions): PromiseLike<unknown>;
};
type RegisteredSdkInput = Readonly<{
  moon: {clientProgramAdmittedStructuredSdkRouteMatches(admission: unknown, selector: string,
    modelId: string, apiMode: string, endpoint: string): unknown};
  admission: unknown; selector: string; modelId: string; apiMode: string; endpoint: string;
  sdkProvider: string; createLanguageModel(fetch: typeof globalThis.fetch): SdkLanguageModel;
  options: LanguageModelV4CallOptions; verifyRequest(body: string): unknown;
  maxRequestBytes: number; maxHeaderBytes: number; maxHeaders: number; signal?: AbortSignal; notify: () => unknown;
}>;
interface PreparedRequest {
  url: string; method: 'POST'; body: string;
  headers: readonly (readonly [string, string])[];
  requestBytes: number; headerBytes: number;
}
interface TransportState {
  invoke: (() => unknown) | undefined;
  physicalCleanup: (() => Promise<boolean>) | undefined;
  physicalRetired: boolean; physicalRetiring: boolean;
  limits: FixedResponseLimits; observeAt: (() => unknown) | undefined;
  observedAt: unknown; rawObservation: (RawResponse & {observedAt: unknown}) | undefined;
  responseMode: 'sdk' | 'saved-sdk';
  rawDigest?: string; saved?: SavedSdkResponse;
  started: boolean; settled: boolean; raw: RawResponse | undefined;
  failure: string | undefined; readerRetired: boolean; retiring: boolean;
  unreadResponse: unknown;
  finishResponse?: () => void;
  bindCredential?: () => void;
  credentialAttempted?: boolean;
}
interface PreparationState {
  controller: AbortController | undefined;
  settled: boolean; retired: boolean; stopped: boolean;
  fetchCount: number; delivered: boolean; violation: string | undefined;
  failure: string | undefined; request: PreparedRequest | undefined;
  responseResolve: ((value: Response) => void) | undefined;
  responseReject: ((reason?: unknown) => void) | undefined;
  decoded: unknown; taken: boolean; notify: (() => unknown) | undefined;
  signal: AbortSignal | undefined; abort: (() => void) | undefined;
  transport: TransportState | undefined;
}
// An unchecked view used only after the original object/body checks. Neither
// a structural type nor a transport return proves reader or physical cleanup.
interface UnreadResponse {body?: null | {cancel(): unknown}}

const preparations = new WeakMap<object, PreparationState>();
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 &&
  (value as number) <= 2_147_483_647;
const issue = (code: string) => Object.assign(new TypeError(code), {code});
const record = (handle: unknown): PreparationState => {
  const value = preparations.get(handle as object);
  if (value === undefined || value.retired) throw issue('ForeignSdkPreparation');
  return value;
};

// Borrow the selected V4 model and forward its one generation Promise.
export function generateSdkLanguageModel(model: SdkLanguageModel, modelId: string, options: LanguageModelV4CallOptions, abortSignal: AbortSignal) {
  if (model?.specificationVersion !== 'v4' || model.modelId !== modelId ||
      typeof model.doGenerate !== 'function' ||
      options.tools !== undefined || options.toolChoice !== undefined) {
    throw issue('InvalidSdkLanguageModel');
  }
  return model.doGenerate({...options, abortSignal});
}

// Private installer selection. The supplied factory belongs to a verified
// Host adapter and receives only the intercepted fetch. SDK code is trusted;
// a fetch override alone is not an isolation boundary for arbitrary modules.
export function prepareRegisteredSdkLanguageModel({moon, admission, selector, modelId,
  apiMode, sdkProvider, endpoint, createLanguageModel, options, verifyRequest,
  maxRequestBytes, maxHeaderBytes, maxHeaders, signal, notify}: RegisteredSdkInput) {
  if (admission === undefined ||
      typeof moon?.clientProgramAdmittedStructuredSdkRouteMatches !== 'function' ||
      typeof selector !== 'string' || typeof modelId !== 'string' ||
      typeof apiMode !== 'string' || typeof endpoint !== 'string' ||
      typeof sdkProvider !== 'string' || sdkProvider.length === 0 ||
      typeof createLanguageModel !== 'function' || typeof verifyRequest !== 'function' ||
      options === null || typeof options !== 'object' ||
      options.tools !== undefined || options.toolChoice !== undefined ||
      moon.clientProgramAdmittedStructuredSdkRouteMatches(admission,
        selector, modelId, apiMode, endpoint) !== true) {
    throw issue('RegisteredSdkRouteUnavailable');
  }
  return interceptSdkRequest({endpoint,verifyRequest,maxRequestBytes,maxHeaderBytes,maxHeaders,
    signal,notify,runSdk(fetch,abortSignal) {
      const model = createLanguageModel(fetch);
      if (model?.provider !== sdkProvider) throw issue('ForeignSdkLanguageModel');
      return generateSdkLanguageModel(model,modelId,options,abortSignal);
    }});
}

// runSdk belongs to a verified private builder, not an arbitrary public model.
// Before invocation, the installed caller must fund the complete SDK input,
// body/header copies, Promise/record and eventual decoder/response holdings.
export function interceptSdkRequest({runSdk, endpoint, maxRequestBytes,
  maxHeaderBytes, maxHeaders, signal, notify, verifyRequest}: {
    runSdk: (fetch: typeof globalThis.fetch, signal: AbortSignal) => unknown;
    endpoint: string; maxRequestBytes: number; maxHeaderBytes: number; maxHeaders: number;
    signal?: AbortSignal; notify: () => unknown; verifyRequest?: (body: string) => unknown;
  }) {
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
  const state: PreparationState = {controller, settled: false, retired: false, stopped: false,
    fetchCount: 0, delivered: false, violation: undefined, failure: undefined,
    request: undefined, responseResolve: undefined, responseReject: undefined,
    decoded: undefined, taken: false, notify, signal, abort: undefined,
    transport: undefined};
  preparations.set(handle, state);
  const wake = () => {
    try { state.notify?.(); } catch { /* Wake is neither permission nor fact. */ }
  };
  const reject = (code: string) => {
    state.violation ??= code;
    state.responseReject?.(issue(code));
    wake();
    return Promise.reject(issue(code));
  };
  const fetch: typeof globalThis.fetch = (input, init) => {
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
    let headers: [string, string][];
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
    const waiting = new Promise<Response>((resolve, rejectResponse) => {
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
    state.abort!();
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

export function pollSdkPreparation(handle: unknown) {
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
export function sdkPreparedRequest(handle: unknown) {
  const state = record(handle);
  if (pollSdkPreparation(handle).kind !== 'ready') return undefined;
  const {url, method, body, requestBytes, headerBytes} = state.request!;
  return Object.freeze({url, method, body, requestBytes, headerBytes});
}

// Only a verified installed caller supplies this physical fetch primitive.
// There is no ambient fetch, endpoint override or authority in this API.
// The complete request/init, limits and closure are fixed BEFORE Core consumes
// its original one-shot send gate. Their holdings must already be funded.
export function prepareSdkTransport(handle: unknown, {fetch, responseLimits, observeAt,
  responseMode = 'sdk'}: {fetch: typeof globalThis.fetch; responseLimits: ResponseLimits; observeAt?: () => unknown; responseMode?: 'sdk' | 'saved-sdk'}) {
  const state = record(handle);
  if (pollSdkPreparation(handle).kind !== 'ready' ||
      state.transport !== undefined || state.delivered || state.settled ||
      typeof fetch !== 'function' ||
      !['sdk', 'saved-sdk'].includes(responseMode) ||
      (observeAt !== undefined && typeof observeAt !== 'function')) {
    throw issue('SdkTransportPreparationRefused');
  }
  const limits = fixedInferResponseLimits(responseLimits);
  const original = state.request!;
  const init = Object.freeze({method: original.method, body: original.body,
    headers: original.headers, redirect: 'error', signal: state.controller!.signal});
  // Selected per-call Client/options are fixed in preparation before Entry.
  // Generic/native transports retain their original fetch behavior.
  const physical = originalLocalModelHttpTransport()
    .prepareOriginalUndiciFetch(fetch, original.url, init, limits, state.controller);
  state.transport = {invoke: physical?.invoke ?? (() => fetch(original.url, init as RequestInit)),
    physicalCleanup: physical?.cleanup, physicalRetired: physical === undefined,
    physicalRetiring: false, limits, observeAt,
    observedAt: undefined, rawObservation: undefined, responseMode,
    started: false, settled: false, raw: undefined, failure: undefined,
    readerRetired: false, retiring: false, unreadResponse: undefined};
  // Extend the SAME already admitted record only for the selected clock.
  // No temporary spread/empty record on the legacy NONE path.
  if (physical?.finishResponse !== undefined) state.transport.finishResponse = physical.finishResponse;
  if (physical?.bindCredential !== undefined) state.transport.bindCredential = physical.bindCredential;
}

export function bindSdkTransportCredential(handle: unknown) {
  const state = record(handle), transport = state.transport;
  if (transport?.bindCredential === undefined || transport.credentialAttempted ||
      transport.started || state.stopped || state.settled) {
    throw issue('ModelProjectCredentialPreparationUnavailable');
  }
  // An error may stop this original preparation. It must not trigger another
  // attempt at credential acquisition, SDK preparation or dispatch.
  transport.credentialAttempted = true;
  const bind = transport.bindCredential;
  bind();
  delete transport.bindCredential;
}

// Original fixed transport start only. The caller must first cross Common's
// durable Entry ACK and final current/stop/authority/egress/reservation gate.
// No await, notification or request construction precedes the actual invoke.
// A throw/lost response is unknown responsibility, not proof of non-send.
export function startSdkTransport(handle: unknown) {
  const state = record(handle);
  const transport = state.transport;
  if (transport === undefined || transport.bindCredential !== undefined || transport.started ||
      state.failure || state.violation || state.stopped ||
      state.delivered || state.settled || state.request === undefined) {
    throw issue('SdkTransportStartRefused');
  }
  transport.started = true;
  let operation;
  try { operation = transport.invoke!(); }
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
    return readBoundedInferResponse(response as PhysicalResponse, transport.limits, state.controller!.signal);
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
    if (transport.responseMode === 'saved-sdk') {
      // Seal what the reader actually returned before exposing its mutable
      // byte backing to the Store port. Decode waits for that exact content.
      transport.rawDigest = createHash('sha256').update(raw.body).digest('hex');
      return;
    }
    deliverSdkTransportBody(state, raw, raw.body);
  }).catch(() => {
    transport.failure ??= 'SdkTransportUnknown';
    state.responseReject?.(issue('SdkTransportUnknown'));
  }).finally(() => {
    transport.finishResponse?.();
    if (Object.hasOwn(transport, 'finishResponse')) delete transport.finishResponse;
    transport.settled = true;
    wake();
  });
}

// This separately funded physical copy is given only to the intercepted
// fetch already suspended inside the selected SDK invocation.
function deliverSdkTransportBody(state: PreparationState, raw: RawResponse, bytes: Uint8Array) {
  const body = [204, 205, 304].includes(raw.status) ? null : bytes;
  deliverOriginalSdkResponse(state, new Response(body as BodyInit | null, {
    status: raw.status, headers: raw.headers as HeadersInit,
  }));
}

// Private continuation after the original Store's durable byte confirmation.
// Matching semantic CIDs or values from a different fetch cannot feed the SDK.
// Core independently verifies the nominal saved receipt against the entered Call.
export function confirmSavedSdkTransportResponse(handle: unknown, originalRaw: TransportState['rawObservation'], saved: SavedSdkResponse) {
  const state = record(handle);
  const transport = state.transport;
  if (transport?.responseMode !== 'saved-sdk' || !transport.settled ||
      transport.failure !== undefined || originalRaw === undefined ||
      originalRaw !== transport.rawObservation || state.delivered ||
      saved?.receipt === undefined || !(saved.bytes instanceof Uint8Array) ||
      saved.bytes.byteLength !== originalRaw.observedBytes ||
      createHash('sha256').update(saved.bytes).digest('hex') !== transport.rawDigest) {
    throw issue('SdkSavedResponseBindingRefused');
  }
  // The SDK parses the confirmed Store copy. No caller-supplied decoded
  // result enters the invocation. Observe the result only through this loan.
  deliverSdkTransportBody(state, originalRaw, saved.bytes);
  transport.saved = saved;
}

export function pollSdkTransport(handle: unknown) {
  const transport = record(handle).transport;
  if (transport === undefined) throw issue('ForeignSdkTransport');
  if (!transport.started) return Object.freeze({kind: 'not-started'});
  if (!transport.settled) return Object.freeze({kind: 'pending'});
  if (transport.raw !== undefined) return Object.freeze({kind: 'response',
    issue: transport.failure});
  return Object.freeze({kind: 'unknown', issue: transport.failure});
}

// Retain an actually observed partial/error body as well as a complete body.
// This does not turn an incomplete transport into a successful response. The
// original capture caller must preserve its exact bytes and EOF separately.
export function sdkTransportRawObservation(handle: unknown) {
  const transport = record(handle).transport;
  if (transport === undefined) throw issue('ForeignSdkTransport');
  if (!transport.settled || transport.raw === undefined) return undefined;
  transport.rawObservation ??= Object.freeze({...transport.raw,
    observedAt: transport.observedAt});
  return transport.rawObservation;
}

function deliverOriginalSdkResponse(state: PreparationState, response: unknown) {
  if (state.failure || state.violation || state.stopped ||
      state.request === undefined || state.delivered || state.settled ||
      !(response instanceof Response)) {
    throw issue('SdkResponseDeliveryRefused');
  }
  state.delivered = true;
  state.responseResolve!(response);
  state.responseResolve = undefined;
  state.responseReject = undefined;
}

export function pollSdkDecode(handle: unknown) {
  const state = record(handle);
  if (state.failure || state.violation) return Object.freeze({kind: 'rejected',
    issue: state.failure ?? state.violation});
  return Object.freeze({kind: state.settled ? 'ready' : 'pending'});
}

// A one-time physical transfer, not a Common output/capture admission.
export function takeSdkDecodedResult(handle: unknown) {
  const state = record(handle);
  if (state.transport?.responseMode === 'saved-sdk') {
    throw issue('SdkDecodedResultUnavailable');
  }
  return takeOriginalSdkDecodedResult(handle, state);
}

// Read once through the exact receipt and byte loan used by the same fetch.
export function takeSavedSdkDecodedResult(handle: unknown, receipt: unknown, bytes: unknown) {
  const state = record(handle), saved = state.transport?.saved;
  if (state.stopped || saved === undefined || saved.receipt !== receipt || saved.bytes !== bytes) {
    throw issue('SdkSavedResponseBindingRefused');
  }
  return takeOriginalSdkDecodedResult(handle, state);
}

function takeOriginalSdkDecodedResult(handle: unknown, state: PreparationState) {
  if (pollSdkDecode(handle).kind !== 'ready' || state.taken) {
    throw issue('SdkDecodedResultUnavailable');
  }
  state.taken = true;
  const value = state.decoded;
  state.decoded = undefined;
  return value;
}

// Retire an unused SDK projection after the original operation settles,
// including when its raw Store cleanup is still pending. Reuse the
// original one-time-transfer bit; do not mutate an escaped value or retire raw,
// transport, request, reader, Promise or entered-call responsibility. This is
// not physical GC, saved response, remote stop or capacity-release evidence.
export function retireSdkDecodedResult(handle: unknown) {
  const state = preparations.get(handle as object);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  // Original preparation cleanup may finish before its parent Owner retires.
  if (state.retired) return true;
  if (!state.settled) return false;
  state.taken = true;
  state.decoded = undefined;
  return true;
}

export function cancelSdkPreparation(handle: unknown) {
  const state = record(handle);
  state.abort!();
}

// Advance only the SAME installed physical duty. This does not clear raw,
// reader, SDK, request or Store aliases, and does not issue a Common receipt.
function advanceOriginalPhysicalCleanup(state: PreparationState, transport: TransportState) {
  if (transport.physicalRetired) return true;
  if (!transport.physicalRetiring) {
    transport.physicalRetiring = true;
    transport.physicalCleanup!().then(retired => {
      transport.physicalRetired = retired === true;
    }, () => { /* Preserve the same original physical cleanup duty. */ }).finally(() => {
      transport.physicalRetiring = false;
      try { state.notify?.(); } catch { /* Physical wake is not Run release. */ }
    });
  }
  return false;
}

// Private OriginalCall observation/progress, not a public ACK factory. Generic
// fetch's initial physicalRetired flag is NOT an original I/O acknowledgement.
// Successful reading must finish before normal close; cancellation/Unknown
// retains independent raw/reader/SDK/Store custody until their actual cleanup.
// Port support DATA only. It neither progresses I/O nor issues an ACK.
export function sdkOriginalIoObservationAvailable(handle: unknown) {
  const state = preparations.get(handle as object);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  return state.transport?.physicalCleanup !== undefined;
}

export function progressSdkOriginalIoCleanup(handle: unknown) {
  const state = preparations.get(handle as object);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  const transport = state.transport;
  if (transport?.physicalCleanup === undefined) return undefined;
  if (!transport.started) return false;
  if (!transport.settled && !state.stopped) return false;
  return advanceOriginalPhysicalCleanup(state, transport);
}

export function cleanupSdkPreparation(handle: unknown) {
  const state = preparations.get(handle as object);
  if (state === undefined) throw issue('ForeignSdkPreparation');
  if (state.retired) return true;
  const transport = state.transport;
  if (transport?.physicalCleanup !== undefined && !transport.physicalRetired) {
    // Preserve request/Client/body/SDK/raw holdings until actual settlement.
    // Request the SAME original controller stop before physical cleanup can
    // disarm its deadline or synchronously report a pending body's failure.
    // The existing physical AND remains separate; abort is never its ACK.
    state.abort!();
    advanceOriginalPhysicalCleanup(state, transport);
    return false;
  }
  if (transport?.started) {
    if (!transport.settled) {
      state.abort!();
      return false;
    }
    if (transport.unreadResponse !== undefined) {
      if (!transport.retiring) {
        transport.retiring = true;
        const response = transport.unreadResponse;
        let retirement;
        try {
          if (response === null || typeof response !== 'object' ||
              (response as UnreadResponse).body === undefined) {
            // An invalid transport return supplied no usable response body.
            retirement = Promise.resolve();
          } else {
            retirement = (response as UnreadResponse).body === null ? Promise.resolve() : (response as UnreadResponse).body!.cancel();
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
    state.abort!();
    return false;
  }
  state.signal?.removeEventListener('abort', state.abort!);
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

import {runtimePair} from './compiler-binding.generated.mjs';
import {prepareOriginalHttpChatRequest} from './original-chat-request.mjs';
import {fixedInferResponseLimits, readBoundedInferResponse} from './bounded-response.mjs';
import type {RequestLimits, ResponseLimits, QuantityCapacity} from '../index.d.ts';

type Projection = Parameters<typeof prepareOriginalHttpChatRequest>[0];
type PhysicalResponse = Parameters<typeof readBoundedInferResponse>[0];
type RawObservation = Awaited<ReturnType<typeof readBoundedInferResponse>> & {observedAt: unknown};
interface SavedRaw {response?: unknown}
type PersistRaw = (call: unknown, raw: RawObservation) => SavedRaw | PromiseLike<SavedRaw>;
type BoundPersistence = PersistRaw & {cleanup(call: unknown): unknown};
interface HttpRuntime {
  [name: string]: unknown;
  clientProgramModelResponseProfileTransportMatches(profile: unknown, ...limits: number[]): unknown;
  clientProgramModelRequestPreflight(advance: () => {_0: boolean; _1: unknown}, cleanup: () => boolean): unknown;
  clientProgramModelAsyncPhysicalRequestPlan(request: unknown, bytes: bigint, tokens: bigint,
    costUnits: bigint, durationMs: bigint, profile: unknown, installation: unknown,
    start: (entry: unknown) => unknown): unknown;
  clientProgramModelPhysicalCallForRequest(entry: unknown, request: unknown, poll: () => unknown,
    cancel: () => void, cleanup: () => boolean): unknown;
  clientProgramModelPhysicalPending(): unknown;
  clientProgramModelPhysicalUnknown(): unknown;
  clientProgramModelPhysicalSavedChat(response: unknown): unknown;
  clientProgramReadReconciledInferRawUsage(original: unknown, response: unknown, quantum: number): unknown;
}
// Unchecked original Common/physical port views. Existing guards and same-entry
// raw custody decide validity; these types issue no grant, saved ACK or stop.
type PhysicalOptions = Omit<Projection, 'limits' | 'moon'> & {moon: Projection['moon'] & HttpRuntime;
  projectionLimits: unknown; endpoint: string; headers: unknown;
  requestLimits: RequestLimits | undefined; responseLimits: ResponseLimits | undefined;
  profile: unknown; installation: unknown; quantities: QuantityCapacity['perAttempt'] | undefined;
  fetch: ((endpoint: string, init: unknown) => unknown) | undefined;
  notify: (() => unknown) | undefined; observeAt: (() => unknown) | undefined;
  checked: ((value: unknown) => unknown) | undefined; signal?: AbortSignal;
  persistRaw?: PersistRaw; cleanupRaw?: (call: unknown) => unknown;
  rawCaptureBinder?: (bind: (registration: unknown, persistence: BoundPersistence) => void) => unknown;
};
interface UnreadResponse {body?: null | {cancel(): unknown}}


const fail: (code: string) => never = code => { throw new TypeError(code); };
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2_147_483_647;

// Private physical adapter of the existing Common plan/call, not a Model
// Owner. Installation must fund every body/record/Promise/reader/Store overlap
// before calling this factory. No endpoint, credential or permission is read
// from a Program. Normal public installation remains unavailable.
export function createHttpChatPreflight({moon, admittedProvider, request,
  modelId, taskCid, promptCid, outputSchemaCid, modelSelector, projectionLimits,
  endpoint, headers, requestLimits, responseLimits, profile, installation,
  quantities, fetch, notify, observeAt, checked, signal,
  persistRaw, cleanupRaw, rawCaptureBinder}: PhysicalOptions) {
  const deferred = rawCaptureBinder !== undefined;
  if (![fetch, notify, observeAt, checked].every(value => typeof value === 'function') ||
      deferred && (typeof rawCaptureBinder !== 'function' || persistRaw !== undefined || cleanupRaw !== undefined) ||
      !deferred && (typeof persistRaw !== 'function' || typeof cleanupRaw !== 'function') ||
      signal !== undefined && !(signal instanceof AbortSignal)) fail('InvalidHTTPChatPhysicalPort');
  if (!['clientProgramModelResponseProfileTransportMatches',
    'clientProgramProjectHTTPChatRequest', 'clientProgramModelRequestPreflight',
    'clientProgramModelAsyncPhysicalRequestPlan', 'clientProgramModelPhysicalCallForRequest',
    'clientProgramModelPhysicalPending', 'clientProgramModelPhysicalUnknown',
    'clientProgramModelPhysicalSavedChat'].every(name => typeof moon?.[name] === 'function')) {
    fail('HTTPChatRuntimeUnavailable');
  }
  let url!: URL;
  try { url = new URL(endpoint); } catch { fail('InvalidHTTPChatEndpoint'); }
  if (url.href !== endpoint || !['http:', 'https:'].includes(url.protocol) ||
      url.username || url.password || url.search || url.hash) fail('InvalidHTTPChatEndpoint');
  if (!positive(requestLimits?.maxBytes) || !positive(requestLimits?.maxHeaderBytes) ||
      !positive(requestLimits?.maxHeaders) || requestLimits!.maxHeaders > 64 ||
      !Array.isArray(headers) || headers.length > requestLimits!.maxHeaders) fail('InvalidHTTPChatRequestLimits');
  const maxRequestBytes = requestLimits!.maxBytes;
  let headerBytes = 0;
  const names = new Set();
  headers = Object.freeze(headers.map(pair => {
    if (!Array.isArray(pair) || pair.length !== 2 ||
        typeof pair[0] !== 'string' || !/^[a-z0-9-]+$/u.test(pair[0]) ||
        typeof pair[1] !== 'string' || /[\r\n]/u.test(pair[1]) || names.has(pair[0])) fail('InvalidHTTPChatHeaders');
    names.add(pair[0]);
    headerBytes += Buffer.byteLength(pair[0]) + Buffer.byteLength(pair[1]);
    if (headerBytes > requestLimits!.maxHeaderBytes) fail('InvalidHTTPChatHeaders');
    return Object.freeze([pair[0], pair[1]] as [string, string]);
  }));
  responseLimits = fixedInferResponseLimits(responseLimits!);
  // Validate the selected physical ceilings against the original Common
  // profile before allocating or registering a preparation. This is not a grant.
  if (moon.clientProgramModelResponseProfileTransportMatches(profile,
    maxRequestBytes, responseLimits.maxBytes, responseLimits.maxChunkBytes,
    responseLimits.maxChunks, responseLimits.maxHeaderBytes) !== true) {
    fail('HTTPChatOriginalTransportLimitsMismatch');
  }
  let controller: AbortController | undefined = new AbortController();
  let body: string | undefined;
  let init: unknown;
  let plan: unknown;
  let call: unknown;
  let response: unknown;
  let raw: RawObservation | undefined;
  let unread: UnreadResponse | undefined;
  let pending = false;
  let readerRetired = false;
  let retiring = false;
  let saving: Promise<void> | undefined;
  let saveStarted = false;
  let failure: unknown;
  let attempted = false;
  let terminal = false;
  let retired = false;
  let rawBound = !deferred;
  let reconciling: Promise<SavedRaw> | undefined;
  let reconciliationPending = false;
  let reconciled: unknown;
  const wake = () => { try { notify?.(); } catch { /* Availability is not permission. */ } };
  const unknown = () => moon.clientProgramModelPhysicalUnknown();
  let abort: (() => void) | undefined = () => { controller?.abort!(); wake(); };
  signal?.addEventListener('abort', abort, {once: true});
  if (signal?.aborted) controller.abort!();
  const poll = () => {
    if (response !== undefined) return moon.clientProgramModelPhysicalSavedChat(response);
    if (failure !== undefined) return unknown();
    if (retired) fail('ForeignHTTPChatCall');
    if (raw !== undefined && !saveStarted) {
      saveStarted = true;
      saving = Promise.resolve().then(() => persistRaw!(call, raw!)).then(saved => {
        if (saved?.response === undefined) fail('MissingSavedHTTPChatRaw');
        response = saved.response;
      }).catch(error => { failure = error; }).finally(() => { saving = undefined; wake(); });
    }
    return moon.clientProgramModelPhysicalPending();
  };
  const cancel = () => {
    if (retired) fail('ForeignHTTPChatCall');
    abort!();
  };
  const cleanup = () => {
    if (retired) return true;
    if (pending || saving !== undefined || reconciliationPending) { abort!(); return false; }
    if (unread !== undefined) {
      if (!retiring) {
        retiring = true;
        let disposal;
        try { disposal = unread.body == null ? Promise.resolve() : unread.body.cancel(); }
        catch { disposal = Promise.reject(Error('HTTPChatReaderCleanupFailed')); }
        Promise.resolve(disposal).then(() => { unread = undefined; }, () => {})
          .finally(() => { retiring = false; wake(); });
      }
      return false;
    }
    if (raw !== undefined && !readerRetired) {
      if (!retiring) {
        retiring = true;
        raw.retryReaderRetirement().then(done => { readerRetired = done; }, () => {})
          .finally(() => { retiring = false; wake(); });
      }
      return false;
    }
    if (saveStarted || deferred && rawBound) {
      try { if (cleanupRaw!(call) !== true) return false; }
      catch { return false; }
    }
    signal?.removeEventListener('abort', abort!);
    body = init = plan = call = response = raw = unread = reconciled = reconciling = undefined;
    request = admittedProvider = profile = installation = quantities = undefined;
    headers = controller = signal = abort = fetch = notify = observeAt = checked = undefined;
    projectionLimits = requestLimits = responseLimits = persistRaw = cleanupRaw = undefined;
    retired = true;
    return true;
  };
  const start = (entry: unknown) => {
    if (retired || attempted) return undefined;
    attempted = true;
    if (!rawBound) { failure = Error('HTTPChatRawBindingUnavailable'); return undefined; }
    call = moon.clientProgramModelPhysicalCallForRequest(entry, request, poll, cancel, cleanup);
    if (call === undefined) { failure = Error('HTTPChatOriginalCallUnavailable'); return undefined; }
    if (controller!.signal.aborted) {
      // Retain the original entered call; a local abort denies this physical
      // start but cannot turn durable Entry custody into a new send permit.
      failure = Error('HTTPChatPreparationCancelled');
      return call;
    }
    pending = true;
    let operation;
    // Common's original final gate immediately precedes this fixed fetch.
    // No notification, await or request construction is interposed here.
    try { operation = fetch!(endpoint, init); }
    catch { operation = Promise.reject(Error('HTTPChatTransportUnknown')); }
    Promise.resolve(operation).then(original => {
      unread = original as UnreadResponse;
      const observedAt = observeAt!();
      return readBoundedInferResponse(original as PhysicalResponse, responseLimits!, controller!.signal)
        .then(value => {
          raw = Object.freeze({...value, observedAt});
          unread = undefined;
          value.readerRetirement.then(done => { readerRetired = done; wake(); }, () => {});
        });
    }).catch(() => { failure ??= Error('HTTPChatTransportUnknown'); })
      .finally(() => { pending = false; wake(); });
    return call;
  };
  const advance = () => {
    if (retired || terminal) return runtimePair(true, plan);
    terminal = true;
    if (controller!.signal.aborted) return runtimePair(true, undefined);
    try {
      body = prepareOriginalHttpChatRequest({moon, admittedProvider, request,
        modelId, taskCid, promptCid, outputSchemaCid, modelSelector, limits: projectionLimits}).body;
      const requestBytes = Buffer.byteLength(body);
      if (body.length > maxRequestBytes || requestBytes > maxRequestBytes) return runtimePair(true, undefined);
      init = Object.freeze({method: 'POST', body, headers, redirect: 'error', signal: controller!.signal});
      plan = checked!(moon.clientProgramModelAsyncPhysicalRequestPlan(request,
        BigInt(requestBytes), quantities!.tokens, quantities!.costUnits,
        quantities!.durationMs, profile, installation, start));
    } catch { plan = undefined; }
    return runtimePair(true, plan);
  };
  const preflight = moon.clientProgramModelRequestPreflight(advance, cleanup);
  if (deferred) {
    try {
      const bound = rawCaptureBinder!((registration, persistence) => {
        if (retired || rawBound || terminal && plan === undefined || registration === undefined ||
            typeof persistence !== 'function' || typeof persistence.cleanup !== 'function') fail('HTTPChatRawBindingRefused');
        persistRaw = persistence;
        cleanupRaw = persistence.cleanup;
        rawBound = true;
      });
      if (bound !== undefined) fail('HTTPChatRawBinderUnavailable');
    } catch {
      // An already retained/bound port belongs to this same rejected
      // preparation. Return its cleanup handle rather than losing custody.
      terminal = true;
      failure = Error('HTTPChatRawBinderUnavailable');
    }
    rawCaptureBinder = undefined;
  }
  return Object.freeze({preflight,
    reconcileRaw(original: unknown) {
      if (retired || call === undefined || original !== call || !saveStarted ||
          failure === undefined || saving !== undefined || raw === undefined) {
        return Promise.reject(Error('HTTPChatRawReconciliationUnavailable'));
      }
      if (reconciling !== undefined) return reconciling;
      reconciliationPending = true;
      reconciling = Promise.resolve().then(() => persistRaw!(call, raw!)).then(saved => {
        if (saved?.response === undefined) fail('MissingSavedHTTPChatRaw');
        reconciled = saved.response;
        return saved;
      }).finally(() => { reconciliationPending = false; wake(); });
      return reconciling;
    },
    readReconciledUsage(original: unknown, quantum: number) {
      if (retired || original !== call || reconciled === undefined ||
          !Number.isInteger(quantum) || quantum < 1 || quantum > 2_147_483_647) fail('HTTPChatRawUsageUnavailable');
      return checked!(moon.clientProgramReadReconciledInferRawUsage(original, reconciled, quantum));
    },
    rawFailure: () => failure,
  });
}

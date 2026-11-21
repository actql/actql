import {Client, buildConnector} from 'undici';
import type {Dispatcher} from 'undici';
import type {Socket} from 'node:net';
import type {PhysicalAcquisitionLimits, PhysicalTransportTimeouts, RequestLimits, ResponseLimits} from '../index.d.ts';
import {types} from 'node:util';
import {fixedInferResponseLimits} from './bounded-response.mjs';

type FixedResponseLimits = ReturnType<typeof fixedInferResponseLimits>;
interface OriginalInstallation {
  endpoint: string; origin: string; path: string;
  maxBytes: number; maxHeaderBytes: number; maxHeaders: number;
  limits: FixedResponseLimits; acquisition: PhysicalAcquisitionLimits;
  timeouts?: PhysicalTransportTimeouts;
}
interface Acquisition {
  reads: number; backingBytes: number; backings: WeakSet<object> | undefined; refused: boolean;
}
interface OriginalRequest {
  method?: unknown; body?: unknown; redirect?: unknown; signal?: unknown; headers?: unknown;
}
interface OriginalReader {
  read(): Promise<IteratorResult<unknown>>;
  cancel(): Promise<void>;
  releaseLock(): void;
}
interface OriginalResponse {
  status: number; headers: {get(name: string): string | null};
  body: {getReader(): OriginalReader; cancel(): Promise<void>};
}
interface PhysicalTransport {
  invoke(): Promise<OriginalResponse>;
  cleanup(): Promise<boolean>;
  finishResponse?(): void;
}
// The pinned connector returns its original Socket although its public
// declaration describes only callback delivery. This private unchecked view
// adds no Socket creation, ownership, validation or close acknowledgement.
type OriginalConnector = (options: buildConnector.Options,
  callback: (error: Error | null, connected?: Socket) => void) => Socket;
interface NativeReadOptions {
  buffer: Buffer | undefined;
  callback: ((this: Socket, length: number, buffer: Buffer) => boolean) | undefined;
}

// Original physical installation data only. This membership neither admits a
// Run/Entry nor issues currentness, capacity, completion or send permission.
// The actual per-call Client/duty is retained in the existing SDK transport.
const installations = new WeakMap<object, Readonly<OriginalInstallation>>();
const issue = (code: string) => Object.assign(new TypeError(code), {code});
const positive = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2_147_483_647;
const acquisitionSnapshots = new WeakSet<object>();

// Private DATA membership only, never a capacity loan or currentness receipt.
// Reuse our own snapshot across material admission/assembler preparation.
export function fixedOriginalAcquisitionLimits(value: unknown): Readonly<PhysicalAcquisitionLimits> {
  if (acquisitionSnapshots.has(value as object)) return value as Readonly<PhysicalAcquisitionLimits>;
  const names = ['maxBorrowedBackingBytes', 'maxPlaintextBytes', 'maxReads'];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => typeof key !== 'string') ||
      keys.slice().sort().some((key, index) => key !== names[index])) {
    throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
  }
  const entries: [string, number][] = names.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (descriptor === undefined || !descriptor.enumerable || !('value' in descriptor) ||
        !positive(descriptor.value)) throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
    return [name, descriptor.value];
  });
  const snapshot = Object.freeze(Object.fromEntries(entries)) as Readonly<PhysicalAcquisitionLimits>;
  acquisitionSnapshots.add(snapshot);
  return snapshot;
}

// Optional explicit physical phase/idle settings and total request/read clock.
// Immutable Host DATA, never quantity observation or a dispatch grant.
export function fixedOriginalTransportTimeouts(value: unknown): Readonly<PhysicalTransportTimeouts> | undefined {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) {
    throw issue('UndiciOriginalTimeoutsUnavailable');
  }
  const names = ['bodyMs', 'connectMs', 'headersMs'];
  const keys = Reflect.ownKeys(value);
  if (keys.some(key => typeof key !== 'string' || ![...names, 'callMs'].includes(key)) ||
      names.some(name => !keys.includes(name))) throw issue('UndiciOriginalTimeoutsUnavailable');
  const fields: [PropertyKey, number][] = keys.sort().map(name => {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field?.enumerable || !Object.hasOwn(field, 'value') || !positive(field.value)) {
      throw issue('UndiciOriginalTimeoutsUnavailable');
    }
    return [name, field.value];
  });
  return Object.freeze(Object.fromEntries(fields)) as Readonly<PhysicalTransportTimeouts>;
}

function bindAcquisitionRead(socket: Socket, limits: PhysicalAcquisitionLimits, acquisition: Acquisition, inputExtent: number) {
  const read = socket.read;
  const descriptor = Object.getOwnPropertyDescriptor(socket, 'read');
  let plaintext = 0;
  // Undici 7.30 Parser.readMore/resume calls this same socket.read before
  // Parser.execute allocates/copies llhttp scratch or exposes body aliases.
  // Node/TLS emission and Readable queue/concat precede this observation:
  // these checks cannot fund or bound that first allocator. Ordinary adoption
  // still requires its original Host coverage and same-Ledger phase envelope.
  const boundedRead = function (...args: [number?]) {
    // Node can still consume an already queued buffer after destroy(). Stop
    // another parser read, but retain the SAME queue/socket/close duty until
    // actual cleanup; this flag is never a physical retirement observation.
    if (acquisition.refused || socket.destroyed) return null;
    // Count every original read invocation, including null/empty probes.
    // Refuse before another read; this still does not bound native emission.
    if (acquisition.reads >= limits.maxReads) {
      acquisition.refused = true;
      socket.destroy(issue('UndiciOriginalAcquisitionReadsExceeded'));
      return null;
    }
    // Undici's un-sized read otherwise lets Node fromList concatenate the
    // entire queued payload BEFORE the acquisition checks below. Select from
    // this same original queue before that allocation, using this Call's
    // already fixed native input extent, not a new capacity or packet bound.
    // read(0) drives an empty producer without accepting a synchronous _read
    // burst as one unbounded chunk; an already queued short response uses its
    // actual length and does not wait for an extent or EOF. Explicit reads
    // retain their existing Node meaning. Emission/native backing still needs
    // the original Host coverage and the whole-phase numerical envelope.
    if (args.length === 0 || args[0] === undefined) {
      const available = socket.readableLength;
      if (!Number.isSafeInteger(available) || available < 0) {
        acquisition.refused = true;
        socket.destroy(issue('UndiciOriginalAcquisitionShapeRefused'));
        return null;
      }
      args[0] = Math.min(available, inputExtent);
    }
    acquisition.reads++;
    const chunk: unknown = Reflect.apply(read, socket, args);
    if (chunk === null) return chunk;
    let code;
    if (!Buffer.isBuffer(chunk)) code = 'UndiciOriginalAcquisitionShapeRefused';
    else if (chunk.byteLength > limits.maxPlaintextBytes - plaintext) {
      code = 'UndiciOriginalAcquisitionPlaintextExceeded';
    } else if (!acquisition.backings!.has(chunk.buffer) &&
        chunk.buffer.byteLength > limits.maxBorrowedBackingBytes - acquisition.backingBytes) {
      code = 'UndiciOriginalAcquisitionBackingExceeded';
    }
    if (code !== undefined) {
      acquisition.refused = true;
      socket.destroy(issue(code));
      return null; // Never forward the refused chunk into the HTTP parser.
    }
    plaintext += (chunk as Buffer).byteLength;
    // A conservative lifetime union, not an observed simultaneous peak. No
    // refund at EOF/cancel/Promise completion; aliases may outlive the read.
    // Weak membership adds no strong buffer alias; its controls need funding.
    if (!acquisition.backings!.has((chunk as Buffer).buffer)) {
      acquisition.backings!.add((chunk as Buffer).buffer);
      acquisition.backingBytes += (chunk as Buffer).buffer.byteLength;
    }
    return chunk;
  };
  Object.defineProperty(socket, 'read', {value: boundedRead, configurable: true, writable: true});
  return () => {
    if (socket.read === boundedRead) {
      if (descriptor === undefined) delete (socket as Partial<Socket>).read;
      else Object.defineProperty(socket, 'read', descriptor);
    }
    acquisition.backings = undefined;
  };
}

// Keep validation-only bindings out of the long-lived Call context shared by
// invoke/connect/cleanup. The comparison remains synchronous and exact; this
// neither releases physical duties nor changes the original capacity grant.
function sameResponseLimits(limits: FixedResponseLimits, original: FixedResponseLimits) {
  if (limits.maxBytes !== original.maxBytes ||
      limits.maxChunkBytes !== original.maxChunkBytes ||
      limits.maxChunks !== original.maxChunks ||
      limits.maxHeaderBytes !== original.maxHeaderBytes ||
      limits.observedHeaders.length !== original.observedHeaders.length) return false;
  for (let index = 0; index < limits.observedHeaders.length; index++) {
    if (limits.observedHeaders[index] !== original.observedHeaders[index]) return false;
  }
  return true;
}

// Private selected Host factory, not an arbitrary Run-provided dispatcher.
// All descriptor/control/module and future Client/native holdings must already
// be funded by the original installation/Call before physical preparation.
export function createOriginalUndiciFetch({endpoint, requestLimits, responseLimits, physicalAcquisitionLimits, transportTimeouts}: {endpoint: string; requestLimits: RequestLimits; responseLimits: ResponseLimits; physicalAcquisitionLimits: unknown; transportTimeouts?: unknown}) {
  const acquisition = fixedOriginalAcquisitionLimits(physicalAcquisitionLimits);
  const timeouts = fixedOriginalTransportTimeouts(transportTimeouts);
  let url;
  try { url = new URL(endpoint); } catch { throw issue('UndiciOriginalEndpointUnavailable'); }
  if (typeof endpoint !== 'string' || url.href !== endpoint ||
      !['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.hash || url.search) throw issue('UndiciOriginalEndpointUnavailable');
  const {maxBytes, maxHeaderBytes, maxHeaders} = requestLimits ?? {};
  if (![maxBytes, maxHeaderBytes, maxHeaders].every(positive) || maxHeaders > 64) {
    throw issue('UndiciOriginalRequestLimitsUnavailable');
  }
  const limits = fixedInferResponseLimits(responseLimits);
  // Direct use is deliberately unavailable. SDK preparation fixes each Call's
  // exact original request before its existing one-shot gate. No pool/queue or
  // deferred Client creation is hidden inside a fetch after that gate.
  const fetch = Object.freeze(function originalUndiciFetch() {
    throw issue('UndiciOriginalRequestNotPrepared');
  });
  const original: OriginalInstallation = {endpoint, origin: url.origin,
    path: url.pathname, maxBytes, maxHeaderBytes, maxHeaders, limits, acquisition};
  if (timeouts !== undefined) original.timeouts = timeouts;
  installations.set(fetch, Object.freeze(original));
  return fetch;
}

// Undefined means the existing generic/native fetch path, not a fallback for
// malformed selected Undici configuration. No caller-controlled hooks run at
// transport start. This thin adapter reuses the original SDK/Model lifetime.
export function prepareOriginalUndiciFetch(fetch: unknown, input: unknown, init: OriginalRequest, responseLimits: ResponseLimits, controller?: AbortController): Readonly<PhysicalTransport> | undefined {
  const original = installations.get(fetch as object);
  if (original === undefined) return undefined;
  if (original.timeouts?.callMs !== undefined &&
      (!(controller instanceof AbortController) || controller.signal !== init?.signal)) {
    throw issue('UndiciOriginalDeadlineControllerUnavailable');
  }
  const limits = fixedInferResponseLimits(responseLimits);
  if (input !== original.endpoint || init?.method !== 'POST' ||
      typeof init.body !== 'string' || Buffer.byteLength(init.body) > original.maxBytes ||
      init.redirect !== 'error' || !(init.signal instanceof AbortSignal) ||
      !Array.isArray(init.headers) || init.headers.length > original.maxHeaders ||
      !sameResponseLimits(limits, original.limits)) {
    throw issue('UndiciOriginalRequestMismatch');
  }
  let headerBytes = 0;
  const headers: string[] = [];
  for (const pair of init.headers as unknown[]) {
    if (!Array.isArray(pair) || pair.length !== 2 || pair.some(value => typeof value !== 'string')) {
      throw issue('UndiciOriginalRequestMismatch');
    }
    headerBytes += Buffer.byteLength(pair[0]) + Buffer.byteLength(pair[1]);
    if (headerBytes > original.maxHeaderBytes) throw issue('UndiciOriginalRequestMismatch');
    headers.push(pair[0], pair[1]);
  }
  // These are acquisition/backpressure controls, NOT hard socket/TLS/chunk or
  // whole-heap bounds. Parser/native/header/backing overlap remains in C's sum.
  // Client.destroy() can acknowledge before an in-progress connector returns.
  // Keep the actual returned socket's close observation separately, including
  // DNS/TLS/connect failure. A request rejection is not its retirement ACK.
  // This original Client never reconnects or reuses another Call's session.
  // Do not register unused resumption tickets in Undici's session cache. Its
  // empty cache/registry, listener and TLS/native lifetimes still need funding.
  let connecting = false;
  let socket: Socket | undefined;
  let socketClosed: Promise<boolean> | undefined;
  let connectorFinished: Promise<boolean> | undefined;
  let retireAcquisition: (() => void) | undefined;
  // The selected Node listener writes into one dedicated buffer fixed during
  // this original preparation, never a new backing chosen after acquisition.
  // Its extent and all controls must be covered by the existing Model envelope
  // BEFORE entering this function. This selection does not issue that loan.
  let nativeInput: Buffer | undefined = Buffer.allocUnsafeSlow(Math.min(limits.maxChunkBytes,
    original.acquisition.maxBorrowedBackingBytes));
  const inputExtent = nativeInput.byteLength;
  const acquisition: Acquisition = {reads: 0, backingBytes: inputExtent,
    backings: new WeakSet([nativeInput.buffer]), refused: false};
  let emittedBytes = 0, socketPush: Socket['push'] | undefined;
  const onread: NativeReadOptions = {
    buffer: nativeInput,
    callback(length, buffer) {
      if (acquisition.refused || socket?.destroyed) return false;
      let code;
      if (this !== socket || buffer !== nativeInput ||
          !Number.isSafeInteger(length) || length <= 0 || length > inputExtent) {
        code = 'UndiciOriginalAcquisitionShapeRefused';
      } else if (acquisition.reads >= original.acquisition.maxReads) {
        code = 'UndiciOriginalAcquisitionReadsExceeded';
      } else if (length > original.acquisition.maxPlaintextBytes - emittedBytes) {
        code = 'UndiciOriginalAcquisitionPlaintextExceeded';
      } else if (length > original.acquisition.maxBorrowedBackingBytes - acquisition.backingBytes) {
        code = 'UndiciOriginalAcquisitionBackingExceeded';
      }
      if (code !== undefined) {
        acquisition.refused = true;
        socket?.destroy(issue(code));
        return false;
      }
      // Reserve from these fixed declaration bounds before allocating a copy.
      // They are not capacity receipts. Native reuse must never overwrite an
      // escaped parser/body view, so only an exact dedicated copy is queued.
      emittedBytes += length;
      // Native deliveries and parser probes share one finite original read
      // ceiling; neither stage can create an unbounded set of controls.
      acquisition.reads++;
      try {
        const copy = Buffer.allocUnsafeSlow(length);
        acquisition.backings!.add(copy.buffer);
        acquisition.backingBytes += copy.buffer.byteLength;
        nativeInput!.copy(copy, 0, 0, length);
        return Reflect.apply(socketPush!, socket, [copy]);
      } catch (error) {
        acquisition.refused = true;
        socket!.destroy(error as Error);
        return false;
      }
    },
  };
  // No buffer generator, ambient dispatcher or independent stream owner.
  // Node CustomBufferJSListener reuses this exact input backing for TCP/TLS;
  // SSL/BIO/handshake native and queued/copy controls remain explicit holdings.
  // A custom connector does not inherit Client.connectTimeout. Bind the
  // selected connect setting directly to this SAME connector's existing timer.
  const connector = (original.timeouts === undefined
    ? buildConnector({allowH2: false, maxCachedSessions: 0, onread} as buildConnector.BuildOptions)
    : buildConnector({allowH2: false, maxCachedSessions: 0, onread, timeout: original.timeouts.connectMs} as buildConnector.BuildOptions)) as unknown as OriginalConnector;
  const connect = (options: buildConnector.Options, callback: (error: Error | null, socket?: Socket | null) => void) => {
    if (connecting) { callback(issue('UndiciOriginalReconnectRefused')); return; }
    connecting = true;
    let finish: (value: boolean) => void;
    connectorFinished = new Promise(resolve => { finish = resolve; });
    socket = connector(options, (error, connected) => {
      try {
        if (connected !== undefined && retireAcquisition === undefined) {
          try { retireAcquisition = bindAcquisitionRead(connected, original.acquisition, acquisition, inputExtent); }
          catch (refusal) {
            connected.destroy(refusal as Error);
            callback(refusal as Error, null);
            return;
          }
        }
        callback(error, connected);
      } finally { finish!(true); }
    });
    socketClosed = socket.closed ? Promise.resolve(true)
      : new Promise(resolve => socket!.once('close', () => resolve(true)));
    socketPush = socket.push;
    return socket;
  };
  let client: Client | undefined = original.timeouts === undefined
    ? new Client(original.origin, {allowH2: false, pipelining: 0, connect,
      maxHeaderSize: limits.maxHeaderBytes, maxResponseSize: limits.maxBytes} as Client.Options)
    : new Client(original.origin, {allowH2: false, pipelining: 0, connect,
      maxHeaderSize: limits.maxHeaderBytes, maxResponseSize: limits.maxBytes,
      headersTimeout: original.timeouts.headersMs, bodyTimeout: original.timeouts.bodyMs} as Client.Options);
  const request = Object.freeze({path: original.path, method: 'POST',
    headers: Object.freeze(headers), body: init.body, signal: init.signal,
    highWaterMark: limits.maxChunkBytes, idempotent: false});
  const method = client.request;
  let pending: Promise<void> | undefined;
  let body: Dispatcher.ResponseData['body'] | undefined;
  let bodyClosed: Promise<boolean> | undefined;
  let destroying: Promise<boolean> | undefined;
  let retired = false;
  const invoke = () => {
    if (retired || destroying !== undefined) throw issue('UndiciOriginalTransportRetired');
    // The existing SDK start bit/Core gate owns one-shot admission. The fixed
    // original Client method/options are the actual first physical operation.
    const response = (Reflect.apply(method, client, [request]) as Promise<Dispatcher.ResponseData>).then(response => {
      const responseBody = response.body;
      body = responseBody;
      // Register settlement immediately, including errors before getReader.
      // Error/destroy flags are not the later actual stream close event.
      responseBody.on('error', () => {});
      if (responseBody.closed) {
        bodyClosed = Promise.resolve(true);
        body = undefined;
      } else {
        bodyClosed = new Promise(resolve => responseBody.once('close', () => {
          // Only this same body's actual close retires our unused alias.
          // Its abort/handler/trailers need not remain pinned by a delayed
          // Socket close. Escaped stream/raw borrowers keep their own roots;
          // Client/connector/Socket/bodyClosed still form the original IO AND.
          if (body === responseBody) body = undefined;
          resolve(true);
        }));
      }
      // Escaped unread/reader views retain this SAME close observation after
      // the transport drops its own references. Do not make their cancellation
      // consult a mutable cell that physical cleanup can retire first.
      return originalResponseView(response, responseBody, bodyClosed!);
    });
    // Cleanup needs settlement of this SAME request, not another retained
    // fulfilled response/header view. Callers keep the original value/error;
    // the handled child carries Unit on either outcome, never an I/O ACK.
    const settled = () => {};
    pending = response.then(settled, settled);
    return response;
  };
  const cleanup = () => {
    if (retired) return Promise.resolve(true);
    if (destroying !== undefined) return destroying;
    // destroyed/closed flags alone are not the Client's close acknowledgement.
    // Also stop the same pending connector socket. Undici's Client destroy
    // path alone cannot acknowledge that physical lifetime before HTTP setup.
    // Supplying the error also settles buildConnector's original callback and
    // timeout path; a bare socket.destroy() need not emit that error callback.
    // The original response can be refused before getReader (for example an
    // observed-header limit). Drive that SAME unread body before awaiting its
    // close. A destroy request is not its ACK: retain all original references
    // until the existing Client/connector/Socket/body observations below agree.
    body?.destroy();
    socket?.destroy(issue('UndiciOriginalTransportRetired'));
    destroying = client!.destroy().then(async () => {
      if (pending !== undefined) await pending;
      if (connectorFinished !== undefined && await connectorFinished !== true) return false;
      if (socketClosed !== undefined && await socketClosed !== true) return false;
      if (bodyClosed !== undefined && await bodyClosed !== true) return false;
      retireAcquisition?.();
      retireAcquisition = undefined;
      acquisition.refused = true;
      acquisition.backings = undefined;
      // Drop the remaining aliases only after physical closure. Escaped body/raw
      // borrowers can still retain the Socket's input buffer: Model/SDK/Store
      // holding settlement, not this IO ACK, decides their byte retirement.
      client = undefined;
      socketPush = undefined;
      onread.buffer = undefined;
      onread.callback = undefined;
      nativeInput = undefined;
      retired = true;
      socket = undefined;
      socketClosed = undefined;
      connectorFinished = undefined;
      body = undefined;
      bodyClosed = undefined;
      pending = undefined;
      return true;
    }, () => false).finally(() => { destroying = undefined; });
    return destroying;
  };
  const physical = Object.freeze({invoke, cleanup});
  return original.timeouts?.callMs === undefined ? physical
    : withOriginalCallDeadline(physical, controller!, original.timeouts.callMs);
}

// Only the explicitly configured physical Call allocates these controls. The
// normal factory adds their Common quote to its original per-Task Model demand
// before Plan/Scope admission. This wraps the SAME transport and controller;
// it is not another lifetime owner, RunCancel, retry or physical cleanup ACK.
function withOriginalCallDeadline(physical: Readonly<PhysicalTransport>, controller: AbortController, ms: number): Readonly<PhysicalTransport> {
  const reason = Object.freeze({code: 'UndiciOriginalCallTimeout'});
  let timer: NodeJS.Timeout | undefined;
  let finished = false;
  const finishResponse = () => {
    finished = true;
    if (timer !== undefined) clearTimeout(timer);
    timer = undefined;
  };
  const expire = () => {
    timer = undefined;
    if (!finished) {
      finished = true;
      // Abort the original physical request/read only. The SDK's Run-cancel
      // function also sets stopped; using it here would falsify cancellation.
      controller.abort(reason);
    }
  };
  return Object.freeze({
    invoke() {
      // Preserve the first physical primitive after the original Entry gate.
      // No timer, observer, await or different request precedes this invoke.
      const response = physical.invoke();
      try { timer = setTimeout(expire, ms); }
      catch (error) {expire(); throw error;}
      return response;
    },
    cleanup() {finishResponse(); return physical.cleanup();},
    finishResponse,
  });
}

function originalHeadersView(originalHeaders: Dispatcher.ResponseData['headers']) {
  // Actual parsed HTTP headers, not SDK defaults or a JSON response parser.
  // Borrow the SAME header map, not the entire response/statusText/trailers/
  // context graph. Duplicate arrays and escaped header views stay borrowed.
  return Object.freeze({get(name: string) {
    const value = originalHeaders[name.toLowerCase()];
    return value === undefined ? null : Array.isArray(value) ? value.join(', ') : value;
  }});
}

function originalResponseView(response: Dispatcher.ResponseData, body: Dispatcher.ResponseData['body'], closed: Promise<boolean>): Readonly<OriginalResponse> {
  // Do not copy the body through Response()/BodyReadable.body/toWeb/text/json.
  const headers = originalHeadersView(response.headers);
  let iterator: AsyncIterator<unknown> | undefined;
  let reader: Readonly<OriginalReader> | undefined;
  let reading: Promise<IteratorResult<unknown>> | undefined;
  const cancel = async () => {
    body.destroy();
    if (await closed !== true) throw issue('UndiciOriginalBodyCleanupPending');
  };
  const stream = Object.freeze({getReader() {
    if (reader !== undefined) throw issue('UndiciOriginalBodyLocked');
    iterator ??= body[Symbol.asyncIterator]();
    const originalReader: Readonly<OriginalReader> = Object.freeze({read() {
      if (reader !== originalReader) throw issue('UndiciOriginalReaderReleased');
      if (reading !== undefined) throw issue('UndiciOriginalReadPending');
      reading = (iterator!.next() as Promise<IteratorResult<unknown>>).finally(() => { reading = undefined; });
      return reading;
    }, cancel, releaseLock() {
      if (reader !== originalReader) throw issue('UndiciOriginalReaderReleased');
      if (reading !== undefined) throw issue('UndiciOriginalReadPending');
      reader = undefined;
    }});
    reader = originalReader;
    return reader;
  }, cancel});
  return Object.freeze({status: response.statusCode, headers, body: stream});
}

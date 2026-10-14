import {Client, buildConnector} from 'undici';
import {fixedInferResponseLimits} from './bounded-response.mjs';

// Original physical installation data only. This membership neither admits a
// Run/Entry nor issues currentness, capacity, completion or send permission.
// The actual per-call Client/duty is retained in the existing SDK transport.
const installations = new WeakMap();
const issue = code => Object.assign(new TypeError(code), {code});
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2_147_483_647;
const acquisitionSnapshots = new WeakSet();

// Private DATA membership only, never a capacity loan or currentness receipt.
// Reuse our own snapshot across material admission/assembler preparation.
export function fixedOriginalAcquisitionLimits(value) {
  if (acquisitionSnapshots.has(value)) return value;
  const names = ['maxBorrowedBackingBytes', 'maxPlaintextBytes', 'maxReads'];
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
  }
  const keys = Reflect.ownKeys(value);
  if (keys.length !== names.length || keys.some(key => typeof key !== 'string') ||
      keys.slice().sort().some((key, index) => key !== names[index])) {
    throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
  }
  const entries = names.map(name => {
    const descriptor = Object.getOwnPropertyDescriptor(value, name);
    if (descriptor === undefined || !descriptor.enumerable || !('value' in descriptor) ||
        !positive(descriptor.value)) throw issue('UndiciOriginalAcquisitionLimitsUnavailable');
    return [name, descriptor.value];
  });
  const snapshot = Object.freeze(Object.fromEntries(entries));
  acquisitionSnapshots.add(snapshot);
  return snapshot;
}

function bindAcquisitionRead(socket, limits, acquisition) {
  const read = socket.read;
  const descriptor = Object.getOwnPropertyDescriptor(socket, 'read');
  let plaintext = 0;
  // Undici 7.30 Parser.readMore/resume calls this same socket.read before
  // Parser.execute allocates/copies llhttp scratch or exposes body aliases.
  // Node/TLS emission and Readable queue/concat precede this observation:
  // these checks cannot fund or bound that first allocator. Ordinary adoption
  // still requires its original Host coverage and same-Ledger phase envelope.
  const boundedRead = function (...args) {
    if (acquisition.refused) return null;
    // Count every original read invocation, including null/empty probes.
    // Refuse before another read; this still does not bound native emission.
    if (acquisition.reads >= limits.maxReads) {
      acquisition.refused = true;
      socket.destroy(issue('UndiciOriginalAcquisitionReadsExceeded'));
      return null;
    }
    acquisition.reads++;
    const chunk = Reflect.apply(read, socket, args);
    if (chunk === null) return chunk;
    let code;
    if (!Buffer.isBuffer(chunk)) code = 'UndiciOriginalAcquisitionShapeRefused';
    else if (chunk.byteLength > limits.maxPlaintextBytes - plaintext) {
      code = 'UndiciOriginalAcquisitionPlaintextExceeded';
    } else if (!acquisition.backings.has(chunk.buffer) &&
        chunk.buffer.byteLength > limits.maxBorrowedBackingBytes - acquisition.backingBytes) {
      code = 'UndiciOriginalAcquisitionBackingExceeded';
    }
    if (code !== undefined) {
      acquisition.refused = true;
      socket.destroy(issue(code));
      return null; // Never forward the refused chunk into the HTTP parser.
    }
    plaintext += chunk.byteLength;
    // A conservative lifetime union, not an observed simultaneous peak. No
    // refund at EOF/cancel/Promise completion; aliases may outlive the read.
    // Weak membership adds no strong buffer alias; its controls need funding.
    if (!acquisition.backings.has(chunk.buffer)) {
      acquisition.backings.add(chunk.buffer);
      acquisition.backingBytes += chunk.buffer.byteLength;
    }
    return chunk;
  };
  Object.defineProperty(socket, 'read', {value: boundedRead, configurable: true, writable: true});
  return () => {
    if (socket.read === boundedRead) {
      if (descriptor === undefined) delete socket.read;
      else Object.defineProperty(socket, 'read', descriptor);
    }
    acquisition.backings = undefined;
  };
}

// Keep validation-only bindings out of the long-lived Call context shared by
// invoke/connect/cleanup. The comparison remains synchronous and exact; this
// neither releases physical duties nor changes the original capacity grant.
function sameResponseLimits(limits, original) {
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
export function createOriginalUndiciFetch({endpoint, requestLimits, responseLimits, physicalAcquisitionLimits}) {
  const acquisition = fixedOriginalAcquisitionLimits(physicalAcquisitionLimits);
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
  installations.set(fetch, Object.freeze({endpoint, origin: url.origin,
    path: url.pathname, maxBytes, maxHeaderBytes, maxHeaders, limits, acquisition}));
  return fetch;
}

// Undefined means the existing generic/native fetch path, not a fallback for
// malformed selected Undici configuration. No caller-controlled hooks run at
// transport start. This thin adapter reuses the original SDK/Model lifetime.
export function prepareOriginalUndiciFetch(fetch, input, init, responseLimits) {
  const original = installations.get(fetch);
  if (original === undefined) return undefined;
  const limits = fixedInferResponseLimits(responseLimits);
  if (input !== original.endpoint || init?.method !== 'POST' ||
      typeof init.body !== 'string' || Buffer.byteLength(init.body) > original.maxBytes ||
      init.redirect !== 'error' || !(init.signal instanceof AbortSignal) ||
      !Array.isArray(init.headers) || init.headers.length > original.maxHeaders ||
      !sameResponseLimits(limits, original.limits)) {
    throw issue('UndiciOriginalRequestMismatch');
  }
  let headerBytes = 0;
  const headers = [];
  for (const pair of init.headers) {
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
  let socket;
  let socketClosed;
  let connectorFinished;
  let retireAcquisition;
  // The selected Node listener writes into one dedicated buffer fixed during
  // this original preparation, never a new backing chosen after acquisition.
  // Its extent and all controls must be covered by the existing Model envelope
  // BEFORE entering this function. This selection does not issue that loan.
  let nativeInput = Buffer.allocUnsafeSlow(Math.min(limits.maxChunkBytes,
    original.acquisition.maxBorrowedBackingBytes));
  const inputExtent = nativeInput.byteLength;
  const acquisition = {reads: 0, backingBytes: inputExtent,
    backings: new WeakSet([nativeInput.buffer]), refused: false};
  let emittedBytes = 0, socketPush;
  const onread = {
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
        acquisition.backings.add(copy.buffer);
        acquisition.backingBytes += copy.buffer.byteLength;
        nativeInput.copy(copy, 0, 0, length);
        return Reflect.apply(socketPush, socket, [copy]);
      } catch (error) {
        acquisition.refused = true;
        socket.destroy(error);
        return false;
      }
    },
  };
  // No buffer generator, ambient dispatcher or independent stream owner.
  // Node CustomBufferJSListener reuses this exact input backing for TCP/TLS;
  // SSL/BIO/handshake native and queued/copy controls remain explicit holdings.
  const connector = buildConnector({allowH2: false, maxCachedSessions: 0, onread});
  const connect = (options, callback) => {
    if (connecting) { callback(issue('UndiciOriginalReconnectRefused')); return; }
    connecting = true;
    let finish;
    connectorFinished = new Promise(resolve => { finish = resolve; });
    socket = connector(options, (error, connected) => {
      try {
        if (connected !== undefined && retireAcquisition === undefined) {
          try { retireAcquisition = bindAcquisitionRead(connected, original.acquisition, acquisition); }
          catch (refusal) {
            connected.destroy(refusal);
            callback(refusal, null);
            return;
          }
        }
        callback(error, connected);
      } finally { finish(true); }
    });
    socketClosed = socket.closed ? Promise.resolve(true)
      : new Promise(resolve => socket.once('close', () => resolve(true)));
    socketPush = socket.push;
    return socket;
  };
  let client = new Client(original.origin, {allowH2: false, pipelining: 0, connect,
    maxHeaderSize: limits.maxHeaderBytes, maxResponseSize: limits.maxBytes});
  const request = Object.freeze({path: original.path, method: 'POST',
    headers: Object.freeze(headers), body: init.body, signal: init.signal,
    highWaterMark: limits.maxChunkBytes, idempotent: false});
  const method = client.request;
  let pending;
  let body;
  let bodyClosed;
  let destroying;
  let retired = false;
  const invoke = () => {
    if (retired || destroying !== undefined) throw issue('UndiciOriginalTransportRetired');
    // The existing SDK start bit/Core gate owns one-shot admission. The fixed
    // original Client method/options are the actual first physical operation.
    pending = Reflect.apply(method, client, [request]).then(response => {
      body = response.body;
      // Register settlement immediately, including errors before getReader.
      // Error/destroy flags are not the later actual stream close event.
      body.on('error', () => {});
      bodyClosed = body.closed ? Promise.resolve(true)
        : new Promise(resolve => body.once('close', () => resolve(true)));
      return originalResponseView(response, body, () => bodyClosed);
    });
    // Cleanup and callers observe the same rejection, never an unhandled one.
    pending.catch(() => {});
    return pending;
  };
  const cleanup = () => {
    if (retired) return Promise.resolve(true);
    if (destroying !== undefined) return destroying;
    // destroyed/closed flags alone are not the Client's close acknowledgement.
    // Also stop the same pending connector socket. Undici's Client destroy
    // path alone cannot acknowledge that physical lifetime before HTTP setup.
    // Supplying the error also settles buildConnector's original callback and
    // timeout path; a bare socket.destroy() need not emit that error callback.
    socket?.destroy(issue('UndiciOriginalTransportRetired'));
    destroying = client.destroy().then(async () => {
      if (pending !== undefined) await pending.catch(() => {});
      if (connectorFinished !== undefined && await connectorFinished !== true) return false;
      if (socketClosed !== undefined && await socketClosed !== true) return false;
      if (bodyClosed !== undefined && await bodyClosed !== true) return false;
      retireAcquisition?.();
      retireAcquisition = undefined;
      acquisition.refused = true;
      acquisition.backings = undefined;
      // Drop our own aliases only after physical closure. Escaped body/raw
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
  return Object.freeze({invoke, cleanup});
}

function originalResponseView(response, body, closed) {
  // Actual parsed HTTP headers, not SDK defaults or a JSON response parser.
  // Do not copy the body through Response()/BodyReadable.body/toWeb/text/json.
  const headers = Object.freeze({get(name) {
    const value = response.headers[name.toLowerCase()];
    return value === undefined ? null : Array.isArray(value) ? value.join(', ') : value;
  }});
  let iterator;
  let reader;
  let reading;
  const cancel = async () => {
    body.destroy();
    if (await closed() !== true) throw issue('UndiciOriginalBodyCleanupPending');
  };
  const stream = Object.freeze({getReader() {
    if (reader !== undefined) throw issue('UndiciOriginalBodyLocked');
    iterator ??= body[Symbol.asyncIterator]();
    const originalReader = Object.freeze({read() {
      if (reader !== originalReader) throw issue('UndiciOriginalReaderReleased');
      if (reading !== undefined) throw issue('UndiciOriginalReadPending');
      reading = iterator.next().finally(() => { reading = undefined; });
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

import {Client, buildConnector} from 'undici';
import {types} from 'node:util';
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

// Optional explicit physical phase/idle settings and total request/read clock.
// Immutable Host DATA, never quantity observation or a dispatch grant.
export function fixedOriginalTransportTimeouts(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || Array.isArray(value) || types.isProxy(value)) {
    throw issue('UndiciOriginalTimeoutsUnavailable');
  }
  const names = ['bodyMs', 'connectMs', 'headersMs'];
  const keys = Reflect.ownKeys(value);
  if (keys.some(key => typeof key !== 'string' || ![...names, 'callMs'].includes(key)) ||
      names.some(name => !keys.includes(name))) throw issue('UndiciOriginalTimeoutsUnavailable');
  const fields = keys.sort().map(name => {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field?.enumerable || !Object.hasOwn(field, 'value') || !positive(field.value)) {
      throw issue('UndiciOriginalTimeoutsUnavailable');
    }
    return [name, field.value];
  });
  return Object.freeze(Object.fromEntries(fields));
}

function bindAcquisitionRead(socket, limits, acquisition, inputExtent) {
  const read = socket.read;
  const descriptor = Object.getOwnPropertyDescriptor(socket, 'read');
  let plaintext = 0;
  // Undici 7.30 Parser.readMore/resume calls this same socket.read before
  // Parser.execute allocates/copies llhttp scratch or exposes body aliases.
  // Node/TLS emission and Readable queue/concat precede this observation:
  // these checks cannot fund or bound that first allocator. Ordinary adoption
  // still requires its original Host coverage and same-Ledger phase envelope.
  const boundedRead = function (...args) {
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
export const unboundOpenAICredential = 'actql-unbound-openai-credential';

// The verified registered adapter supplies a single credential reference
// and wire position. Snapshot only DATA. The environment is read by the
// prepared credential port during the original authorized continuation.
function snapshotRegisteredCredential(value, endpoint, protocol) {
  const names = ['endpoint', 'reference', 'header', 'prefix', 'placeholder', 'maxBytes'];
  if (value === null || typeof value !== 'object' || types.isProxy(value) ||
      Object.getPrototypeOf(value) !== Object.prototype || Reflect.ownKeys(value).length !== names.length) {
    throw issue('RegisteredSdkCredentialUnavailable');
  }
  const fields = {};
  for (const name of names) {
    const field = Object.getOwnPropertyDescriptor(value, name);
    if (!field?.enumerable || !Object.hasOwn(field, 'value')) throw issue('RegisteredSdkCredentialUnavailable');
    fields[name] = field.value;
  }
  const {reference, header, prefix, placeholder, maxBytes} = fields;
  if (fields.endpoint !== endpoint || protocol !== 'https:' ||
      typeof reference !== 'string' || !/^[A-Z_][A-Z0-9_]{0,255}$/u.test(reference) ||
      typeof header !== 'string' || !/^[a-z][a-z0-9-]{0,63}$/u.test(header) ||
      ['connection', 'content-length', 'expect', 'host', 'proxy-authorization', 'proxy-connection',
        'te', 'trailer', 'transfer-encoding', 'upgrade'].includes(header) ||
      typeof prefix !== 'string' || prefix !== '' && !/^[A-Za-z][A-Za-z0-9_-]{0,15} $/u.test(prefix) ||
      typeof placeholder !== 'string' || !/^[\x21-\x7e]{1,64}$/u.test(placeholder) ||
      !positive(maxBytes) || maxBytes > 4096) throw issue('RegisteredSdkCredentialUnavailable');
  return Object.freeze({reference, header, prefix, marker: prefix + placeholder, maxBytes,
    missing: 'ModelProjectCredentialUnavailable', unavailable: 'ModelProjectCredentialPreparationUnavailable'});
}

export function createOriginalUndiciFetch({endpoint, requestLimits, responseLimits, physicalAcquisitionLimits,
  transportTimeouts, openAICredentialBytes, registeredCredential}) {
  const acquisition = fixedOriginalAcquisitionLimits(physicalAcquisitionLimits);
  const timeouts = fixedOriginalTransportTimeouts(transportTimeouts);
  let url;
  try { url = new URL(endpoint); } catch { throw issue('UndiciOriginalEndpointUnavailable'); }
  if (typeof endpoint !== 'string' || url.href !== endpoint ||
      !['http:', 'https:'].includes(url.protocol) || url.username || url.password ||
      url.hash || url.search) throw issue('UndiciOriginalEndpointUnavailable');
  let credential;
  if (openAICredentialBytes !== undefined) {
    if (registeredCredential !== undefined || !positive(openAICredentialBytes) || openAICredentialBytes > 4096 ||
        endpoint !== 'https://api.openai.com/v1/chat/completions') throw issue('OpenAIProjectCredentialEndpointUnavailable');
    credential = Object.freeze({reference: 'OPENAI_API_KEY', header: 'authorization', prefix: 'Bearer ',
      marker: 'Bearer ' + unboundOpenAICredential, maxBytes: openAICredentialBytes,
      missing: 'OpenAIProjectCredentialUnavailable', unavailable: 'OpenAIProjectCredentialPreparationUnavailable'});
  } else if (registeredCredential !== undefined) {
    credential = snapshotRegisteredCredential(registeredCredential, endpoint, url.protocol);
  }
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
  const original = {endpoint, origin: url.origin,
    path: url.pathname, maxBytes, maxHeaderBytes, maxHeaders, limits, acquisition};
  if (timeouts !== undefined) original.timeouts = timeouts;
  if (credential !== undefined) original.credential = credential;
  installations.set(fetch, Object.freeze(original));
  return fetch;
}

// Undefined means the existing generic/native fetch path, not a fallback for
// malformed selected Undici configuration. No caller-controlled hooks run at
// transport start. This thin adapter reuses the original SDK/Model lifetime.
export function prepareOriginalUndiciFetch(fetch, input, init, responseLimits, controller) {
  const original = installations.get(fetch);
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
  const credential = original.credential;
  let headerBytes = 0;
  let headers = [];
  let credentialIndex;
  for (const pair of init.headers) {
    if (!Array.isArray(pair) || pair.length !== 2 || pair.some(value => typeof value !== 'string')) {
      throw issue('UndiciOriginalRequestMismatch');
    }
    headerBytes += Buffer.byteLength(pair[0]) + Buffer.byteLength(pair[1]);
    if (headerBytes > original.maxHeaderBytes) throw issue('UndiciOriginalRequestMismatch');
    if (credential !== undefined && pair[0].toLowerCase() === credential.header) {
      if (credentialIndex !== undefined || pair[1] !== credential.marker) {
        throw issue('UndiciOriginalRequestMismatch');
      }
      credentialIndex = headers.length + 1;
    }
    headers.push(pair[0], pair[1]);
  }
  if (credential !== undefined && credentialIndex === undefined) {
    throw issue('UndiciOriginalRequestMismatch');
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
  // A custom connector does not inherit Client.connectTimeout. Bind the
  // selected connect setting directly to this SAME connector's existing timer.
  const connector = original.timeouts === undefined
    ? buildConnector({allowH2: false, maxCachedSessions: 0, onread})
    : buildConnector({allowH2: false, maxCachedSessions: 0, onread, timeout: original.timeouts.connectMs});
  const connect = (options, callback) => {
    if (connecting) { callback(issue('UndiciOriginalReconnectRefused')); return; }
    connecting = true;
    let finish;
    connectorFinished = new Promise(resolve => { finish = resolve; });
    socket = connector(options, (error, connected) => {
      try {
        if (connected !== undefined && retireAcquisition === undefined) {
          try { retireAcquisition = bindAcquisitionRead(connected, original.acquisition, acquisition, inputExtent); }
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
  let client = original.timeouts === undefined
    ? new Client(original.origin, {allowH2: false, pipelining: 0, connect,
      maxHeaderSize: limits.maxHeaderBytes, maxResponseSize: limits.maxBytes})
    : new Client(original.origin, {allowH2: false, pipelining: 0, connect,
      maxHeaderSize: limits.maxHeaderBytes, maxResponseSize: limits.maxBytes,
      headersTimeout: original.timeouts.headersMs, bodyTimeout: original.timeouts.bodyMs});
  let request = Object.freeze({path: original.path, method: 'POST',
    headers: credentialIndex === undefined ? Object.freeze(headers) : headers, body: init.body, signal: init.signal,
    highWaterMark: limits.maxChunkBytes, idempotent: false});
  if (credentialIndex === undefined) headers = undefined;
  const method = client.request;
  let pending;
  let body;
  let bodyClosed;
  let destroying;
  let retired = false;
  const bindCredential = credentialIndex === undefined ? undefined : () => {
    if (retired || destroying !== undefined || pending !== undefined || headers === undefined || init.signal.aborted) {
      throw issue(credential.unavailable);
    }
    // The SDK has already supplied the exact placeholder in its selected
    // header. The suspended SDK never sees the value read for this Call.
    const key = process.env[credential.reference];
    if (typeof key !== 'string' || key.length === 0 || key.length > credential.maxBytes ||
        headerBytes - credential.marker.length + credential.prefix.length + key.length > original.maxHeaderBytes ||
        !/^[\x21-\x7e]+$/u.test(key)) {
      throw issue(credential.missing);
    }
    headers[credentialIndex] = credential.prefix + key;
    Object.freeze(headers);
    headers = undefined;
  };
  const invoke = () => {
    if (retired || destroying !== undefined) throw issue('UndiciOriginalTransportRetired');
    if (headers !== undefined) throw issue(credential.unavailable);
    // The existing SDK start bit/Core gate owns one-shot admission. The fixed
    // original Client method/options are the actual first physical operation.
    const response = Reflect.apply(method, client, [request]).then(response => {
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
      return originalResponseView(response, responseBody, bodyClosed);
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
    destroying = client.destroy().then(async () => {
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
      request = headers = undefined;
      return true;
    }, () => false).finally(() => { destroying = undefined; });
    return destroying;
  };
  const physical = bindCredential === undefined ? Object.freeze({invoke, cleanup})
    : Object.freeze({invoke, cleanup, bindCredential});
  return original.timeouts?.callMs === undefined ? physical
    : withOriginalCallDeadline(physical, controller, original.timeouts.callMs);
}

// Only the explicitly configured physical Call allocates these controls. The
// normal factory adds their Common quote to its original per-Task Model demand
// before Plan/Scope admission. This wraps the SAME transport and controller;
// it is not another lifetime owner, RunCancel, retry or physical cleanup ACK.
function withOriginalCallDeadline(physical, controller, ms) {
  const reason = Object.freeze({code: 'UndiciOriginalCallTimeout'});
  let timer;
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
  const port = {
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
  };
  if (physical.bindCredential !== undefined) port.bindCredential = physical.bindCredential;
  return Object.freeze(port);
}

function originalHeadersView(originalHeaders) {
  // Actual parsed HTTP headers, not SDK defaults or a JSON response parser.
  // Borrow the SAME header map, not the entire response/statusText/trailers/
  // context graph. Duplicate arrays and escaped header views stay borrowed.
  return Object.freeze({get(name) {
    const value = originalHeaders[name.toLowerCase()];
    return value === undefined ? null : Array.isArray(value) ? value.join(', ') : value;
  }});
}

function originalResponseView(response, body, closed) {
  // Do not copy the body through Response()/BodyReadable.body/toWeb/text/json.
  const headers = originalHeadersView(response.headers);
  let iterator;
  let reader;
  let reading;
  const cancel = async () => {
    body.destroy();
    if (await closed !== true) throw issue('UndiciOriginalBodyCleanupPending');
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

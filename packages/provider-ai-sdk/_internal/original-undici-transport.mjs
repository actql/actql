import {Client, buildConnector} from 'undici';
import {fixedInferResponseLimits} from './bounded-response.mjs';

// Original physical installation data only. This membership neither admits a
// Run/Entry nor issues currentness, capacity, completion or send permission.
// The actual per-call Client/duty is retained in the existing SDK transport.
const installations = new WeakMap();
const issue = code => Object.assign(new TypeError(code), {code});
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2_147_483_647;

// Private selected Host factory, not an arbitrary Run-provided dispatcher.
// All descriptor/control/module and future Client/native holdings must already
// be funded by the original installation/Call before physical preparation.
export function createOriginalUndiciFetch({endpoint, requestLimits, responseLimits}) {
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
    path: url.pathname, maxBytes, maxHeaderBytes, maxHeaders, limits}));
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
      ['maxBytes', 'maxChunkBytes', 'maxChunks', 'maxHeaderBytes'].some(name =>
        limits[name] !== original.limits[name]) ||
      limits.observedHeaders.length !== original.limits.observedHeaders.length ||
      limits.observedHeaders.some((name, index) => name !== original.limits.observedHeaders[index])) {
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
  const connector = buildConnector({allowH2: false, maxCachedSessions: 0});
  let connecting = false;
  let socket;
  let socketClosed;
  let connectorFinished;
  const connect = (options, callback) => {
    if (connecting) { callback(issue('UndiciOriginalReconnectRefused')); return; }
    connecting = true;
    let finish;
    connectorFinished = new Promise(resolve => { finish = resolve; });
    socket = connector(options, (error, connected) => {
      try { callback(error, connected); } finally { finish(true); }
    });
    socketClosed = socket.closed ? Promise.resolve(true)
      : new Promise(resolve => socket.once('close', () => resolve(true)));
    return socket;
  };
  const client = new Client(original.origin, {allowH2: false, pipelining: 0, connect,
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

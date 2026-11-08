// The common typed HTTP exchange between a provider's meaning (its MoonBit
// hooks or Node driver) and the physical credential resource. A provider
// selects the method, the exact path, query parameters, allowed non-secret
// request headers and body; this boundary assembles one exact request target
// and admits only the response headers an installation declared, under fixed
// caps. No secret passes here: the credential resource attaches it.
//
// An over-long or unexpected header observation is a typed refusal, never a
// shortened observation that a provider could read as "no next page".
// Observed header values are returned to the provider that declared them and
// are not retained by this boundary.
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

export const exchangeLimits = Object.freeze({
  maxRequestHeaders: 16,
  maxHeaderNameBytes: 64,
  maxHeaderValueBytes: 1024,
  maxQueryPairs: 32,
  maxQueryBytes: 4096,
  maxObservedHeaders: 16,
  maxObservedHeaderBytes: 8192,
});

export const exchangeMethods = Object.freeze(['GET', 'POST', 'PATCH', 'PUT',
  'DELETE']);

// The typed request and physical resource share one method/body policy. The
// typed boundary historically allows an absent POST/PATCH body; the physical
// resource requires it. PUT always requires a string; GET/DELETE never take
// one. This validates transport shape, not JSON or provider Effect meaning.
export function checkHttpRequestMethodBody(method, body,
  {requireBody = false} = {}) {
  if (!exchangeMethods.includes(method)) fail('InvalidHttpRequestMethod');
  const bodyless = method === 'GET' || method === 'DELETE';
  if ((body !== undefined && typeof body !== 'string') ||
      (bodyless && body !== undefined) ||
      (!bodyless && (requireBody || method === 'PUT') && body === undefined)) {
    fail('InvalidHttpRequestBody');
  }
}

// Headers the credential resource owns, that carry credentials, or that
// reshape the connection. A provider never sets them, and an installation
// never declares them as observed response headers.
const reservedRequestHeaders = new Set([
  'authorization', 'proxy-authorization', 'cookie', 'set-cookie', 'host',
  'x-cybozu-api-token', 'x-cybozu-authorization',
  'content-length', 'content-type', 'transfer-encoding', 'connection',
  'upgrade', 'keep-alive', 'te', 'trailer', 'expect', 'proxy-connection',
  'forwarded', 'x-forwarded-for', 'x-forwarded-host', 'x-forwarded-proto',
]);

const headerNamePattern = /^[a-z0-9][a-z0-9-]*$/u;
const visibleAscii = /^[\x21-\x7e][\x20-\x7e]*$/u;

function checkHeaderName(name, code) {
  if (typeof name !== 'string' || !headerNamePattern.test(name) ||
      Buffer.byteLength(name) > exchangeLimits.maxHeaderNameBytes) {
    fail(code);
  }
  return name;
}

function checkHeaderValue(value, code) {
  if (typeof value !== 'string' || !visibleAscii.test(value) ||
      value.endsWith(' ') ||
      Buffer.byteLength(value) > exchangeLimits.maxHeaderValueBytes) {
    fail(code);
  }
  return value;
}

// Allowed non-secret request headers, as ordered `[name, value]` pairs with
// lowercase names. `accept` may be replaced here; everything the resource
// owns is reserved.
export function ownRequestHeaders(headers = []) {
  if (!Array.isArray(headers) ||
      headers.length > exchangeLimits.maxRequestHeaders) {
    fail('InvalidHttpRequestHeaders');
  }
  const names = new Set();
  return Object.freeze(headers.map(pair => {
    if (!Array.isArray(pair) || pair.length !== 2) {
      fail('InvalidHttpRequestHeaders');
    }
    const name = checkHeaderName(pair[0], 'InvalidHttpRequestHeaders');
    if (reservedRequestHeaders.has(name)) fail('ReservedHttpRequestHeader');
    if (names.has(name)) fail('InvalidHttpRequestHeaders');
    names.add(name);
    return Object.freeze([name, checkHeaderValue(pair[1],
      'InvalidHttpRequestHeaders')]);
  }));
}

// RFC 3986 unreserved characters only; the credential resource re-checks the
// whole exact request target before sending.
const encodeComponent = value => encodeURIComponent(value)
  .replace(/[!'()*]/gu, character =>
    `%${character.charCodeAt(0).toString(16).toUpperCase()}`);

// Physical RFC 3986 encoding demand, before allocating encoded strings. Stop
// at the SAME owner's bound; this does not interpret provider query meaning.
function componentBytes(value, remaining) {
  let bytes = 0;
  for (const unit of value) {
    const point = unit.codePointAt(0);
    if (point >= 0xd800 && point <= 0xdfff) throw new URIError('URI malformed');
    bytes += /^[A-Za-z0-9._~-]$/u.test(unit) ? 1
      : point < 128 ? 3 : point < 2048 ? 6 : point < 65536 ? 9 : 12;
    if (bytes > remaining) fail('InvalidHttpRequestQuery');
  }
  return bytes;
}

// The exact request target: the provider's path plus its ordered query
// pairs, encoded here so that no caller text reaches the wire unencoded. A
// path that already carries its own encoded query (a provider-built locator)
// takes no further pairs; the credential resource re-checks the whole target.
export function requestTarget(path, query = [], {maxQueryBytes = exchangeLimits.maxQueryBytes} = {}) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('InvalidHttpRequestTarget');
  }
  // A selected installed Reader may supply its separately funded query
  // constructor bound. It is not the request-body bound or provider DATA.
  if (!Number.isSafeInteger(maxQueryBytes) || maxQueryBytes < 1 || maxQueryBytes > 2147483647 ||
      !Array.isArray(query) || query.length > exchangeLimits.maxQueryPairs) {
    fail('InvalidHttpRequestQuery');
  }
  if (arguments[2] !== undefined && Buffer.byteLength(path) > maxQueryBytes) fail('InvalidHttpRequestTarget');
  if (query.length === 0) return path;
  if (path.includes('?')) fail('InvalidHttpRequestTarget');
  let bytes = query.length - 1;
  const encoded = query.map(pair => {
    if (!Array.isArray(pair) || pair.length !== 2) {
      fail('InvalidHttpRequestQuery');
    }
    const key = pair[0], value = pair[1];
    if (typeof key !== 'string' || !key || typeof value !== 'string') fail('InvalidHttpRequestQuery');
    bytes += 1 + componentBytes(key, maxQueryBytes - bytes - 1);
    bytes += componentBytes(value, maxQueryBytes - bytes);
    if (bytes > maxQueryBytes) fail('InvalidHttpRequestQuery');
    return `${encodeComponent(key)}=${encodeComponent(value)}`;
  }).join('&');
  if (Buffer.byteLength(encoded) > maxQueryBytes) {
    fail('InvalidHttpRequestQuery');
  }
  return `${path}?${encoded}`;
}

// One owned request: method, exact target, owned headers and an optional
// string body (POST/PATCH/PUT only).
export function ownHttpRequest({method, path, query, headers, body}, queryConstruction) {
  checkHttpRequestMethodBody(method, body);
  return Object.freeze({
    method,
    target: requestTarget(path, query, queryConstruction),
    headers: ownRequestHeaders(headers),
    ...(body === undefined ? {} : {body}),
  });
}

const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype);
const viewByteLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength').get;
const viewBacking = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer').get;
const arrayBufferByteLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
const copyViewBytes = Uint8Array.prototype.set;

// An explicitly bounded binary request is a separate transport shape. Keep
// the legacy String/JSON shape unchanged. Copy only the selected Uint8Array
// view, before any await or credential use; never decode/re-encode its bytes.
// These clamps are not a ContentRef issuer, original holding or reservation.
export function ownHttpByteRequest({method, path, query, headers, body,
  bodyBytes, bodyMediaType, maxBodyBytes}) {
  if (body !== undefined || !(bodyBytes instanceof Uint8Array) ||
      !Number.isSafeInteger(maxBodyBytes) || maxBodyBytes < 0) fail('InvalidHttpRequestBody');
  let length;
  try {
    // Intrinsic brands/lengths cannot be replaced by own JS properties. The
    // ArrayBuffer getter also refuses cross-realm SharedArrayBuffer backing.
    arrayBufferByteLength.call(viewBacking.call(bodyBytes));
    length = viewByteLength.call(bodyBytes);
  } catch { fail('InvalidHttpRequestBody'); }
  if (length > maxBodyBytes) fail('InvalidHttpRequestBody');
  checkHeaderValue(bodyMediaType, 'InvalidHttpRequestBody');
  // The existing body-bearing method rules and exact target/header admission
  // apply unchanged. The temporary empty String is shape-only, never sent.
  const {body: _, ...request} = ownHttpRequest({method, path, query, headers, body: ''});
  // Query/header getters run during metadata admission. They can resize or
  // detach an unshared input; never return an incompletely initialized copy.
  if (viewByteLength.call(bodyBytes) !== length) fail('InvalidHttpRequestBody');
  const owned = Buffer.allocUnsafeSlow(length);
  try { copyViewBytes.call(owned, bodyBytes); }
  catch { fail('InvalidHttpRequestBody'); }
  return Object.freeze({...request, bodyBytes: owned, bodyMediaType, maxBodyBytes});
}

// Whether a lowercase header name may be declared or set by a provider.
export function reservedHttpHeader(name) {
  return reservedRequestHeaders.has(name);
}

// The response header names an installation declared it reads. A reserved
// name refuses the declaration here, before any credential use or request.
export function ownResponseHeaderNames(names = []) {
  if (!Array.isArray(names) ||
      names.length > exchangeLimits.maxObservedHeaders ||
      new Set(names).size !== names.length) {
    fail('InvalidHttpResponseHeaderNames');
  }
  return Object.freeze(names.map(name => {
    checkHeaderName(name, 'InvalidHttpResponseHeaderNames');
    if (reservedRequestHeaders.has(name)) fail('InvalidHttpResponseHeaderNames');
    return name;
  }));
}

// Observe the declared names from a received header map (Node's lowercase
// map; repeated headers arrive joined, `set-cookie` is never declarable
// since it is reserved). Absent headers are absent; a value or total beyond
// the caps refuses the whole observation.
export function observeResponseHeaders(received, names) {
  const owned = ownResponseHeaderNames(names);
  const entries = [];
  let total = 0;
  for (const name of owned) {
    const value = received?.[name];
    if (value === undefined) continue;
    if (typeof value !== 'string') fail('HttpHeaderObservationInvalid');
    const bytes = Buffer.byteLength(value);
    total += bytes;
    if (bytes > exchangeLimits.maxHeaderValueBytes ||
        total > exchangeLimits.maxObservedHeaderBytes) {
      fail('HttpHeaderObservationExceeded');
    }
    entries.push(Object.freeze([name, value]));
  }
  return Object.freeze(entries);
}

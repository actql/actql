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

export const exchangeMethods = Object.freeze(['GET', 'POST', 'PATCH']);

// Headers the credential resource owns, that carry credentials, or that
// reshape the connection. A provider never sets them.
const reservedRequestHeaders = new Set([
  'authorization', 'proxy-authorization', 'cookie', 'set-cookie', 'host',
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

// The exact request target: the provider's path plus its ordered query
// pairs, encoded here so that no caller text reaches the wire unencoded. A
// path that already carries its own encoded query (a provider-built locator)
// takes no further pairs; the credential resource re-checks the whole target.
export function requestTarget(path, query = []) {
  if (typeof path !== 'string' || path.length === 0) {
    fail('InvalidHttpRequestTarget');
  }
  if (!Array.isArray(query) || query.length > exchangeLimits.maxQueryPairs) {
    fail('InvalidHttpRequestQuery');
  }
  if (query.length === 0) return path;
  if (path.includes('?')) fail('InvalidHttpRequestTarget');
  const encoded = query.map(pair => {
    if (!Array.isArray(pair) || pair.length !== 2 ||
        typeof pair[0] !== 'string' || pair[0].length === 0 ||
        typeof pair[1] !== 'string') {
      fail('InvalidHttpRequestQuery');
    }
    return `${encodeComponent(pair[0])}=${encodeComponent(pair[1])}`;
  }).join('&');
  if (Buffer.byteLength(encoded) > exchangeLimits.maxQueryBytes) {
    fail('InvalidHttpRequestQuery');
  }
  return `${path}?${encoded}`;
}

// One owned request: method, exact target, owned headers and an optional
// string body (mutations only).
export function ownHttpRequest({method, path, query, headers, body}) {
  if (!exchangeMethods.includes(method)) fail('InvalidHttpRequestMethod');
  if ((body !== undefined && typeof body !== 'string') ||
      (method === 'GET' && body !== undefined)) {
    fail('InvalidHttpRequestBody');
  }
  return Object.freeze({
    method,
    target: requestTarget(path, query),
    headers: ownRequestHeaders(headers),
    ...(body === undefined ? {} : {body}),
  });
}

// The response header names an installation declared it reads.
export function ownResponseHeaderNames(names = []) {
  if (!Array.isArray(names) ||
      names.length > exchangeLimits.maxObservedHeaders ||
      new Set(names).size !== names.length) {
    fail('InvalidHttpResponseHeaderNames');
  }
  return Object.freeze(names.map(name =>
    checkHeaderName(name, 'InvalidHttpResponseHeaderNames')));
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
    if (reservedRequestHeaders.has(name)) fail('InvalidHttpResponseHeaderNames');
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

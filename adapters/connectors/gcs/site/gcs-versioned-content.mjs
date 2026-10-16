import {createHash} from 'node:crypto';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  '../../../host-common/owned-invocation-context.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

const operation = 'gcs:file:read';
const origin = 'https://storage.googleapis.com';
const observedHeaders = Object.freeze(['content-encoding', 'content-range',
  'x-goog-generation', 'x-goog-metageneration']);
const fail = code => { throw Object.assign(new Error(code), {code}); };
const count = value => Number.isSafeInteger(value) && value >= 0;
const token = value => typeof value === 'string' && /^[1-9][0-9]{0,19}$/u.test(value);
const size = value => typeof value === 'string' && /^(0|[1-9][0-9]{0,19})$/u.test(value);
const encode = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);

function physicalRequest(target, phase, metageneration, contentEncoding = 'identity', sizeBytes) {
  return ownHttpRequest({method: 'GET',
    path: `/storage/v1/b/${encode(target.bucket)}/o/${encode(target.objectName)}`,
    query: [['generation', target.generation], ['ifGenerationMatch', target.generation],
      ...(phase === 'media' ? [['alt', 'media'], ['ifMetagenerationMatch', metageneration]] : [])],
    // GCS may otherwise transparently decompress a stored gzip object. The
    // selected original metadata fixes this request's exact representation;
    // the existing HTTP adapter returns raw bytes and must not decode them.
    headers: [['accept-encoding', phase === 'media' ? contentEncoding : 'identity'],
      ...(phase === 'media' && contentEncoding === 'gzip' && sizeBytes > 0n
        ? [['range', `bytes=0-${sizeBytes - 1n}`]] : [])]});
}

// The same immutable operation envelope is observed by the existing keyed
// request owner and submitted to the credential boundary. No second request
// encoder or caller-provided URI can disagree with the actual selected read.
export function gcsMetadataRequestWire(target) {
  return Buffer.from(JSON.stringify(physicalRequest(checkedTarget(target), 'metadata')), 'utf8');
}

function exactText(value, maxBytes, allowEmpty = false) {
  return typeof value === 'string' && (allowEmpty || value.length > 0) &&
    value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value) &&
    Buffer.byteLength(value) <= maxBytes;
}

// Validate the Host-resolved physical locator before the common request owner
// observes a send. Encoding alone would permit an out-of-scope object to
// consume an attempt and leave fictitious transport cleanup responsibility.
function checkedTarget(target) {
  if (!target || !exactText(target.bucket, 222) ||
      !exactText(target.objectName, 1024) || !exactText(target.prefix, 1024, true) ||
      !target.objectName.startsWith(target.prefix) || !token(target.generation)) {
    fail('InvalidGcsContentRead');
  }
  return Object.freeze({...target});
}

function authorization(owned, original) {
  if (!owned.grant || owned.scope.operation !== operation ||
      owned.scope.resourceOrigin !== origin || !count(owned.scope.siteGeneration) ||
      (original && !invocationBindingsMatch(owned.scope, original))) {
    fail('InvalidGcsContentAuthorization');
  }
  return owned;
}

function setup(options) {
  const {moon, limits, initialAuthorization, credential,
    authorizationForRequest, recheckAuthorization, chargeBody, chargeVerification, receiveContent,
    callResource = callHttpsCredentialResource} = options;
  const target = checkedTarget(options.target);
  if ((moon !== undefined && (typeof moon?.gcsContentMetadataJson !== 'function' ||
      typeof moon?.gcsContentMetadataFailureCode !== 'function')) ||
      !limits || !count(limits.maxMetadataBytes) || limits.maxMetadataBytes === 0 ||
      limits.maxMetadataBytes > 2147483391 ||
      !count(limits.maxContentBytes) || !count(limits.maxRequestBytes) ||
      limits.maxRequestBytes === 0 || !count(limits.maxAttempts) ||
      limits.maxAttempts < 2 || !count(limits.maxTimeMs) || limits.maxTimeMs === 0 ||
      limits.maxTimeMs > 2_147_483_647 ||
      [authorizationForRequest, recheckAuthorization, chargeBody, chargeVerification, receiveContent,
        callResource].some(callback => typeof callback !== 'function')) {
    fail('InvalidGcsContentRead');
  }
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationForRequest,
      recheckAuthorization, chargeBody, chargeVerification, receiveContent, callResource}});
  authorization(context.authorization);
  return Object.freeze({...context, target, moon});
}

function responseHeaders(response, expectedEncoding = 'identity', rangeSize) {
  if (!Array.isArray(response.headers)) fail('InvalidGcsContentResponse');
  const result = new Map();
  for (const pair of response.headers) {
    if (!Array.isArray(pair) || pair.length !== 2 ||
        !observedHeaders.includes(pair[0]) || typeof pair[1] !== 'string' ||
        result.has(pair[0])) fail('InvalidGcsContentResponse');
    result.set(pair[0], pair[1]);
  }
  const encoding = result.get('content-encoding');
  const range = result.get('content-range');
  // Only the one complete stored-byte interval selected from original
  // metadata can be a complete ContentRef. No partial/multipart assembly,
  // suffix/unsatisfied range, wildcard extent or server-derived size is used.
  const rangeMatches = response.statusCode === 206
    ? rangeSize !== undefined && range === `bytes 0-${rangeSize - 1n}/${rangeSize}`
    : range === undefined;
  if (!rangeMatches || (expectedEncoding === 'gzip'
    ? encoding !== 'gzip' : encoding !== undefined && encoding !== 'identity')) {
    fail('GcsContentRepresentationUnsupported');
  }
  return result;
}

function metadata(moon, body, target, limits) {
  if (moon === undefined) return legacyMetadata(body, target, limits);
  let projection;
  try {
    projection = checked(moon.gcsContentMetadataJson(body, target.bucket,
      target.objectName, target.generation, BigInt(limits.maxContentBytes), limits.maxMetadataBytes));
  } catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsContentMetadataFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
  // Only parse the Core-issued private projection, never reinterpret the
  // provider bytes or default a missing admission. This view and its String
  // overlap remain part of the original read envelope's managed inventory.
  const value = JSON.parse(projection);
  return Object.freeze({...value, sizeBytes: BigInt(value.sizeBytes)});
}

// Preserve the historical explicitly supplied source-only adapter ABI. The
// ordinary installed provider always supplies its portable Connector module;
// absence here is not a numeric default or a new normal profile. This legacy
// interpretation remains an explicit migration boundary, not Core admission.
function legacyMetadata(body, target, limits) {
  let value;
  try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(body)); }
  catch { fail('InvalidGcsContentMetadata'); }
  if (!value || Array.isArray(value) || typeof value !== 'object' ||
      value.bucket !== target.bucket || value.name !== target.objectName ||
      value.generation !== target.generation || !token(value.metageneration) ||
      !size(value.size) || BigInt(value.size) > BigInt(limits.maxContentBytes) ||
      !exactText(value.contentType, 1024)) fail('GcsContentMetadataMismatch');
  if (value.contentEncoding !== undefined && value.contentEncoding !== 'identity' &&
      value.contentEncoding !== 'gzip') fail('GcsContentRepresentationUnsupported');
  const digest = (text, length) => {
    if (typeof text !== 'string' || text.length !== 4 * Math.ceil(length / 3)) fail('InvalidGcsContentDigest');
    const bytes = Buffer.from(text, 'base64');
    if (bytes.length !== length || bytes.toString('base64') !== text) fail('InvalidGcsContentDigest');
    return text;
  };
  return Object.freeze({bucket: target.bucket, objectName: target.objectName,
    generation: target.generation, metageneration: value.metageneration,
    sizeBytes: BigInt(value.size), mediaType: value.contentType,
    ...(value.contentEncoding === 'gzip' ? {contentEncoding: 'gzip'} : {}),
    crc32c: digest(value.crc32c, 4),
    ...(value.md5Hash === undefined ? {} : {md5: digest(value.md5Hash, 16)})});
}

// Castagnoli's reflected polynomial. The 256-entry transport checksum table
// is constant; scanning received bytes yields between fixed-size chunks.
const crcTable = Uint32Array.from({length: 256}, (_, index) => {
  let crc = index;
  for (let bit = 0; bit < 8; bit++) {
    crc = (crc >>> 1) ^ ((crc & 1) ? 0x82f63b78 : 0);
  }
  return crc >>> 0;
});

async function checkedDigests(body, expected, signal, chargeVerification) {
  if (BigInt(body.length) !== expected.sizeBytes) fail('GcsContentSizeMismatch');
  let crc = 0xffffffff;
  const sha = createHash('sha256');
  const md5 = expected.md5 === undefined ? undefined : createHash('md5');
  for (let offset = 0; offset < body.length; offset += 4096) {
    signal.throwIfAborted();
    const chunk = body.subarray(offset, offset + 4096);
    // The existing owner accounts verification before the transport scans
    // each chunk. Report physical bytes, not invented common logical work.
    await chargeVerification(chunk.length, signal);
    signal.throwIfAborted();
    for (const byte of chunk) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
    sha.update(chunk);
    md5?.update(chunk);
    await yieldTurn(undefined, {signal});
  }
  signal.throwIfAborted();
  const crcBytes = Buffer.alloc(4);
  crcBytes.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  if (crcBytes.toString('base64') !== expected.crc32c ||
      (md5 && md5.digest('base64') !== expected.md5)) fail('GcsContentDigestMismatch');
  return Object.freeze({contentCid: `sha256:${sha.digest('hex')}`,
    crc32c: expected.crc32c});
}

// Site-only transport for a Host-resolved, versioned Resource. The caller
// reserves response/verification capacity and retains every charge ticket in its existing
// acquisition/capture owner, including on failure. This function neither
// issues a ContentRef nor declares Source acquisition complete. receiveContent
// must transfer the verified bytes into that owner before returning; a Program
// cannot supply target, credential, authorization or a reference envelope.
export async function readGcsVersionedContent(options) {
  const context = setup(options);
  const {moon, target, limits, callbacks, scope, credential} = context;
  const signal = AbortSignal.any([AbortSignal.timeout(limits.maxTimeMs),
    ...(options.signal === undefined ? [] : [options.signal])]);
  const observations = [];
  async function request(phase, maxBytes, metageneration, contentEncoding = 'identity', sizeBytes) {
    signal.throwIfAborted();
    const rangeSize = phase === 'media' && contentEncoding === 'gzip' && sizeBytes > 0n
      ? sizeBytes : undefined;
    const selected = physicalRequest(target, phase, metageneration, contentEncoding, sizeBytes);
    const auth = phase === 'metadata' ? context.authorization
      : authorization(ownInvocationAuthorization(
        await callbacks.authorizationForRequest(Object.freeze({phase, target,
          requestWire: Buffer.from(JSON.stringify(selected), 'utf8')}), signal)), scope);
    signal.throwIfAborted();
    const response = await invokeScopedCredentialOperation({
      authorization: auth, credential, callResource: callbacks.callResource,
      operation, method: selected.method, path: selected.target,
      headers: selected.headers, responseHeaders: observedHeaders,
      maxRequestBytes: limits.maxRequestBytes,
      maxResponseBytes: Math.max(1, maxBytes), signal,
    });
    if (!Buffer.isBuffer(response.body)) fail('InvalidGcsContentResponse');
    // Account original wire bytes even for a rejected or malformed reply.
    const charge = await callbacks.chargeBody(response.body,
      Object.freeze({phase, useCid: response.useCid}));
    signal.throwIfAborted();
    if (charge === undefined || charge === null) fail('GcsContentChargeMissing');
    if (response.body.length > maxBytes) fail('GcsContentResponseBytesExceeded');
    if (!response.accepted || (response.statusCode !== 200 &&
        !(response.statusCode === 206 && rangeSize !== undefined))) fail('GcsContentResourceRejected');
    const headers = responseHeaders(response, phase === 'media' ? contentEncoding : 'identity', rangeSize);
    if (headers.has('x-goog-generation') &&
        headers.get('x-goog-generation') !== target.generation) {
      fail('GcsContentMetadataMismatch');
    }
    observations.push(Object.freeze({phase, useCid: response.useCid,
      receivedBytes: response.body.length}));
    return {body: response.body, headers, charge};
  }
  const metaResponse = await request('metadata', limits.maxMetadataBytes);
  const meta = metadata(moon, metaResponse.body, target, limits);
  if (metaResponse.headers.has('x-goog-metageneration') &&
      metaResponse.headers.get('x-goog-metageneration') !== meta.metageneration) {
    fail('GcsContentMetadataMismatch');
  }
  const media = await request('media', limits.maxContentBytes, meta.metageneration,
    meta.contentEncoding, meta.sizeBytes);
  if (media.headers.has('x-goog-metageneration') &&
      media.headers.get('x-goog-metageneration') !== meta.metageneration) {
    fail('GcsContentMetadataMismatch');
  }
  const digests = await checkedDigests(media.body, meta, signal,
    callbacks.chargeVerification);
  authorization(ownInvocationAuthorization(
    await callbacks.recheckAuthorization(Object.freeze({target, metadata: meta}), signal)), scope);
  signal.throwIfAborted();
  const receipt = await callbacks.receiveContent(media.body,
    Object.freeze({metadata: meta, digests, metadataCharge: metaResponse.charge,
      contentCharge: media.charge, observations: Object.freeze(observations)}), signal);
  // A cancelled or failed handoff remains the caller's cleanup responsibility.
  signal.throwIfAborted();
  // Bytes may already have reached the same capture owner. A missing receipt
  // cannot complete the read or become a keyed ContentRef row; preserve its
  // original tickets and custody rather than retrying or discarding content.
  if (receipt === undefined || receipt === null) fail('GcsContentCaptureReceiptMissing');
  return Object.freeze({receipt, metadata: meta, digests,
    observations: Object.freeze(observations)});
}

import {createHash} from 'node:crypto';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  '../../../host-common/owned-invocation-context.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';

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

function physicalRequest(target, phase, metageneration) {
  return ownHttpRequest({method: 'GET',
    path: `/storage/v1/b/${encode(target.bucket)}/o/${encode(target.objectName)}`,
    query: [['generation', target.generation], ['ifGenerationMatch', target.generation],
      ...(phase === 'media' ? [['alt', 'media'], ['ifMetagenerationMatch', metageneration]] : [])],
    headers: [['accept-encoding', 'identity']]});
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
  const {limits, initialAuthorization, credential,
    authorizationForRequest, recheckAuthorization, chargeBody, chargeVerification, receiveContent,
    callResource = callHttpsCredentialResource} = options;
  const target = checkedTarget(options.target);
  if (!limits || !count(limits.maxMetadataBytes) || limits.maxMetadataBytes === 0 ||
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
  return Object.freeze({...context, target});
}

function responseHeaders(response) {
  if (!Array.isArray(response.headers)) fail('InvalidGcsContentResponse');
  const result = new Map();
  for (const pair of response.headers) {
    if (!Array.isArray(pair) || pair.length !== 2 ||
        !observedHeaders.includes(pair[0]) || typeof pair[1] !== 'string' ||
        result.has(pair[0])) fail('InvalidGcsContentResponse');
    result.set(pair[0], pair[1]);
  }
  if (result.has('content-range') || (result.has('content-encoding') &&
      result.get('content-encoding') !== 'identity')) {
    fail('GcsContentRepresentationUnsupported');
  }
  return result;
}

function digestText(value, bytes) {
  if (typeof value !== 'string' || value.length !== 4 * Math.ceil(bytes / 3)) {
    fail('InvalidGcsContentDigest');
  }
  const decoded = Buffer.from(value, 'base64');
  if (decoded.length !== bytes || decoded.toString('base64') !== value) {
    fail('InvalidGcsContentDigest');
  }
  return value;
}

function metadata(body, target, limits) {
  let value;
  try {
    value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(body));
  } catch { fail('InvalidGcsContentMetadata'); }
  if (!value || Array.isArray(value) || typeof value !== 'object' ||
      value.bucket !== target.bucket || value.name !== target.objectName ||
      value.generation !== target.generation || !token(value.metageneration) ||
      !size(value.size) || BigInt(value.size) > BigInt(limits.maxContentBytes) ||
      !exactText(value.contentType, 1024)) fail('GcsContentMetadataMismatch');
  if (value.contentEncoding !== undefined && value.contentEncoding !== 'identity') {
    fail('GcsContentRepresentationUnsupported');
  }
  return Object.freeze({bucket: target.bucket, objectName: target.objectName,
    generation: target.generation, metageneration: value.metageneration,
    sizeBytes: BigInt(value.size), mediaType: value.contentType,
    crc32c: digestText(value.crc32c, 4),
    ...(value.md5Hash === undefined ? {} : {md5: digestText(value.md5Hash, 16)})});
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
  const {target, limits, callbacks, scope, credential} = context;
  const signal = AbortSignal.any([AbortSignal.timeout(limits.maxTimeMs),
    ...(options.signal === undefined ? [] : [options.signal])]);
  const observations = [];
  async function request(phase, maxBytes, metageneration) {
    signal.throwIfAborted();
    const selected = physicalRequest(target, phase, metageneration);
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
    if (!response.accepted || response.statusCode !== 200) fail('GcsContentResourceRejected');
    const headers = responseHeaders(response);
    if (headers.has('x-goog-generation') &&
        headers.get('x-goog-generation') !== target.generation) {
      fail('GcsContentMetadataMismatch');
    }
    observations.push(Object.freeze({phase, useCid: response.useCid,
      receivedBytes: response.body.length}));
    return {body: response.body, headers, charge};
  }
  const metaResponse = await request('metadata', limits.maxMetadataBytes);
  const meta = metadata(metaResponse.body, target, limits);
  if (metaResponse.headers.has('x-goog-metageneration') &&
      metaResponse.headers.get('x-goog-metageneration') !== meta.metageneration) {
    fail('GcsContentMetadataMismatch');
  }
  const media = await request('media', limits.maxContentBytes, meta.metageneration);
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
  return Object.freeze({receipt, metadata: meta, digests,
    observations: Object.freeze(observations)});
}

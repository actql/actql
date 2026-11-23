import {createHash} from 'node:crypto';
import {setImmediate as yieldTurn} from 'node:timers/promises';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  '../../../host-common/owned-invocation-context.mjs';
import {ownHttpRequest} from '../../../host-common/http-exchange.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';

type Phase = 'metadata' | 'media';
type Encoding = 'identity' | 'gzip';
type Target = Readonly<{bucket: string; objectName: string; prefix: string; generation: string}>;
type ContentLimits = Readonly<{maxMetadataBytes: number; maxContentBytes: number;
  maxRequestBytes: number; maxAttempts: number; maxTimeMs: number}>;
type MetadataProjection = Readonly<{
  bucket: string; objectName: string; generation: string; metageneration: string;
  sizeBytes: string; mediaType: string; contentEncoding?: Encoding; crc32c: string; md5?: string;
}>;
type Metadata = Omit<MetadataProjection, 'sizeBytes'> & Readonly<{sizeBytes: bigint}>;
type BodyMetadata = Readonly<{
  bucket?: unknown; name?: unknown; generation?: unknown; metageneration?: unknown;
  size?: unknown; contentType?: unknown; contentEncoding?: unknown; crc32c?: unknown; md5Hash?: unknown;
}>;
type Runtime = Readonly<{
  gcsContentMetadataJson(body: Buffer, bucket: string, name: string, generation: string,
    maxContentBytes: bigint, maxMetadataBytes: number): unknown;
  gcsContentMetadataFailureCode(issue: unknown): string;
}>;
type Response = Awaited<ReturnType<typeof callHttpsCredentialResource>>;
type Authorization = ReturnType<typeof ownInvocationAuthorization>;
type Scope = Readonly<{operation?: string; resourceOrigin?: string; siteGeneration?: number}>;
type VerifiedDigests = Readonly<{contentCid: string; crc32c: string}>;
type Observation = Readonly<{phase: Phase; useCid: string; receivedBytes: number}>;
type ContentOptions = Readonly<{
  moon?: Runtime; target: Target; limits: ContentLimits; initialAuthorization: unknown;
  credential: unknown; signal?: AbortSignal; callResource?: (...args: never[]) => unknown;
  authorizationForRequest(request: Readonly<{phase: Phase; target: Target; requestWire: Buffer}>,
    signal: AbortSignal): unknown;
  recheckAuthorization(original: Readonly<{target: Target; metadata: Metadata}>, signal: AbortSignal): unknown;
  chargeBody(body: Buffer, original: Readonly<{phase: Phase; useCid: string}>): unknown;
  chargeVerification(byteCount: number, signal: AbortSignal): unknown;
  receiveContent(body: Buffer, original: Readonly<{metadata: Metadata; digests: VerifiedDigests;
    metadataCharge: unknown; contentCharge: unknown; observations: readonly Observation[]}>,
    signal: AbortSignal): unknown;
}>;
type ContentCallbacks = Pick<ContentOptions, 'authorizationForRequest' | 'recheckAuthorization' |
  'chargeBody' | 'chargeVerification' | 'receiveContent'> & Readonly<{callResource: unknown}>;

const operation = 'gcs:file:read';
const origin = 'https://storage.googleapis.com';
const observedHeaders = Object.freeze(['content-encoding', 'content-range',
  'x-goog-generation', 'x-goog-metageneration']);
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const count = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
const token = (value: unknown): value is string => typeof value === 'string' && /^[1-9][0-9]{0,19}$/u.test(value);
const size = (value: unknown): value is string => typeof value === 'string' && /^(0|[1-9][0-9]{0,19})$/u.test(value);
const encode = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  char => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);

function physicalRequest(target: Target, phase: Phase, metageneration?: string,
  contentEncoding: Encoding = 'identity', sizeBytes?: bigint) {
  return ownHttpRequest({method: 'GET',
    path: `/storage/v1/b/${encode(target.bucket)}/o/${encode(target.objectName)}`,
    query: [['generation', target.generation], ['ifGenerationMatch', target.generation],
      ...(phase === 'media' ? [['alt', 'media'], ['ifMetagenerationMatch', metageneration]] : [])],
    // GCS may otherwise transparently decompress a stored gzip object. The
    // selected original metadata fixes this request's exact representation;
    // the existing HTTP adapter returns raw bytes and must not decode them.
    headers: [['accept-encoding', phase === 'media' ? contentEncoding : 'identity'],
      ...(phase === 'media' && contentEncoding === 'gzip' && sizeBytes! > 0n
        ? [['range', `bytes=0-${sizeBytes! - 1n}`]] : [])]});
}

// The same immutable operation envelope is observed by the existing keyed
// request owner and submitted to the credential boundary. No second request
// encoder or caller-provided URI can disagree with the actual selected read.
export function gcsMetadataRequestWire(target: Target) {
  return Buffer.from(JSON.stringify(physicalRequest(checkedTarget(target), 'metadata')), 'utf8');
}

function exactText(value: unknown, maxBytes: number, allowEmpty = false): value is string {
  return typeof value === 'string' && (allowEmpty || value.length > 0) &&
    value.isWellFormed() && !/[\u0000-\u001f\u007f]/u.test(value) &&
    Buffer.byteLength(value) <= maxBytes;
}

// Validate the Host-resolved physical locator before the common request owner
// observes a send. Encoding alone would permit an out-of-scope object to
// consume an attempt and leave fictitious transport cleanup responsibility.
function checkedTarget(target: Target) {
  if (!target || !exactText(target.bucket, 222) ||
      // JSON object names are opaque Unicode, not HTTP header values or XML
      // names. The physical encoder escapes controls; CR/LF remain forbidden.
      typeof target.objectName !== 'string' || target.objectName.length === 0 ||
      !target.objectName.isWellFormed() || /[\r\n]/u.test(target.objectName) ||
      Buffer.byteLength(target.objectName) > 1024 || typeof target.prefix !== 'string' ||
      !target.prefix.isWellFormed() || Buffer.byteLength(target.prefix) > 1024 ||
      !target.objectName.startsWith(target.prefix) || !token(target.generation)) {
    fail('InvalidGcsContentRead');
  }
  return Object.freeze({...target});
}

function authorization(owned: Authorization, original?: unknown) {
  if (!owned.grant || (owned.scope as Scope).operation !== operation ||
      (owned.scope as Scope).resourceOrigin !== origin || !count((owned.scope as Scope).siteGeneration) ||
      (original && !invocationBindingsMatch(owned.scope, original))) {
    fail('InvalidGcsContentAuthorization');
  }
  return owned;
}

function setup(options: ContentOptions) {
  const {moon, limits, initialAuthorization, credential,
    authorizationForRequest, recheckAuthorization, chargeBody, chargeVerification, receiveContent,
    callResource = callHttpsCredentialResource} = options;
  const target = checkedTarget(options.target);
  if ((moon !== undefined && (typeof moon?.gcsContentMetadataJson !== 'function' ||
      typeof moon?.gcsContentMetadataFailureCode !== 'function')) ||
      !limits || !count(limits.maxMetadataBytes) || limits.maxMetadataBytes === 0 ||
      (moon !== undefined && limits.maxMetadataBytes > 2147483391) ||
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
  return Object.freeze({...context, target, moon}) as typeof context & Readonly<{
    target: Target; moon?: Runtime; limits: ContentLimits; callbacks: ContentCallbacks;
  }>;
}

function responseHeaders(response: Response, expectedEncoding: Encoding = 'identity', rangeSize?: bigint) {
  if (!Array.isArray(response.headers)) fail('InvalidGcsContentResponse');
  const result = new Map<string, string>();
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

function metadata(moon: Runtime | undefined, body: Buffer, target: Target, limits: ContentLimits): Metadata {
  if (moon === undefined) return legacyMetadata(body, target, limits);
  let projection: string;
  try {
    projection = checked(moon.gcsContentMetadataJson(body, target.bucket,
      target.objectName, target.generation, BigInt(limits.maxContentBytes), limits.maxMetadataBytes)) as string;
  } catch (failure) {
    if ((failure as {code?: unknown} | null)?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsContentMetadataFailureCode((failure as Error).cause);
    throw Object.assign(new Error(code, {cause: (failure as Error).cause}), {code});
  }
  // Only parse the Core-issued private projection, never reinterpret the
  // provider bytes or default a missing admission. This view and its String
  // overlap remain part of the original read envelope's managed inventory.
  const value = JSON.parse(projection) as MetadataProjection;
  return Object.freeze({...value, sizeBytes: BigInt(value.sizeBytes)});
}

// Preserve the historical explicitly supplied source-only adapter ABI. The
// ordinary installed provider always supplies its portable Connector module;
// absence here is not a numeric default or a new normal profile. This legacy
// interpretation remains an explicit migration boundary, not Core admission.
function legacyMetadata(body: Buffer, target: Target, limits: ContentLimits): Metadata {
  let value: BodyMetadata;
  try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(body)) as BodyMetadata; }
  catch { fail('InvalidGcsContentMetadata'); }
  if (!value || Array.isArray(value) || typeof value !== 'object' ||
      value.bucket !== target.bucket || value.name !== target.objectName ||
      value.generation !== target.generation || !token(value.metageneration) ||
      !size(value.size) || BigInt(value.size) > BigInt(limits.maxContentBytes) ||
      !exactText(value.contentType, 1024)) fail('GcsContentMetadataMismatch');
  if (value.contentEncoding !== undefined && value.contentEncoding !== 'identity' &&
      value.contentEncoding !== 'gzip') fail('GcsContentRepresentationUnsupported');
  return Object.freeze({bucket: target.bucket, objectName: target.objectName,
    generation: target.generation, metageneration: value.metageneration,
    sizeBytes: BigInt(value.size), mediaType: value.contentType,
    ...(value.contentEncoding === 'gzip' ? {contentEncoding: 'gzip' as const} : {}),
    crc32c: legacyDigest(value.crc32c, 4),
    ...(value.md5Hash === undefined ? {} : {md5: legacyDigest(value.md5Hash, 16)})});
}

function legacyDigest(value: unknown, bytes: number) {
  if (typeof value !== 'string' || value.length !== 4 * Math.ceil(bytes / 3)) {
    fail('InvalidGcsContentDigest');
  }
  const decoded = Buffer.from(value, 'base64');
  if (decoded.length !== bytes || decoded.toString('base64') !== value) {
    fail('InvalidGcsContentDigest');
  }
  return value;
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

async function checkedDigests(body: Buffer, expected: Metadata, signal: AbortSignal,
  chargeVerification: ContentOptions['chargeVerification']) {
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
export async function readGcsVersionedContent(options: ContentOptions) {
  const context = setup(options);
  const {moon, target, limits, callbacks, scope, credential} = context;
  const signal = AbortSignal.any([AbortSignal.timeout(limits.maxTimeMs),
    ...(options.signal === undefined ? [] : [options.signal])]);
  const observations: Observation[] = [];
  async function request(phase: Phase, maxBytes: number, metageneration?: string,
    contentEncoding: Encoding = 'identity', sizeBytes?: bigint) {
    signal.throwIfAborted();
    const rangeSize = phase === 'media' && contentEncoding === 'gzip' && sizeBytes! > 0n
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
    }) as Response;
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

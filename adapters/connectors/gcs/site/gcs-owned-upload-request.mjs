// Physical projections borrow the same sealed provider request. They neither
// acquire Content nor issue a Ref, permission, claim, receipt or retry policy.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimePair} from '../../../host-common/compiler-binding.generated.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';

const originals = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = value => Number.isInteger(value) && value > 0 && value <= 2147483647;
const viewLength = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'byteLength').get;
const viewBacking = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'buffer').get;
const bufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;

export function gcsUploadResult(moon, result) {
  try { return checked(result); }
  catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsUploadFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
}

function bytes(value) {
  try {
    if (!(value instanceof Uint8Array) || viewLength.call(value) > 2147483647) {
      fail('GcsInvalidUploadAbiBytes');
    }
    // A concurrent SharedArrayBuffer writer cannot change content between the
    // original digest/checksum and the sealed body copy.
    bufferLength.call(viewBacking.call(value));
  } catch { fail('GcsInvalidUploadAbiBytes'); }
  return value;
}

export function admitGcsUploadObservation(moon, binding, {name, statusCode, body}) {
  if (typeof name !== 'string' || !Number.isInteger(statusCode) ||
      statusCode < 100 || statusCode > 599) fail('GcsInvalidUploadAbiObservation');
  return gcsUploadResult(moon, moon.gcsUploadObservation(binding, name, statusCode, bytes(body)));
}

// The existing capture first retains the original physical response/charge.
// This is DATA admission only: accepted/useCid are required port observations,
// never proof of an Account decision, original dispatch or cleanup ACK.
export function admitGcsUploadTargetObservation(moon, binding, name, response) {
  if (typeof moon?.gcsUploadTargetObservation !== 'function') {
    fail('GcsUploadTargetObservationUnavailable');
  }
  const observation = response?.observation;
  if (typeof name !== 'string' || observation?.accepted !== true ||
      !/^sha256:[0-9a-f]{64}$/u.test(observation.useCid ?? '') ||
      !Number.isInteger(observation.statusCode) || observation.statusCode < 100 ||
      observation.statusCode > 599 || !Array.isArray(response?.headers)) {
    fail('GcsInvalidUploadTargetReadObservation');
  }
  if (response.headers.length > 3) fail('GcsUploadCapacityExceeded');
  if (response.headers.some(pair =>
        !Array.isArray(pair) || pair.length !== 2 ||
        typeof pair[0] !== 'string' || typeof pair[1] !== 'string')) {
    fail('GcsInvalidUploadTargetReadObservation');
  }
  // At most three pinned callback tuples; no provider payload is stringified,
  // decoded or normalized by Node. The original bytes/headers stay retained.
  return gcsUploadResult(moon, moon.gcsUploadTargetObservation(binding, name,
    observation.statusCode, bytes(observation.body),
    response.headers.map(([key, value]) => runtimePair(key, value))));
}

// The existing installed capture/Effect owns funding and retains this original
// response before parsing it. This read cannot turn a refusal into absence or
// issue an upload grant, and never retries a missing response.
export async function readGcsUploadTarget({moon, binding, name, authorization,
  credential, callResource, maxRequestBytes, signal}) {
  if (typeof name !== 'string' || !integer(maxRequestBytes)) {
    fail('GcsInvalidUploadTargetRead');
  }
  const path = gcsUploadResult(moon, moon.gcsUploadMetadataPath(binding, name));
  const maxResponseBytes = moon.gcsUploadMetadataMaxBytes(binding);
  if (!integer(maxResponseBytes)) fail('GcsInvalidUploadTargetRead');
  if (authorization?.scope?.resourceOrigin !== 'https://storage.googleapis.com' ||
      authorization?.scope?.operation !== 'gcs:file:read') {
    fail('ForeignGcsUploadTargetReadAuthorization');
  }
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({authorization, credential,
    callResource, operation: 'gcs:file:read', method: 'GET', path,
    headers: [['accept', 'application/json'], ['accept-encoding', 'identity']],
    responseHeaders: ['content-encoding', 'x-goog-generation', 'x-goog-metageneration'],
    maxRequestBytes, maxResponseBytes, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    accepted: response.accepted, statusCode: response.statusCode, body: response.body}),
    headers: response.headers});
}

export function prepareOwnedGcsMultipartUpload({moon, binding, before, contentBytes,
  contentRefCid, contentCid, mediaType, overwrite, marker, maxProjectionBytes}) {
  if (![contentRefCid, contentCid, mediaType, marker].every(value => typeof value === 'string') ||
      !integer(maxProjectionBytes) || (overwrite !== undefined && typeof overwrite !== 'boolean')) {
    fail('GcsInvalidUploadAbiInput');
  }
  const handle = gcsUploadResult(moon, moon.gcsUploadPrepareMultipart(binding, before,
    bytes(contentBytes), contentRefCid, contentCid, mediaType,
    overwrite === undefined ? 'absent' : overwrite ? 'true' : 'false', marker));
  const request = Object.freeze(JSON.parse(gcsUploadResult(moon,
    moon.gcsUploadProjection(binding, handle, maxProjectionBytes))));
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

function original(request, binding) {
  const owner = originals.get(request);
  if (owner === undefined) fail('ForeignGcsUploadRequest');
  if (binding !== undefined && binding !== owner.binding) fail('GcsForeignUploadBinding');
  return owner;
}

export function ownedGcsUploadBody(request, binding) {
  const owner = original(request, binding);
  return gcsUploadResult(owner.moon, owner.moon.gcsUploadBody(owner.binding, owner.handle));
}

export function recheckOwnedGcsUpload(request, current, binding) {
  const owner = original(request, binding);
  return gcsUploadResult(owner.moon, owner.moon.gcsUploadRecheck(owner.binding, owner.handle, current));
}

// Data consistency, not an applied outcome. The existing Effect/reconciliation
// owner must separately authenticate its retained original request and claim.
export function ownedGcsUploadResponseMatches(request, metadata, binding) {
  const owner = original(request, binding);
  return owner.moon.gcsUploadResponseMatches(owner.binding, owner.handle, metadata);
}

// Only the original installed Effect's durable claim invokes this operation.
// A lost response throws the same failure; there is no catch/retry or re-read.
export async function sendOwnedGcsUpload({request, authorization, credential,
  callResource, maxRequestBytes, maxResponseBytes, signal}) {
  original(request);
  if (!integer(maxRequestBytes) || !integer(maxResponseBytes) ||
      request.body_byte_length > maxRequestBytes) fail('GcsInvalidUploadTransportLimits');
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      authorization?.scope?.operation !== request.operation) fail('ForeignGcsUploadAuthorization');
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({authorization, credential, callResource,
    operation: request.operation, method: request.method, path: request.path,
    bodyBytes: ownedGcsUploadBody(request), bodyMediaType: request.body_media_type,
    headers: [['accept', 'application/json']],
    responseHeaders: ['x-goog-generation', 'x-goog-metageneration'],
    maxRequestBytes, maxResponseBytes, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    accepted: response.accepted, statusCode: response.statusCode, body: response.body}),
    headers: response.headers});
}

// The existing Effect Ledger authenticates the exact original direct response
// before this projection, including saved-response recovery. Observation DATA
// alone is not that proof. A later metadata GET uses responseMatches instead;
// its failure cannot be relabelled as a failed dispatch.
export function projectOwnedGcsUploadResponse(request, observation, maxProjectionBytes) {
  const owner = original(request);
  if (!integer(maxProjectionBytes)) fail('GcsInvalidUploadTransportLimits');
  const status = observation?.statusCode;
  if (!Number.isInteger(status) || status < 100 || status > 599) {
    fail('GcsInvalidUploadResponse');
  }
  return Object.freeze(JSON.parse(gcsUploadResult(owner.moon,
    owner.moon.gcsUploadResponseProjection(owner.binding, owner.handle,
      status, bytes(observation.body), maxProjectionBytes))));
}

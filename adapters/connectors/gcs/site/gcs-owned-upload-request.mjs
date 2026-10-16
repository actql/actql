// Physical projections borrow the same sealed provider request. They neither
// acquire Content nor issue a Ref, permission, claim, receipt or retry policy.
import {checked} from '../../../host-common/runtime-result.mjs';
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

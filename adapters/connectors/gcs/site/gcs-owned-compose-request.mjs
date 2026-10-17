// Physical adapter over the same portable request. No read approval, resource
// loan, dispatch claim, response ACK or retry permission is issued here.
import {checked} from '../../../host-common/runtime-result.mjs';
import {invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';

const originals = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const viewBacking = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'buffer').get;
const viewLength = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'byteLength').get;
const bufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
function bytes(value) {
  try {
    if (!(value instanceof Uint8Array) || viewLength.call(value) > 2147483647) {
      fail('GcsInvalidComposeResponse');
    }
    // Reject concurrent SharedArrayBuffer writers; the same synchronous parse
    // must see the retained original response, not a moving byte projection.
    bufferLength.call(viewBacking.call(value));
  } catch { fail('GcsInvalidComposeResponse'); }
  return value;
}
function abi(moon, name) {
  if (typeof moon?.[name] !== 'function') fail('GcsComposeRuntimeUnavailable');
}
function result(moon, operation) {
  if (typeof moon?.gcsComposeFailureCode !== 'function') fail('GcsComposeRuntimeUnavailable');
  try { return checked(operation()); }
  catch (cause) {
    if (cause?.code !== 'MoonBitHostFailure') throw cause;
    const code = moon.gcsComposeFailureCode(cause.cause);
    throw Object.assign(new Error(code, {cause: cause.cause}), {code});
  }
}
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
};

export function prepareGcsComposeBinding(moon, target, {maxSources, maxResultBytes}) {
  if (!integer(maxSources) || maxSources > 32 || typeof maxResultBytes !== 'bigint' ||
      maxResultBytes < 0n || maxResultBytes > 5497558138880n) fail('GcsInvalidComposeLimits');
  if (typeof moon?.gcsComposeBinding !== 'function') fail('GcsComposeRuntimeUnavailable');
  return result(moon, () => moon.gcsComposeBinding(target, maxSources, maxResultBytes));
}

export function prepareOwnedGcsComposition({moon, binding, before, sources, marker,
  maxProjectionBytes}) {
  if (!Array.isArray(sources) || sources.length < 1 || sources.length > 32 ||
      typeof marker !== 'string' || !integer(maxProjectionBytes)) fail('GcsInvalidComposeInput');
  if (typeof moon?.gcsComposePrepare !== 'function' ||
      typeof moon.gcsComposeProjection !== 'function') fail('GcsComposeRuntimeUnavailable');
  const handle = result(moon, () => moon.gcsComposePrepare(binding, before, [...sources], marker));
  const projection = result(moon, () => moon.gcsComposeProjection(binding, handle, maxProjectionBytes));
  const request = freeze(JSON.parse(projection));
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

function original(request, binding) {
  const owner = originals.get(request);
  if (owner === undefined || binding !== undefined && binding !== owner.binding) {
    fail('ForeignGcsComposeRequest');
  }
  return owner;
}

export function ownedGcsCompositionBody(request, binding) {
  const owner = original(request, binding);
  abi(owner.moon, 'gcsComposeBody');
  return result(owner.moon, () => owner.moon.gcsComposeBody(owner.binding, owner.handle));
}

export function recheckOwnedGcsComposition(request, current, sources, binding) {
  const owner = original(request, binding);
  abi(owner.moon, 'gcsComposeRecheck');
  if (!Array.isArray(sources) || sources.length < 1 || sources.length > 32) {
    fail('GcsInvalidComposeInput');
  }
  return result(owner.moon, () => owner.moon.gcsComposeRecheck(owner.binding, owner.handle,
    current, [...sources]));
}

export function ownedGcsCompositionResponseMatches(request, observed, binding) {
  const owner = original(request, binding);
  abi(owner.moon, 'gcsComposeResponseMatches');
  return owner.moon.gcsComposeResponseMatches(owner.binding, owner.handle, observed);
}

// Exactly one invocation under the existing Effect's original durable claim.
// Reject/throw (including original cleanup facets) propagates without resend.
export async function sendOwnedGcsComposition({request, authorization, credential,
  callResource, maxRequestBytes, maxResponseBytes, signal}) {
  original(request);
  if (!integer(maxRequestBytes) || !integer(maxResponseBytes) ||
      request.body_byte_length > maxRequestBytes) fail('GcsInvalidComposeTransportLimits');
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      authorization?.scope?.operation !== request.operation) fail('ForeignGcsComposeAuthorization');
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({authorization, credential, callResource,
    operation: request.operation, method: request.method, path: request.path,
    body: ownedGcsCompositionBody(request), headers: [['accept', 'application/json']],
    responseHeaders: ['x-goog-generation', 'x-goog-metageneration'],
    maxRequestBytes, maxResponseBytes, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    accepted: response.accepted, statusCode: response.statusCode, body: response.body}),
    headers: response.headers});
}

// A later GET cannot classify an original send failure. This projection is for
// the separately authenticated same dispatch/retained direct response only.
export function projectOwnedGcsCompositionResponse(request, observation, maxProjectionBytes) {
  const owner = original(request);
  abi(owner.moon, 'gcsComposeResponseProjection');
  const status = observation?.statusCode;
  if (!integer(maxProjectionBytes) || !Number.isInteger(status) || status < 100 || status > 599 ||
      !(observation?.body instanceof Uint8Array)) fail('GcsInvalidComposeResponse');
  return freeze(JSON.parse(result(owner.moon, () => owner.moon.gcsComposeResponseProjection(
    owner.binding, owner.handle, status, bytes(observation.body), maxProjectionBytes))));
}

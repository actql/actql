// Physical projections borrow their original provider handles. DTO equality,
// a copied marker, or a successful projection is not a permission or receipt.
import {checked} from '../../../host-common/runtime-result.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';

const originals = new WeakMap();
const wire = value => canonicalJson(value, {dataKeys: true});
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = (value, minimum = 1) => Number.isSafeInteger(value) &&
  value >= minimum && value <= 2147483647;
const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};

export function gcsOwnedResult(moon, result) {
  try { return checked(result); }
  catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsObjectFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
}

function metadataArguments(limits) {
  if (!limits || !integer(limits.maxBytes) || !integer(limits.maxNodes) ||
      !integer(limits.maxDepth) || !integer(limits.maxEntries, 0)) {
    fail('InvalidGcsObjectAbiLimits');
  }
  return [limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxEntries];
}

export function prepareGcsObjectBinding(moon, {kind, bucket, prefix, catalogCid,
  installationCid, contractCid, permissions, metadata, maxPathBytes,
  maxBodyBytes, maxIdentityBytes}) {
  if ([kind, bucket, prefix, catalogCid, installationCid, contractCid]
    .some(value => typeof value !== 'string') || !Array.isArray(permissions) ||
      permissions.some(value => typeof value !== 'string')) {
    fail('InvalidGcsObjectAbiBinding');
  }
  if (![maxPathBytes, maxBodyBytes, maxIdentityBytes].every(value => integer(value))) {
    fail('InvalidGcsObjectAbiLimits');
  }
  return gcsOwnedResult(moon, moon.gcsObjectMutationBinding(kind, bucket, prefix,
    catalogCid, installationCid, contractCid, permissions, ...metadataArguments(metadata),
    maxPathBytes, maxBodyBytes, maxIdentityBytes));
}

export function admitGcsObjectMetadata(moon, {bytes, bucket, prefix, name, limits}) {
  return gcsOwnedResult(moon, moon.gcsObjectMetadata(bytes, bucket, prefix, name,
    ...metadataArguments(limits)));
}

export function projectGcsObjectMetadata(moon, original, limits) {
  return freeze(JSON.parse(gcsOwnedResult(moon, moon.gcsObjectMetadataJson(original,
    ...metadataArguments(limits)))));
}

export function projectOwnedGcsObjectRequest(moon, binding, handle, maxProjectionBytes) {
  if (!integer(maxProjectionBytes)) fail('InvalidGcsObjectAbiLimits');
  const projection = JSON.parse(gcsOwnedResult(moon,
    moon.gcsObjectRequestProjection(binding, handle, maxProjectionBytes)));
  const body = gcsOwnedResult(moon, moon.gcsObjectRequestBody(binding, handle));
  const value = JSON.parse(gcsOwnedResult(moon, moon.gcsObjectRequestChanges(binding, handle)));
  const request = freeze({...projection, body, value});
  originals.set(request, Object.freeze({moon, binding, handle}));
  return request;
}

export function prepareOwnedGcsMetadataPatch({moon, binding, original, value,
  marker, maxProjectionBytes}) {
  const handle = gcsOwnedResult(moon, moon.gcsObjectPreparePatch(binding, original,
    Buffer.from(wire(value), 'utf8'), marker));
  return projectOwnedGcsObjectRequest(moon, binding, handle, maxProjectionBytes);
}

export function prepareOwnedGcsObjectDelete({moon, binding, original, maxProjectionBytes}) {
  const handle = gcsOwnedResult(moon, moon.gcsObjectPrepareDelete(binding, original));
  return projectOwnedGcsObjectRequest(moon, binding, handle, maxProjectionBytes);
}

function originalRequest(request, binding) {
  const original = originals.get(request);
  if (original === undefined) fail('ForeignGcsObjectRequest');
  const {moon, handle} = original;
  // This same-object borrow is checked by the portable provider Owner. A JS
  // copy, equal body/CID or changed permission binding cannot substitute it.
  gcsOwnedResult(moon, moon.gcsObjectRequestBody(binding ?? original.binding, handle));
  return original;
}

export function ownedGcsObjectRequestCid(request, binding) {
  originalRequest(request, binding);
  return request.request_cid;
}

export function recheckOwnedGcsObjectRequest(request, current, binding) {
  const original = originalRequest(request, binding);
  return gcsOwnedResult(original.moon, original.moon.gcsObjectRecheck(
    binding ?? original.binding, original.handle, current));
}

// Called only by the installed Effect owner's original durable dispatch claim.
// This transport neither issues that claim nor interprets provider settlement.
// Rejected responses and the original thrown failure pass to that Owner.
export async function sendOwnedGcsObjectRequest({request, authorization, credential,
  callResource, maxRequestBytes, maxResponseBytes, signal}) {
  originalRequest(request);
  if (!integer(maxRequestBytes) || !integer(maxResponseBytes)) {
    fail('InvalidGcsObjectTransportLimits');
  }
  if (authorization?.scope?.resourceOrigin !== request.origin ||
      authorization?.scope?.operation !== request.operation) {
    fail('ForeignGcsObjectAuthorization');
  }
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({authorization, credential,
    callResource, operation: request.operation, method: request.method, path: request.path,
    body: request.has_body ? request.body : undefined,
    // Content framing belongs to the existing physical HTTP/credential owner.
    headers: [['accept', 'application/json']],
    responseHeaders: ['x-goog-generation', 'x-goog-metageneration'],
    maxRequestBytes, maxResponseBytes, signal});
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    accepted: response.accepted, statusCode: response.statusCode, body: response.body}),
    headers: response.headers});
}

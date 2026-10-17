// Physical projections borrow their original provider handles. DTO equality,
// a copied marker, or a successful projection is not a permission or receipt.
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimePair} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {invokeScopedCredentialOperation} from
  '../../../host-common/owned-invocation-context.mjs';
import {openHttpsCredentialBinding, closeHttpsCredentialBinding} from
  '../../../site-node/https-credential-resource.mjs';

const originals = new WeakMap();
const wire = value => canonicalJson(value, {dataKeys: true});
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = (value, minimum = 1) => Number.isSafeInteger(value) &&
  value >= minimum && value <= 2147483647;
const viewBacking = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'buffer').get;
const viewLength = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(Uint8Array.prototype),
  'byteLength').get;
const bufferLength = Object.getOwnPropertyDescriptor(ArrayBuffer.prototype, 'byteLength').get;
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

// Installed Effect input already carries the existing typed Value wire. Its
// Json envelope is admitted by the same portable Value/GCS owners, never
// unwrapped or guessed from arbitrary JavaScript objects at this boundary.
export function prepareOwnedGcsEffectMetadataPatch({moon, binding, original, value,
  marker, maxProjectionBytes}) {
  if (typeof moon?.gcsObjectPrepareEffectPatch !== 'function') {
    fail('GcsOriginalMutationPreparationUnavailable');
  }
  const handle = gcsOwnedResult(moon, moon.gcsObjectPrepareEffectPatch(binding, original,
    Buffer.from(wire(value), 'utf8'), marker));
  return projectOwnedGcsObjectRequest(moon, binding, handle, maxProjectionBytes);
}

export function prepareOwnedGcsObjectDelete({moon, binding, original, maxProjectionBytes}) {
  const handle = gcsOwnedResult(moon, moon.gcsObjectPrepareDelete(binding, original));
  return projectOwnedGcsObjectRequest(moon, binding, handle, maxProjectionBytes);
}

// Retain the same raw response before this DATA interpretation. Port fields
// are observations, not Account authority or a physical-response cleanup ACK.
export function admitGcsObjectTargetObservation(moon, binding, name, response) {
  const observation = response?.observation;
  if (typeof moon?.gcsObjectTargetObservation !== 'function') {
    fail('GcsObjectTargetObservationUnavailable');
  }
  if (typeof name !== 'string' || observation?.accepted !== true ||
      !/^sha256:[0-9a-f]{64}$/u.test(observation.useCid ?? '') ||
      !integer(observation.statusCode, 100) || observation.statusCode > 599 ||
      !Array.isArray(response?.headers) || response.headers.length > 3 ||
      response.headers.some(pair => !Array.isArray(pair) || pair.length !== 2 ||
        typeof pair[0] !== 'string' || typeof pair[1] !== 'string')) {
    fail('GcsInvalidObjectTargetReadObservation');
  }
  const body = observation.body;
  try {
    if (!(body instanceof Uint8Array) || viewLength.call(body) > 2147483647) {
      fail('GcsInvalidObjectTargetReadObservation');
    }
    bufferLength.call(viewBacking.call(body));
  } catch { fail('GcsInvalidObjectTargetReadObservation'); }
  return gcsOwnedResult(moon, moon.gcsObjectTargetObservation(binding, name,
    observation.statusCode, body, response.headers.map(([key, value]) => runtimePair(key, value))));
}

// The existing Effect/capture Owner supplies funding and the original read
// approval before this call, retains the response before interpretation, and
// keeps cleanup pending through the final physical borrower. No local retry.
export async function readGcsObjectTarget({moon, binding, name, authorization,
  credential, callResource, maxRequestBytes, signal}) {
  if (typeof name !== 'string' || !integer(maxRequestBytes)) fail('GcsInvalidObjectTargetRead');
  if (typeof moon?.gcsObjectMetadataPath !== 'function' ||
      typeof moon?.gcsObjectMetadataMaxBytes !== 'function') fail('GcsObjectTargetReadUnavailable');
  const path = gcsOwnedResult(moon, moon.gcsObjectMetadataPath(binding, name));
  const maxResponseBytes = moon.gcsObjectMetadataMaxBytes(binding);
  if (!integer(maxResponseBytes)) fail('GcsInvalidObjectTargetRead');
  if (authorization?.scope?.resourceOrigin !== 'https://storage.googleapis.com' ||
      authorization?.scope?.operation !== 'gcs:file:read') fail('ForeignGcsObjectTargetReadAuthorization');
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

function originalRequest(request, binding) {
  const original = originals.get(request);
  if (original === undefined || original.lifetime?.retiring) fail('ForeignGcsObjectRequest');
  const {moon, handle} = original;
  // This same-object borrow is checked by the portable provider Owner. A JS
  // copy, equal body/CID or changed permission binding cannot substitute it.
  gcsOwnedResult(moon, moon.gcsObjectRequestBody(binding ?? original.binding, handle));
  return original;
}

// The original installed capture retains this child before prepare(). Its
// caller must already own the real read/preparation envelope: these clamps
// and this Credential binding do not reserve material or issue approval.
// No normal installer selects this child without that original supplier.
export function createGcsMutationRequestChild({moon, binding, kind, name, value,
  marker, maxProjectionBytes, maxRequestBytes, maxSecretBytes, credential,
  callResource, authorizationForRow, assertCurrent, signal, valueEncoding = 'source_json'}) {
  const lifetime = {retiring: false};
  let configuration = {moon, binding, kind, name, value, marker,
    maxProjectionBytes, maxRequestBytes, maxSecretBytes, credential,
    callResource, authorizationForRow, assertCurrent, signal, valueEncoding};
  let preparing = false, prepared, response, physicalBinding;
  let changes, credentialSnapshot;
  let preparation, releaseFlight, retired = false;
  let fencePending = false, fenceFlight;
  let failure, cleanup, cleanupStatus, cleanupRetry, invalidCleanup = false, failed = false;
  const unavailable = () => fail('GcsOriginalMutationPreparationUnavailable');
  const current = original => {
    if (lifetime.retiring || configuration !== original) unavailable();
    original.signal?.throwIfAborted();
    const result = original.assertCurrent();
    if (result !== undefined) {
      if (typeof result?.then === 'function') {
        // An invalid asynchronous fence is still an outstanding borrower.
        // Refuse admission without dropping that same pending continuation.
        fencePending = true;
        fenceFlight = Promise.resolve(result).then(
          () => { fencePending = false;fenceFlight = undefined; },
          () => { fencePending = false;fenceFlight = undefined; });
      }
      unavailable();
    }
    if (lifetime.retiring || configuration !== original) unavailable();
    original.signal?.throwIfAborted();
  };
  const rememberFailure = primary => {
    failed = true;
    failure = primary;
    // Diagnostic property access must not replace the original thrown value.
    // A malformed/throwing cleanup facet stays pending, not assumed absent.
    try {
      cleanup = primary?.cleanupHandle;
      if (cleanup !== undefined) {
        cleanupStatus = cleanup?.status;
        cleanupRetry = cleanup?.retry;
        invalidCleanup = typeof cleanupStatus !== 'function' || typeof cleanupRetry !== 'function';
      } else if (primary?.cleanupPending === true) invalidCleanup = true;
    } catch { invalidCleanup = true; }
  };
  const release = () => {
    lifetime.retiring = true;
    if (retired) return Promise.resolve(false);
    if (releaseFlight !== undefined) return releaseFlight;
    releaseFlight = (async () => {
      let closed = true;
      // Drive only this original Credential binding, even while its prepare
      // Promise remains unresolved. Pending close is never physical ACK.
      if (physicalBinding !== undefined) {
        closed = closeHttpsCredentialBinding(physicalBinding) === 'closed';
      }
      if (preparing || fencePending || !closed || invalidCleanup) return false;
      if (cleanup !== undefined) {
        if (Reflect.apply(cleanupStatus, cleanup, [])?.pending !== false) {
          if (await Reflect.apply(cleanupRetry, cleanup, []) === false) return false;
          if (Reflect.apply(cleanupStatus, cleanup, [])?.pending !== false) return false;
        }
      }
      if (prepared !== undefined) originals.delete(prepared.request);
      prepared = undefined;
      preparation = undefined;
      fenceFlight = undefined;
      response = undefined;
      changes = undefined;
      credentialSnapshot = undefined;
      configuration = undefined;
      physicalBinding = undefined;
      failure = undefined;
      failed = false;
      cleanup = cleanupStatus = cleanupRetry = undefined;
      retired = true;
      return true;
    })().finally(() => { releaseFlight = undefined; });
    return releaseFlight;
  };
  return Object.freeze({
    prepare() {
      if (lifetime.retiring) return Promise.reject(Object.assign(
        new Error('GcsOriginalMutationPreparationUnavailable'), {code: 'GcsOriginalMutationPreparationUnavailable'}));
      if (preparation !== undefined) return preparation;
      const original = configuration;
      preparing = true;
      preparation = (async () => {
        if (!['patch_metadata', 'delete'].includes(original.kind) ||
            !['source_json', 'effect_value'].includes(original.valueEncoding) ||
            ![original.maxRequestBytes, original.maxProjectionBytes, original.maxSecretBytes].every(n => integer(n)) ||
            typeof original.authorizationForRow !== 'function' ||
            typeof original.assertCurrent !== 'function' ||
            typeof original.callResource !== 'function' ||
            ['gcsObjectMutationKind', 'gcsObjectMetadataPath', 'gcsObjectMetadataMaxBytes',
              'gcsObjectTargetObservation', 'gcsObjectFailureCode', 'gcsObjectRequestProjection',
              'gcsObjectRequestBody', 'gcsObjectRequestChanges',
              ...(original.kind === 'patch_metadata'
                ? ['gcsObjectCheckPatchInput', original.valueEncoding === 'effect_value'
                  ? 'gcsObjectPrepareEffectPatch' : 'gcsObjectPreparePatch'] : ['gcsObjectPrepareDelete'])]
              .some(name => typeof original.moon?.[name] !== 'function') ||
            original.moon.gcsObjectMutationKind(original.binding) !== original.kind) unavailable();
        // Path/binding refusal must precede a fresh read decision or secret.
        gcsOwnedResult(original.moon, original.moon.gcsObjectMetadataPath(original.binding, original.name));
        credentialSnapshot = Object.freeze({...original.credential});
        // This child owns its one new binding. It cannot close or replace a
        // caller's already-owned binding without that original borrow seam.
        if (credentialSnapshot.binding !== undefined) unavailable();
        if (original.kind === 'patch_metadata') {
          // Snapshot the original admitted row DATA before the first await.
          // This additional wire/Buffer overlaps the caller row and raw GET;
          // it belongs to that caller's funded preparation workspace.
          changes = Buffer.from(wire(original.value), 'utf8');
          if (changes.byteLength > original.moon.gcsObjectMetadataMaxBytes(original.binding)) {
            fail('GcsObjectRequestCapacityExceeded');
          }
          if (!/^sha256:[0-9a-f]{64}$/u.test(original.marker ?? '')) unavailable();
          gcsOwnedResult(original.moon, original.moon.gcsObjectCheckPatchInput(
            original.binding, changes, original.marker, original.valueEncoding === 'effect_value'));
        } else if (wire(original.value) !== '{}') fail('GcsInvalidObjectChanges');
        current(original);
        const authorization = await original.authorizationForRow();
        current(original);
        physicalBinding = openHttpsCredentialBinding({...credentialSnapshot,
          scope: authorization?.scope, maxSecretBytes: original.maxSecretBytes});
        response = await readGcsObjectTarget({moon: original.moon, binding: original.binding,
          name: original.name, authorization, credential: {...credentialSnapshot, binding: physicalBinding},
          callResource: original.callResource, maxRequestBytes: original.maxRequestBytes, signal: original.signal});
        current(original);
        const before = admitGcsObjectTargetObservation(original.moon, original.binding, original.name, response);
        const request = original.kind === 'patch_metadata'
          ? projectOwnedGcsObjectRequest(original.moon, original.binding,
            gcsOwnedResult(original.moon, original.moon[original.valueEncoding === 'effect_value'
              ? 'gcsObjectPrepareEffectPatch' : 'gcsObjectPreparePatch'](original.binding,
              before, changes, original.marker)), original.maxProjectionBytes)
          : prepareOwnedGcsObjectDelete({moon: original.moon, binding: original.binding,
            original: before, maxProjectionBytes: original.maxProjectionBytes});
        const owned = originals.get(request);
        originals.set(request, {...owned, lifetime});
        prepared = Object.freeze({request, requestCid: request.request_cid});
        current(original);
        return prepared;
      })().catch(primary => { rememberFailure(primary);throw primary; })
        .finally(() => { preparing = false; });
      return preparation;
    },
    release,
    retry: release,
    status() {
      return Object.freeze({pending: !retired,
        ...(failed ? {errors: Object.freeze([failure])} : {})});
    },
  });
}

export function ownedGcsObjectRequestCid(request, binding) {
  originalRequest(request, binding);
  return request.request_cid;
}

// A detached initial-capture projection of this same request's original GET.
// It never performs a replacement read or supplies an apply-current proof.
export function projectOwnedGcsMetadataPatchTarget(request, maxProjectionBytes, binding) {
  const original = originalRequest(request, binding);
  if (!integer(maxProjectionBytes)) fail('InvalidGcsObjectAbiLimits');
  if (typeof original.moon?.gcsObjectPatchEffectTarget !== 'function') {
    fail('GcsOriginalMutationPreparationUnavailable');
  }
  return freeze(JSON.parse(gcsOwnedResult(original.moon,
    original.moon.gcsObjectPatchEffectTarget(binding ?? original.binding,
      original.handle, maxProjectionBytes))));
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

// A matching metadata body is correlation only. The original Effect/Store
// still authenticates dispatch and retained response before settlement.
export function ownedGcsObjectResponseMatches(request, observed, binding) {
  const original = originalRequest(request, binding);
  if (typeof original.moon.gcsObjectResponseMatches !== 'function') fail('GcsObjectResponseUnavailable');
  return original.moon.gcsObjectResponseMatches(original.binding, original.handle, observed);
}

// Use only with that same authenticated direct response, including retained
// response recovery. Never pass a later GET failure as a DELETE confirmation.
export function projectOwnedGcsObjectResponse(request, observation, maxProjectionBytes) {
  const original = originalRequest(request);
  if (typeof original.moon.gcsObjectResponseProjection !== 'function') fail('GcsObjectResponseUnavailable');
  const status = observation?.statusCode;
  if (!integer(maxProjectionBytes) || !Number.isInteger(status) || status < 100 || status > 599) {
    fail('InvalidGcsObjectResponse');
  }
  const body = observation?.body;
  try {
    if (!(body instanceof Uint8Array) || viewLength.call(body) > 2147483647) fail('InvalidGcsObjectResponse');
    // No concurrent SharedArrayBuffer mutation between admission and meaning.
    bufferLength.call(viewBacking.call(body));
  } catch { fail('InvalidGcsObjectResponse'); }
  return freeze(JSON.parse(gcsOwnedResult(original.moon,
    original.moon.gcsObjectResponseProjection(original.binding, original.handle,
      status, body, maxProjectionBytes))));
}

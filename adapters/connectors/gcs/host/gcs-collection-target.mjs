// Original Connector DATA only. The installed Common owner must retain its
// checked Mapping/Command pair and issue the reference with actual currentness.
import {checked} from '../../../host-common/runtime-result.mjs';

const originals = new WeakMap();
const fail = code => { throw Object.assign(new Error(code), {code}); };
const integer = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;

function collectionResult(moon, result) {
  try { return checked(result); }
  catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsCollectionFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
}

export function prepareGcsCollectionTarget(moon, {project, bucket, prefix, targetRef,
  resourceKind, catalogCid, installationCid, maxBytes, maxNodes, maxDepth}) {
  if ([project, bucket, prefix, targetRef, resourceKind, catalogCid, installationCid]
    .some(value => typeof value !== 'string')) fail('InvalidGcsCollectionAbiBinding');
  if (![maxBytes, maxNodes, maxDepth].every(integer)) fail('InvalidGcsCollectionAbiLimits');
  const binding = collectionResult(moon, moon.gcsCollectionBinding(project, bucket,
    prefix, targetRef, resourceKind, catalogCid, installationCid, maxBytes, maxNodes, maxDepth));
  // Borrow the canonical provider strings unchanged. A wire copy can be used
  // as DATA, but cannot recover this original binding or a Common reference.
  const target = Object.freeze({identityWire: moon.gcsCollectionIdentityJson(binding),
    identityCid: moon.gcsCollectionIdentityCid(binding),
    resourceWire: moon.gcsCollectionResourceJson(binding)});
  originals.set(target, {moon, binding});
  return target;
}

export function checkGcsCollectionTarget(original, selected, installationCid, targetRef) {
  const owner = originals.get(original), candidate = originals.get(selected);
  if (owner === undefined || candidate === undefined || owner.moon !== candidate.moon ||
      typeof installationCid !== 'string' || typeof targetRef !== 'string') {
    fail('ForeignGcsCollectionTarget');
  }
  collectionResult(owner.moon, owner.moon.gcsCollectionCheckBinding(owner.binding,
    candidate.binding, installationCid, targetRef));
}

// The fixed provider projection borrows only this original collection handle.
// It returns declaration DATA, never the handle or a Common ResourceReference.
export function gcsCollectionUploadMapping(original, declaredWire, connectorId,
  {maxBytes, maxNodes, maxDepth}) {
  const owner = originals.get(original);
  if (owner === undefined) fail('ForeignGcsCollectionTarget');
  if (typeof declaredWire !== 'string' || typeof connectorId !== 'string') {
    fail('GcsInvalidUploadDeclarationBinding');
  }
  if (![maxBytes, maxNodes, maxDepth].every(integer)) fail('GcsInvalidUploadDeclarationLimits');
  try {
    return checked(owner.moon.gcsUploadMappingJson(owner.binding, declaredWire, connectorId,
      maxBytes, maxNodes, maxDepth));
  } catch (failure) {
    if (failure?.code !== 'MoonBitHostFailure') throw failure;
    const code = owner.moon.gcsUploadDeclarationFailureCode(failure.cause);
    throw Object.assign(new Error(code, {cause: failure.cause}), {code});
  }
}

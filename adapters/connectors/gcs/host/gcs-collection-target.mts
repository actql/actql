// Original Connector DATA only. The installed Common owner must retain its
// checked Mapping/Command pair and issue the reference with actual currentness.
import {checked} from '../../../host-common/runtime-result.mjs';
import {gcsUploadResult} from '../site/gcs-owned-upload-request.mjs';

type Limits = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number}>;
type CollectionInput = Limits & Readonly<{
  project: string; bucket: string; prefix: string; targetRef: string;
  resourceKind: string; catalogCid: string; installationCid: string;
}>;
type UploadInput = Readonly<{
  commandCid: string; permissions: readonly string[];
  metadata: (Limits & Readonly<{maxEntries: number}>) | null | undefined;
  maxContentBytes: number; maxBodyBytes: number; maxPathBytes: number; maxIdentityBytes: number;
}>;
type Core = Parameters<typeof gcsUploadResult>[0] & {
  gcsCollectionBinding(project: string, bucket: string, prefix: string, targetRef: string, resourceKind: string,
    catalogCid: string, installationCid: string, maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  gcsCollectionFailureCode(cause: unknown): string;
  gcsCollectionIdentityJson(binding: unknown): string;
  gcsCollectionIdentityCid(binding: unknown): string;
  gcsCollectionResourceJson(binding: unknown): string;
  gcsCollectionCheckBinding(original: unknown, selected: unknown, installationCid: string, targetRef: string): unknown;
  gcsUploadMappingJson(binding: unknown, declaredWire: string, connectorId: string,
    maxBytes: number, maxNodes: number, maxDepth: number): unknown;
  gcsUploadDeclarationFailureCode(cause: unknown): string;
  gcsCollectionIssueReference(binding: unknown, pair: unknown, declaredWire: string, connectorId: string,
    issuer: unknown, maxBytes: number, maxNodes: number, maxDepth: number, maxWork: number): unknown;
  gcsCollectionReferenceFailureCode(cause: unknown): string;
  gcsUploadBinding(binding: unknown, commandCid: string, permissions: readonly string[],
    maxBytes: number, maxNodes: number, maxDepth: number, maxEntries: number, maxContentBytes: number,
    maxBodyBytes: number, maxPathBytes: number, maxIdentityBytes: number): unknown;
};
type CollectionTarget = Readonly<{identityWire: string; identityCid: string; resourceWire: string}>;

const originals = new WeakMap<CollectionTarget, {moon: Core; binding: unknown}>();
const fail: (code: string) => never = code => { throw Object.assign(new Error(code), {code}); };
const integer = (value: unknown): value is number =>
  Number.isSafeInteger(value) && (value as number) > 0 && (value as number) <= 2147483647;

function collectionResult(moon: Core, result: unknown) {
  try { return checked(result); }
  catch (failure) {
    if ((failure as {code?: unknown} | null | undefined)?.code !== 'MoonBitHostFailure') throw failure;
    const code = moon.gcsCollectionFailureCode((failure as Error).cause);
    throw Object.assign(new Error(code, {cause: (failure as Error).cause}), {code});
  }
}

export function prepareGcsCollectionTarget(moon: Core, {project, bucket, prefix, targetRef,
  resourceKind, catalogCid, installationCid, maxBytes, maxNodes, maxDepth}: CollectionInput) {
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

export function checkGcsCollectionTarget(original: unknown, selected: unknown,
  installationCid: unknown, targetRef: unknown) {
  const owner = originals.get(original as CollectionTarget), candidate = originals.get(selected as CollectionTarget);
  if (owner === undefined || candidate === undefined || owner.moon !== candidate.moon ||
      typeof installationCid !== 'string' || typeof targetRef !== 'string') {
    fail('ForeignGcsCollectionTarget');
  }
  collectionResult(owner.moon, owner.moon.gcsCollectionCheckBinding(owner.binding,
    candidate.binding, installationCid, targetRef));
}

// The fixed provider projection borrows only this original collection handle.
// It returns declaration DATA, never the handle or a Common ResourceReference.
export function gcsCollectionUploadMapping(original: unknown, declaredWire: unknown, connectorId: unknown,
  {maxBytes, maxNodes, maxDepth}: Limits): string {
  const owner = originals.get(original as CollectionTarget);
  if (owner === undefined) fail('ForeignGcsCollectionTarget');
  if (typeof declaredWire !== 'string' || typeof connectorId !== 'string') {
    fail('GcsInvalidUploadDeclarationBinding');
  }
  if (![maxBytes, maxNodes, maxDepth].every(integer)) fail('GcsInvalidUploadDeclarationLimits');
  try {
    return checked(owner.moon.gcsUploadMappingJson(owner.binding, declaredWire, connectorId,
      maxBytes, maxNodes, maxDepth)) as string;
  } catch (failure) {
    if ((failure as {code?: unknown} | null | undefined)?.code !== 'MoonBitHostFailure') throw failure;
    const code = owner.moon.gcsUploadDeclarationFailureCode((failure as Error).cause);
    throw Object.assign(new Error(code, {cause: (failure as Error).cause}), {code});
  }
}

// Called only with the existing installed Host's original issuer. Possessing
// the DATA frame or equal wire cannot replace that issuer or its currentness.
export function issueGcsCollectionReference(original: unknown, pair: unknown, declaredWire: unknown, connectorId: unknown,
  issuer: unknown, {maxBytes, maxNodes, maxDepth, maxWork}: Limits & Readonly<{maxWork: number}>) {
  const owner = originals.get(original as CollectionTarget);
  if (owner === undefined) fail('ForeignGcsCollectionTarget');
  if (typeof declaredWire !== 'string' || typeof connectorId !== 'string') {
    fail('GcsForeignCollectionSelection');
  }
  if (![maxBytes, maxNodes, maxDepth, maxWork].every(integer)) {
    fail('GcsCollectionReferenceInvalidLimits');
  }
  try {
    return checked(owner.moon.gcsCollectionIssueReference(owner.binding, pair,
      declaredWire, connectorId, issuer, maxBytes, maxNodes, maxDepth, maxWork));
  } catch (failure) {
    if ((failure as {code?: unknown} | null | undefined)?.code !== 'MoonBitHostFailure') throw failure;
    const code = owner.moon.gcsCollectionReferenceFailureCode((failure as Error).cause);
    throw Object.assign(new Error(code, {cause: (failure as Error).cause}), {code});
  }
}

// The installed driver borrows this same provider collection handle. A copied
// DATA frame cannot construct the upload binding; this is not an issuer/grant.
export function prepareGcsCollectionUploadBinding(original: unknown, {commandCid, permissions,
  metadata, maxContentBytes, maxBodyBytes, maxPathBytes, maxIdentityBytes}: UploadInput) {
  const owner = originals.get(original as CollectionTarget);
  if (owner === undefined) fail('ForeignGcsCollectionTarget');
  if (typeof commandCid !== 'string' || !Array.isArray(permissions) ||
      permissions.some(value => typeof value !== 'string') || !metadata ||
      ![metadata.maxBytes, metadata.maxNodes, metadata.maxDepth,
        maxBodyBytes, maxPathBytes, maxIdentityBytes].every(integer) ||
      !Number.isInteger(metadata.maxEntries) || metadata.maxEntries < 0 ||
      metadata.maxEntries > 2147483647 || !Number.isInteger(maxContentBytes) ||
      maxContentBytes < 0 || maxContentBytes > 2147483647) fail('GcsInvalidUploadAbiLimits');
  return gcsUploadResult(owner.moon, owner.moon.gcsUploadBinding(owner.binding,
    commandCid, permissions, metadata.maxBytes, metadata.maxNodes, metadata.maxDepth,
    metadata.maxEntries, maxContentBytes, maxBodyBytes, maxPathBytes, maxIdentityBytes));
}

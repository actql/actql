// Installed Host authority for exact committed Manifest inspection.
// MoonBit owns grant meaning; this adapter performs current authorization and
// delegates durable use-count and trusted-clock effects to the Store.
const authorities = new WeakMap();
const services = new WeakMap();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;

export class ManifestAccessError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new ManifestAccessError(code, cause); };

export function installManifestAccessAuthority(configuration) {
  if (!exactKeys(configuration, [
    'admitManifestRead', 'authorizeManifestRead',
  ]) || typeof configuration.admitManifestRead !== 'function' ||
      typeof configuration.authorizeManifestRead !== 'function') {
    fail('InvalidManifestAccessAuthority');
  }
  const authority = Object.freeze({});
  authorities.set(authority, Object.freeze({...configuration}));
  return authority;
}

export function installManifestAccessService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.consumeManifestReadGrant !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.issueManifestReadGrant !== 'function' ||
      typeof configuration.control.manifestReadGrantAllowsBytes !==
        'function' ||
      typeof configuration.control.manifestReadGrantValidAt !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidManifestAccessService');
  }
  const service = Object.freeze({});
  services.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: authorities.get(configuration.authority),
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

function validateRequest(request) {
  if (!exactKeys(request, [
    'indexKey', 'principalId', 'purpose', 'attemptId',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0 ||
      typeof request.attemptId !== 'string' || request.attemptId.length === 0) {
    fail('InvalidManifestAccessRequest');
  }
}

function validateAdmission(admission) {
  if (!exactKeys(admission, [
    'authorizationContextCid', 'clockContractCid', 'dataCeilingCid',
    'expiresAt', 'maxBytes', 'maxUses',
  ]) || !cidPattern.test(admission.authorizationContextCid) ||
      !cidPattern.test(admission.clockContractCid) ||
      !cidPattern.test(admission.dataCeilingCid) ||
      typeof admission.expiresAt !== 'string' ||
      !Number.isSafeInteger(admission.maxBytes) || admission.maxBytes < 0 ||
      !positive(admission.maxUses)) {
    fail('InvalidManifestReadAdmission');
  }
}

function observedAt(now) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidManifestAccessClock');
  }
  return value;
}

function immutableJson(wire) {
  let value;
  try { value = JSON.parse(wire); }
  catch (error) { fail('InvalidManifestControlResult', error); }
  const freeze = item => {
    if (item !== null && typeof item === 'object') {
      for (const child of Object.values(item)) freeze(child);
      Object.freeze(item);
    }
    return item;
  };
  return freeze(value);
}

export async function readAuthorizedManifest(service, request) {
  const installed = services.get(service) ?? fail('ForeignManifestService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    principalId: request.principalId,
    purpose: request.purpose,
    attemptId: request.attemptId,
  });
  if (await installed.authority.authorizeManifestRead(requestFacts) !== true) {
    fail('ManifestAccessDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ManifestAccessDenied');
  const index = await installed.store.readPublicationContract(
    entry.public_index_entry_cid, 'public_index_entry',
  );
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const at = observedAt(installed.now);
  const facts = Object.freeze({...requestFacts, entry, index, manifest});
  const admission = await installed.authority.admitManifestRead(facts);
  validateAdmission(admission);
  await installed.store.observeTrustedClock(admission.clockContractCid, at);
  const grant = installed.control.issueManifestReadGrant(
    index,
    manifest,
    {
      principalId: request.principalId,
      purpose: request.purpose,
      dataCeilingCid: admission.dataCeilingCid,
      maxBytes: admission.maxBytes,
      maxUses: admission.maxUses,
      expiresAt: admission.expiresAt,
      authorizationContextCid: admission.authorizationContextCid,
    },
    installed.limits,
  );
  const byteCount = new TextEncoder().encode(manifest.wire).byteLength;
  if (!installed.control.manifestReadGrantAllowsBytes(grant, byteCount) ||
      !installed.control.manifestReadGrantValidAt(grant, at)) {
    fail('ManifestAccessDenied');
  }
  const authorization = Object.freeze({...facts, stage: 'read', grant, at});
  if (await installed.authority.authorizeManifestRead(authorization) !== true) {
    fail('ManifestAccessDenied');
  }
  const usage = await installed.store.consumeManifestReadGrant(
    grant.wire, request.attemptId,
  );
  const response = Object.freeze({
    manifestCid: manifest.identity,
    manifest: immutableJson(manifest.wire),
    grantCid: grant.identity,
    idempotent: usage.idempotent,
  });
  if (await installed.authority.authorizeManifestRead(Object.freeze({
    ...authorization, stage: 'response', response,
  })) !== true) {
    fail('ManifestAccessDenied');
  }
  return response;
}

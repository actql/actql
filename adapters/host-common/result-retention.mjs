// Common authorization and sequencing for mandatory durable Result deletion.
// MoonBit decides retention state. The Store owns physical reclamation and
// reports when active readers or failed cleanup still retain responsibility.

const authorities = new WeakMap();
const services = new WeakMap();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;

export class ResultRetentionError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new ResultRetentionError(code, cause); };

export function installResultRetentionAuthority(configuration) {
  if (!exactKeys(configuration, ['authorizeResultDeletion']) ||
      typeof configuration.authorizeResultDeletion !== 'function') {
    fail('InvalidResultRetentionAuthority');
  }
  const authority = Object.freeze({});
  authorities.set(authority, Object.freeze({
    authorizeResultDeletion: configuration.authorizeResultDeletion,
  }));
  return authority;
}

export function installResultRetentionService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.retireCommittedResult !== 'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidResultRetentionService');
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
    'indexKey', 'resultName', 'reason',
  ]) || !exactKeys(request.indexKey, [
    'tenantId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.tenantId !== 'string' ||
      request.indexKey.tenantId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidResultRetentionRequest');
  }
}

function observedAt(now) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultRetentionClock');
  }
  return value;
}

export async function retireExpiredResult(service, request) {
  const installed = services.get(service) ??
    fail('ForeignResultRetentionService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestedAt = observedAt(installed.now);
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    resultName: request.resultName,
    reason: request.reason,
    observedAt: requestedAt,
  });
  if (await installed.authority.authorizeResultDeletion(requestFacts) !==
      true) {
    fail('ResultRetentionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultRetentionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const retentionCid =
    installed.control.resultReadRetentionPolicyCid(
      manifest, request.resultName,
    );
  const retention = await installed.store.readPublicationContract(
    retentionCid, 'result_retention_policy',
  );
  const clockCid = installed.control.resultRetentionClockContractCid(
    retention,
  );
  await installed.store.observeTrustedClock(clockCid, requestedAt);
  if (installed.control.resultReadAvailability(
    manifest, request.resultName, retention, requestedAt,
  ) !== 'delete_due') {
    fail('ResultDeletionNotDue');
  }
  const resultDefinitionCid =
    installed.control.resultReadDefinitionCid(
      manifest, request.resultName,
    );
  if (await installed.authority.authorizeResultDeletion(Object.freeze({
    ...requestFacts,
    stage: 'delete',
    entry,
    manifest,
    retention,
    resultDefinitionCid,
  })) !== true) {
    fail('ResultRetentionDenied');
  }
  const retired = await installed.store.retireCommittedResult(
    indexKey, resultDefinitionCid,
  );
  return Object.freeze({
    resultName: request.resultName,
    resultDefinitionCid,
    observedAt: requestedAt,
    cleanupPending: retired.cleanup.status().pending,
    cleanupHandle: retired.cleanup,
  });
}

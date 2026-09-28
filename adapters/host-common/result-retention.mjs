// Common authorization and sequencing for mandatory durable Result deletion.
// MoonBit decides retention state. The Store owns physical reclamation and
// reports when active readers or failed cleanup still retain responsibility.

const authorities = new WeakMap();
const services = new WeakMap();
const extensionAuthorities = new WeakMap();
const extensionServices = new WeakMap();
const metadataAuthorities = new WeakMap();
const metadataServices = new WeakMap();
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

export function installResultRetentionExtensionAuthority(configuration) {
  if (!exactKeys(configuration, ['authorizeResultExtension']) ||
      typeof configuration.authorizeResultExtension !== 'function') {
    fail('InvalidResultRetentionExtensionAuthority');
  }
  const authority = Object.freeze({});
  extensionAuthorities.set(authority, Object.freeze({
    authorizeResultExtension: configuration.authorizeResultExtension,
  }));
  return authority;
}

export function installMetadataRetentionAuthority(configuration) {
  if (!exactKeys(configuration, ['authorizeMetadataDeletion']) ||
      typeof configuration.authorizeMetadataDeletion !== 'function') {
    fail('InvalidMetadataRetentionAuthority');
  }
  const authority = Object.freeze({});
  metadataAuthorities.set(authority, Object.freeze({
    authorizeMetadataDeletion: configuration.authorizeMetadataDeletion,
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

export function installResultRetentionExtensionService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      typeof configuration.store.putCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.issueResultRetentionExtension !==
        'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !extensionAuthorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidResultRetentionExtensionService');
  }
  const service = Object.freeze({});
  extensionServices.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: extensionAuthorities.get(configuration.authority),
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

export function installMetadataRetentionService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.retireCommittedPublicationMetadata !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.manifestResultNames !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultMetadataRetentionState !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      !metadataAuthorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidMetadataRetentionService');
  }
  const service = Object.freeze({});
  metadataServices.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: metadataAuthorities.get(configuration.authority),
    now: configuration.now,
    limits: Object.freeze({...configuration.limits}),
  }));
  return service;
}

function validateRequest(request) {
  if (!exactKeys(request, [
    'indexKey', 'resultName', 'reason',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
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

function validateMetadataRequest(request) {
  if (!exactKeys(request, ['indexKey', 'reason']) ||
      !exactKeys(request.indexKey, [
        'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
      ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidMetadataRetentionRequest');
  }
}

export async function retireExpiredPublicationMetadata(service, request) {
  const installed = metadataServices.get(service) ??
    fail('ForeignMetadataRetentionService');
  validateMetadataRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const observed = observedAt(installed.now);
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    reason: request.reason,
    observedAt: observed,
  });
  if (await installed.authority.authorizeMetadataDeletion(requestFacts) !==
      true) {
    fail('MetadataRetentionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('MetadataRetentionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const names = installed.control.manifestResultNames(
    manifest, installed.limits,
  );
  if (!Array.isArray(names) || names.length === 0) {
    fail('InvalidMetadataRetentionInventory');
  }
  const retentions = [];
  for (const resultName of names) {
    const retentionCid = installed.control.resultReadRetentionPolicyCid(
      manifest, resultName,
    );
    const retention = await installed.store.readPublicationContract(
      retentionCid, 'result_retention_policy',
    );
    const clockCid = installed.control.resultRetentionClockContractCid(
      retention,
    );
    await installed.store.observeTrustedClock(clockCid, observed);
    if (installed.control.resultMetadataRetentionState(
      retention, observed,
    ) !== 'delete_due') {
      fail('MetadataDeletionNotDue');
    }
    retentions.push(retention);
  }
  if (await installed.authority.authorizeMetadataDeletion(Object.freeze({
    ...requestFacts,
    stage: 'delete',
    entry,
    manifest,
    resultNames: Object.freeze([...names]),
    retentions: Object.freeze(retentions),
  })) !== true) {
    fail('MetadataRetentionDenied');
  }
  const retired = await installed.store.retireCommittedPublicationMetadata(
    indexKey, observed,
  );
  return Object.freeze({
    observedAt: observed,
    cleanupPending: retired.cleanup.status().pending,
    cleanupHandle: retired.cleanup,
  });
}

function validateExtensionRequest(request) {
  if (!exactKeys(request, [
    'indexKey', 'resultName', 'availableUntil', 'reason',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      typeof request.availableUntil !== 'string' ||
      request.availableUntil.length === 0 ||
      typeof request.reason !== 'string' || request.reason.length === 0) {
    fail('InvalidResultRetentionExtensionRequest');
  }
}

export async function extendResultRetention(service, request) {
  const installed = extensionServices.get(service) ??
    fail('ForeignResultRetentionExtensionService');
  validateExtensionRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const admittedAt = observedAt(installed.now);
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    resultName: request.resultName,
    availableUntil: request.availableUntil,
    reason: request.reason,
    observedAt: admittedAt,
  });
  if (await installed.authority.authorizeResultExtension(requestFacts) !==
      true) {
    fail('ResultRetentionExtensionDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultRetentionExtensionDenied');
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const baseCid = installed.control.resultReadRetentionPolicyCid(
    manifest, request.resultName,
  );
  const base = await installed.store.readPublicationContract(
    baseCid, 'result_retention_policy',
  );
  const resultDefinitionCid = installed.control.resultReadDefinitionCid(
    manifest, request.resultName,
  );
  const clockCid = installed.control.resultRetentionClockContractCid(base);
  await installed.store.observeTrustedClock(clockCid, admittedAt);
  for (let attempt = 0; attempt < 3; attempt++) {
    let current;
    try {
      current = await installed.store.readCommittedResultRetentionExtension(
        indexKey, resultDefinitionCid,
      );
    } catch (error) {
      if (error?.code === 'PublicationObjectMissing') {
        fail('ResultRetentionExtensionUnavailable', error);
      }
      throw error;
    }
    const effective = current?.extension ?? base;
    if (current !== undefined) {
      installed.control.resultReadExtendedAvailability(
        manifest, request.resultName, base, effective, admittedAt,
      );
    }
    let extension;
    try {
      extension = installed.control.issueResultRetentionExtension(
        effective,
        request.availableUntil,
        admittedAt,
        installed.limits,
      );
      if (installed.control.resultReadExtendedAvailability(
        manifest, request.resultName, base, extension, admittedAt,
      ) !== 'available') {
        fail('ResultRetentionExtensionNotAvailable');
      }
    } catch (error) {
      fail('ResultRetentionExtensionNotAllowed', error);
    }
    if (await installed.authority.authorizeResultExtension(Object.freeze({
      ...requestFacts,
      stage: 'extend',
      entry,
      manifest,
      base,
      current: current?.extension,
      extension,
      resultDefinitionCid,
    })) !== true) {
      fail('ResultRetentionExtensionDenied');
    }
    try {
      const stored =
        await installed.store.putCommittedResultRetentionExtension(
          indexKey,
          resultDefinitionCid,
          current?.extension?.identity,
          extension,
          admittedAt,
        );
      return Object.freeze({
        resultName: request.resultName,
        resultDefinitionCid,
        admittedAt,
        extension: stored.extension,
        idempotent: stored.idempotent,
      });
    } catch (error) {
      if (error?.code !== 'PublicationRetentionExtensionConflict' ||
          attempt === 2) throw error;
    }
  }
  fail('ResultRetentionExtensionConflict');
}

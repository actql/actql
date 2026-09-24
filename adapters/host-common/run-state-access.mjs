// Authorized current-state projection for one durably committed Run.
// MoonBit owns inventory, availability relations, aggregate and next action.
// This adapter only observes current Store and Host-policy facts.
const authorities = new WeakMap();
const services = new WeakMap();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;

export class RunStateAccessError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new RunStateAccessError(code, cause); };

export function installRunStateAuthority(configuration) {
  if (!exactKeys(configuration, [
    'authorizeRunState', 'resultPolicyAvailable',
  ]) || typeof configuration.authorizeRunState !== 'function' ||
      typeof configuration.resultPolicyAvailable !== 'function') {
    fail('InvalidRunStateAuthority');
  }
  const authority = Object.freeze({});
  authorities.set(authority, Object.freeze({...configuration}));
  return authority;
}

export function installRunStateService(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'limits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.latestRecordContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.withCommittedResult !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.manifestResultNames !== 'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      typeof configuration.control.runDefinitionRunId !== 'function' ||
      typeof configuration.control.projectCommittedPublicationState !==
        'function' ||
      typeof configuration.control.issueSucceededRunState !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive)) {
    fail('InvalidRunStateService');
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
  if (!exactKeys(request, ['indexKey', 'principalId', 'purpose']) ||
      !exactKeys(request.indexKey, [
        'tenantId', 'authorityScopeCid', 'runDefinitionCid',
      ]) || typeof request.indexKey.tenantId !== 'string' ||
      request.indexKey.tenantId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0) {
    fail('InvalidRunStateRequest');
  }
}

function observedAt(now) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidRunStateClock');
  }
  return value;
}

function unavailableFrom(error, at) {
  switch (error?.code) {
    case 'PublicationObjectMissing':
      return {state: 'unavailable', reason: 'deleted', observedAt: at};
    case 'PublicationObjectCorrupt':
    case 'PublicationDurableBindingMismatch':
    case 'PublicationContractCorrupt':
    case 'InvalidPublicationStoreObject':
      return {
        state: 'unavailable', reason: 'integrity_failed', observedAt: at,
      };
    case 'PublicationClockUncertain':
      return {state: 'unknown', reason: 'clock_uncertain', observedAt: at};
    default:
      return {state: 'unknown', reason: 'store_query_failed', observedAt: at};
  }
}

async function observeResult(installed, context, resultName, at) {
  const retentionCid = installed.control.resultReadRetentionPolicyCid(
    context.manifest, resultName,
  );
  let retention;
  try {
    retention = await installed.store.readPublicationContract(
      retentionCid, 'result_retention_policy',
    );
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  const clockCid = installed.control.resultRetentionClockContractCid(
    retention,
  );
  try {
    await installed.store.observeTrustedClock(clockCid, at);
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  const definitionCid = installed.control.resultReadDefinitionCid(
    context.manifest, resultName,
  );
  let retained;
  try {
    retained =
      await installed.store.readCommittedResultRetentionExtension(
        context.indexKey, definitionCid,
      );
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  const retentionState = retained === undefined
    ? installed.control.resultReadAvailability(
      context.manifest, resultName, retention, at,
    )
    : installed.control.resultReadExtendedAvailability(
      context.manifest,
      resultName,
      retention,
      retained.extension,
      at,
    );
  if (retentionState === 'delete_due') {
    try {
      await installed.store.withCommittedResult(
        context.indexKey,
        definitionCid,
        () => true,
        async () => undefined,
      );
      return {
        name: resultName,
        state: 'unavailable',
        reason: 'retention_expired',
        observedAt: at,
      };
    } catch (error) {
      return {name: resultName, ...unavailableFrom(error, at)};
    }
  }
  if (retentionState === 'retention_expired') {
    return {
      name: resultName,
      state: 'unavailable',
      reason: 'retention_expired',
      observedAt: at,
    };
  }
  if (retentionState !== 'available') {
    return {
      name: resultName,
      state: 'unknown',
      reason: 'store_query_failed',
      observedAt: at,
    };
  }
  let policyAvailable;
  try {
    policyAvailable = await installed.authority.resultPolicyAvailable(
      Object.freeze({
        ...context,
        resultName,
        retention: retained?.extension ?? retention,
        baseRetention: retention,
        observedAt: at,
      }),
    );
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
  if (policyAvailable !== true) {
    return {
      name: resultName,
      state: 'unavailable',
      reason: 'policy_unavailable',
      observedAt: at,
    };
  }
  try {
    await installed.store.withCommittedResult(
      context.indexKey,
      definitionCid,
      () => true,
      async () => undefined,
    );
    return {
      name: resultName,
      state: 'available',
      reason: 'confirmed_present',
      observedAt: at,
    };
  } catch (error) {
    return {name: resultName, ...unavailableFrom(error, at)};
  }
}

export async function inspectAuthorizedRunState(service, request) {
  const installed = services.get(service) ?? fail('ForeignRunStateService');
  validateRequest(request);
  const indexKey = Object.freeze({...request.indexKey});
  const requestFacts = Object.freeze({
    stage: 'request',
    indexKey,
    principalId: request.principalId,
    purpose: request.purpose,
  });
  if (await installed.authority.authorizeRunState(requestFacts) !== true) {
    fail('RunStateAccessDenied');
  }
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('RunStateAccessDenied');
  const [index, record] = await Promise.all([
    installed.store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry'),
    installed.store.latestRecordContract(entry.publication_attempt_cid),
  ]);
  try {
    if (installed.control.projectCommittedPublicationState(record, index) !==
        'succeeded') {
      fail('InvalidCommittedPublicationState');
    }
  } catch (error) {
    if (error instanceof RunStateAccessError) throw error;
    fail('InvalidCommittedPublicationState', error);
  }
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const runDefinition = await installed.store.readPublicationContract(
    entry.run_definition_cid, 'run_definition',
  );
  const names = installed.control.manifestResultNames(
    manifest, installed.limits,
  );
  const at = observedAt(installed.now);
  const context = Object.freeze({
    indexKey,
    entry,
    manifest,
    runDefinition,
    principalId: request.principalId,
    purpose: request.purpose,
  });
  const observations = [];
  for (const name of names) {
    observations.push(await observeResult(installed, context, name, at));
  }
  const wire = installed.control.issueSucceededRunState({
    runId: installed.control.runDefinitionRunId(runDefinition),
    updatedAt: at,
    declaredResults: names,
    observations,
  }, installed.limits);
  let state;
  try { state = JSON.parse(wire); }
  catch (error) { fail('InvalidRunStateControlResult', error); }
  if (await installed.authority.authorizeRunState(Object.freeze({
    ...context,
    stage: 'response',
    state,
  })) !== true) {
    fail('RunStateAccessDenied');
  }
  return Object.freeze(state);
}

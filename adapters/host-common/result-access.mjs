// Installed Host authority for current Result read and egress admission.
// MoonBit owns grant and delivery semantics. This module keeps caller input
// separate from Host-owned authorization and delegates physical effects.
import {deliverPublishedResult} from './result-delivery.mjs';
import {validDeliveryAttemptLookup, validResultDescription,
  withinResultDescriptionLimits, resultDescriptionLimits} from
  '../../packages/client-wire/index.mjs';

const authorities = new WeakMap();
const services = new WeakMap();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;
const indexKeyFields = [
  'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
];

// Copy only the typed request fields before any authorization or Store await.
// This leaves in-process grants and MoonBit handles on their original owners.
function ownedResultRequest(input, delivery) {
  const fields = [
    'indexKey', 'principalId', 'purpose', 'resultName', 'attemptId',
    ...(delivery ? ['format'] : []),
  ];
  if (!exactKeys(input, fields) ||
      !exactKeys(input.indexKey, indexKeyFields)) {
    fail('InvalidResultAccessRequest');
  }
  const sourceKey = input.indexKey;
  const indexKey = Object.freeze({
    namespaceId: sourceKey.namespaceId,
    authorityScopeCid: sourceKey.authorityScopeCid,
    runDefinitionCid: sourceKey.runDefinitionCid,
  });
  return Object.freeze({
    indexKey,
    principalId: input.principalId,
    purpose: input.purpose,
    resultName: input.resultName,
    attemptId: input.attemptId,
    ...(delivery ? {format: input.format} : {}),
  });
}

export class ResultAccessError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new ResultAccessError(code, cause); };

function validateAuthority(configuration) {
  const {authorizeResultDescription, admitResultDescription, ...reads} =
    configuration ?? {};
  if ((authorizeResultDescription !== undefined ||
      admitResultDescription !== undefined) &&
      (typeof authorizeResultDescription !== 'function' ||
       typeof admitResultDescription !== 'function')) {
    fail('InvalidResultAccessAuthority');
  }
  if (!(exactKeys(reads, [
    'authorizeResultReadRequest', 'admitResultRead',
    'authorizeResultRead',
  ]) || exactKeys(reads, [
    'authorizeResultReadRequest', 'admitResultRead',
    'authorizeResultRead', 'authorizeDeliveryAttemptLookup',
  ])) || typeof configuration.authorizeResultReadRequest !== 'function' ||
      typeof configuration.admitResultRead !== 'function' ||
      typeof configuration.authorizeResultRead !== 'function' ||
      configuration.authorizeDeliveryAttemptLookup !== undefined &&
        typeof configuration.authorizeDeliveryAttemptLookup !== 'function') {
    fail('InvalidResultAccessAuthority');
  }
}

export function installResultAccessAuthority(configuration) {
  validateAuthority(configuration);
  const authority = Object.freeze({});
  authorities.set(authority, Object.freeze({
    authorizeResultReadRequest: configuration.authorizeResultReadRequest,
    admitResultRead: configuration.admitResultRead,
    authorizeResultRead: configuration.authorizeResultRead,
    authorizeDeliveryAttemptLookup:
      configuration.authorizeDeliveryAttemptLookup,
    authorizeResultDescription: configuration.authorizeResultDescription,
    admitResultDescription: configuration.admitResultDescription,
  }));
  return authority;
}

export async function describeAuthorizedResult(service, input, signal) {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const {maxWireBytes, maxNodes, maxDepth, ...readInput} = input ?? {};
  const request = ownedResultRequest(readInput, true);
  validateRequest(request);
  const limits = Object.freeze({maxWireBytes, maxNodes, maxDepth});
  if (!Object.keys(resultDescriptionLimits).every(key =>
    positive(limits[key]) && limits[key] <= resultDescriptionLimits[key])) {
    fail('InvalidResultAccessRequest');
  }
  const {store, control, authority, now} = installed;
  if (typeof authority.authorizeResultDescription !== 'function' ||
      typeof authority.admitResultDescription !== 'function' ||
      typeof store.readCommittedResultDescriptionEvidence !== 'function' ||
      typeof store.consumeManifestReadGrant !== 'function' ||
      ['describeCommittedResult', 'resultMetadataRetentionState',
        'issueManifestReadGrant', 'manifestReadGrantAllowsBytes',
        'manifestReadGrantValidAt'].some(name =>
        typeof control[name] !== 'function')) {
    fail('ClientOperationUnavailable');
  }
  signal?.throwIfAborted();
  const authorize = async facts => {
    let allowed;
    try { allowed = await authority.authorizeResultDescription(facts); }
    catch { fail('ResultAccessDenied'); }
    if (allowed !== true) fail('ResultAccessDenied');
    signal?.throwIfAborted();
  };
  await authorize(Object.freeze({...request, stage: 'request'}));
  let entry, index, manifest, retention, evidence;
  try {
    entry = await store.confirmCommittedIndex(request.indexKey);
    if (entry === undefined) fail('ResultAccessDenied');
    index = await store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry');
    manifest = await store.readPublicationContract(
      entry.result_manifest_cid, 'result_manifest');
    const definitionCid = control.resultReadDefinitionCid(
      manifest, request.resultName);
    retention = await store.readPublicationContract(
      control.resultReadRetentionPolicyCid(manifest, request.resultName),
      'result_retention_policy');
    evidence = await store.readCommittedResultDescriptionEvidence(
      request.indexKey, definitionCid);
  } catch (error) {
    if (error?.code === 'PublicationLookupDenied') fail('ResultAccessDenied');
    if (['PublicationObjectMissing', 'PublicationContractMissing']
      .includes(error?.code)) {
      fail('ResultDescriptionUnavailable', error);
    }
    throw error;
  }
  const effectiveRetention = evidence.retained?.extension ?? retention;
  const clockCid = control.resultRetentionClockContractCid(retention);
  const checkRetained = async () => {
    const at = observedAt(now);
    await store.observeTrustedClock(clockCid, at);
    // Validate the stored extension's exact base binding using its owner.
    if (evidence.retained !== undefined) {
      control.resultReadExtendedAvailability(manifest, request.resultName,
        retention, effectiveRetention, at);
    }
    if (control.resultMetadataRetentionState(effectiveRetention, at) !==
        'retained') fail('ResultDescriptionUnavailable');
    return at;
  };
  const at = await checkRetained();
  const facts = Object.freeze({...request, index, manifest,
    retention: effectiveRetention, observedAt: at});
  const admission = await authority.admitResultDescription(facts);
  validateAdmission(admission);
  // Metadata consumes the existing Manifest grant, not a payload delivery.
  const grant = control.issueManifestReadGrant(index, manifest, {
    principalId: request.principalId, purpose: request.purpose,
    dataCeilingCid: admission.dataCeilingCid,
    maxBytes: admission.maxBytes, maxUses: admission.maxUses,
    expiresAt: admission.expiresAt,
    authorizationContextCid: admission.authorizationContextCid,
  }, installed.limits);
  const authorizedFacts = Object.freeze({...facts, grant,
    authorizationContextCid: admission.authorizationContextCid,
    egressAdmissionCid: admission.egressAdmissionCid});
  await authorize(Object.freeze({...authorizedFacts, stage: 'read'}));
  const response = Object.freeze({ref: request.indexKey,
    ...control.describeCommittedResult(index, manifest, request.resultName,
      evidence.bindings, evidence.definition, evidence.schemaWire,
      request.format, installed.limits)});
  if (!withinResultDescriptionLimits(response, limits)) {
    fail('ResultDescriptionTooLarge');
  }
  if (!validResultDescription(response, {ref: request.indexKey,
    resultName: request.resultName, format: request.format}, limits)) {
    fail('InvalidResultDescription');
  }
  const byteCount = new TextEncoder().encode(JSON.stringify(response)).length;
  if (!control.manifestReadGrantAllowsBytes(grant, byteCount) ||
      !control.manifestReadGrantValidAt(grant, await checkRetained())) {
    fail('ResultAccessDenied');
  }
  await store.consumeManifestReadGrant(grant.wire, request.attemptId);
  await authorize(Object.freeze({...authorizedFacts, stage: 'response'}));
  if (!control.manifestReadGrantValidAt(grant, await checkRetained())) {
    fail('ResultAccessDenied');
  }
  if ((await store.confirmCommittedIndex(request.indexKey))
        ?.public_index_entry_cid !== entry.public_index_entry_cid) {
    fail('ResultDescriptionUnavailable');
  }
  signal?.throwIfAborted();
  return response;
}

function validateServiceConfiguration(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'createDigest', 'limits',
    'frameLimits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      typeof configuration.store.observeTrustedClock !== 'function' ||
      typeof configuration.store.readCommittedResultRetentionExtension !==
        'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.issueResultReadGrant !== 'function' ||
      typeof configuration.control.resultReadRetentionPolicyCid !==
        'function' ||
      typeof configuration.control.resultReadAvailability !== 'function' ||
      typeof configuration.control.resultReadExtendedAvailability !==
        'function' ||
      typeof configuration.control.resultReadDefinitionCid !== 'function' ||
      typeof configuration.control.resultRetentionClockContractCid !==
        'function' ||
      typeof configuration.control.resultReadGrantValidAt !== 'function' ||
      typeof configuration.control.beginResultAccessProgress !== 'function' ||
      typeof configuration.control.resultAccessProgressAction !== 'function' ||
      typeof configuration.control
        .recordResultAccessRequestAuthorization !== 'function' ||
      typeof configuration.control.recordResultAccessResolution !==
        'function' ||
      typeof configuration.control.recordResultAccessInitialAvailability !==
        'function' ||
      typeof configuration.control.recordResultAccessReadAdmission !==
        'function' ||
      typeof configuration.control.recordResultAccessGrant !== 'function' ||
      !authorities.has(configuration.authority) ||
      typeof configuration.now !== 'function' ||
      typeof configuration.createDigest !== 'function' ||
      !exactKeys(configuration.limits, [
        'maxWireBytes', 'maxNodes', 'maxDepth',
      ]) || !Object.values(configuration.limits).every(positive) ||
      !exactKeys(configuration.frameLimits, [
        'maxRowBytes', 'maxDepth', 'maxFrameBytes',
      ]) || !Object.values(configuration.frameLimits).every(positive)) {
    fail('InvalidResultAccessService');
  }
}

export function installResultAccessService(configuration) {
  validateServiceConfiguration(configuration);
  const service = Object.freeze({});
  services.set(service, Object.freeze({
    store: configuration.store,
    control: configuration.control,
    authority: authorities.get(configuration.authority),
    now: configuration.now,
    createDigest: configuration.createDigest,
    limits: Object.freeze({...configuration.limits}),
    frameLimits: Object.freeze({...configuration.frameLimits}),
  }));
  return service;
}

export async function inspectAuthorizedDeliveryAttempt(service, input) {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const request = ownedResultRequest(input, false);
  if (typeof request.indexKey.namespaceId !== 'string' ||
      !request.indexKey.namespaceId ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' || !request.principalId ||
      typeof request.purpose !== 'string' || !request.purpose ||
      typeof request.resultName !== 'string' || !request.resultName ||
      typeof request.attemptId !== 'string' || !request.attemptId ||
      request.attemptId.length > 256) {
    fail('InvalidResultAccessRequest');
  }
  const authorize = installed.authority.authorizeDeliveryAttemptLookup;
  if (typeof authorize !== 'function' ||
      typeof installed.store.lookupDeliveryAttempt !== 'function') {
    fail('ResultAttemptLookupUnavailable');
  }
  let allowed;
  try { allowed = await authorize(request); }
  catch { fail('ResultAccessDenied'); }
  if (allowed !== true) fail('ResultAccessDenied');
  const found = await installed.store.lookupDeliveryAttempt(request);
  if (found === undefined) return Object.freeze({kind: 'not_found'});
  const reply = Object.freeze({kind: 'found',
    attempt: found.attempt, record: found.record ?? null,
    hostReleaseReceipt: found.hostReleaseReceipt ?? null});
  if (!validDeliveryAttemptLookup(reply, {
    attemptId: request.attemptId,
    runDefinitionCid: request.indexKey.runDefinitionCid,
    resultName: request.resultName,
  })) {
    fail('InvalidDeliveryAttemptLookup');
  }
  return reply;
}

function validateRequest(request) {
  if (!exactKeys(request, [
    'indexKey', 'principalId', 'purpose', 'resultName', 'format',
    'attemptId',
  ]) || !exactKeys(request.indexKey, [
    'namespaceId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.namespaceId !== 'string' ||
      request.indexKey.namespaceId.length === 0 ||
      !cidPattern.test(request.indexKey.authorityScopeCid) ||
      !cidPattern.test(request.indexKey.runDefinitionCid) ||
      typeof request.principalId !== 'string' ||
      request.principalId.length === 0 ||
      typeof request.purpose !== 'string' || request.purpose.length === 0 ||
      typeof request.resultName !== 'string' ||
      request.resultName.length === 0 ||
      !['json', 'jsonl', 'csv'].includes(request.format) ||
      typeof request.attemptId !== 'string' ||
      request.attemptId.length === 0) {
    fail('InvalidResultAccessRequest');
  }
}

function validateAdmission(admission) {
  if (!exactKeys(admission, [
    'authorizationContextCid', 'dataCeilingCid', 'egressAdmissionCid',
    'expiresAt', 'maxBytes', 'maxUses',
  ]) || !cidPattern.test(admission.authorizationContextCid) ||
      !cidPattern.test(admission.dataCeilingCid) ||
      !cidPattern.test(admission.egressAdmissionCid) ||
      typeof admission.expiresAt !== 'string' ||
      admission.expiresAt.length === 0 ||
      !Number.isSafeInteger(admission.maxBytes) || admission.maxBytes < 0 ||
      !positive(admission.maxUses)) {
    fail('InvalidResultReadAdmission');
  }
}

function observedAt(now) {
  const value = now();
  if (typeof value !== 'string' || value.length === 0) {
    fail('InvalidResultAccessClock');
  }
  return value;
}

export async function deliverAuthorizedResult(
  service,
  input,
  sink,
  signal,
) {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  const request = ownedResultRequest(input, true);
  validateRequest(request);
  if (sink === null || typeof sink !== 'object' ||
      typeof sink.write !== 'function' ||
      typeof sink.finish !== 'function' || signal !== undefined &&
      (signal === null || typeof signal.throwIfAborted !== 'function')) {
    fail('InvalidResultAccessRequest');
  }
  signal?.throwIfAborted();
  const progress = installed.control.beginResultAccessProgress();
  const requireAction = expected => {
    if (installed.control.resultAccessProgressAction(progress) !== expected) {
      fail('InvalidResultAccessProgress');
    }
  };
  requireAction('authorize_request');
  const indexKey = request.indexKey;
  let requestAuthorized = false;
  try {
    requestAuthorized = await installed.authority
      .authorizeResultReadRequest(Object.freeze({
        indexKey,
        principalId: request.principalId,
        purpose: request.purpose,
        resultName: request.resultName,
        format: request.format,
        attemptId: request.attemptId,
      }));
  } catch {
    installed.control.recordResultAccessRequestAuthorization(progress, false);
    fail('ResultAccessDenied');
  }
  signal?.throwIfAborted();
  installed.control.recordResultAccessRequestAuthorization(
    progress, requestAuthorized === true,
  );
  if (requestAuthorized !== true) fail('ResultAccessDenied');
  requireAction('resolve_committed_result');
  let entry;
  let index;
  let manifest;
  let retention;
  let retained;
  try {
    entry = await installed.store.confirmCommittedIndex(indexKey);
    if (entry === undefined) {
      installed.control.recordResultAccessResolution(progress, false);
      fail('ResultAccessDenied');
    }
    index = await installed.store.readPublicationContract(
      entry.public_index_entry_cid, 'public_index_entry',
    );
    manifest = await installed.store.readPublicationContract(
      entry.result_manifest_cid, 'result_manifest',
    );
    const retentionPolicyCid =
      installed.control.resultReadRetentionPolicyCid(
        manifest, request.resultName,
      );
    retention = await installed.store.readPublicationContract(
      retentionPolicyCid, 'result_retention_policy',
    );
    const resultDefinitionCid = installed.control.resultReadDefinitionCid(
      manifest, request.resultName,
    );
    retained = await installed.store.readCommittedResultRetentionExtension(
      indexKey, resultDefinitionCid,
    );
  } catch (error) {
    if (installed.control.resultAccessProgressAction(progress) ===
        'resolve_committed_result') {
      installed.control.recordResultAccessResolution(progress, false);
    }
    if (error?.code === 'PublicationObjectMissing') {
      fail('ResultUnavailable', error);
    }
    throw error;
  }
  installed.control.recordResultAccessResolution(progress, true);
  const admittedAt = observedAt(installed.now);
  const availability = observed => retained === undefined
    ? installed.control.resultReadAvailability(
      manifest, request.resultName, retention, observed,
    )
    : installed.control.resultReadExtendedAvailability(
      manifest,
      request.resultName,
      retention,
      retained.extension,
      observed,
    );
  const clockContractCid =
    installed.control.resultRetentionClockContractCid(retention);
  await installed.store.observeTrustedClock(clockContractCid, admittedAt);
  const initiallyAvailable = availability(admittedAt) === 'available';
  requireAction('check_initial_availability');
  installed.control.recordResultAccessInitialAvailability(
    progress, initiallyAvailable,
  );
  if (!initiallyAvailable) {
    fail('ResultUnavailable');
  }
  const requestFacts = Object.freeze({
    indexKey,
    index,
    manifest,
    principalId: request.principalId,
    purpose: request.purpose,
    resultName: request.resultName,
    format: request.format,
    attemptId: request.attemptId,
    retention: retained?.extension ?? retention,
    baseRetention: retention,
    observedAt: admittedAt,
  });
  requireAction('admit_read');
  let admission;
  try {
    admission = await installed.authority.admitResultRead(requestFacts);
    validateAdmission(admission);
  } catch (error) {
    installed.control.recordResultAccessReadAdmission(progress, false);
    throw error;
  }
  installed.control.recordResultAccessReadAdmission(progress, true);
  requireAction('issue_grant');
  let grant;
  try {
    grant = installed.control.issueResultReadGrant(
      index,
      manifest,
      {
        resultNames: [request.resultName],
        formats: [request.format],
        principalId: request.principalId,
        purpose: request.purpose,
        dataCeilingCid: admission.dataCeilingCid,
        maxBytes: admission.maxBytes,
        maxUses: admission.maxUses,
        expiresAt: admission.expiresAt,
        authorizationContextCid: admission.authorizationContextCid,
        egressAdmissionCid: admission.egressAdmissionCid,
      },
      installed.limits,
    );
  } catch (error) {
    installed.control.recordResultAccessGrant(progress, false);
    throw error;
  }
  installed.control.recordResultAccessGrant(progress, true);
  requireAction('start_delivery');
  const authorize = async facts => {
    await installed.store.observeTrustedClock(
      clockContractCid, facts.observedAt,
    );
    if (availability(facts.observedAt) !== 'available') {
      return false;
    }
    const allowed = await installed.authority.authorizeResultRead(
      Object.freeze({
        ...requestFacts,
        grant,
        authorizationContextCid: admission.authorizationContextCid,
        egressAdmissionCid: admission.egressAdmissionCid,
        delivery: facts,
      }),
    );
    if (allowed !== true) return false;
    const authorizedAt = observedAt(installed.now);
    await installed.store.observeTrustedClock(
      clockContractCid, authorizedAt,
    );
    const usableAt = observedAt(installed.now);
    return availability(usableAt) === 'available' &&
      installed.control.resultReadGrantValidAt(grant, usableAt);
  };
  return deliverPublishedResult({
    store: installed.store,
    control: installed.control,
    indexKey,
    grant,
    resultName: request.resultName,
    format: request.format,
    attemptId: request.attemptId,
    limits: installed.limits,
    frameLimits: installed.frameLimits,
    now: installed.now,
    sink,
    createDigest: installed.createDigest,
    authorize,
    signal,
  });
}

// Installed Host authority for current Result read and egress admission.
// MoonBit owns grant and delivery semantics. This module keeps caller input
// separate from Host-owned authorization and delegates physical effects.
import {deliverPublishedResult} from './result-delivery.mjs';

const authorities = new WeakMap();
const services = new WeakMap();
const cidPattern = /^sha256:[0-9a-f]{64}$/u;
const exactKeys = (value, keys) => value !== null &&
  typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const positive = value => Number.isSafeInteger(value) && value > 0;

export class ResultAccessError extends Error {
  constructor(code, cause) {
    super(code, cause === undefined ? undefined : {cause});
    this.code = code;
    this.primaryFailure = cause;
  }
}

const fail = (code, cause) => { throw new ResultAccessError(code, cause); };

function validateAuthority(configuration) {
  if (!exactKeys(configuration, [
    'admitResultRead', 'authorizeResultRead',
  ]) || typeof configuration.admitResultRead !== 'function' ||
      typeof configuration.authorizeResultRead !== 'function') {
    fail('InvalidResultAccessAuthority');
  }
}

export function installResultAccessAuthority(configuration) {
  validateAuthority(configuration);
  const authority = Object.freeze({});
  authorities.set(authority, Object.freeze({
    admitResultRead: configuration.admitResultRead,
    authorizeResultRead: configuration.authorizeResultRead,
  }));
  return authority;
}

function validateServiceConfiguration(configuration) {
  if (!exactKeys(configuration, [
    'store', 'control', 'authority', 'now', 'createDigest', 'limits',
    'frameLimits',
  ]) || configuration.store === null ||
      typeof configuration.store !== 'object' ||
      typeof configuration.store.confirmCommittedIndex !== 'function' ||
      typeof configuration.store.readPublicationContract !== 'function' ||
      configuration.control === null ||
      typeof configuration.control !== 'object' ||
      typeof configuration.control.issueResultReadGrant !== 'function' ||
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

function validateRequest(request) {
  if (!exactKeys(request, [
    'indexKey', 'principalId', 'purpose', 'resultName', 'format',
    'attemptId',
  ]) || !exactKeys(request.indexKey, [
    'tenantId', 'authorityScopeCid', 'runDefinitionCid',
  ]) || typeof request.indexKey.tenantId !== 'string' ||
      request.indexKey.tenantId.length === 0 ||
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
  request,
  sink,
  signal,
) {
  const installed = services.get(service) ?? fail('ForeignResultAccessService');
  validateRequest(request);
  if (sink === null || typeof sink !== 'object' ||
      typeof sink.write !== 'function' || signal !== undefined &&
      (signal === null || typeof signal.throwIfAborted !== 'function')) {
    fail('InvalidResultAccessRequest');
  }
  signal?.throwIfAborted();
  const indexKey = Object.freeze({...request.indexKey});
  const entry = await installed.store.confirmCommittedIndex(indexKey);
  if (entry === undefined) fail('ResultAccessDenied');
  const index = await installed.store.readPublicationContract(
    entry.public_index_entry_cid, 'public_index_entry',
  );
  const manifest = await installed.store.readPublicationContract(
    entry.result_manifest_cid, 'result_manifest',
  );
  const admittedAt = observedAt(installed.now);
  const requestFacts = Object.freeze({
    indexKey,
    index,
    manifest,
    principalId: request.principalId,
    purpose: request.purpose,
    resultName: request.resultName,
    format: request.format,
    attemptId: request.attemptId,
    observedAt: admittedAt,
  });
  const admission = await installed.authority.admitResultRead(requestFacts);
  validateAdmission(admission);
  const grant = installed.control.issueResultReadGrant(
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
  const authorize = facts => installed.authority.authorizeResultRead(
    Object.freeze({
      ...requestFacts,
      grant,
      authorizationContextCid: admission.authorizationContextCid,
      egressAdmissionCid: admission.egressAdmissionCid,
      delivery: facts,
    }),
  );
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

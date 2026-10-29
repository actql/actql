import {runtimeField, runtimeIsError, runtimeIsBoxedNone, runtimeIsOk, runtimeIsBoxedSome} from './compiler-binding.generated.mjs';
import * as owner from './dist/remote_coordinator_abi.js';

const siteInteger = value => typeof value === 'bigint' && value >= 0n &&
  value <= 9223372036854775807n;
const siteOptionalInteger = value => value == null || siteInteger(value);
const siteArray = (value, valid) => {
  if (!Array.isArray(value) || value.length > 64) return false;
  // Array.every skips holes; every supplied slot must be a typed observation.
  for (let index = 0; index < value.length; index++) {
    if (!Object.hasOwn(value, index) || !valid(value[index])) return false;
  }
  return true;
};
const siteBoolean = value => typeof value === 'boolean';
const invalidSiteInput = () => { throw new TypeError('InvalidSitePlanningInput'); };

// Pure planning over trusted current observations. This is the existing common
// Site selector, not remote authentication, resource admission or a dispatch.
export const sitePlanning = Object.freeze({
  plan: input => {
    if (input === null || typeof input !== 'object' ||
        !['durationMilliseconds', 'startupMilliseconds', 'transferMilliseconds']
          .every(key => siteOptionalInteger(input[key])) ||
        !['capacitySupported', 'acceptsTransfer', 'transferProviderAvailable']
          .every(key => siteBoolean(input[key])) ||
        !['transferRequired', 'sharedTransfer', 'sourceRevoked', 'estimateAvailable']
          .every(key => siteArray(input[key], siteBoolean)) ||
        !['transferBytes', 'retainedBytes', 'executionBytes']
          .every(key => siteArray(input[key], siteInteger))) invalidSiteInput();
    const result = owner.coordinatorPlanSiteCandidate(
      input.durationMilliseconds ?? undefined, input.startupMilliseconds ?? undefined,
      input.capacitySupported, input.acceptsTransfer,
      input.transferProviderAvailable, input.transferMilliseconds ?? undefined,
      input.transferRequired, input.sharedTransfer, input.sourceRevoked,
      input.estimateAvailable, input.transferBytes, input.retainedBytes,
      input.executionBytes);
    const code = runtimeField(result, 0), duration = runtimeField(result, 1);
    return Object.freeze({code, durationMilliseconds: code === 0 ? duration : null});
  },
  select: (durations, keys) => {
    if (!siteArray(durations, siteInteger) || !siteArray(keys, value =>
      typeof value === 'string' && value.length > 0 && value.length <= 256 &&
      !/[\u0000-\u001f\u007f]/u.test(value))) invalidSiteInput();
    return owner.coordinatorSelectSiteCandidate(durations, keys);
  },
});

function checked(result) {
  if (runtimeIsOk(result)) return runtimeField(result, 0);
  if (runtimeIsError(result)) {
    throw Object.assign(new Error('CoordinatorOwnerRejected', {cause: runtimeField(result, 0)}),
      {code: 'CoordinatorOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidCoordinatorOwnerResult'),
    {code: 'InvalidCoordinatorOwnerResult'});
}

// Portable construction/admission only. Context is not retained readiness;
// persist the original returned binding JSON/CID before requesting retention.
export const bundleRetention = Object.freeze({
  prepareDistribution: members => checked(
    owner.coordinatorBundleDistributionPrepare(members)),
  distributionIdentity: owner.coordinatorBundleDistributionIdentity,
  distributionJson: value => checked(owner.coordinatorBundleDistributionJson(value)),
  distributionProjection: owner.coordinatorBundleDistributionProjection,
  distributionContains: owner.coordinatorBundleDistributionContains,
  admitDistributionJson: (body, cid) => checked(
    owner.coordinatorBundleDistributionAdmitJson(body, cid)),
  prepareHoldScope: value => checked(owner.coordinatorBundleHoldScopePrepare(
    value.distribution, value.coordinatorAuthority, value.workspaceId,
    value.authorityScopeCid, value.environment, value.setRevisionCid,
    value.runtimeBundleCid, value.siteKey, value.siteGeneration, value.attemptId)),
  holdScopeIdentity: owner.coordinatorBundleHoldScopeIdentity,
  holdScopeJson: value => checked(owner.coordinatorBundleHoldScopeJson(value)),
  holdScopeProjection: owner.coordinatorBundleHoldScopeProjection,
  admitHoldScopeJson: (distribution, body, cid) => checked(
    owner.coordinatorBundleHoldScopeAdmitJson(distribution, body, cid)),
  holdBindingIdentity: owner.coordinatorBundleHoldBindingIdentity,
  holdBindingJson: value => checked(owner.coordinatorBundleHoldBindingJson(value)),
  holdBindingProjection: owner.coordinatorBundleHoldBindingProjection,
  holdBindingScope: value => checked(owner.coordinatorBundleHoldBindingScope(value)),
  admitHoldBindingJson: (distribution, body, cid) => checked(
    owner.coordinatorBundleHoldBindingAdmitJson(distribution, body, cid)),
  prepareCustodyContextQuery: (distribution, scope) => checked(
    owner.coordinatorBundleCustodyContextQueryPrepare(distribution, scope)),
  prepareCustodyRequest: (distribution, binding, operation) => checked(
    owner.coordinatorBundleCustodyRequestPrepare(distribution, binding, operation)),
  custodyRequestIdentity: owner.coordinatorBundleCustodyRequestIdentity,
  custodyRequestJson: value => checked(owner.coordinatorBundleCustodyRequestJson(value)),
  custodyRequestOperation: owner.coordinatorBundleCustodyRequestOperation,
  custodyRequestScope: owner.coordinatorBundleCustodyRequestScope,
  custodyRequestBinding: value => owner.coordinatorBundleCustodyRequestBindings(value)[0],
  admitCustodyRequestJson: (body, cid) => checked(
    owner.coordinatorBundleCustodyRequestAdmitJson(body, cid)),
  admitCustodyResponseJson: (request, body, cid) => checked(
    owner.coordinatorBundleCustodyResponseAdmitJson(request, body, cid)),
  custodyResponseIdentity: owner.coordinatorBundleCustodyResponseIdentity,
  custodyResponseJson: value => checked(owner.coordinatorBundleCustodyResponseJson(value)),
  custodyResponseKind: owner.coordinatorBundleCustodyResponseKind,
  custodyResponseBinding: owner.coordinatorBundleCustodyResponseBinding,
  custodyResponseObservation: owner.coordinatorBundleCustodyResponseObservationText,
  custodyResponseCatalog: value =>
    owner.coordinatorBundleCustodyResponseCatalogText(value) || undefined,
  custodyResponseRevision: value => {
    const revision = owner.coordinatorBundleCustodyResponseRevisionText(value);
    return revision === '' ? undefined : Number(revision);
  },
});

export const createJournal = authority =>
  checked(owner.coordinatorCreateJournal(authority));

// Only after the exact successful Output record was durably committed.
export const outputReportAckJson = (record, originalReport) =>
  checked(owner.coordinatorOutputReportAckJson(record, originalReport));

// The receiver must first establish this current, definitive refusal.
export const outputReportRefusalJson = (record, originalReport, reason) =>
  checked(owner.coordinatorOutputReportRefusalJson(record, originalReport, reason));

// These handles carry canonical metadata, not persistence or approval proof.
// Keep the admitted common value private so a caller cannot forge a report by
// copying fields or pass an unrelated owner handle to reply construction.
const effectCheckpointHandles = new WeakMap();
const effectCheckpointValue = handle => {
  const value = effectCheckpointHandles.get(handle);
  if (value === undefined) throw new TypeError('InvalidEffectCheckpointReport');
  return value;
};
const effectResumeAuthenticationFields = ['key_id', 'reviewer_id',
  'expected_authority_scope_cid', 'authority_context_cid', 'policy_cid', 'proof_preimage'];
const snapshotTextRecord = (value, fields) => {
  if (value === null || typeof value !== 'object' ||
      Object.keys(value).length !== fields.length ||
      !fields.every(key => Object.hasOwn(value, key))) return null;
  const snapshot = fields.map(key => value[key]);
  return snapshot.every(item => typeof item === 'string') ? snapshot : null;
};

// This only serializes an original, approved common Resolution. Authenticate
// and persist the claim through the existing Run Owner, then fence immediately
// before handout. A transported claim is never a current Site observation.
const prepareEffectResumeDeliveryJson = (serialize, report, resolutionWire, authentication, reviewers, claim, limits) => {
  const invalid = () => { throw new TypeError('InvalidEffectResumeDeliveryInput'); };
  if (typeof resolutionWire !== 'string' || !Array.isArray(reviewers)) invalid();
  const count = reviewers.length;
  if (count > 64 || claim === null || typeof claim !== 'object' || Object.keys(claim).length !== 2 ||
      !Object.hasOwn(claim, 'claimant') || !Object.hasOwn(claim, 'generation') ||
      limits === null || typeof limits !== 'object') invalid();
  // Snapshot caller values once; validation and the Owner see the same facts.
  const claimant = claim.claimant, generation = claim.generation;
  const bounds = [limits.maxWireBytes, limits.maxNodes, limits.maxDepth];
  if (typeof claimant !== 'string' || claimant.length === 0 || claimant.length > 256 ||
      !siteInteger(generation) || generation === 0n ||
      !bounds.every((value, index) => Number.isSafeInteger(value) && value > 0 &&
        value <= [262144, 4096, 32][index])) invalid();
  const fields = snapshotTextRecord(authentication, effectResumeAuthenticationFields);
  if (fields === null) invalid();
  const keys = [], ids = [];
  for (let index = 0; index < count; index++) {
    if (!Object.hasOwn(reviewers, index)) invalid();
    const pair = snapshotTextRecord(reviewers[index], ['key_id', 'reviewer_id']);
    if (pair === null) invalid();
    keys.push(pair[0]);
    ids.push(pair[1]);
  }
  const utf8 = new TextEncoder();
  // UTF-16 length is a safe lower bound on UTF-8 bytes. Reject first so the
  // encoder cannot allocate an arbitrarily large buffer for a refused input.
  const byteLength = (value, maximum) => {
    if (value.length > maximum) invalid();
    const length = utf8.encode(value).length;
    if (length > maximum) invalid();
    return length;
  };
  byteLength(claimant, 256);
  let remaining = bounds[0];
  for (const value of [resolutionWire, ...fields, ...keys, ...ids]) {
    remaining -= byteLength(value, remaining);
  }
  return checked(serialize(effectCheckpointValue(report),
    resolutionWire, fields, keys, ids, claimant, generation, ...bounds));
};
export const effectResumeDeliveries = Object.freeze({
  prepareJson: (...args) => prepareEffectResumeDeliveryJson(owner.coordinatorEffectResumeDeliveryJson, ...args),
  preparePollJson: (...args) => prepareEffectResumeDeliveryJson(owner.coordinatorEffectResumePollJson, ...args),
});
const effectCurrentQueries = new WeakMap(), effectCurrentReplies = new WeakMap();
const effectCurrentValue = (values, handle) => {
  const value = values.get(handle);
  if (value === undefined) throw new TypeError('InvalidEffectCurrentHandle');
  return value;
};
const effectCurrentLimits = supplied => {
  if (supplied === null || typeof supplied !== 'object') throw new TypeError('InvalidEffectCurrentLimits');
  const names = ['maxWireBytes', 'maxNodes', 'maxDepth'], values = names.map(name => supplied[name]);
  if (!values.every((value, index) => Number.isSafeInteger(value) && value > 0 && value <= [65536, 4096, 32][index])) {
    throw new TypeError('InvalidEffectCurrentLimits');
  }
  return values;
};
const effectCurrentText = value => {
  if (typeof value !== 'string' || value.length === 0 || value.length > 256 ||
      new TextEncoder().encode(value).length > 256) throw new TypeError('InvalidEffectCurrentInput');
  return value;
};
export const effectCurrentObservations = Object.freeze({
  prepareQuery: (report, effectId, queryId, limits) => {
    const bounds = effectCurrentLimits(limits);
    const value = checked(owner.coordinatorEffectCurrentQueryPrepare(effectCheckpointValue(report),
      effectCurrentText(effectId), effectCurrentText(queryId), ...bounds));
    const handle = Object.freeze({}); effectCurrentQueries.set(handle, value); return handle;
  },
  queryJson: query => owner.coordinatorEffectCurrentQueryProjection(effectCurrentValue(effectCurrentQueries, query))[0],
  pollJson: query => checked(owner.coordinatorEffectCurrentPollJson(effectCurrentValue(effectCurrentQueries, query))),
  queryFacts: query => {
    const [, queryCid, reportCid, dispatchCid, checkpointCid, effectId, queryId] =
      owner.coordinatorEffectCurrentQueryProjection(effectCurrentValue(effectCurrentQueries, query));
    return Object.freeze({queryCid, reportCid, dispatchCid, checkpointCid, effectId, queryId});
  },
  admitReplyJson: (query, body, limits) => {
    const bounds = effectCurrentLimits(limits);
    if (typeof body !== 'string' || body.length > bounds[0] || new TextEncoder().encode(body).length > bounds[0]) {
      throw new TypeError('InvalidEffectCurrentInput');
    }
    const value = checked(owner.coordinatorEffectCurrentReplyAdmit(effectCurrentValue(effectCurrentQueries, query), body, ...bounds));
    const handle = Object.freeze({}); effectCurrentReplies.set(handle, {value, query}); return handle;
  },
  replyFacts: reply => {
    const {value, query} = effectCurrentValue(effectCurrentReplies, reply);
    const [, replyCid, head, action, saved] = owner.coordinatorEffectCurrentReplyProjection(value);
    const facts = effectCurrentObservations.queryFacts(query), recoveryAction = Number(action);
    return Object.freeze({...facts, replyCid, ledgerHeadCid: head === '' ? undefined : head,
      recoveryAction, responseSaved: saved === 'true',
      unknownEffects: Object.freeze(recoveryAction === 3 || recoveryAction === 4 ? [facts.effectId] : [])});
  },
});
export const effectCheckpointReports = Object.freeze({
  admit: (body, request, limits) => {
    if (typeof body !== 'string' || limits === null || typeof limits !== 'object' ||
        ![['maxWireBytes', 262144], ['maxNodes', 4096], ['maxDepth', 32]]
          .every(([key, maximum]) => Number.isSafeInteger(limits[key]) &&
            limits[key] > 0 && limits[key] <= maximum)) {
      throw new TypeError('InvalidEffectCheckpointReportInput');
    }
    const value = checked(owner.coordinatorEffectCheckpointReportAdmit(body,
      request, limits.maxWireBytes, limits.maxNodes, limits.maxDepth));
    const handle = Object.freeze({});
    effectCheckpointHandles.set(handle, value);
    return handle;
  },
  facts: handle => {
    const [reportCid, dispatchCid, checkpointCid, checkpointWire] =
      owner.coordinatorEffectCheckpointReportProjection(effectCheckpointValue(handle));
    return Object.freeze({reportCid, dispatchCid, checkpointCid, checkpointWire});
  },
  // The receiving Host calls this only after its existing Run Owner confirms
  // the exact waiting commit. This serializer does not perform that commit.
  acceptedJson: handle => checked(owner.coordinatorEffectCheckpointAcceptedJson(
    effectCheckpointValue(handle))),
  refusedJson: (handle, reason) => checked(owner.coordinatorEffectCheckpointRefusedJson(
    effectCheckpointValue(handle), reason)),
  admitReplyJson: (handle, body) => {
    if (typeof body !== 'string') throw new TypeError('InvalidEffectCheckpointReplyInput');
    const [kind, reason] = checked(owner.coordinatorEffectCheckpointReplyAdmit(
      effectCheckpointValue(handle), body));
    return Object.freeze(kind === 'accepted' ? {kind} : {kind, reason});
  },
});

export const prepareDispatch = input => checked(owner.coordinatorPrepareDispatch(
  input.coordinatorAuthority, input.runDefinitionCid, input.taskKey,
  input.taskAttempt, input.dispatchId, input.siteKey, input.siteGeneration,
  input.runtimeBundleCid, input.connectorRegistration,
  input.connectorRevision, input.strategyRevision, input.inputBindingCid,
  input.obligationsCid, input.budgetCid,
  input.evidenceIssuerCapabilityCid, input.grantCid,
));

export const dispatchCid = owner.coordinatorDispatchCid;
export const dispatchJson = request => checked(owner.coordinatorDispatchJson(request));
export const admitDispatchJson = (body, claimedCid) =>
  checked(owner.coordinatorAdmitDispatchJson(body, claimedCid));
export const dispatchRoute = owner.coordinatorDispatchRoute;
export const pollDispatchJson = (request, inputBindingBody,
  maxBindingBytes) => checked(owner.coordinatorPollDispatchJson(
    request, inputBindingBody, maxBindingBytes));
export const pollDispatchMaterialsJson = (request, inputBindingBody,
  maxBindingBytes, runMaterials) => checked(
  owner.coordinatorPollDispatchMaterialsJson(
    request, inputBindingBody, maxBindingBytes, runMaterials));
export const pollQueryJson = request =>
  checked(owner.coordinatorPollQueryJson(request));
export const pollCancelJson = request =>
  checked(owner.coordinatorPollCancelJson(request));
export const pollReleaseJson = request =>
  checked(owner.coordinatorPollReleaseJson(request));
export const admitPollNotSeen = (body, request) =>
  checked(owner.coordinatorAdmitPollNotSeen(body, request));
export const deliveryEnvelopeJson = (request, body) =>
  checked(owner.coordinatorDeliveryEnvelopeJson(request, body));
function validateDeliveryContext(context) {
  if (context === null || typeof context !== 'object' ||
      typeof context.coordinatorAuthority !== 'string' ||
      typeof context.siteKey !== 'string' ||
      !Number.isSafeInteger(context.siteGeneration) ||
      context.siteGeneration < 0 || context.siteGeneration > 2147483647 ||
      typeof context.authorizationCurrent !== 'boolean' ||
      typeof context.cancellationRequested !== 'boolean') {
    throw new TypeError('InvalidCoordinatorRedeliveryContext');
  }
}
export const redeliveryEligible = (record, request, notSeenBody, context) => {
  validateDeliveryContext(context);
  if (typeof notSeenBody !== 'string') {
    throw new TypeError('InvalidCoordinatorRedeliveryContext');
  }
  return checked(owner.coordinatorRedeliveryEligible(record, request,
    notSeenBody, context.coordinatorAuthority, context.siteKey,
    context.siteGeneration, context.authorizationCurrent,
    context.cancellationRequested));
};
export const initialDeliveryEligible = (record, request, context) => {
  validateDeliveryContext(context);
  if (typeof context.outcomePersistedBeforeEverySend !== 'boolean') {
    throw new TypeError('InvalidCoordinatorInitialDeliveryContext');
  }
  return checked(owner.coordinatorInitialDeliveryEligible(record, request,
    context.coordinatorAuthority, context.siteKey, context.siteGeneration,
    context.authorizationCurrent, context.cancellationRequested,
    context.outcomePersistedBeforeEverySend));
};
export const prepareIntent = (journal, request) =>
  checked(owner.coordinatorPrepareIntent(journal, request));
export const intentIsNew = owner.coordinatorIntentIsNew;
export const admissionDurableJson = admission =>
  checked(owner.coordinatorAdmissionDurableJson(admission));
export const commitIntent = admission =>
  checked(owner.coordinatorCommitIntent(admission));
export const admitDurableJson = body =>
  checked(owner.coordinatorAdmitDurableJson(body));
export const restoreDurable = (journal, durable) =>
  checked(owner.coordinatorRestoreDurable(journal, durable));
export const durableRevision = owner.coordinatorDurableRevision;
export const durableDispatchCid = owner.coordinatorDurableDispatchCid;
export const durableRequest = owner.coordinatorDurableRequest;
export const acceptedSiteOutput = durable => {
  const option = checked(owner.coordinatorAcceptedSiteOutput(durable));
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option) || !Array.isArray(runtimeField(option, 0)) ||
      runtimeField(option, 0).length !== 14 ||
      !runtimeField(option, 0).every(value => typeof value === 'string')) {
    throw Object.assign(new Error('InvalidCoordinatorOutputProjection'),
      {code: 'InvalidCoordinatorOutputProjection'});
  }
  const [evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid] = runtimeField(option, 0);
  return Object.freeze({evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid});
};
// An admitted transport candidate still requires the original Run's trusted
// Source, policy and authorization checks before Invocation/publication.
export const acceptedSourceObservation = durable => {
  const option = owner.coordinatorAcceptedSourceObservation(durable);
  if (runtimeIsBoxedNone(option)) return undefined;
  if (!runtimeIsBoxedSome(option) || !Array.isArray(runtimeField(option, 0)) ||
      runtimeField(option, 0).length !== 5 ||
      !runtimeField(option, 0).every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorSourceObservationProjection');
  }
  const [ordinal, sourceEvidenceWire, inputLogicalWire,
    captureStartedAt, captureCompletedAt] = runtimeField(option, 0);
  const taskOrdinal = Number(ordinal);
  if (!Number.isSafeInteger(taskOrdinal) || taskOrdinal < 0 ||
      String(taskOrdinal) !== ordinal) {
    throw new Error('InvalidCoordinatorSourceObservationProjection');
  }
  return Object.freeze({taskOrdinal, sourceEvidenceWire, inputLogicalWire,
    captureStartedAt, captureCompletedAt});
};
export const issueOutputPlanPollJson = (durable, input) => {
  const integer = value => typeof value === 'bigint'
    ? value > 0n && value <= 9223372036854775807n
    : Number.isSafeInteger(value) && value > 0;
  if (input === null || typeof input !== 'object' ||
      !['storeAuthorityCid', 'publicationAttemptCid',
        'resultDefinitionCid', 'orderingEvidenceCid',
        'coordinatorAuthority', 'transferAttempt', 'destinationSiteKey',
        'sourceGrantCid', 'destinationGrantCid', 'routeCapabilityCid',
        'transferOrigin'].every(key => typeof input[key] === 'string') ||
      input.transferRoute !== 'direct' && input.transferRoute !== 'store' ||
      !Number.isSafeInteger(input.destinationSiteGeneration) ||
      input.destinationSiteGeneration < 0 ||
      input.destinationSiteGeneration > 2147483647 ||
      !integer(input.transferMaxBytes) ||
      !integer(input.transferExpiresUnixMs)) {
    throw new TypeError('InvalidCoordinatorOutputIntentInput');
  }
  return checked(owner.coordinatorIssueOutputPlanPollJson(
    durable, input.storeAuthorityCid, input.publicationAttemptCid,
    input.resultDefinitionCid, input.orderingEvidenceCid,
    input.coordinatorAuthority, input.transferAttempt, input.transferRoute,
    input.destinationSiteKey, input.destinationSiteGeneration,
    BigInt(input.transferMaxBytes), BigInt(input.transferExpiresUnixMs),
    input.sourceGrantCid, input.destinationGrantCid,
    input.routeCapabilityCid, input.transferOrigin));
};
export const admitCheckedOutputPlan = (durable, pollBody, planBody,
  expectedResultDefinitionCid, {maxChunks, maxManifestBytes,
    maxReferencedBytes}) => {
  if (typeof pollBody !== 'string' || typeof planBody !== 'string' ||
      typeof expectedResultDefinitionCid !== 'string' ||
      !Number.isSafeInteger(maxChunks) || maxChunks < 1 ||
      !Number.isSafeInteger(maxManifestBytes) || maxManifestBytes < 1 ||
      !(typeof maxReferencedBytes === 'bigint' &&
        maxReferencedBytes > 0n && maxReferencedBytes <= 9223372036854775807n ||
        Number.isSafeInteger(maxReferencedBytes) && maxReferencedBytes > 0)) {
    throw new TypeError('InvalidCoordinatorOutputPlanInput');
  }
  return checked(owner.coordinatorAdmitCheckedOutputPlan(
    durable, pollBody, planBody, expectedResultDefinitionCid, maxChunks,
    maxManifestBytes, BigInt(maxReferencedBytes)));
};
export const checkedOutputPlanCid = owner.coordinatorCheckedOutputPlanCid;
export const checkedOutputIntentCid = owner.coordinatorCheckedOutputIntentCid;
export const checkedOutputPublicationFacts = plan => {
  const facts = owner.coordinatorCheckedOutputPublicationFacts(plan);
  if (!Array.isArray(facts) || facts.length !== 7 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorOutputPublicationFacts');
  }
  const [resultDefinitionCid, logicalRelationCid, resultSchemaCid,
    orderingEvidenceCid, codecContractCid, rowCount, materialGenerationCid] =
    facts;
  return Object.freeze({resultDefinitionCid, logicalRelationCid,
    resultSchemaCid, orderingEvidenceCid, codecContractCid,
    rowCount: BigInt(rowCount), materialGenerationCid});
};
export const durableOutputPublicationFacts = durable => {
  const facts = owner.coordinatorDurableOutputPublicationFacts(durable);
  if (!Array.isArray(facts) || facts.length !== 8 ||
      !facts.every(value => typeof value === 'string')) {
    throw new Error('InvalidCoordinatorDurableOutputPublicationFacts');
  }
  const [storeAuthorityCid, resultDefinitionCid, logicalRelationCid,
    resultSchemaCid, orderingEvidenceCid, codecContractCid, rowCount,
    materialGenerationCid] = facts;
  if (!/^(0|[1-9][0-9]*)$/u.test(rowCount)) {
    throw new Error('InvalidCoordinatorDurableOutputPublicationFacts');
  }
  return Object.freeze({storeAuthorityCid, resultDefinitionCid,
    logicalRelationCid, resultSchemaCid, orderingEvidenceCid,
    codecContractCid, rowCount: BigInt(rowCount), materialGenerationCid});
};
// In-process Store handles from the admitted Output Plan. Physical adapters
// must verify custody and persist each transition before committing it.
export const payloadRequestFromOutput =
  owner.coordinatorPayloadRequestFromOutput;
// Historical typed DATA only. Current read authority and physical sealed
// generation remain with the existing Store/publication caller.
export const payloadRequestFromDurable = owner.coordinatorPayloadRequestFromDurable;
export function payloadRequestFacts(request) {
  const values = owner.coordinatorPayloadRequestFacts(request);
  if (!Array.isArray(values) || values.length !== 10 ||
      values.some(value => typeof value !== 'string') ||
      values.slice(0, 8).some(value => !/^sha256:[0-9a-f]{64}$/u.test(value)) ||
      values.slice(8).some(value => !/^(0|[1-9][0-9]*)$/u.test(value))) {
    throw new Error('InvalidCoordinatorPayloadRequestFacts');
  }
  const [storeAuthorityCid, publicationAttemptCid, materialGenerationCid,
    resultDefinitionCid, logicalRelationCid, resultSchemaCid,
    orderingEvidenceCid, codecContractCid, maxBytes, rowCount] = values;
  return Object.freeze({storeAuthorityCid, publicationAttemptCid, materialGenerationCid,
    resultDefinitionCid, logicalRelationCid, resultSchemaCid, orderingEvidenceCid,
    codecContractCid, maxBytes: BigInt(maxBytes), rowCount: BigInt(rowCount)});
}
export const payloadRequestCid = owner.coordinatorPayloadRequestCid;
export const payloadRequestMaxBytes = owner.coordinatorPayloadRequestMaxBytes;
export const admitPayloadRequestJson = (body, claimedCid) =>
  checked(owner.coordinatorPayloadAdmitRequestJson(body, claimedCid));
export const preparePayloadRecord = owner.coordinatorPayloadPrepareRecord;
export const payloadRecordDurableJson = record =>
  checked(owner.coordinatorPayloadRecordDurableJson(record));
export const admitDurablePayloadJson = body =>
  checked(owner.coordinatorPayloadAdmitDurableJson(body));
export const durablePayloadRevision = owner.coordinatorPayloadDurableRevision;
export const durablePayloadState = owner.coordinatorPayloadDurableState;
export const durablePayloadRequestCid =
  owner.coordinatorPayloadDurableRequestCid;
export const restoreDurablePayload = durable =>
  checked(owner.coordinatorPayloadRestoreDurable(durable));
export const preparePayloadReserved = record =>
  checked(owner.coordinatorPayloadPrepareReserved(record));
export const preparePayloadWriting = record =>
  checked(owner.coordinatorPayloadPrepareWriting(record));
export const preparePayloadOpaqueOwned = (record, custodyCid) =>
  checked(owner.coordinatorPayloadPrepareOpaqueOwned(record, custodyCid));
export const preparePayloadOpaqueSealed = (record, custodyCid,
  actualBytes, physicalDigest) => {
  if (!(typeof actualBytes === 'bigint' && actualBytes >= 0n &&
      actualBytes <= 9223372036854775807n ||
      Number.isSafeInteger(actualBytes) && actualBytes >= 0)) {
    throw new TypeError('InvalidPayloadActualBytes');
  }
  return checked(owner.coordinatorPayloadPrepareOpaqueSealed(
    record, custodyCid, BigInt(actualBytes), physicalDigest));
};
export const preparePayloadOpaqueReclaiming = (record, custodyCid) =>
  checked(owner.coordinatorPayloadPrepareOpaqueReclaiming(record, custodyCid));
export const preparePayloadReclaimed = record =>
  checked(owner.coordinatorPayloadPrepareReclaimed(record));
export const payloadTransitionDurableJson = transition =>
  checked(owner.coordinatorPayloadTransitionDurableJson(transition));
export const payloadTransitionExpectedRevision =
  owner.coordinatorPayloadTransitionExpectedRevision;
/** Call only after the exact next payload body was durably persisted. */
export const commitPayloadTransition = transition =>
  checked(owner.coordinatorPayloadCommitTransition(transition));
export const payloadRecordOpaqueGeneration = record => {
  const value = owner.coordinatorPayloadRecordOpaqueGeneration(record);
  if (value === undefined || typeof value === 'string') return value;
  throw new Error('InvalidPayloadGenerationProjection');
};
export const payloadRecordOpaqueOwnership = record => {
  const value = owner.coordinatorPayloadRecordOpaqueOwnership(record);
  if (value === undefined || typeof value === 'string') return value;
  throw new Error('InvalidPayloadOwnershipProjection');
};
export const payloadRecordDigest = owner.coordinatorPayloadRecordDigest;
export const payloadRecordActualBytes =
  owner.coordinatorPayloadRecordActualBytes;
export const prepareOutputIntent = (journal, plan) =>
  checked(owner.coordinatorPrepareOutputIntent(journal, plan));
export const outputIntentIsNew = owner.coordinatorOutputIntentIsNew;
/** Call only after the matching output intent and plan were persisted. */
export const commitOutputIntent = admission =>
  checked(owner.coordinatorCommitOutputIntent(admission));
export const outputRecordStatus = owner.coordinatorOutputRecordStatus;
export const outputInitialPollJson = record =>
  checked(owner.coordinatorOutputInitialPollJson(record));
export const outputAdmissionDurableJson = plan =>
  checked(owner.coordinatorOutputAdmissionDurableJson(plan));
export const admitDurableOutputJson = (body, dispatch,
  expectedResultDefinitionCid, {maxChunks, maxManifestBytes,
    maxReferencedBytes}) => {
  if (typeof body !== 'string' ||
      typeof expectedResultDefinitionCid !== 'string' ||
      !Number.isSafeInteger(maxChunks) || maxChunks < 1 ||
      !Number.isSafeInteger(maxManifestBytes) || maxManifestBytes < 1 ||
      !(typeof maxReferencedBytes === 'bigint' &&
        maxReferencedBytes > 0n && maxReferencedBytes <= 9223372036854775807n ||
        Number.isSafeInteger(maxReferencedBytes) && maxReferencedBytes > 0)) {
    throw new TypeError('InvalidCoordinatorDurableOutputInput');
  }
  return checked(owner.coordinatorAdmitDurableOutputJson(
    body, dispatch, expectedResultDefinitionCid, maxChunks,
    maxManifestBytes, BigInt(maxReferencedBytes)));
};
export const restoreDurableOutput = (journal, durable) =>
  checked(owner.coordinatorRestoreDurableOutput(journal, durable));
export const durableOutputRevision = owner.coordinatorDurableOutputRevision;
export const durableOutputJson = owner.coordinatorDurableOutputJson;
export const durableOutputPollJson = durable =>
  checked(owner.coordinatorDurableOutputPollJson(durable));
export const durableOutputRequestJson = durable =>
  checked(owner.coordinatorDurableOutputRequestJson(durable));
export const admitOutputTransferReplyJson = (durable, reply) =>
  checked(owner.coordinatorAdmitOutputTransferReplyJson(durable, reply));
export const outputTransferRequestCid = durable =>
  owner.coordinatorOutputTransferRequestCid(durable);
export const prepareOutputResultJson = (durable, reply,
  payloadPhysicalDigest) => checked(owner.coordinatorPrepareOutputResultJson(
    durable, reply, payloadPhysicalDigest));
export const prepareOutputUnknown = record =>
  checked(owner.coordinatorPrepareOutputUnknown(record));
export const prepareOutputSuccessJson = (record, body) =>
  checked(owner.coordinatorPrepareOutputSuccessJson(record, body));
export const outputTransitionExpectedRevision =
  owner.coordinatorOutputTransitionExpectedRevision;
export const outputTransitionDurableJson = (durable, transition) =>
  checked(owner.coordinatorOutputTransitionDurableJson(durable, transition));
/** Call only after the exact next output body was atomically persisted. */
export const commitOutputTransition = transition =>
  checked(owner.coordinatorCommitOutputTransition(transition));
export const outputResultJson = record =>
  checked(owner.coordinatorOutputResultJson(record));
export const prepareUnknown = record =>
  checked(owner.coordinatorPrepareUnknown(record));
export const admitResponseJson = (body, request, statusReply) =>
  checked(owner.coordinatorAdmitResponseJson(body, request, statusReply));
export const prepareResponseObservation = (record, response) =>
  checked(owner.coordinatorPrepareResponseObservation(record, response));
export const transitionExpectedRevision =
  owner.coordinatorTransitionExpectedRevision;
export const transitionIsReplay = owner.coordinatorTransitionIsReplay;
export const transitionDurableJson = (durable, transition) =>
  checked(owner.coordinatorTransitionDurableJson(durable, transition));
export const responseDurableJson = (durable, transition, response) =>
  checked(owner.coordinatorResponseDurableJson(durable, transition, response));
export const commitTransition = transition =>
  checked(owner.coordinatorCommitTransition(transition));
export const recordStateCodes = owner.coordinatorRecordStateCodes;
export const exactRetransmissionEligible =
  owner.coordinatorExactRetransmissionEligible;

export const canRetireCancellationDelivery =
  owner.coordinatorCanRetireCancellationDelivery;

// One namespace for the existing Common report value. Copied handles and raw
// projections cannot stand in for the admitted original.
const holderTerminalHandles = new WeakMap();
const holderTerminalValue = handle => {
  const value = holderTerminalHandles.get(handle);
  if (value === undefined) throw new TypeError('InvalidHolderTerminalReport');
  return value;
};
export const holderTerminalReports = Object.freeze({
  admit: (body, maximum) => {
    if (typeof body !== 'string' || !Number.isSafeInteger(maximum) ||
        maximum < 1 || maximum > 262144) throw new TypeError('InvalidHolderTerminalReportInput');
    const value = checked(owner.coordinatorHolderTerminalReportAdmit(body, maximum));
    const handle = Object.freeze({});
    holderTerminalHandles.set(handle, value);
    return handle;
  },
  facts: handle => {
    const [reportCid, rootDispatchCid] = owner.coordinatorHolderTerminalReportProjection(holderTerminalValue(handle));
    return Object.freeze({reportCid, rootDispatchCid});
  },
  requests: handle => Object.freeze([...owner.coordinatorHolderTerminalReportDispatches(holderTerminalValue(handle))]),
  acceptedJson: handle => checked(owner.coordinatorHolderTerminalAcceptedJson(holderTerminalValue(handle))),
  admitReplyJson: (handle, body) => {
    if (typeof body !== 'string') throw new TypeError('InvalidHolderTerminalReplyInput');
    checked(owner.coordinatorHolderTerminalReplyAdmit(holderTerminalValue(handle), body));
  },
});

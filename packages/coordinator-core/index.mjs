import * as owner from './dist/remote_coordinator_abi.js';

function checked(result) {
  if (result?.$tag === 1) return result._0;
  if (result?.$tag === 0) {
    throw Object.assign(new Error('CoordinatorOwnerRejected', {cause: result._0}),
      {code: 'CoordinatorOwnerRejected'});
  }
  throw Object.assign(new Error('InvalidCoordinatorOwnerResult'),
    {code: 'InvalidCoordinatorOwnerResult'});
}

export const createJournal = authority =>
  checked(owner.coordinatorCreateJournal(authority));

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
export const pollQueryJson = request =>
  checked(owner.coordinatorPollQueryJson(request));
export const pollReleaseJson = request =>
  checked(owner.coordinatorPollReleaseJson(request));
export const admitPollNotSeen = (body, request) =>
  checked(owner.coordinatorAdmitPollNotSeen(body, request));
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
  if (option?.$tag === 0) return undefined;
  if (option?.$tag !== 1 || !Array.isArray(option._0) ||
      option._0.length !== 14 ||
      !option._0.every(value => typeof value === 'string')) {
    throw Object.assign(new Error('InvalidCoordinatorOutputProjection'),
      {code: 'InvalidCoordinatorOutputProjection'});
  }
  const [evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid] = option._0;
  return Object.freeze({evidenceCid, measurementCid, dispatchRequestCid,
    materialGeneration, holdingEvidenceCid, managedProfileCid,
    resultSchemaCid, logicalViewCid, representationCodecCid,
    physicalManifestCid, measurementEvidenceCid, rowCount,
    retainedBytes, subjectCid});
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
export const transitionDurableJson = (durable, transition) =>
  checked(owner.coordinatorTransitionDurableJson(durable, transition));
export const responseDurableJson = (durable, transition, response) =>
  checked(owner.coordinatorResponseDurableJson(durable, transition, response));
export const commitTransition = transition =>
  checked(owner.coordinatorCommitTransition(transition));
export const recordStateCodes = owner.coordinatorRecordStateCodes;
export const exactRetransmissionEligible =
  owner.coordinatorExactRetransmissionEligible;

import {checked} from '../../../host-common/runtime-result.mjs';
import {projectSalesforceSingleObservation,
  sendRawSalesforceSingleRecord} from
  '../site/salesforce-single-write.mjs';
import {projectSalesforceCollectionObservation,
  sendRawSalesforceContinueCollection} from
  '../site/salesforce-collection-write.mjs';
import {matchesSalesforceCredentialOrg} from
  '../site/salesforce-credential-binding.mjs';
import {captureClaimedEffectResponse,
  captureClaimedEffectCollectionResponse,
  snapshotEffectDispatchClaim,
  snapshotEffectDispatchClaims} from '../../../host-node/effect-physical-dispatch.mjs';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {ownInvocationContext, ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';
import {recoverProjectedEffectResponse} from '../../../host-node/effect-response-recovery.mjs';
import {recoverRetainedSalesforceCatalog} from
  '../site/salesforce-catalog-recovery.mjs';
import {recoverNamedSalesforceObservation} from
  '../site/salesforce-named-describe.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Rebuild provider request material from a recovered Preview and exact
// prepared Ledger claims. This does not restore apply or credential authority.
// The ordinary apply owner must repeat whole-set and current Site admission.
export function recoverPreparedSalesforceSingleRequests({
  moon, previewWire, runIdentityCid, authoringContextCid, members,
  previewLimits, bodyLimits, requestLimits, maxMembers, maxRows,
  maxIdentityBytes = 4096,
}) {
  const positive = value => Number.isSafeInteger(value) && value > 0;
  if (!moon || typeof previewWire !== 'string' ||
      typeof runIdentityCid !== 'string' ||
      typeof authoringContextCid !== 'string' ||
      !Array.isArray(members) || members.length === 0 ||
      !positive(maxMembers) || members.length > maxMembers ||
      !positive(maxRows) || maxRows > 100_000 ||
      !previewLimits || !bodyLimits || !requestLimits ||
      !positive(previewLimits.maxWireBytes) ||
      !positive(previewLimits.maxNodes) ||
      !positive(previewLimits.maxDepth) ||
      !positive(bodyLimits.maxBytes) ||
      !positive(bodyLimits.maxNodes) ||
      !positive(bodyLimits.maxDepth) ||
      !positive(requestLimits.maxPathBytes) ||
      !positive(requestLimits.maxTargetBytes) ||
      !positive(requestLimits.maxBodyBytes) ||
      !positive(maxIdentityBytes)) {
    fail('InvalidSalesforcePreparedRequestRecovery');
  }
  let totalRows = 0;
  for (const member of members) {
    if (!member?.projection || typeof member.apiVersion !== 'string' ||
        typeof member.resourceOrigin !== 'string' ||
        !Array.isArray(member.claims) || member.claims.length === 0) {
      fail('InvalidSalesforcePreparedRequestRecovery');
    }
    totalRows += member.claims.length;
    if (totalRows > maxRows) fail('InvalidSalesforcePreparedRequestRecovery');
  }
  const preview = checked(moon.salesforceAdmitRecoveryPreview(
    previewWire, runIdentityCid, authoringContextCid,
    previewLimits.maxWireBytes, previewLimits.maxNodes,
    previewLimits.maxDepth));
  if (moon.salesforceRecoveryPreviewMemberCount(preview) !==
      members.length) {
    fail('InvalidSalesforcePreparedRequestRecovery');
  }
  const requests = members.map((member, memberIndex) => {
    if (moon.salesforceRecoveryPreviewRowCount(preview, memberIndex) !==
        member.claims.length) {
      fail('InvalidSalesforcePreparedRequestRecovery');
    }
    return Object.freeze(member.claims.map((claim, rowIndex) => {
      if (typeof claim?.canonicalRequestCid !== 'string') {
        fail('InvalidSalesforcePreparedRequestRecovery');
      }
      return checked(moon.salesforceRecoverSingleWriteRequest(
        preview, memberIndex, rowIndex, member.projection,
        member.apiVersion, bodyLimits.maxBytes, bodyLimits.maxNodes,
        bodyLimits.maxDepth, requestLimits.maxPathBytes,
        requestLimits.maxTargetBytes, requestLimits.maxBodyBytes,
        maxIdentityBytes, member.resourceOrigin,
        claim.canonicalRequestCid));
    }));
  });
  return Object.freeze({preview, requests: Object.freeze(requests)});
}

// Re-admit the original bounded Catalog projection from the encrypted Run
// capture, then rebuild each exact prepared request from its Preview row and
// durable claim. A fresh Catalog and mutation grant are still required before
// sending any reconstructed request. A member's recovery entry is either a
// retained Catalog sync (`salesforce-catalog`) or the retained describe of
// exactly its Resource (`salesforce-named-catalog`).
export function recoverCapturedSalesforceSingleRequests({
  moon, recovered, recorded, previewWire, runIdentityCid,
  authoringContextCid, previewLimits, bodyLimits, requestLimits,
  maxMembers, maxRows, maxRetainedBytes,
}) {
  if (!Array.isArray(recovered?.connectorRecovery) ||
      !Array.isArray(recorded?.members) ||
      recovered.connectorRecovery.length !== recorded.members.length ||
      typeof previewWire !== 'string' ||
      !Number.isSafeInteger(maxRetainedBytes) ||
      maxRetainedBytes < 1) {
    fail('InvalidSalesforceCapturedRequestRecovery');
  }
  let previewBody;
  try { previewBody = JSON.parse(previewWire); }
  catch { fail('InvalidSalesforceCapturedRequestRecovery'); }
  if (!Array.isArray(previewBody.effects) ||
      previewBody.effects.length !== recorded.members.length) {
    fail('InvalidSalesforceCapturedRequestRecovery');
  }
  const catalogs = [];
  const members = recovered.connectorRecovery.map((entry, memberIndex) => {
    if (entry.memberIndex !== memberIndex ||
        !['salesforce-catalog', 'salesforce-named-catalog']
          .includes(entry.kind) ||
        typeof entry.wire !== 'string') {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    let profile;
    try { profile = JSON.parse(entry.wire); }
    catch { fail('InvalidSalesforceCapturedRequestRecovery'); }
    const operation = new Map([
      ['create', 0], ['update', 1], ['upsert', 2],
    ]).get(profile.operation);
    if (operation === undefined ||
        previewBody.effects[memberIndex].effect_kind !== profile.operation ||
        previewBody.effects[memberIndex].write_footprint?.resource_kind !==
          profile.resourceName ||
        typeof profile.apiVersion !== 'string' ||
        typeof profile.resourceOrigin !== 'string' ||
        typeof profile.externalTargetField !== 'string' ||
        !Array.isArray(profile.fieldNames) ||
        profile.fieldNames.length === 0 ||
        !profile.fieldNames.every(name => typeof name === 'string')) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    const named = entry.kind === 'salesforce-named-catalog';
    const retained = named ? profile.evidence : profile.catalog;
    // Retained describe bytes are base64 inside the saved wire.
    if (typeof retained?.observationJson !== 'string' ||
        (named && Buffer.byteLength(entry.wire, 'utf8') >
          2 * maxRetainedBytes)) {
      fail('InvalidSalesforceCapturedRequestRecovery');
    }
    const catalog = named ? {observation: recoverNamedSalesforceObservation({
      moon, evidence: retained, expectedObservationCid: entry.observationCid})}
      : recoverRetainedSalesforceCatalog({moon, retained,
        expectedObservationCid: entry.observationCid, maxRetainedBytes});
    const binding = JSON.parse(retained.observationJson).binding;
    if (binding.resource_origin !== profile.resourceOrigin ||
        binding.run_invocation_cid !== previewBody.invocation_cid) {
      fail('ForeignSalesforceCapturedRequestRecovery');
    }
    const projection = checked(moon.salesforcePrepareWriteProjection(
      catalog.observation, binding.tenant, binding.principal,
      binding.environment, binding.connection_revision, binding.org_id,
      binding.site_key, binding.site_generation,
      binding.connector_registration, binding.connector_revision,
      binding.resource_origin, binding.run_invocation_cid,
      binding.dispatch_request_cid, binding.sync_occurrence,
      profile.resourceName, operation, profile.externalTargetField,
      profile.fieldNames, profile.fieldNames.length));
    catalogs.push(catalog.observation);
    return Object.freeze({projection, apiVersion: profile.apiVersion,
      resourceOrigin: profile.resourceOrigin,
      claims: recorded.members[memberIndex].claims});
  });
  const result = recoverPreparedSalesforceSingleRequests({moon, previewWire,
    runIdentityCid, authoringContextCid, members,
    previewLimits, bodyLimits, requestLimits, maxMembers, maxRows});
  return Object.freeze({...result, catalogs: Object.freeze(catalogs)});
}

// An authorized evidence read is not another mutation attempt. The Host
// supplies the current evidence-view decision; this adapter checks the exact
// immutable request and stored claim, then only reprojects saved bytes.
export async function recoverStoredSalesforceSingleResponse({
  ledger,
  claim,
  commonMoon,
  moon,
  request,
  resourceOrigin,
  authorizeEvidenceRead,
  limits,
  maxRequestIdentityBytes = 4096,
}) {
  if (!ledger || typeof ledger.readClaimedResponse !== 'function' ||
      typeof ledger.scopeCid !== 'string' || !claim || !commonMoon ||
      !moon || !request || typeof resourceOrigin !== 'string' ||
      typeof authorizeEvidenceRead !== 'function' || !limits) {
    fail('InvalidSalesforceEffectResponseRead');
  }
  const ownedLimits = ownInvocationLimits(limits);
  const ownedClaim = snapshotEffectDispatchClaim(claim);
  const expectedCid = checked(moon.salesforceSingleWriteRequestCid(
    request, resourceOrigin, maxRequestIdentityBytes));
  return recoverProjectedEffectResponse({
    ledger, claims: ownedClaim, commonMoon, expectedRequestCid: expectedCid,
    providerBinding: {orgId: moon.salesforceSingleWriteRequestOrgId(request)},
    authorizeEvidenceRead,
    invalidCode: 'InvalidSalesforceEffectResponseRead',
    foreignCode: 'ForeignSalesforceEffectResponse',
    projectStored: stored => projectSalesforceSingleObservation({
      moon, request,
      observation: Object.freeze({
        useCid: stored.credentialUseCid,
        statusCode: stored.statusCode,
        body: stored.responseBytes,
      }),
      limits: ownedLimits,
    }),
  });
}

export async function recoverStoredSalesforceCollectionResponse({
  ledger,
  claims,
  commonMoon,
  moon,
  request,
  resourceOrigin,
  authorizeEvidenceRead,
  limits,
  maxRequestIdentityBytes = 4096,
}) {
  const ownedClaims = Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims) : undefined;
  if (!ledger || typeof ledger.readClaimedBatchResponse !== 'function' ||
      typeof ledger.scopeCid !== 'string' || !ownedClaims ||
      ownedClaims.length === 0 || !commonMoon || !moon || !request ||
      typeof resourceOrigin !== 'string' ||
      typeof authorizeEvidenceRead !== 'function' || !limits ||
      !Number.isSafeInteger(limits.maxRows) || limits.maxRows < 1 ||
      ownedClaims.length > limits.maxRows ||
      moon.salesforceCollectionWriteRequestRowCount(request) !==
        ownedClaims.length) {
    fail('InvalidSalesforceEffectResponseRead');
  }
  const ownedLimits = ownInvocationLimits(limits);
  const expectedCid = checked(moon.salesforceCollectionWriteRequestCid(
    request, resourceOrigin, maxRequestIdentityBytes));
  return recoverProjectedEffectResponse({
    ledger, claims: ownedClaims, commonMoon, expectedRequestCid: expectedCid,
    providerBinding: {
      orgId: moon.salesforceCollectionWriteRequestOrgId(request),
    },
    authorizeEvidenceRead, batch: true,
    invalidCode: 'InvalidSalesforceEffectResponseRead',
    foreignCode: 'ForeignSalesforceEffectResponse',
    projectStored: stored => projectSalesforceCollectionObservation({
      moon, request,
      observation: Object.freeze({
        useCid: stored.credentialUseCid,
        statusCode: stored.statusCode,
        body: stored.responseBytes,
      }),
      limits: ownedLimits,
    }),
  });
}

// Low-level physical custody used only after the caller has established the
// Preview row binding and whole-set apply admission.
export async function captureClaimedSalesforceSingleResponse({
  ledger,
  claim,
  moon,
  request,
  currentObservation,
  authorization,
  credential,
  limits,
  signal,
  maxRequestIdentityBytes = 4096,
  callResource,
}) {
  const scope = authorization?.scope;
  if (!moon || !request || !currentObservation || !scope ||
      !authorization.grant || !credential || !limits ||
      !matchesSalesforceCredentialOrg(credential,
        moon.salesforceSingleWriteRequestOrgId(request)) ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 ||
      scope.operation !==
        moon.salesforceSingleWriteRequestGrantOperation(request) ||
      !moon.salesforceSingleWriteRequestScopeMatches(
        request, scope.tenant, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin,
        scope.runInvocationCid, scope.dispatchRequestCid)) {
    fail('ForeignSalesforceEffectWrite');
  }
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {callResource}});
  const ownedClaim = snapshotEffectDispatchClaim(claim);
  const ownedScope = context.scope;
  checked(moon.salesforceRecheckSingleWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceSingleWriteRequestCid(
    request, ownedScope.resourceOrigin, maxRequestIdentityBytes));
  const captured = await captureClaimedEffectResponse({
    ledger,
    claim: ownedClaim,
    requestCid,
    execute: () => sendRawSalesforceSingleRecord({
      moon, request, currentObservation,
      authorization: context.authorization,
      credential: context.credential,
      limits: context.limits, signal,
      callResource: context.callbacks.callResource,
    }),
    projectStored: stored => projectSalesforceSingleObservation({
      moon, request,
      observation: Object.freeze({
        useCid: stored.credentialUseCid,
        statusCode: stored.statusCode,
        body: stored.responseBytes,
      }),
      limits: context.limits,
    }),
  });
  if (captured.claimed) return captured;
  return Object.freeze({claimed: false,
    ownership: Object.freeze({action: captured.ownership.action})});
}

const admitSalesforceSingleEffectRow = ({
  commonMoon,
  admittedPreview,
  memberIndex,
  rowIndex,
  rowPreviewCid,
  claim,
  moon,
  request,
  maxRequestIdentityBytes = 4096,
}) => {
  if (!commonMoon || !admittedPreview || !moon || !request || !claim ||
      !Number.isSafeInteger(memberIndex) ||
      !Number.isSafeInteger(rowIndex) ||
      typeof rowPreviewCid !== 'string') {
    fail('InvalidSalesforceEffectRowBinding');
  }
  if (!checked(moon.salesforceSingleWriteRequestMatchesPreviewFootprint(
      admittedPreview, memberIndex, rowIndex, request,
      maxRequestIdentityBytes))) {
    fail('ForeignSalesforceEffectFootprint');
  }
  const ownedClaim = snapshotEffectDispatchClaim(claim);
  runtimeCore(commonMoon).effectApplicationControl.admitMemberRow(
    admittedPreview, memberIndex, rowIndex,
    moon.salesforceSingleWriteRequestEffectKind(request), ownedClaim.scope,
    rowPreviewCid, ownedClaim.locator, ownedClaim.key);
  return ownedClaim;
};

const settleSalesforceSingleEffectResponse = ({
  ledger, claim, admittedPreview, memberIndex, rowIndex,
  moon, request, observed, limits, maxRequestIdentityBytes,
}) => {
  if (observed?.kind !== 'typed-success-response' &&
      observed?.kind !== 'typed-failure-response') return undefined;
  const projection = checked(moon.salesforceProjectSingleEffectOutcome(
    admittedPreview, memberIndex, rowIndex, request, observed.response,
    maxRequestIdentityBytes, limits.maxResponseBytes, limits.maxNodes,
    limits.maxDepth));
  const outcome = ledger.recordAdmittedRowOutcome({
    claim, preview: admittedPreview, memberIndex,
    previewRowIndex: rowIndex,
    outcomeWire: moon.salesforceWriteEffectOutcomeWire(projection),
  });
  const terminal = ledger.commitAdmittedRowOutcome({
    claim, preview: admittedPreview, memberIndex,
    previewRowIndex: rowIndex,
  });
  return Object.freeze({outcomeReceipt: outcome.receipt,
    terminal: terminal.transition});
};

// Bind one physical REST request to the admitted member and row before the
// low-level custody path can claim a possible-dispatch fact.
export async function captureSalesforceSingleEffectWrite({
  commonMoon,
  admittedPreview,
  memberIndex,
  rowIndex,
  rowPreviewCid,
  claim,
  moon,
  request,
  authorizeEvidenceRead,
  ...physical
}) {
  const ownedClaim = admitSalesforceSingleEffectRow({commonMoon,
    admittedPreview, memberIndex, rowIndex, rowPreviewCid, claim, moon,
    request, maxRequestIdentityBytes:
      physical.maxRequestIdentityBytes ?? 4096});
  const projectionLimits = ownInvocationLimits(physical.limits);
  const resourceOrigin = physical.authorization?.scope?.resourceOrigin;
  const captured = await captureClaimedSalesforceSingleResponse({
    claim: ownedClaim, moon, request, ...physical,
  });
  let result = captured;
  if (!captured.claimed) {
    result = Object.freeze({claimed: false,
      ownership: Object.freeze({action: captured.ownership.action})});
    if (authorizeEvidenceRead === undefined) return result;
    const recovery = await recoverStoredSalesforceSingleResponse({
      ledger: physical.ledger, claim: ownedClaim, commonMoon, moon, request,
      resourceOrigin, authorizeEvidenceRead, limits: projectionLimits,
      maxRequestIdentityBytes: physical.maxRequestIdentityBytes ?? 4096,
    });
    result = Object.freeze({...result, recovered: recovery.recovered});
  }
  const observed = result.claimed ? result.physical : result.recovered;
  const settled = settleSalesforceSingleEffectResponse({
    ledger: physical.ledger, claim: ownedClaim, admittedPreview,
    memberIndex, rowIndex, moon, request, observed,
    limits: projectionLimits,
    maxRequestIdentityBytes: physical.maxRequestIdentityBytes ?? 4096,
  });
  return settled === undefined ? result : Object.freeze({...result,
    ...settled});
}

// Re-admit an already saved HTTP response without a mutation grant, current
// Catalog refresh, secret resolution, or another physical send. The evidence
// view must authorize the exact immutable dispatch before projection.
export async function reconcileStoredSalesforceSingleEffectWrite({
  ledger, commonMoon, admittedPreview, memberIndex, rowIndex,
  rowPreviewCid, claim, moon, request, resourceOrigin,
  authorizeEvidenceRead, limits, maxRequestIdentityBytes = 4096,
}) {
  const ownedClaim = admitSalesforceSingleEffectRow({commonMoon,
    admittedPreview, memberIndex, rowIndex, rowPreviewCid, claim, moon,
    request, maxRequestIdentityBytes});
  const ownedLimits = ownInvocationLimits(limits);
  const recovery = await recoverStoredSalesforceSingleResponse({
    ledger, claim: ownedClaim, commonMoon, moon, request, resourceOrigin,
    authorizeEvidenceRead, limits: ownedLimits,
    maxRequestIdentityBytes,
  });
  const settled = settleSalesforceSingleEffectResponse({
    ledger, claim: ownedClaim, admittedPreview, memberIndex, rowIndex,
    moon, request, observed: recovery.recovered, limits: ownedLimits,
    maxRequestIdentityBytes,
  });
  return Object.freeze({...recovery, ...(settled ?? {})});
}

// The admitted Preview fixes the member's ordered row identities, logical
// correlations, and derived keys. The caller still owns checked input,
// payload equivalence, whole-set preflight, and current apply admission.
export async function captureSalesforceCollectionEffectWrite({
  ledger,
  claims,
  admittedPreview,
  memberIndex,
  firstRow,
  commonMoon,
  moon,
  request,
  currentObservation,
  authorization,
  credential,
  limits,
  signal,
  maxRequestIdentityBytes = 4096,
  maxBindingWork = 100_000,
  authorizeEvidenceRead,
  callResource,
}) {
  const scope = authorization?.scope;
  const ownedClaims = Array.isArray(claims)
    ? snapshotEffectDispatchClaims(claims) : undefined;
  const count = moon && request &&
    moon.salesforceCollectionWriteRequestRowCount(request);
  if (!commonMoon || !moon || !request || !currentObservation || !scope ||
      !authorization.grant || !credential || !limits ||
      !admittedPreview ||
      !ownedClaims || ownedClaims.length === 0 ||
      !Number.isSafeInteger(count) || count !== ownedClaims.length ||
      !Number.isSafeInteger(memberIndex) ||
      !Number.isSafeInteger(firstRow) ||
      !Number.isSafeInteger(maxBindingWork) || maxBindingWork < 1 ||
      maxBindingWork > 1_000_000 ||
      !Number.isSafeInteger(limits.maxRequestBytes) ||
      limits.maxRequestBytes < 1 || limits.maxRequestBytes > 1_000_000 ||
      !Number.isSafeInteger(limits.maxResponseBytes) ||
      limits.maxResponseBytes < 1 || limits.maxResponseBytes > 1_000_000 ||
      !Number.isSafeInteger(limits.maxNodes) ||
      limits.maxNodes < 1 || limits.maxNodes > 1000 ||
      !Number.isSafeInteger(limits.maxDepth) ||
      limits.maxDepth < 1 || limits.maxDepth > 32 ||
      !Number.isSafeInteger(limits.maxRows) ||
      limits.maxRows < 1 || limits.maxRows > 200 ||
      !matchesSalesforceCredentialOrg(credential,
        moon.salesforceCollectionWriteRequestOrgId(request)) ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 ||
      scope.operation !==
        moon.salesforceCollectionWriteRequestGrantOperation(request) ||
      !moon.salesforceCollectionWriteRequestScopeMatches(
        request, scope.tenant, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin,
        scope.runInvocationCid, scope.dispatchRequestCid)) {
    fail('ForeignSalesforceEffectCollection');
  }
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {callResource}});
  const ownedScope = context.scope;
  checked(moon.salesforceRecheckCollectionWriteRequest(
    request, currentObservation));
  if (!checked(moon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
      admittedPreview, memberIndex, firstRow, request,
      maxRequestIdentityBytes, maxBindingWork))) {
    fail('ForeignSalesforceEffectFootprint');
  }
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceCollectionWriteRequestCid(
    request, ownedScope.resourceOrigin, maxRequestIdentityBytes));
  const rowCids = Array.from({length: count}, (_, index) =>
    moon.salesforceCollectionWriteRequestRowCid(request, index));
  const effect = runtimeCore(commonMoon).effectApplicationControl;
  effect.admitCollectionBatch(
    admittedPreview, memberIndex, firstRow,
    moon.salesforceCollectionWriteRequestEffectKind(request),
    ownedClaims[0].scope, rowCids,
    ownedClaims.map(claim => claim.locator),
    ownedClaims.map(claim => claim.key), context.limits.maxRows,
    maxBindingWork);
  const captured = await captureClaimedEffectCollectionResponse({
    ledger, claims: ownedClaims, requestCid,
    execute: () => sendRawSalesforceContinueCollection({
      moon, request, currentObservation,
      authorization: context.authorization,
      credential: context.credential,
      limits: context.limits, signal,
      callResource: context.callbacks.callResource,
    }),
    projectStored: stored => projectSalesforceCollectionObservation({
      moon, request,
      observation: Object.freeze({
        useCid: stored.credentialUseCid,
        statusCode: stored.statusCode,
        body: stored.responseBytes,
      }),
      limits: context.limits,
    }),
  });
  let result = captured;
  if (!captured.claimed) {
    result = Object.freeze({claimed: false,
      ownership: Object.freeze({actions: captured.ownership.actions})});
    if (authorizeEvidenceRead === undefined) return result;
    const recovery = await recoverStoredSalesforceCollectionResponse({
      ledger, claims: ownedClaims, commonMoon, moon, request,
      resourceOrigin: ownedScope.resourceOrigin, authorizeEvidenceRead,
      limits: context.limits, maxRequestIdentityBytes,
    });
    result = Object.freeze({...result, recovered: recovery.recovered});
  }
  const observed = result.claimed ? result.physical : result.recovered;
  if (observed?.kind !== 'typed-row-response') return result;
  const responseEvidence = ledger.prepareOwnedBatchResponseEvidence(
    ownedClaims);
  const outcomeReceipts = [];
  const terminalTransitions = [];
  for (let index = 0; index < count; index++) {
    const projection = checked(moon.salesforceProjectCollectionEffectOutcome(
      admittedPreview, memberIndex, firstRow, observed.result, index,
      context.limits.maxResponseBytes, context.limits.maxNodes,
      context.limits.maxDepth));
    const outcome = ledger.recordAdmittedRowOutcome({
      claims: ownedClaims, batchRowIndex: index, preview: admittedPreview,
      memberIndex, previewRowIndex: firstRow + index,
      responseEvidence,
      outcomeWire: moon.salesforceWriteEffectOutcomeWire(projection),
    });
    outcomeReceipts.push(outcome.receipt);
    const terminal = ledger.commitAdmittedRowOutcome({
      claims: ownedClaims, batchRowIndex: index, preview: admittedPreview,
      memberIndex, previewRowIndex: firstRow + index,
      responseEvidence,
    });
    terminalTransitions.push(terminal.transition);
  }
  return Object.freeze({...result,
    outcomeReceipts: Object.freeze(outcomeReceipts),
    terminalTransitions: Object.freeze(terminalTransitions)});
}

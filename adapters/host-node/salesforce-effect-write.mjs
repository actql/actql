import {checked} from '../host-common/runtime-result.mjs';
import {projectSalesforceSingleObservation,
  sendRawSalesforceSingleRecord} from
  '../site-node/salesforce-single-write.mjs';
import {projectSalesforceCollectionObservation,
  sendRawSalesforceContinueCollection} from
  '../site-node/salesforce-collection-write.mjs';
import {matchesSalesforceCredentialOrg} from
  '../site-node/salesforce-credential-binding.mjs';
import {captureClaimedEffectResponse,
  captureClaimedEffectCollectionResponse,
  snapshotEffectDispatchClaim,
  snapshotEffectDispatchClaims} from './effect-physical-dispatch.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {ownInvocationContext, ownInvocationLimits} from
  '../host-common/owned-invocation-context.mjs';
import {readAuthorizedEffectResponse} from './effect-response-recovery.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

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
  const {stored} = await readAuthorizedEffectResponse({
    ledger, claims: ownedClaim, commonMoon, expectedRequestCid: expectedCid,
    providerBinding: {orgId: moon.salesforceSingleWriteRequestOrgId(request)},
    authorizeEvidenceRead,
    invalidCode: 'InvalidSalesforceEffectResponseRead',
    foreignCode: 'ForeignSalesforceEffectResponse',
  });
  if (stored === undefined) return Object.freeze({recovered: undefined});
  return Object.freeze({
    recovered: projectSalesforceSingleObservation({
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
  const {stored} = await readAuthorizedEffectResponse({
    ledger, claims: ownedClaims, commonMoon, expectedRequestCid: expectedCid,
    providerBinding: {
      orgId: moon.salesforceCollectionWriteRequestOrgId(request),
    },
    authorizeEvidenceRead, batch: true,
    invalidCode: 'InvalidSalesforceEffectResponseRead',
    foreignCode: 'ForeignSalesforceEffectResponse',
  });
  if (stored === undefined) return Object.freeze({recovered: undefined});
  return Object.freeze({
    recovered: projectSalesforceCollectionObservation({
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
  const ownedScope = context.scope;
  checked(moon.salesforceRecheckSingleWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceSingleWriteRequestCid(
    request, ownedScope.resourceOrigin, maxRequestIdentityBytes));
  const captured = await captureClaimedEffectResponse({
    ledger,
    claim,
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
  const stored = captured.ownership?.response;
  if (captured.claimed || stored === undefined) return captured;
  // The Store has verified these exact physical bytes. Re-projecting them is
  // read-only: it never claims another use or sends the mutation again.
  const recovered = projectSalesforceSingleObservation({
    moon, request,
    observation: Object.freeze({
      useCid: stored.credentialUseCid,
      statusCode: stored.statusCode,
      body: stored.responseBytes,
    }),
    limits: context.limits,
  });
  return Object.freeze({...captured, recovered});
}

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
  ...physical
}) {
  if (!commonMoon || !admittedPreview || !moon || !request || !claim ||
      !Number.isSafeInteger(memberIndex) ||
      !Number.isSafeInteger(rowIndex) ||
      typeof rowPreviewCid !== 'string') {
    fail('InvalidSalesforceEffectRowBinding');
  }
  if (!checked(moon.salesforceSingleWriteRequestMatchesPreviewFootprint(
      admittedPreview, memberIndex, rowIndex, request,
      physical.maxRequestIdentityBytes ?? 4096))) {
    fail('ForeignSalesforceEffectFootprint');
  }
  runtimeCore(commonMoon).effectApplicationControl.admitMemberRow(
    admittedPreview, memberIndex, rowIndex,
    moon.salesforceSingleWriteRequestEffectKind(request), claim.scope,
    rowPreviewCid, claim.locator, claim.key);
  return captureClaimedSalesforceSingleResponse({
    claim, moon, request, ...physical,
  });
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
  if (captured.claimed ||
      !captured.ownership.actions.every(action => action === 3)) {
    return captured;
  }
  const response = ledger.readClaimedBatchResponse(ownedClaims);
  if (!response) return captured;
  const recovered = projectSalesforceCollectionObservation({
    moon, request,
    observation: Object.freeze({
      useCid: response.credentialUseCid,
      statusCode: response.statusCode,
      body: response.responseBytes,
    }),
    limits: context.limits,
  });
  return Object.freeze({...captured, recovered});
}

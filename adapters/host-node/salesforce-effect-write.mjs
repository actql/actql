import {checked} from '../host-common/runtime-result.mjs';
import {projectSalesforceSingleObservation, writeSalesforceSingleRecord} from
  '../site-node/salesforce-single-write.mjs';
import {projectSalesforceCollectionObservation,
  writeSalesforceContinueCollection} from
  '../site-node/salesforce-collection-write.mjs';
import {matchesSalesforceCredentialOrg} from
  '../site-node/salesforce-credential-binding.mjs';
import {captureClaimedEffectResponse,
  captureClaimedEffectCollectionResponse,
  snapshotEffectDispatchClaims} from './effect-physical-dispatch.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

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
  checked(moon.salesforceRecheckSingleWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceSingleWriteRequestCid(
    request, scope.resourceOrigin, maxRequestIdentityBytes));
  const captured = await captureClaimedEffectResponse({
    ledger,
    claim,
    requestCid,
    execute: () => writeSalesforceSingleRecord({
      moon, request, currentObservation, authorization, credential,
      limits, signal, callResource,
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
    limits,
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
  checked(moon.salesforceRecheckCollectionWriteRequest(
    request, currentObservation));
  if (!checked(moon.salesforceCollectionWriteRequestMatchesPreviewFootprint(
      admittedPreview, memberIndex, firstRow, request,
      maxRequestIdentityBytes, maxBindingWork))) {
    fail('ForeignSalesforceEffectFootprint');
  }
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceCollectionWriteRequestCid(
    request, scope.resourceOrigin, maxRequestIdentityBytes));
  const rowCids = Array.from({length: count}, (_, index) =>
    moon.salesforceCollectionWriteRequestRowCid(request, index));
  const effect = runtimeCore(commonMoon).effectApplicationControl;
  effect.admitCollectionBatch(
    admittedPreview, memberIndex, firstRow,
    moon.salesforceCollectionWriteRequestEffectKind(request),
    ownedClaims[0].scope, rowCids,
    ownedClaims.map(claim => claim.locator),
    ownedClaims.map(claim => claim.key), limits.maxRows, maxBindingWork);
  const captured = await captureClaimedEffectCollectionResponse({
    ledger, claims: ownedClaims, requestCid,
    execute: () => writeSalesforceContinueCollection({
      moon, request, currentObservation, authorization, credential,
      limits, signal, callResource,
    }),
  });
  if (captured.claimed ||
      !captured.ownership.actions.every(action => action === 3)) {
    return captured;
  }
  let response;
  for (let index = 0; index < ownedClaims.length; index++) {
    const locatorCid = effect.logicalItemLocatorCid(ownedClaims[index].locator);
    const entry = ledger.currentAdmitted(locatorCid);
    if (!entry || !effect.ledgerEntryAdmitsDispatch(
        entry, ownedClaims[index].scope, ownedClaims[index].locator,
        ownedClaims[index].key, requestCid)) {
      return captured;
    }
    const dispatchEntryCid = effect.ledgerEntryCid(entry);
    if (index === 0) {
      response = ledger.response(dispatchEntryCid);
      if (!response) return captured;
    }
    if (response.batchMembers?.[index]?.dispatchEntryCid !==
        dispatchEntryCid ||
        response.batchMembers[index].logicalItemLocatorCid !== locatorCid) {
      fail('EffectCollectionResponseBindingMismatch');
    }
  }
  if (response.batchOwnerCid !== response.dispatchEntryCid ||
      response.batchPosition !== 0 ||
      response.batchCount !== ownedClaims.length ||
      response.batchMembers.length !== ownedClaims.length) {
    fail('EffectCollectionResponseBindingMismatch');
  }
  const recovered = projectSalesforceCollectionObservation({
    moon, request,
    observation: Object.freeze({
      useCid: response.credentialUseCid,
      statusCode: response.statusCode,
      body: response.responseBytes,
    }),
    limits,
  });
  return Object.freeze({...captured, recovered});
}

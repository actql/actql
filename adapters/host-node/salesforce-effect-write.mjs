import {checked} from '../host-common/runtime-result.mjs';
import {writeSalesforceSingleRecord} from
  '../site-node/salesforce-single-write.mjs';
import {writeSalesforceContinueCollection} from
  '../site-node/salesforce-collection-write.mjs';
import {matchesSalesforceCredentialOrg} from
  '../site-node/salesforce-credential-binding.mjs';
import {captureClaimedEffectResponse,
  captureClaimedEffectCollectionResponse} from './effect-physical-dispatch.mjs';
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
  return captureClaimedEffectResponse({
    ledger,
    claim,
    requestCid,
    execute: () => writeSalesforceSingleRecord({
      moon, request, currentObservation, authorization, credential,
      limits, signal, callResource,
    }),
  });
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
  const count = moon && request &&
    moon.salesforceCollectionWriteRequestRowCount(request);
  if (!commonMoon || !moon || !request || !currentObservation || !scope ||
      !authorization.grant || !credential || !limits ||
      !admittedPreview ||
      !Array.isArray(claims) || claims.length === 0 ||
      !Number.isSafeInteger(count) || count !== claims.length ||
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
  signal?.throwIfAborted();
  const requestCid = checked(moon.salesforceCollectionWriteRequestCid(
    request, scope.resourceOrigin, maxRequestIdentityBytes));
  const rowCids = Array.from({length: count}, (_, index) =>
    moon.salesforceCollectionWriteRequestRowCid(request, index));
  const effect = runtimeCore(commonMoon).effectApplicationControl;
  effect.admitCollectionBatch(
    admittedPreview, memberIndex, firstRow,
    moon.salesforceCollectionWriteRequestEffectKind(request), claims[0].scope,
    rowCids, claims.map(claim => claim.locator),
    claims.map(claim => claim.key), limits.maxRows, maxBindingWork);
  return captureClaimedEffectCollectionResponse({
    ledger, claims, requestCid,
    execute: () => writeSalesforceContinueCollection({
      moon, request, currentObservation, authorization, credential,
      limits, signal, callResource,
    }),
  });
}

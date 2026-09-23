import {checked} from '../host-common/runtime-result.mjs';
import {writeSalesforceSingleRecord} from
  '../site-node/salesforce-single-write.mjs';
import {matchesSalesforceCredentialOrg} from
  '../site-node/salesforce-credential-binding.mjs';
import {captureClaimedEffectResponse} from './effect-physical-dispatch.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// The caller must have completed whole-set Preview and apply admission. The
// exact MoonBit-issued transport request is bound to the durable row claim
// before the Site adapter is allowed to make an HTTPS mutation.
export async function captureSalesforceSingleEffectWrite({
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

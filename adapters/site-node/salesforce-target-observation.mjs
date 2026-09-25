import {checked} from '../host-common/runtime-result.mjs';
import {invokeScopedCredentialOperation, ownInvocationContext} from
  '../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Acquire bounded physical bytes for a prospective update-side Preview.
// This is neither a target guard nor evidence that a write may be sent. The
// Connector must project the returned record and bind its exact target before
// the common Preview and apply admission can use it.
export async function observeSalesforceSingleTarget({
  moon, request, currentCatalog, authorization, credential, limits,
  signal, callResource = callHttpsCredentialResource,
}) {
  if (!moon || !request || !currentCatalog || !authorization?.grant ||
      !credential || typeof callResource !== 'function' ||
      !Number.isSafeInteger(limits?.maxResponseBytes) ||
      limits.maxResponseBytes < 1 || limits.maxResponseBytes > 1_000_000 ||
      !Number.isSafeInteger(limits.maxNodes) || limits.maxNodes < 1 ||
      limits.maxNodes > 100_000 ||
      !Number.isSafeInteger(limits.maxDepth) || limits.maxDepth < 1 ||
      limits.maxDepth > 64 ||
      !Number.isSafeInteger(limits.maxIdentityBytes) ||
      limits.maxIdentityBytes < 1 || limits.maxIdentityBytes > 1_000_000) {
    fail('InvalidSalesforceTargetObservation');
  }
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {callResource}});
  const scope = context.scope;
  if (moon.salesforceSingleWriteRequestMethod(request) !== 'PATCH' ||
      scope.operation !== 'salesforce:record:observe' ||
      !matchesSalesforceCredentialOrg(context.credential,
        moon.salesforceSingleWriteRequestOrgId(request)) ||
      !moon.salesforceSingleWriteRequestScopeMatches(
        request, scope.tenant, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin,
        scope.runInvocationCid, scope.dispatchRequestCid)) {
    fail('ForeignSalesforceTargetObservation');
  }
  checked(moon.salesforceRecheckSingleWriteRequest(request, currentCatalog));
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({
    authorization: context.authorization,
    credential: context.credential,
    callResource: context.callbacks.callResource,
    operation: 'salesforce:record:observe', method: 'GET',
    path: moon.salesforceSingleWriteRequestPath(request),
    maxResponseBytes: context.limits.maxResponseBytes,
    signal,
  });
  if (response.statusCode !== 200 && response.statusCode !== 404) {
    fail('SalesforceTargetObservationRejected');
  }
  // A 404, especially on an external-ID path, is not proof that the
  // approved target was absent. Only a verified 200 yields a version guard.
  const record = response.statusCode === 200 ? checked(
    moon.salesforcePrepareTargetObservation(
      request, response.statusCode, response.body,
      context.limits.maxResponseBytes, context.limits.maxNodes,
      context.limits.maxDepth, context.limits.maxIdentityBytes)) : undefined;
  return Object.freeze({
    request, useCid: response.useCid, statusCode: response.statusCode,
    body: response.body, record,
    versionCid: record === undefined ? undefined :
      moon.salesforceTargetObservationVersionCid(record),
  });
}

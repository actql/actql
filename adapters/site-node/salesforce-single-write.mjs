import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const count = value => Number.isSafeInteger(value) && value > 0;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// This reports a bounded physical observation, not an Effect outcome. The
// Host must own preflight, durable dispatch, receipt admission and recovery.
export async function writeSalesforceSingleRecord({
  moon,
  request,
  currentObservation,
  authorization,
  credential,
  limits,
  signal,
  callResource = callHttpsCredentialResource,
}) {
  if (!moon || !request || !currentObservation || !authorization?.grant ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.scope ||
      !credential || typeof credential !== 'object' ||
      typeof callResource !== 'function' || !limits ||
      !count(limits.maxRequestBytes) || limits.maxRequestBytes > 1_000_000 ||
      !count(limits.maxResponseBytes) ||
      limits.maxResponseBytes > 1_000_000 ||
      !count(limits.maxNodes) || limits.maxNodes > 1000 ||
      !count(limits.maxDepth) || limits.maxDepth > 32) {
    fail('InvalidSalesforceSingleWrite');
  }
  const scope = authorization.scope;
  const operation = moon.salesforceSingleWriteRequestGrantOperation(request);
  if (!matchesSalesforceCredentialOrg(credential,
      moon.salesforceSingleWriteRequestOrgId(request)) ||
      scope.operation !== operation ||
      !moon.salesforceSingleWriteRequestScopeMatches(
        request, scope.tenant, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
        scope.dispatchRequestCid)) {
    fail('ForeignSalesforceSingleWrite');
  }
  checked(moon.salesforceRecheckSingleWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const response = await callResource({
    ...credential,
    ...authorization,
    operations: new Map([[operation, Object.freeze({
      method: moon.salesforceSingleWriteRequestMethod(request),
      path: moon.salesforceSingleWriteRequestPath(request),
      body: moon.salesforceSingleWriteRequestBody(request),
    })]]),
    maxRequestBytes: limits.maxRequestBytes,
    maxResponseBytes: limits.maxResponseBytes,
    returnRejectedResponse: true,
    signal,
  });
  const observation = Object.freeze({
    useCid: response.useCid,
    statusCode: response.statusCode,
    body: response.body,
  });
  if (!response.accepted) {
    return Object.freeze({kind: 'provider-response', observation});
  }
  try {
    const projected = checked(moon.salesforceProjectSingleWriteSuccess(
      request, response.statusCode, response.body,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth));
    return Object.freeze({
      kind: 'typed-success-response',
      observation,
      result: checked(moon.salesforceSingleWriteSuccessProjection(projected)),
    });
  } catch (cause) {
    // An HTTP success with an invalid or unsupported response is not a
    // confirmed Effect success. Preserve the exact bounded observation.
    return Object.freeze({
      kind: 'unclassified-response', observation, cause,
    });
  }
}

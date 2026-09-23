import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const count = value => Number.isSafeInteger(value) && value > 0;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// The same MoonBit projection is used for a fresh HTTPS observation and a
// durable batch response recovered after restart. It never performs I/O.
export function projectSalesforceCollectionObservation({
  moon, request, observation, limits,
}) {
  if (!moon || !request || !observation || !limits ||
      !count(limits.maxResponseBytes) || limits.maxResponseBytes > 1_000_000 ||
      !count(limits.maxNodes) || limits.maxNodes > 1000 ||
      !count(limits.maxDepth) || limits.maxDepth > 32 ||
      !count(limits.maxRows) || limits.maxRows > 200 ||
      !Number.isSafeInteger(observation.statusCode) ||
      observation.statusCode < 100 || observation.statusCode > 599 ||
      !(observation.body instanceof Uint8Array)) {
    fail('InvalidSalesforceCollectionObservation');
  }
  if (observation.statusCode < 200 || observation.statusCode >= 300) {
    return Object.freeze({kind: 'provider-response', observation});
  }
  try {
    const projected = checked(moon.salesforceProjectCollectionWriteResponse(
      request, observation.statusCode, observation.body,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth,
      limits.maxRows));
    return Object.freeze({
      kind: 'typed-row-response', observation,
      result: projected,
      rowCount: moon.salesforceCollectionWriteResponseRowCount(projected),
    });
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response', observation, cause});
  }
}

// One physical Collections call for rows of one admitted continue member.
// This is not apply admission, a dispatch permit, or an Effect receipt.
export async function writeSalesforceContinueCollection({
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
      !count(limits.maxDepth) || limits.maxDepth > 32 ||
      !count(limits.maxRows) || limits.maxRows > 200) {
    fail('InvalidSalesforceCollectionWrite');
  }
  const scope = authorization.scope;
  const operation = moon.salesforceCollectionWriteRequestGrantOperation(request);
  const rowCount = moon.salesforceCollectionWriteRequestRowCount(request);
  if (!count(rowCount) || rowCount > limits.maxRows) {
    fail('SalesforceCollectionRowLimitExceeded');
  }
  if (!matchesSalesforceCredentialOrg(credential,
      moon.salesforceCollectionWriteRequestOrgId(request)) ||
      scope.operation !== operation ||
      !moon.salesforceCollectionWriteRequestScopeMatches(
        request, scope.tenant, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
        scope.dispatchRequestCid)) {
    fail('ForeignSalesforceCollectionWrite');
  }
  checked(moon.salesforceRecheckCollectionWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const response = await callResource({
    ...credential,
    ...authorization,
    operations: new Map([[operation, Object.freeze({
      method: moon.salesforceCollectionWriteRequestMethod(request),
      path: moon.salesforceCollectionWriteRequestPath(request),
      body: moon.salesforceCollectionWriteRequestBody(request),
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
  return projectSalesforceCollectionObservation({
    moon, request, observation, limits,
  });
}

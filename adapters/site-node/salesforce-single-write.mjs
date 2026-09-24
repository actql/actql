import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';
import {invokeScopedCredentialOperation, ownInvocationContext} from
  '../host-common/owned-invocation-context.mjs';

const count = value => Number.isSafeInteger(value) && value > 0;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

// Reclassify the same bounded physical bytes after a ledger restart. MoonBit
// owns the typed Salesforce response judgment; this function never sends.
export function projectSalesforceSingleObservation({
  moon, request, observation, limits,
}) {
  if (!moon || !request || !observation || !limits ||
      !count(limits.maxResponseBytes) || limits.maxResponseBytes > 1_000_000 ||
      !count(limits.maxNodes) || limits.maxNodes > 1000 ||
      !count(limits.maxDepth) || limits.maxDepth > 32 ||
      !Number.isSafeInteger(observation.statusCode) ||
      observation.statusCode < 100 || observation.statusCode > 599 ||
      !(observation.body instanceof Uint8Array)) {
    fail('InvalidSalesforceSingleObservation');
  }
  if (observation.statusCode < 200 || observation.statusCode >= 300) {
    return Object.freeze({kind: 'provider-response', observation});
  }
  try {
    const projected = checked(moon.salesforceProjectSingleWriteSuccess(
      request, observation.statusCode, observation.body,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth));
    return Object.freeze({
      kind: 'typed-success-response', observation,
      response: projected,
      result: checked(moon.salesforceSingleWriteSuccessProjection(projected)),
    });
  } catch (cause) {
    // An HTTP success with an invalid or unsupported response is not a
    // confirmed Effect success. Preserve the exact bounded observation.
    return Object.freeze({kind: 'unclassified-response', observation, cause});
  }
}

// This reports a bounded physical observation, not an Effect outcome. The
// Host must own preflight, durable dispatch, receipt admission and recovery.
export async function sendRawSalesforceSingleRecord({
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
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {callResource}});
  const scope = context.scope;
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
  const response = await invokeScopedCredentialOperation({
    authorization: context.authorization,
    credential: context.credential,
    callResource: context.callbacks.callResource, operation,
    method: moon.salesforceSingleWriteRequestMethod(request),
    path: moon.salesforceSingleWriteRequestPath(request),
    body: moon.salesforceSingleWriteRequestBody(request),
    maxRequestBytes: context.limits.maxRequestBytes,
    maxResponseBytes: context.limits.maxResponseBytes,
    signal,
  });
  const observation = Object.freeze({
    useCid: response.useCid,
    statusCode: response.statusCode,
    body: response.body,
  });
  return Object.freeze({observation, limits: context.limits});
}

export async function writeSalesforceSingleRecord(options) {
  const raw = await sendRawSalesforceSingleRecord(options);
  return projectSalesforceSingleObservation({
    moon: options.moon, request: options.request,
    observation: raw.observation, limits: raw.limits,
  });
}

import {checked} from '../../../host-common/runtime-result.mjs';
import {invokeScopedCredentialOperation, ownInvocationContext,
  ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const validLimits = limits =>
  Number.isSafeInteger(limits?.maxResponseBytes) &&
  limits.maxResponseBytes >= 1 && limits.maxResponseBytes <= 1_000_000 &&
  Number.isSafeInteger(limits.maxNodes) &&
  limits.maxNodes >= 1 && limits.maxNodes <= 100_000 &&
  Number.isSafeInteger(limits.maxDepth) &&
  limits.maxDepth >= 1 && limits.maxDepth <= 64 &&
  Number.isSafeInteger(limits.maxIdentityBytes) &&
  limits.maxIdentityBytes >= 1 && limits.maxIdentityBytes <= 1_000_000;

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
      !validLimits(limits)) {
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
    beforeWire: record === undefined ? undefined :
      moon.salesforceTargetObservationBeforeValueWire(record),
  });
}

// Keep the complete physical target-read inventory under one bounded Site
// operation. The caller still owns the Preview and MoonBit whole-set guard
// admission; no observation here is a write permit.
export async function observeSalesforceTargetSet({
  moon, members, maxMembers, maxRows, maxTotalResponseBytes, signal,
}) {
  if (!moon || !Array.isArray(members) || members.length === 0 ||
      !Number.isSafeInteger(maxMembers) || maxMembers < 1 ||
      maxMembers > 1024 ||
      members.length > maxMembers || !Number.isSafeInteger(maxRows) ||
      maxRows < 1 || maxRows > 100_000 ||
      !Number.isSafeInteger(maxTotalResponseBytes) ||
      maxTotalResponseBytes < 1 || maxTotalResponseBytes > 100_000_000) {
    fail('InvalidSalesforceTargetSet');
  }
  let totalRows = 0;
  const owned = members.map(member => {
    if (!Array.isArray(member?.requests) ||
        member.requests.length === 0 ||
        typeof member.authorizationForRow !== 'function' ||
        !member.currentCatalog || !member.credential ||
        !validLimits(member.limits)) {
      fail('InvalidSalesforceTargetSet');
    }
    totalRows += member.requests.length;
    if (totalRows > maxRows) fail('InvalidSalesforceTargetSet');
    return Object.freeze({
      requests: Object.freeze([...member.requests]),
      currentCatalog: member.currentCatalog,
      authorizationForRow: member.authorizationForRow,
      credential: Object.freeze({...member.credential}),
      limits: ownInvocationLimits(member.limits),
    });
  });
  const observations = [];
  let observedBytes = 0;
  for (let memberIndex = 0; memberIndex < owned.length; memberIndex++) {
    const member = owned[memberIndex];
    const rows = [];
    for (let rowIndex = 0; rowIndex < member.requests.length; rowIndex++) {
      signal?.throwIfAborted();
      const remaining = maxTotalResponseBytes - observedBytes;
      if (remaining < 1) fail('SalesforceTargetSetByteLimit');
      const authorization = await member.authorizationForRow(rowIndex);
      const observed = await observeSalesforceSingleTarget({
        moon, request: member.requests[rowIndex],
        currentCatalog: member.currentCatalog,
        authorization, credential: member.credential,
        limits: {...member.limits,
          maxResponseBytes: Math.min(member.limits.maxResponseBytes,
            remaining)}, signal,
      });
      observedBytes += observed.body.byteLength;
      if (observed.versionCid === undefined) {
        fail('UnresolvedSalesforceTarget');
      }
      rows.push(observed);
    }
    observations.push(Object.freeze(rows));
  }
  return Object.freeze(observations);
}

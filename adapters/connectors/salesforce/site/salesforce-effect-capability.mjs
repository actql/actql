import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationAuthorization} from
  '../../../host-common/owned-invocation-context.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const owners = new WeakMap();
const fail = () => {
  throw Object.assign(new Error('InvalidSalesforceEffectCapability'), {
    code: 'InvalidSalesforceEffectCapability',
  });
};

function currentGrant(owner) {
  const {credential, authorization} = owner;
  const {control, journal, now} = credential;
  const grant = journal.checkGrant(control.identity(authorization.grant),
    BigInt(now()), authorization.scope, control);
  return control.projection(grant)[7];
}

function checkRequests(owner, requests, runtimeBundleCid) {
  if (!Array.isArray(requests) || requests.length === 0 ||
      requests.length > owner.maxRows) fail();
  const {moon, authorization, credential, evidence} = owner;
  const scope = authorization.scope;
  for (const request of requests) {
    if (!matchesSalesforceCredentialOrg(credential,
        moon.salesforceSingleWriteRequestOrgId(request)) ||
        scope.operation !==
          moon.salesforceSingleWriteRequestGrantOperation(request) ||
        !moon.salesforceSingleWriteRequestScopeMatches(request,
          scope.tenant, scope.principal, scope.environment,
          scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
          scope.connectorRevision, scope.resourceOrigin,
          scope.runInvocationCid, scope.dispatchRequestCid)) fail();
    checked(moon.salesforceCheckWriteCapabilityRequest(evidence,
      request, runtimeBundleCid));
  }
}

// The loaded Connector defines the supported profile in MoonBit, and the
// Site's declaration must cover each request (Resource, operation, fields,
// key). The Site
// authenticates the configured runtime and connection against its signed
// grant journal; no secret is resolved and no credential use is consumed.
export function issueSalesforceEffectCapability({moon, requests,
  currentObservation, authorization, credential, declaration,
  collection = false, maxRows, maxBytes}) {
  if (!moon || !Array.isArray(requests) || !requests[0] || !declaration ||
      !currentObservation || typeof collection !== 'boolean' ||
      !Number.isSafeInteger(maxRows) || maxRows < 1 || maxRows > 100_000 ||
      !Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > 1_000_000 ||
      typeof credential?.journal?.checkGrant !== 'function' ||
      typeof credential.control?.projection !== 'function' ||
      (credential.now !== undefined && typeof credential.now !== 'function')) {
    fail();
  }
  const owner = {
    moon, maxRows,
    credential: Object.freeze({...credential, now: credential.now ?? Date.now}),
    authorization: ownInvocationAuthorization({...authorization,
      useId: 'capability-admission'}),
  };
  // The Site's admitted declaration must cover every request's Resource,
  // operation, fields and upsert key, for this same Site, before any grant
  // or credential check.
  for (const request of requests) {
    checked(moon.salesforceCheckDeclaredSingleWrite(declaration, request));
  }
  const runtimeBundleCid = currentGrant(owner);
  owner.evidence = checked(moon.salesforcePrepareWriteCapability(
    requests[0], runtimeBundleCid, collection, maxBytes));
  checkRequests(owner, requests, runtimeBundleCid);
  checked(moon.salesforceRecheckWriteCapability(owner.evidence,
    currentObservation));
  const result = Object.freeze({
    identity: moon.salesforceWriteCapabilityIdentity(owner.evidence),
    wire: moon.salesforceWriteCapabilityBody(owner.evidence),
  });
  owners.set(result, Object.freeze(owner));
  return result;
}

export function inspectSalesforceEffectCapability(capability, requests,
  {currentObservation, collection} = {}) {
  const owner = owners.get(capability);
  if (!owner) fail();
  const runtimeBundleCid = currentGrant(owner);
  checkRequests(owner, requests, runtimeBundleCid);
  if (currentObservation !== undefined) {
    checked(owner.moon.salesforceRecheckWriteCapability(owner.evidence,
      currentObservation));
  }
  const route = owner.moon.salesforceWriteCapabilityRoute(owner.evidence);
  if (collection !== undefined && collection !== (route === 1)) fail();
  return Object.freeze({identity: capability.identity, route});
}

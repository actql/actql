import {checked} from '../../../host-common/runtime-result.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation, ownInvocationContext,
  ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
// Membership is issued only by the actual Account read below, never by a
// restored Catalog, copied response, ETag string or equal content identity.
const accountTargetOriginals = new WeakMap();
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
async function observeSingleTarget({
  moon, request, currentCatalog, authorization, credential, limits,
  signal, callResource = callHttpsCredentialResource,
}, accountConditional) {
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
        request, scope.namespaceId, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin,
        scope.runInvocationCid, scope.dispatchRequestCid)) {
    fail('ForeignSalesforceTargetObservation');
  }
  checked(moon.salesforceRecheckSingleWriteRequest(request, currentCatalog));
  if (accountConditional &&
      // The checked SingleWriteRequest Owner derives this exact object/Id path.
      // External-ID and collection routes cannot satisfy this profile.
      (!/^\/services\/data\/v[1-9][0-9]*\.[0-9]+\/sobjects\/Account\/[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?$/u
        .test(moon.salesforceSingleWriteRequestPath(request)) ||
       moon.salesforceSingleWriteRequestGrantOperation(request) !== 'salesforce:record:update')) {
    fail('SalesforceAccountConditionalProfileUnavailable');
  }
  const useProjection = accountConditional ? context.credential.control.useProjection : undefined;
  const grantIdentity = accountConditional ? context.credential.control.identity : undefined;
  const expectedGrantCid = accountConditional
    ? Reflect.apply(grantIdentity, context.credential.control, [context.authorization.grant]) : undefined;
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({
    authorization: context.authorization,
    credential: accountConditional ? {...context.credential,
      retainRunResponseOriginal: true} : context.credential,
    callResource: context.callbacks.callResource,
    operation: 'salesforce:record:observe', method: 'GET',
    path: moon.salesforceSingleWriteRequestPath(request),
    ...(accountConditional ? {
      headers: [['accept', 'application/json'], ['accept-encoding', 'identity']],
      responseHeaders: ['etag', 'content-encoding'],
    } : {}),
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
  const observed = Object.freeze({
    request, useCid: response.useCid, statusCode: response.statusCode,
    body: response.body, record,
    versionCid: record === undefined ? undefined :
      moon.salesforceTargetObservationVersionCid(record),
    beforeWire: record === undefined ? undefined :
      moon.salesforceTargetObservationBeforeValueWire(record),
  });
  if (accountConditional) {
    accountTargetOriginals.set(observed, {moon, request, currentCatalog,
      control: context.credential.control, journal: context.credential.journal,
      scope: context.scope, expectedGrantCid, expectedUseId: context.authorization.useId,
      useProjection,
      response, signal, failure: undefined, facts: undefined});
  }
  return observed;
}

export function observeSalesforceSingleTarget(options) {
  return observeSingleTarget(options, false);
}

// A distinct physical read profile. Each call still needs its original read
// grant and consumes one ordinary Credential use. This issues no write permit,
// request identity, saved evidence, currentness or conditional send authority.
export function observeSalesforceAccountConditionalTarget(options) {
  return observeSingleTarget(options, true);
}

// A synchronous historical borrow, not a transport or digest authority.
// The existing Credential Owner checks the original received body both before
// and after the finisher, including result inspection. An observed mutation
// is terminal even if another alias later restores the bytes.
export function withSalesforceAccountTargetOriginal(observed, originals, consume) {
  const original = accountTargetOriginals.get(observed);
  if (original === undefined || original.moon !== originals?.moon ||
      original.request !== originals.request ||
      original.currentCatalog !== originals.currentCatalog ||
      original.control !== originals.credential?.control ||
      original.journal !== originals.credential?.journal || typeof consume !== 'function') {
    fail('SalesforceAccountTargetOriginalUnavailable');
  }
  if (original.failure !== undefined) throw original.failure;
  const check = () => {
    try {
      if (accountTargetOriginals.get(observed) !== original) {
        fail('SalesforceAccountTargetOriginalUnavailable');
      }
      original.signal?.throwIfAborted();
      return withHttpsCredentialRunResponseOriginal(original.response,
        original.control, original.journal, credentialFacts => {
          const use = Reflect.apply(original.useProjection, original.control, [credentialFacts.use]);
          const {requestRepresentation: sent, responseRepresentation: received} = credentialFacts;
          const values = name => original.response.headers
            .filter(pair => pair[0] === name).map(pair => pair[1]);
          const etags = values('etag');
          const encodings = values('content-encoding');
          if (observed.record === undefined || observed.statusCode !== 200 ||
              credentialFacts.response !== original.response ||
              credentialFacts.scope.operation !== 'salesforce:record:observe' ||
              !invocationBindingsMatch(credentialFacts.scope, original.scope) ||
              use[0] !== original.response.useCid || use[1] !== original.expectedGrantCid ||
              use[2] !== original.expectedUseId ||
              credentialFacts.method !== 'GET' ||
              credentialFacts.path !== original.moon.salesforceSingleWriteRequestPath(original.request) ||
              credentialFacts.requestBodyBytes !== 0 ||
              sent?.accept !== 'application/json' || sent.acceptEncoding !== 'identity' ||
              sent.ifMatch !== undefined || received?.etagCount !== 1 ||
              received.contentEncodingCount > 1 || etags.length !== 1 ||
              typeof etags[0] !== 'string' || etags[0].length > 1024 ||
              !/^"[\x21\x23-\x7e\x80-\xff]*"$/u.test(etags[0]) ||
              encodings.length !== received.contentEncodingCount ||
              (encodings.length !== 0 && encodings[0] !== 'identity')) {
            fail('SalesforceAccountConditionalRepresentationUnavailable');
          }
          original.facts ??= Object.freeze({request: original.request,
            targetObservation: observed.record, versionCid: observed.versionCid,
            etag: etags[0], response: original.response, credentialFacts});
          return original.facts;
        });
    } catch (cause) { original.failure = cause; throw cause; }
  };
  const facts = check();
  let primary;
  let failed = false;
  let result;
  try {
    result = consume(facts);
    if (result !== null && result !== undefined && typeof result.then === 'function') {
      void Promise.resolve(result).catch(() => {});
      fail('InvalidSalesforceAccountTargetConsumer');
    }
  } catch (cause) { failed = true; primary = cause; }
  try { check(); }
  catch (cause) { if (!failed) throw cause; }
  if (failed) throw primary;
  return result;
}

// Retire this borrow only. Escaped response aliases, confirmed Credential
// outcomes and physical child/Store cleanup remain their original owners'.
export function retireSalesforceAccountTargetOriginal(observed) {
  accountTargetOriginals.delete(observed);
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
    const readChild = member?.readChild;
    if (!Array.isArray(member?.requests) ||
        member.requests.length === 0 ||
        typeof member.authorizationForRow !== 'function' ||
        readChild !== undefined && typeof readChild !== 'function' ||
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
      // Retain the original callback and receiver before the first await. The
      // shared owner still admits and retains its original physical child.
      readChild: readChild === undefined ? undefined
        : (...args) => Reflect.apply(readChild, member, args),
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
        ...(member.readChild === undefined ? {} : {callResource: input =>
          member.readChild(authorization, input, rowIndex)}),
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

import {checked} from '../../../host-common/runtime-result.mjs';
import {callHttpsCredentialResource, withHttpsCredentialRunResponseOriginal} from
  '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';

// Live Describe correspondence is held only for an explicitly retained result.
// Recovered Catalog evidence never registers in this map.
const describeOriginals = new WeakMap();

const versionPattern = /^v[1-9][0-9]*\.[0-9]+$/;
const namePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const describeOperation = 'salesforce:catalog:describe';
export {describeOperation as salesforceDescribeOperation};
export const NAMED_EVIDENCE_VERSION = 'actql-salesforce-named-evidence/0.1';

const count = value => Number.isInteger(value) && value >= 0 &&
  value <= 2_147_483_647;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

/// Describe exactly the named Resources, without the provider's full sObject
/// listing. Each describe uses its own authorization, which the caller issues
/// only after deciding metadata read authority for that Resource. The
/// observation is always incomplete; `retainEvidence` keeps the exact
/// describe responses so the observation can be reprojected later without
/// provider I/O.
export async function describeSalesforceResources({
  moon, apiVersion, connectionRevision, orgId, syncOccurrence,
  maxObservationBytes, resources, authorizationForDescribe, credential,
  describeLimits: requestedLimits, retainEvidence = false,
  retainPublicationOriginals = false,
  maxRetainedBytes = 0, callResource = callHttpsCredentialResource, signal, controlConstruction,
}) {
  if (!moon || !versionPattern.test(apiVersion) ||
      typeof connectionRevision !== 'string' || connectionRevision === '' ||
      !matchesSalesforceCredentialOrg(credential, orgId) ||
      typeof syncOccurrence !== 'string' || syncOccurrence === '' ||
      !count(maxObservationBytes) || maxObservationBytes === 0 ||
      !Array.isArray(resources) || resources.length === 0 ||
      resources.some(name => typeof name !== 'string' ||
        !namePattern.test(name)) ||
      new Set(resources).size !== resources.length ||
      typeof authorizationForDescribe !== 'function' ||
      typeof retainEvidence !== 'boolean' ||
      typeof retainPublicationOriginals !== 'boolean' ||
      (retainPublicationOriginals && !retainEvidence) ||
      (retainEvidence && (!count(maxRetainedBytes) ||
        maxRetainedBytes === 0)) ||
      typeof callResource !== 'function' ||
      controlConstruction !== undefined && typeof controlConstruction !== 'function') {
    fail('InvalidSalesforceNamedDescribe');
  }
  const limits = ownInvocationLimits(requestedLimits);
  if (!count(limits.maxBytes) || limits.maxBytes === 0 ||
      !count(limits.maxNodes) || !count(limits.maxDepth) ||
      !count(limits.maxFields) || !count(limits.maxNameUnits)) {
    fail('InvalidSalesforceCatalogLimits');
  }
  // The same Run control frame backs each synchronous phase. The HTTP await
  // stays outside it; retained Catalog/evidence backing survives between phases.
  const construct = callback => controlConstruction === undefined ? callback()
    : controlConstruction(undefined, callback, []);
  const sync = construct(() => checked(moon.salesforceCatalogBeginNamed([...resources])));
  const prefix = `/services/data/${apiVersion}/sobjects/`;
  const bodies = [];
  const originalResponses = [];
  const useCids = [];
  const digests = [];
  let scope;
  let retainedBytes = 0;
  let interruptionCode;
  let originalPublicationFailure;
  for (const name of resources) {
    if (signal?.aborted) {
      interruptionCode = 'SalesforceCatalogCancelled';
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
    try {
      const authorization = ownInvocationAuthorization(
        await authorizationForDescribe(name));
      if (!authorization?.grant || typeof authorization.useId !== 'string' ||
          authorization.scope?.operation !== describeOperation ||
          (scope !== undefined &&
            !invocationBindingsMatch(authorization.scope, scope))) {
        fail('InvalidSalesforceCatalogAuthorization');
      }
      scope ??= authorization.scope;
      const remaining = retainEvidence
        ? maxRetainedBytes - retainedBytes : limits.maxBytes;
      if (remaining < 1) fail('SalesforceCatalogRetainedLimit');
      const response = await invokeScopedCredentialOperation({
        authorization, credential: retainPublicationOriginals
          ? {...credential, retainRunResponseOriginal: true} : credential, callResource,
        operation: describeOperation, method: 'GET',
        path: `${prefix}${name}/describe`,
        maxResponseBytes: Math.min(limits.maxBytes, remaining), signal,
      });
      if (retainPublicationOriginals) originalResponses.push(Object.freeze({name, response, path: `${prefix}${name}/describe`}));
      construct(() => {
        const bytes = Buffer.from(response.body);
        retainedBytes += retainEvidence ? bytes.byteLength : 0;
        bodies.push(retainEvidence ? bytes.toString('base64') : null);
        useCids.push(response.useCid);
        digests.push(moon.salesforceCatalogResponseSha256(response.body));
        if (response.accepted) {
          checked(moon.salesforceCatalogDescribe(sync, name, response.body,
            limits.maxBytes, limits.maxNodes, limits.maxDepth,
            limits.maxFields, limits.maxNameUnits));
        } else {
          checked(moon.salesforceCatalogUnavailable(sync, name,
            moon.salesforceCatalogHttpFailure(response.statusCode,
              response.body, limits.maxBytes)));
        }
      });
    } catch (error) {
      if (error?.code === 'MoonBitHostFailure' ||
          error?.code === 'InvalidHostRuntimeResult') throw error;
      interruptionCode = signal?.aborted ? 'SalesforceCatalogCancelled'
        : typeof error?.code === 'string' ? error.code
          : 'SalesforceCatalogInterrupted';
      if (retainPublicationOriginals) originalPublicationFailure = {cause: error};
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
  }
  checked(moon.salesforceCatalogFinish(sync));
  // Original Journal outcome/cleanup failures belong to the same Host owner.
  // The live publication path must not replace their carrier with a status code.
  if (originalPublicationFailure !== undefined) throw originalPublicationFailure.cause;
  if (scope === undefined) {
    // No describe was authorized: nothing was observed.
    fail(interruptionCode ?? 'SalesforceCatalogInterrupted');
  }
  while (useCids.length < resources.length) {
    useCids.push(undefined);
    digests.push(undefined);
    bodies.push(null);
  }
  return construct(() => {
    const observation = checked(moon.salesforcePrepareCatalogObservation(
      sync, scope.namespaceId, scope.principal, scope.environment,
      connectionRevision, orgId, scope.siteKey, scope.siteGeneration,
      scope.connectorRegistration, scope.connectorRevision,
      scope.resourceOrigin, scope.runInvocationCid, scope.dispatchRequestCid,
      syncOccurrence, '', useCids, digests, maxObservationBytes));
    const observationJson = moon.salesforceCatalogObservationJson(observation);
    const outcomes = resources.map(name =>
      moon.salesforceCatalogResourceState(sync, name));
    const result = Object.freeze({
      observation, observationJson,
      observationCid: moon.salesforceCatalogObservationCid(observation),
      status: interruptionCode === undefined ? 'observed' : 'interrupted',
      interruptionCode,
      evidence: retainEvidence ? Object.freeze({
        version: NAMED_EVIDENCE_VERSION,
        names: Object.freeze([...resources]),
        outcomes: Object.freeze(outcomes),
        describeBodyBase64: Object.freeze(bodies),
        describeUseCids: Object.freeze(useCids.map(value => value ?? null)),
        describeResponseSha256: Object.freeze(
          digests.map(value => value ?? null)),
        describeLimits: Object.freeze({...limits}),
        maxObservationBytes,
        observationJson,
      }) : undefined,
    });
    if (retainPublicationOriginals && interruptionCode === undefined) {
      describeOriginals.set(result, {credential, responses: Object.freeze(originalResponses)});
    }
    return result;
  });
}

// The same physical Credential Owner confirms the original grant/use and raw
// response. This synchronous projection issues neither authority nor custody.
export function withSalesforceNamedDescribeOriginals(result, credential, consume) {
  const original = describeOriginals.get(result);
  if (original === undefined || original.credential !== credential ||
      typeof consume !== 'function' ||
      original.responses.length !== result.evidence.names.length) {
    fail('SalesforceDescribeOriginalUnavailable');
  }
  const operations = original.responses.map(({name, response, path}, index) =>
    withHttpsCredentialRunResponseOriginal(response, credential.control,
      credential.journal, facts => {
        if (name !== result.evidence.names[index] || facts.method !== 'GET' ||
            facts.scope.operation !== describeOperation || facts.path !== path ||
            facts.requestBodyBytes !== 0 ||
            facts.response !== response || response.useCid !== result.evidence.describeUseCids[index] ||
            facts.responseSha256 !== result.evidence.describeResponseSha256[index] ||
            response.body.toString('base64') !== result.evidence.describeBodyBase64[index]) {
          fail('SalesforceDescribeOriginalChanged');
        }
        return Object.freeze({name, ...facts});
      }));
  // Raw aliases reach the synchronous finisher. The Credential Owner remains
  // the sole membership/hash authority before any result can leave this borrow.
  const recheckOriginals = () => {
    for (const {response} of original.responses) {
      withHttpsCredentialRunResponseOriginal(response, credential.control,
        credential.journal, () => undefined);
    }
  };
  let value;
  try {
    value = consume(Object.freeze({observation: result.observation,
      observationJson: result.observationJson, observationCid: result.observationCid,
      evidence: result.evidence, operations: Object.freeze(operations)}));
    if (value !== null && value !== undefined && typeof value.then === 'function') {
      void Promise.resolve(value).catch(() => {});
      fail('InvalidSalesforcePublicationConsumer');
    }
  } catch (cause) {
    // Observe and latch changed original membership even on failure, while
    // retaining the finisher's exact primary exception and cleanup carrier.
    try { recheckOriginals(); } catch { /* The original Credential Owner retains this failure. */ }
    throw cause;
  }
  recheckOriginals();
  return value;
}

/// Reproject retained describe-only evidence. It must reproduce the exact
/// observation (`expectedObservationCid`); no credential or provider I/O is
/// used, and the result stays incomplete.
export function recoverNamedSalesforceObservation({moon, evidence,
  expectedObservationCid, beforeRecover}) {
  if (!moon || evidence?.version !== NAMED_EVIDENCE_VERSION ||
      !Array.isArray(evidence.names) ||
      typeof evidence.observationJson !== 'string' ||
      typeof expectedObservationCid !== 'string') {
    fail('InvalidSalesforceNamedEvidence');
  }
  const n = evidence.names.length;
  for (const key of ['outcomes', 'describeBodyBase64', 'describeUseCids',
    'describeResponseSha256']) {
    if (!Array.isArray(evidence[key]) || evidence[key].length !== n) {
      fail('InvalidSalesforceNamedEvidence');
    }
  }
  const binding = JSON.parse(evidence.observationJson).binding;
  const limits = evidence.describeLimits;
  // The caller's existing member token already funds the encoded input and
  // binary/lexical prelude. Wider inventories keep the complete old quote
  // BEFORE allocation; the exact one-body case grows after observing bytes.
  if (beforeRecover !== undefined && typeof beforeRecover !== 'function') {
    fail('InvalidSalesforceNamedEvidence');
  }
  if (n !== 1) beforeRecover?.(evidence, undefined);
  const bodies = evidence.describeBodyBase64.map(value => value === null ? undefined
    : Buffer.from(value, 'base64'));
  if (n === 1) beforeRecover?.(evidence, bodies);
  const observation = checked(moon.salesforceRecoverNamedCatalogObservation(
    evidence.observationJson, [...evidence.names], bodies,
    [...evidence.outcomes],
    binding.namespace_id, binding.principal, binding.environment,
    binding.connection_revision, binding.org_id, binding.site_key,
    binding.site_generation, binding.connector_registration,
    binding.connector_revision, binding.resource_origin,
    binding.run_invocation_cid, binding.dispatch_request_cid,
    binding.sync_occurrence,
    evidence.describeUseCids.map(value => value ?? undefined),
    evidence.describeResponseSha256.map(value => value ?? undefined),
    limits.maxBytes, limits.maxNodes, limits.maxDepth, limits.maxFields,
    limits.maxNameUnits, evidence.maxObservationBytes));
  if (moon.salesforceCatalogObservationCid(observation) !==
      expectedObservationCid) {
    fail('ForeignSalesforceNamedEvidence');
  }
  return observation;
}

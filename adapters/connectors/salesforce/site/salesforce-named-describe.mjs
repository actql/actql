import {checked} from '../../../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from
  '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';

const versionPattern = /^v[1-9][0-9]*\.[0-9]+$/;
const namePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const describeOperation = 'salesforce:catalog:describe';
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
  maxRetainedBytes = 0, callResource = callHttpsCredentialResource, signal,
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
      (retainEvidence && (!count(maxRetainedBytes) ||
        maxRetainedBytes === 0)) ||
      typeof callResource !== 'function') {
    fail('InvalidSalesforceNamedDescribe');
  }
  const limits = ownInvocationLimits(requestedLimits);
  if (!count(limits.maxBytes) || limits.maxBytes === 0 ||
      !count(limits.maxNodes) || !count(limits.maxDepth) ||
      !count(limits.maxFields) || !count(limits.maxNameUnits)) {
    fail('InvalidSalesforceCatalogLimits');
  }
  const sync = checked(moon.salesforceCatalogBeginNamed([...resources]));
  const prefix = `/services/data/${apiVersion}/sobjects/`;
  const bodies = [];
  const useCids = [];
  const digests = [];
  let scope;
  let retainedBytes = 0;
  let interruptionCode;
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
        authorization, credential, callResource,
        operation: describeOperation, method: 'GET',
        path: `${prefix}${name}/describe`,
        maxResponseBytes: Math.min(limits.maxBytes, remaining), signal,
      });
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
    } catch (error) {
      if (error?.code === 'MoonBitHostFailure' ||
          error?.code === 'InvalidHostRuntimeResult') throw error;
      interruptionCode = signal?.aborted ? 'SalesforceCatalogCancelled'
        : typeof error?.code === 'string' ? error.code
          : 'SalesforceCatalogInterrupted';
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
  }
  checked(moon.salesforceCatalogFinish(sync));
  if (scope === undefined) {
    // No describe was authorized: nothing was observed.
    fail(interruptionCode ?? 'SalesforceCatalogInterrupted');
  }
  while (useCids.length < resources.length) {
    useCids.push(undefined);
    digests.push(undefined);
    bodies.push(null);
  }
  const observation = checked(moon.salesforcePrepareCatalogObservation(
    sync, scope.tenant, scope.principal, scope.environment,
    connectionRevision, orgId, scope.siteKey, scope.siteGeneration,
    scope.connectorRegistration, scope.connectorRevision,
    scope.resourceOrigin, scope.runInvocationCid, scope.dispatchRequestCid,
    syncOccurrence, '', useCids, digests, maxObservationBytes));
  const observationJson = moon.salesforceCatalogObservationJson(observation);
  const outcomes = resources.map(name =>
    moon.salesforceCatalogResourceState(sync, name));
  return Object.freeze({
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
}

/// Reproject retained describe-only evidence. It must reproduce the exact
/// observation (`expectedObservationCid`); no credential or provider I/O is
/// used, and the result stays incomplete.
export function recoverNamedSalesforceObservation({moon, evidence,
  expectedObservationCid}) {
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
  const observation = checked(moon.salesforceRecoverNamedCatalogObservation(
    evidence.observationJson, [...evidence.names],
    evidence.describeBodyBase64.map(value => value === null ? undefined
      : Buffer.from(value, 'base64')),
    [...evidence.outcomes],
    binding.tenant, binding.principal, binding.environment,
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

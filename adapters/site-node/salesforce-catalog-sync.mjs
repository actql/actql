import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';

const versionPattern = /^v[1-9][0-9]*\.[0-9]+$/;
const namePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const listOperation = 'salesforce:catalog:list';
const describeOperation = 'salesforce:catalog:describe';
const bindingKeys = Object.freeze([
  'issuerAuthority', 'principal', 'tenant', 'environment',
  'siteKey', 'siteGeneration', 'runtimeBundleCid',
  'connectorRegistration', 'connectorRevision', 'resourceOrigin',
  'runInvocationCid', 'taskAttempt', 'dispatchRequestCid',
]);

const count = value => Number.isInteger(value) && value >= 0 &&
  value <= 2_147_483_647;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

function validateLimits(limits) {
  if (limits === null || typeof limits !== 'object' ||
      !count(limits.maxBytes) || limits.maxBytes === 0 ||
      !count(limits.maxNodes) || !count(limits.maxDepth) ||
      !count(limits.maxResources) || !count(limits.maxSelected) ||
      !count(limits.maxNameUnits) ||
      limits.maxSelected > limits.maxResources) {
    fail('InvalidSalesforceCatalogLimits');
  }
}

function validateAuthorization(authorization, operation, originalScope) {
  if (!authorization || typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.grant ||
      !authorization.scope || authorization.scope.operation !== operation ||
      !count(authorization.scope.siteGeneration)) {
    fail('InvalidSalesforceCatalogAuthorization');
  }
  if (originalScope !== undefined && bindingKeys.some(
    key => authorization.scope[key] !== originalScope[key])) {
    fail('ForeignSalesforceCatalogBinding');
  }
  return authorization.scope;
}

function operations(scope, path) {
  return new Map([[scope.operation, Object.freeze({method: 'GET', path})]]);
}

async function scopedGet({authorization, path, maxBytes, credential,
  callResource, signal}) {
  return await callResource({
    ...credential,
    ...authorization,
    operations: operations(authorization.scope, path),
    maxResponseBytes: maxBytes,
    returnRejectedResponse: true,
    signal,
  });
}

/// Run one bounded catalog observation at the Site. The MoonBit sync owns
/// resource identity and completeness; this adapter only performs scoped I/O.
export async function syncSalesforceCatalog({
  moon,
  apiVersion,
  connectionRevision,
  syncOccurrence,
  maxObservationBytes,
  listAuthorization,
  authorizationForDescribe,
  credential,
  listLimits,
  describeLimits,
  callResource = callHttpsCredentialResource,
  signal,
}) {
  if (!moon || !versionPattern.test(apiVersion) ||
      typeof connectionRevision !== 'string' ||
      connectionRevision.length === 0 ||
      typeof syncOccurrence !== 'string' || syncOccurrence.length === 0 ||
      !count(maxObservationBytes) || maxObservationBytes === 0 ||
      typeof authorizationForDescribe !== 'function' ||
      !credential || typeof callResource !== 'function') {
    fail('InvalidSalesforceCatalogSync');
  }
  validateLimits(listLimits);
  validateLimits({...describeLimits,
    maxResources: describeLimits?.maxFields,
    maxSelected: describeLimits?.maxFields,
  });
  const listScope = validateAuthorization(listAuthorization, listOperation);
  signal?.throwIfAborted();
  const prefix = `/services/data/${apiVersion}/sobjects/`;
  const listResponse = await scopedGet({
    authorization: listAuthorization,
    path: prefix,
    maxBytes: listLimits.maxBytes,
    credential,
    callResource,
    signal,
  });
  if (!listResponse.accepted) {
    const reason = moon.salesforceCatalogHttpFailure(
      listResponse.statusCode, listResponse.body, listLimits.maxBytes);
    throw Object.assign(new Error('SalesforceCatalogListRejected'), {
      code: 'SalesforceCatalogListRejected', reason,
    });
  }
  const listing = checked(moon.salesforceProjectListing(
    listResponse.body,
    listLimits.maxBytes,
    listLimits.maxNodes,
    listLimits.maxDepth,
    listLimits.maxResources,
    listLimits.maxSelected,
    listLimits.maxNameUnits,
  ));
  const sync = moon.salesforceCatalogBegin(listing);
  const selectedNames = moon.salesforceCatalogResourceNames(listing);
  const describeUseCids = [];
  const describeResponseSha256 = [];
  let interruptionCode;
  while (true) {
    const name = moon.salesforceCatalogNext(sync);
    if (name === undefined || name === null) break;
    if (!namePattern.test(name)) fail('InvalidSalesforceCatalogResource');
    if (signal?.aborted) {
      interruptionCode = 'SalesforceCatalogCancelled';
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
    try {
      const authorization = await authorizationForDescribe(name);
      validateAuthorization(authorization, describeOperation, listScope);
      const response = await scopedGet({
        authorization,
        path: `${prefix}${name}/describe`,
        maxBytes: describeLimits.maxBytes,
        credential,
        callResource,
        signal,
      });
      describeUseCids.push(response.useCid);
      describeResponseSha256.push(
        moon.salesforceCatalogResponseSha256(response.body));
      if (response.accepted) {
        checked(moon.salesforceCatalogDescribe(
          sync, name, response.body,
          describeLimits.maxBytes,
          describeLimits.maxNodes,
          describeLimits.maxDepth,
          describeLimits.maxFields,
          describeLimits.maxNameUnits,
        ));
      } else {
        const reason = moon.salesforceCatalogHttpFailure(
          response.statusCode, response.body, describeLimits.maxBytes);
        checked(moon.salesforceCatalogUnavailable(sync, name, reason));
      }
    } catch (error) {
      if (error?.code === 'MoonBitHostFailure' ||
          error?.code === 'InvalidHostRuntimeResult') throw error;
      interruptionCode = signal?.aborted
        ? 'SalesforceCatalogCancelled'
        : typeof error?.code === 'string'
          ? error.code
          : 'SalesforceCatalogInterrupted';
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
  }
  const complete = checked(moon.salesforceCatalogFinish(sync));
  while (describeUseCids.length < selectedNames.length) {
    describeUseCids.push(undefined);
    describeResponseSha256.push(undefined);
  }
  const observation = checked(moon.salesforcePrepareCatalogObservation(
    sync,
    listScope.tenant,
    listScope.principal,
    listScope.environment,
    connectionRevision,
    listScope.siteKey,
    listScope.siteGeneration,
    listScope.connectorRegistration,
    listScope.connectorRevision,
    listScope.resourceOrigin,
    listScope.runInvocationCid,
    listScope.dispatchRequestCid,
    syncOccurrence,
    listResponse.useCid,
    describeUseCids,
    describeResponseSha256,
    maxObservationBytes,
  ));
  return Object.freeze({
    sync,
    listing,
    observation,
    observationCid: moon.salesforceCatalogObservationCid(observation),
    observationJson: moon.salesforceCatalogObservationJson(observation),
    status: interruptionCode !== undefined
      ? 'interrupted'
      : complete ? 'complete' : 'partial',
    interruptionCode,
    listUseCid: listResponse.useCid,
    describeUseCids: Object.freeze(describeUseCids),
    describeResponseSha256: Object.freeze(describeResponseSha256),
  });
}

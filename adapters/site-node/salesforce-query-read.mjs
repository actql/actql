import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {syncSalesforceCatalog} from './salesforce-catalog-sync.mjs';

const operation = 'salesforce:query:read';
const bindingKeys = Object.freeze([
  'issuerAuthority', 'principal', 'tenant', 'environment',
  'siteKey', 'siteGeneration', 'runtimeBundleCid',
  'connectorRegistration', 'connectorRevision', 'resourceOrigin',
  'runInvocationCid', 'taskAttempt', 'dispatchRequestCid',
]);
const count = value => Number.isSafeInteger(value) && value >= 0;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

function validateAuthorization(authorization, originalScope) {
  if (!authorization || typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.grant ||
      !authorization.scope || authorization.scope.operation !== operation ||
      !count(authorization.scope.siteGeneration) ||
      (originalScope && bindingKeys.some(
        key => authorization.scope[key] !== originalScope[key]))) {
    fail('InvalidSalesforceQueryAuthorization');
  }
  return authorization.scope;
}

function validateLimits(limits) {
  if (!limits || !count(limits.maxBytes) || limits.maxBytes === 0 ||
      !count(limits.maxNodes) || limits.maxNodes === 0 ||
      !count(limits.maxDepth) || limits.maxDepth === 0 ||
      !count(limits.maxRows) || limits.maxRows === 0 ||
      !count(limits.maxLocatorUnits) || limits.maxLocatorUnits === 0 ||
      !count(limits.maxPages) || limits.maxPages === 0 ||
      !count(limits.maxTotalRows)) {
    fail('InvalidSalesforceQueryLimits');
  }
}

function validateRead({
  moon,
  plan,
  initialAuthorization,
  authorizationForPage,
  credential,
  refreshCatalog,
  limits,
  consumePage,
  callResource = callHttpsCredentialResource,
}) {
  if (!moon || !plan ||
      typeof authorizationForPage !== 'function' ||
      typeof consumePage !== 'function' || !credential ||
      typeof credential !== 'object' ||
      !refreshCatalog || typeof refreshCatalog !== 'object' ||
      typeof callResource !== 'function') {
    fail('InvalidSalesforceQueryRead');
  }
  validateLimits(limits);
  const scope = validateAuthorization(initialAuthorization);
  if (!moon.salesforceReadProjectionScopeMatches(
    plan, scope.tenant, scope.principal, scope.environment,
    scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
    scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
    scope.dispatchRequestCid,
  )) {
    fail('ForeignSalesforceQueryProjection');
  }
  return scope;
}

async function recheckCurrentCatalog(options) {
  const {moon, plan, credential, refreshCatalog, callResource, signal} = options;
  const refreshed = await syncSalesforceCatalog({
    ...refreshCatalog,
    moon,
    credential,
    callResource,
    signal,
  });
  if (refreshed.status === 'interrupted') {
    fail('SalesforceCatalogRefreshInterrupted');
  }
  checked(moon.salesforceRecheckReadProjection(plan, refreshed.observation));
  return Object.freeze({
    observationCid: refreshed.observationCid,
    observationJson: refreshed.observationJson,
    listUseCid: refreshed.listUseCid,
    describeUseCids: refreshed.describeUseCids,
  });
}

async function driveQueryPages({
  moon,
  initialAuthorization,
  authorizationForPage,
  credential,
  limits,
  consumePage,
  callResource,
  signal,
}, scope, owner) {
  const pages = [];
  try {
    while (true) {
      const path = checked(owner.nextPath());
      if (path === undefined || path === null) break;
      signal?.throwIfAborted();
      const authorization = pages.length === 0
        ? initialAuthorization
        : await authorizationForPage(path, pages.length);
      validateAuthorization(authorization, scope);
      signal?.throwIfAborted();
      const response = await callResource({
        ...credential,
        ...authorization,
        operations: new Map([[operation, Object.freeze({method: 'GET', path})]]),
        maxResponseBytes: limits.maxBytes,
        returnRejectedResponse: true,
        signal,
      });
      if (!response.accepted) {
        fail('SalesforceQueryResourceRejected');
      }
      const page = checked(owner.acceptPage(path, response.body));
      await consumePage(page, Object.freeze({path, pageIndex: pages.length}));
      owner.acknowledgePage?.(page);
      pages.push(Object.freeze({
        path,
        useCid: response.useCid,
        responseSha256: moon.salesforceQueryPageResponseSha256(page),
        rows: moon.salesforceQueryPageRowCount(page),
      }));
    }
    if (!owner.complete()) {
      fail('SalesforceQueryIncomplete');
    }
    return Object.freeze({
      ...owner.finish(),
      pages: Object.freeze(pages),
      rowCount: owner.rowCount(),
    });
  } catch (error) {
    owner.interrupt();
    throw error;
  }
}

/// Read one bounded query and its locator chain at the Site. The MoonBit
/// owner chooses every request path and decides when observation is complete.
/// The caller receives bounded pages, never an implied Acquisition receipt.
export async function readSalesforceQuery(options) {
  const {moon, plan, apiVersion, limits} = options;
  if (typeof apiVersion !== 'string') fail('InvalidSalesforceQueryRead');
  const scope = validateRead(options);
  const currentCatalog = await recheckCurrentCatalog(options);
  const read = checked(moon.salesforceBeginQueryRead(
    plan, apiVersion, limits.maxBytes, limits.maxNodes, limits.maxDepth,
    limits.maxRows, limits.maxLocatorUnits, limits.maxPages,
    BigInt(limits.maxTotalRows),
  ));
  const result = await driveQueryPages({callResource: callHttpsCredentialResource,
    ...options}, scope, {
    nextPath: () => moon.salesforceQueryReadNextPath(read),
    acceptPage: (path, body) => moon.salesforceQueryReadAcceptPage(read, path,
      body),
    acknowledgePage: page => checked(
      moon.salesforceQueryReadAcknowledgePage(read, page)),
    complete: () => moon.salesforceQueryReadComplete(read),
    rowCount: () => moon.salesforceQueryReadRowCount(read),
    finish: () => ({read}),
    interrupt: () => moon.salesforceQueryReadInterrupt(read),
  });
  return Object.freeze({...result, currentCatalog});
}

/// Use the same physical query path while MoonBit appends each page to one
/// common managed output owner. The receipt is content evidence, not an
/// Acquisition completion or a grant to consume the result.
export async function readSalesforceManagedQuery(options) {
  const {moon, plan, apiVersion, limits, values} = options;
  if (typeof apiVersion !== 'string' || !values) {
    fail('InvalidSalesforceQueryRead');
  }
  const scope = validateRead({consumePage: async () => {}, ...options});
  const currentCatalog = await recheckCurrentCatalog(options);
  const query = checked(moon.salesforcePrepareManagedQuery(
    plan, apiVersion, limits.maxBytes, limits.maxNodes, limits.maxDepth,
    limits.maxRows, limits.maxLocatorUnits, limits.maxPages,
    BigInt(limits.maxTotalRows), values,
  ));
  const result = await driveQueryPages({callResource: callHttpsCredentialResource,
    consumePage: async () => {}, ...options}, scope, {
    nextPath: () => moon.salesforceManagedQueryNextPath(query),
    acceptPage: (path, body) => moon.salesforceManagedQueryAcceptPage(
      query, path, body),
    complete: () => moon.salesforceManagedQueryComplete(query),
    rowCount: () => moon.salesforceManagedQueryRowCount(query),
    finish: () => ({receipt: checked(moon.salesforceManagedQueryFinish(query))}),
    interrupt: () => moon.salesforceManagedQueryCancel(query),
  });
  return Object.freeze({...result, currentCatalog});
}

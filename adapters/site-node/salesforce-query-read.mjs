import {checked} from '../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {syncSalesforceCatalog} from './salesforce-catalog-sync.mjs';
import {invocationBindingsMatch, ownInvocationAuthorization,
  ownInvocationContext} from
  '../host-common/owned-invocation-context.mjs';

const operation = 'salesforce:query:read';
const count = value => Number.isSafeInteger(value) && value >= 0;
const fail = code => {
  throw Object.assign(new Error(code), {code});
};

function validateAuthorization(authorization, originalScope) {
  if (!authorization || typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.grant ||
      !authorization.scope || authorization.scope.operation !== operation ||
      !count(authorization.scope.siteGeneration) ||
      (originalScope && !invocationBindingsMatch(
        authorization.scope, originalScope))) {
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
  const context = ownInvocationContext({
    authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationForPage, consumePage, callResource},
  });
  const scope = validateAuthorization(context.authorization);
  if (!moon.salesforceReadProjectionScopeMatches(
    plan, scope.tenant, scope.principal, scope.environment,
    scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
    scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
    scope.dispatchRequestCid,
  )) {
    fail('ForeignSalesforceQueryProjection');
  }
  return Object.freeze({...context,
    refreshCatalog: Object.freeze({...refreshCatalog}),
  });
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
      const authorization = ownInvocationAuthorization(pages.length === 0
        ? initialAuthorization
        : await authorizationForPage(path, pages.length));
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
    const rowCount = owner.rowCount();
    return Object.freeze({
      ...owner.finish(),
      pages: Object.freeze(pages),
      rowCount,
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
  const context = validateRead(options);
  const currentCatalog = await recheckCurrentCatalog({
    ...options, credential: context.credential,
    refreshCatalog: context.refreshCatalog,
    callResource: context.callbacks.callResource,
  });
  const ownedLimits = context.limits;
  const read = checked(moon.salesforceBeginQueryRead(
    plan, apiVersion, ownedLimits.maxBytes, ownedLimits.maxNodes,
    ownedLimits.maxDepth, ownedLimits.maxRows,
    ownedLimits.maxLocatorUnits, ownedLimits.maxPages,
    BigInt(ownedLimits.maxTotalRows),
  ));
  const result = await driveQueryPages({
    ...options, initialAuthorization: context.authorization,
    authorizationForPage: context.callbacks.authorizationForPage,
    consumePage: context.callbacks.consumePage,
    callResource: context.callbacks.callResource,
    credential: context.credential, limits: ownedLimits,
  }, context.scope, {
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
  const context = validateRead({consumePage: async () => {}, ...options});
  const currentCatalog = await recheckCurrentCatalog({
    ...options, credential: context.credential,
    refreshCatalog: context.refreshCatalog,
    callResource: context.callbacks.callResource,
  });
  const ownedLimits = context.limits;
  const query = checked(moon.salesforcePrepareManagedQuery(
    plan, apiVersion, ownedLimits.maxBytes, ownedLimits.maxNodes,
    ownedLimits.maxDepth, ownedLimits.maxRows,
    ownedLimits.maxLocatorUnits, ownedLimits.maxPages,
    BigInt(ownedLimits.maxTotalRows), values,
  ));
  const result = await driveQueryPages({
    ...options, initialAuthorization: context.authorization,
    authorizationForPage: context.callbacks.authorizationForPage,
    consumePage: async () => {},
    callResource: context.callbacks.callResource,
    credential: context.credential, limits: ownedLimits,
  }, context.scope, {
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

/// Read the exact selected Acquisition attempt through the same bounded Site
/// transport. This moves the attempt only to AwaitingCleanup. The Host must
/// separately confirm physical settlement, verify evidence, and capture it.
export async function readSalesforceIssuedBroad(options) {
  const {moon, hostRun, apiVersion, limits, maxCaptureRows,
    captureLimits} = options;
  if (!moon || !hostRun ||
      typeof moon.salesforceBroadHostAttempt !== 'function' ||
      typeof apiVersion !== 'string' ||
      !count(maxCaptureRows) || !captureLimits ||
      !count(captureLimits.maxNodes) ||
      !count(captureLimits.maxTextBytes) ||
      !count(captureLimits.maxDepth) ||
      !count(captureLimits.maxWork)) {
    fail('InvalidSalesforceIssuedBroadRead');
  }
  const attempt = moon.salesforceBroadHostAttempt(hostRun);
  const plan = moon.salesforceIssuedBroadPlan(attempt);
  const physical = {...options, plan, consumePage: async () => {}};
  const context = validateRead(physical);
  // Claim the exact attempt before the first await. A rejected duplicate
  // must not abort the owner that already holds this physical read.
  checked(moon.salesforceIssuedBroadBegin(
    attempt, apiVersion, context.limits.maxBytes, context.limits.maxNodes,
    context.limits.maxDepth, context.limits.maxRows,
    context.limits.maxLocatorUnits, context.limits.maxPages,
    BigInt(context.limits.maxTotalRows), maxCaptureRows,
    captureLimits.maxNodes, captureLimits.maxTextBytes,
    captureLimits.maxDepth, captureLimits.maxWork,
  ));
  try {
    const currentCatalog = await recheckCurrentCatalog({
      ...physical, credential: context.credential,
      refreshCatalog: context.refreshCatalog,
      callResource: context.callbacks.callResource,
    });
    const result = await driveQueryPages({
      ...physical,
      initialAuthorization: context.authorization,
      authorizationForPage: context.callbacks.authorizationForPage,
      callResource: context.callbacks.callResource,
      credential: context.credential, limits: context.limits,
    }, context.scope, {
      nextPath: () => moon.salesforceIssuedBroadNextPath(attempt),
      acceptPage: (path, body) =>
        moon.salesforceIssuedBroadAcceptPage(attempt, path, body),
      complete: () => moon.salesforceIssuedBroadComplete(attempt),
      rowCount: () => moon.salesforceIssuedBroadRowCount(attempt),
      finish: () => {
        checked(moon.salesforceIssuedBroadFinish(attempt));
        return {hostRun};
      },
      interrupt: () => moon.salesforceBroadHostAbort(hostRun),
    });
    return Object.freeze({...result, currentCatalog});
  } catch (error) {
    moon.salesforceBroadHostAbort(hostRun);
    throw error;
  }
}

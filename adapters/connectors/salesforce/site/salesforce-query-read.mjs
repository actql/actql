import {types} from 'node:util';
import {runtimeField, runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {syncSalesforceCatalog} from './salesforce-catalog-sync.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  '../../../host-common/owned-invocation-context.mjs';

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
  chargePage,
  callResource = callHttpsCredentialResource,
}) {
  if (!moon || !plan ||
      typeof authorizationForPage !== 'function' ||
      typeof consumePage !== 'function' ||
      (chargePage !== undefined && typeof chargePage !== 'function') || !credential ||
      typeof credential !== 'object' ||
      !refreshCatalog || (typeof refreshCatalog !== 'object' &&
        typeof refreshCatalog !== 'function') ||
      typeof callResource !== 'function') {
    fail('InvalidSalesforceQueryRead');
  }
  validateLimits(limits);
  const context = ownInvocationContext({
    authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationForPage, consumePage, chargePage, callResource},
  });
  const scope = validateAuthorization(context.authorization);
  if (!moon.salesforceReadProjectionScopeMatches(
    plan, scope.namespaceId, scope.principal, scope.environment,
    scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
    scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
    scope.dispatchRequestCid,
  )) {
    fail('ForeignSalesforceQueryProjection');
  }
  return Object.freeze({...context,
    refreshCatalog: typeof refreshCatalog === 'function' ? refreshCatalog
      : Object.freeze({...refreshCatalog}),
  });
}

// `refreshCatalog` is either a full-sync request or a function returning a
// fresh observation (for example a describe-only recheck of the Resource).
async function recheckCurrentCatalog(options) {
  const {moon, plan, credential, refreshCatalog, callResource, signal} = options;
  const refreshed = typeof refreshCatalog === 'function'
    ? await refreshCatalog({signal})
    : await syncSalesforceCatalog({
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
  chargePage,
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
      const response = await invokeScopedCredentialOperation({
        authorization, credential, callResource, operation,
        method: 'GET', path,
        maxResponseBytes: limits.maxBytes,
        signal,
      });
      const accepted = response.accepted;
      // Account the exact received body before any provider decoding. The
      // neutral owner binds this single-use admission to the selected run.
      const charge = await chargePage?.(response.body);
      if (!accepted) {
        fail('SalesforceQueryResourceRejected');
      }
      const page = checked(owner.acceptPage(path, response.body));
      await consumePage(page, Object.freeze({path, pageIndex: pages.length,
        charge}));
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
    chargePage: context.callbacks.chargePage,
    callResource: context.callbacks.callResource,
    credential: context.credential, limits: ownedLimits,
  }, context.scope, {
    nextPath: () => moon.salesforceQueryReadNextPath(read),
    acceptPage: (path, body) => {
      const result = moon.salesforceQueryReadAcceptPage(read, path, body);
      const violation = runtimeIsError(result)
        ? moon.salesforceQueryReadValueViolation(plan, runtimeField(result, 0))
        : undefined;
      if (typeof violation === 'string') {
        throw Object.assign(new Error('SalesforceValueViolation'), {
          code: 'SalesforceValueViolation',
          violation: Object.freeze(JSON.parse(violation))});
      }
      return result;
    },
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
    chargePage: context.callbacks.chargePage,
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

const own = (value, name) => {
  if (value === null || typeof value !== 'object' || types.isProxy(value)) fail('InvalidSalesforceSourceRead');
  const field = Object.getOwnPropertyDescriptor(value, name);
  if (!field || !Object.hasOwn(field, 'value')) fail('InvalidSalesforceSourceRead');
  return field.value;
};
const method = (value, name) => {
  const fn = own(value, name);
  if (typeof fn !== 'function' || types.isProxy(fn)) fail('InvalidSalesforceSourceRead');
  return fn;
};

// The existing codec has already selected this immutable invocation. Preserve
// the Site issuer's original grant/scope for the shared Reader's nominal check;
// the copied primitive scope in invokeScopedCredentialOperation is DATA only.
// This projector performs no physical call, Account decision or grant issuance.
export function readSalesforceSourceChild(context, originalAuthorization, input) {
  const grant = own(originalAuthorization, 'grant'), scope = own(originalAuthorization, 'scope');
  const suppliedScope = own(input, 'scope');
  const originalFields = Object.getOwnPropertyDescriptors(scope);
  if (own(input, 'grant') !== grant || types.isProxy(suppliedScope) ||
      Reflect.ownKeys(originalFields).length !== Reflect.ownKeys(suppliedScope).length ||
      Reflect.ownKeys(originalFields).some(name => !Object.hasOwn(originalFields[name], 'value') ||
        own(suppliedScope, name) !== originalFields[name].value)) fail('ForeignSalesforceSourceReadChild');
  const operation = own(scope, 'operation'), operations = own(input, 'operations');
  if (!(operations instanceof Map) || types.isProxy(operations) || operations.size !== 1 ||
      !operations.has(operation)) fail('InvalidSalesforceSourceReadChild');
  const request = operations.get(operation);
  if (own(request, 'method') !== 'GET' || Object.hasOwn(request, 'body') ||
      Object.hasOwn(request, 'bodyBytes')) fail('InvalidSalesforceSourceReadChild');
  const authorization = Object.freeze({grant, scope, useId: own(input, 'useId')});
  return Reflect.apply(method(context, 'readChild'), context, [{operation, prepare() {
    return Object.freeze({original: input, originalAuthorization, authorization,
      request, project(response) {return response;}});
  }}]);
}

// Same Salesforce plan/recheck/query codecs, now driven inside ONE admitted
// shared Reader. Preparing this protocol retains original facts only. The two
// metadata reads and all query pages happen after its original binding opens.
export function prepareSalesforceSourceReadSequence(options) {
  let {moon, queryMoon, site, declaration, preparedRead, originalAuthorization, recover, limits, responseCapacity} = options;
  options = undefined;
  let describe = method(site, 'describeForAcquisition');
  // The common owner selected this original acquisition before dispatch.
  // Its complete-input variant is not a QueryRequirement or a Query cast.
  let recheck = method(moon, preparedRead.wholeInput === true
    ? 'clientProgramRecheckSalesforceInputProjection'
    : 'clientProgramRecheckSalesforceRowProjection');
  let values = method(moon, 'clientProgramSalesforceQueryPageValues');
  let credential = own(site, 'credential'), apiVersion = own(site, 'apiVersion');
  const scope = own(originalAuthorization, 'scope');
  if (typeof recover !== 'function' || scope.operation !== 'salesforce:query:read' ||
      scope.runInvocationCid !== own(preparedRead, 'runInvocationCid') ||
      scope.dispatchRequestCid !== own(preparedRead, 'dispatchRequestCid')) fail('ForeignSalesforceSourceRead');
  if (responseCapacity !== undefined && typeof responseCapacity !== 'function') fail('InvalidSalesforceSourceRead');
  let started = false, pending = false, retired = false, largestResponse = 0, capacity;
  const sequence = Object.freeze({...(responseCapacity === undefined ? {} : {responseCapacity(bytes) {
    if (this !== sequence || !pending || retired || !Number.isSafeInteger(bytes) || bytes < 0 ||
        bytes > limits.maxBytes) fail('InvalidSalesforceSourceResponseExtent');
    if (capacity === undefined || bytes > largestResponse) {
      largestResponse = Math.max(largestResponse, bytes);
      capacity = Reflect.apply(responseCapacity, undefined, [largestResponse]);
    }
    return capacity;
  }}), async read(context, initialAuthorization) {
    if (this !== sequence || started || retired) fail('SalesforceSourceReadAlreadyStarted');
    started = true;pending = true;
    try {
      if (initialAuthorization?.grant !== originalAuthorization.grant ||
          initialAuthorization.scope !== originalAuthorization.scope) fail('ForeignSalesforceSourceRead');
      const project = method(context, 'project'), consumeObservation = method(context, 'consumeObservation');
      const consumeValues = method(context, 'consumeValues');
      const metadata = async suffix => {
        const observed = await Reflect.apply(describe, site, [{resource: preparedRead.resource,
          runInvocationCid: preparedRead.runInvocationCid, dispatchRequestCid: preparedRead.dispatchRequestCid,
          occurrence: `${preparedRead.nonce}-${suffix}`, approval: preparedRead.approval,
          signal: preparedRead.signal,
          readChild: (original, input) => readSalesforceSourceChild(context, original, input)}]);
        const observation = Reflect.apply(project, context, [recover, undefined,
          [observed.evidence, preparedRead.runInvocationCid]]);
        await Reflect.apply(consumeObservation, context, []);
        return Object.freeze({status: 'observed', observation,
          observationCid: observed.observationCid, observationJson: observed.evidence.observationJson});
      };
      let current = await metadata('plan');
      const plan = Reflect.apply(project, context, [(...args) => checked(Reflect.apply(recheck, moon, args)),
        undefined, [declaration, preparedRead.acquisition, current.observation, 4096]]);
      // The plan retains its original selected fields/binding. Relinquish the
      // full first Catalog before the independent current Describe begins.
      current = undefined;
      await readSalesforceQuery({moon: queryMoon, plan, apiVersion, limits,
        initialAuthorization, credential, signal: preparedRead.signal,
        authorizationForPage: (_path, index) => Object.freeze({...initialAuthorization,
          useId: `${preparedRead.nonce}-query-${index}`}),
        refreshCatalog: () => metadata('recheck'),
        callResource: input => readSalesforceSourceChild(context, originalAuthorization, input),
        async consumePage(page) {
          const projected = Reflect.apply(project, context, [values, moon, [page]]);
          await Reflect.apply(consumeValues, context, [runtimeField(projected, 0), runtimeField(projected, 1)]);
        }});
    } finally {pending = false;}
  }, retire() {
    if (this !== sequence) fail('ForeignSalesforceSourceRead');
    if (pending) return false;
    if (!retired) {
      moon = queryMoon = site = declaration = preparedRead = originalAuthorization = recover = limits = undefined;
      describe = recheck = values = credential = responseCapacity = capacity = undefined;
      retired = true;
    }
    return true;
  }});
  return sequence;
}

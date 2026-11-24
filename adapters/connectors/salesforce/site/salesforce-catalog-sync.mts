import {checked} from '../../../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext, ownInvocationLimits} from
  '../../../host-common/owned-invocation-context.mjs';

type HttpsResource = typeof callHttpsCredentialResource;
export type SalesforceReadResponse = Pick<Awaited<ReturnType<HttpsResource>>,
  'accepted' | 'statusCode' | 'body' | 'useCid'>;
export type SalesforceReadCall = (request: Parameters<HttpsResource>[0]) =>
  SalesforceReadResponse | PromiseLike<SalesforceReadResponse>;
export type SalesforceCatalogScope = Readonly<{
  operation: string; namespaceId: string; principal: string; environment: string; siteKey: string;
  siteGeneration: number; connectorRegistration: string; connectorRevision: string; resourceOrigin: string;
  runInvocationCid: string; dispatchRequestCid: string;
}>;
export type SalesforceReadAuthorization = Readonly<{grant: unknown; useId: string; scope: SalesforceCatalogScope}>;
type Credential = NonNullable<Parameters<typeof matchesSalesforceCredentialOrg>[0]>;
type ReadOptions = Readonly<{credential: object; callResource: SalesforceReadCall; signal?: AbortSignal}>;
type Bounds = Readonly<{maxBytes: number; maxNodes: number; maxDepth: number; maxNameUnits: number}>;
type ListLimits = Bounds & Readonly<{maxResources: number; maxSelected: number}>;
type DescribeLimits = Bounds & Readonly<{maxFields: number}>;
type DescribeAuthorization = (name: string) => unknown | PromiseLike<unknown>;
type Context = Omit<ReturnType<typeof ownInvocationContext>, 'authorization' | 'limits' | 'callbacks'> &
  Readonly<{authorization: SalesforceReadAuthorization; limits: ListLimits; callbacks: Readonly<{
    callResource: SalesforceReadCall; authorizationForDescribe: DescribeAuthorization;
  }>}>;

type ProjectionBounds = [body: Uint8Array, bytes: number, nodes: number, depth: number,
  maxResources: number, maxSelected: number, nameUnits: number];
export type SalesforceCatalogRuntime = Readonly<{
  salesforceCatalogHttpFailure(status: number | undefined, body: Uint8Array, maxBytes: number): number;
  salesforceProjectListing(...bounds: ProjectionBounds): unknown;
  salesforceProjectListingFor(...input: [...bounds: ProjectionBounds, resources: readonly string[]]): unknown;
  salesforceCatalogBegin(listing: unknown): unknown;
  salesforceCatalogResourceNames(listing: unknown): readonly string[];
  salesforceCatalogNext(sync: unknown): string | null | undefined;
  salesforceCatalogCancel(sync: unknown): unknown;
  salesforceCatalogResponseSha256(body: Uint8Array): string;
  salesforceCatalogDescribe(sync: unknown, name: string, body: Uint8Array, bytes: number, nodes: number,
    depth: number, fields: number, nameUnits: number): unknown;
  salesforceCatalogUnavailable(sync: unknown, name: string, reason: number): unknown;
  salesforceCatalogFinish(sync: unknown): unknown;
  salesforcePrepareCatalogObservation(sync: unknown, namespace: string, principal: string, environment: string,
    connectionRevision: string, orgId: string, site: string, generation: number, registration: string,
    revision: string, origin: string, invocation: string, dispatch: string, occurrence: string,
    listUse: string, describeUses: readonly (string | undefined)[], responseDigests: readonly (string | undefined)[],
    maxBytes: number): unknown;
  salesforceCatalogObservationCid(value: unknown): string;
  salesforceCatalogObservationJson(value: unknown): string;
}>;
export type SalesforceCatalogRequest = Readonly<{
  moon: SalesforceCatalogRuntime; apiVersion: string; connectionRevision: string; orgId: string; syncOccurrence: string;
  maxObservationBytes: number; listAuthorization: SalesforceReadAuthorization;
  authorizationForDescribe: DescribeAuthorization; credential: Credential;
  listLimits: ListLimits; describeLimits: DescribeLimits; retainResponses?: boolean; maxRetainedBytes?: number;
  callResource?: SalesforceReadCall; signal?: AbortSignal; resources?: readonly string[];
}>;
type CatalogFailure = Readonly<{code?: unknown}> | null | undefined;

const versionPattern = /^v[1-9][0-9]*\.[0-9]+$/;
const namePattern = /^[A-Za-z_][A-Za-z0-9_]*$/;
const listOperation = 'salesforce:catalog:list';
const describeOperation = 'salesforce:catalog:describe';

const count = (value: number) => Number.isInteger(value) && value >= 0 &&
  value <= 2_147_483_647;
const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

function validateLimits(limits: ListLimits) {
  if (limits === null || typeof limits !== 'object' ||
      !count(limits.maxBytes) || limits.maxBytes === 0 ||
      !count(limits.maxNodes) || !count(limits.maxDepth) ||
      !count(limits.maxResources) || !count(limits.maxSelected) ||
      !count(limits.maxNameUnits) ||
      limits.maxSelected > limits.maxResources) {
    fail('InvalidSalesforceCatalogLimits');
  }
}

function validateAuthorization(authorization: SalesforceReadAuthorization, operation: string, originalScope?: SalesforceCatalogScope) {
  if (!authorization || typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.grant ||
      !authorization.scope || authorization.scope.operation !== operation ||
      !count(authorization.scope.siteGeneration)) {
    fail('InvalidSalesforceCatalogAuthorization');
  }
  if (originalScope !== undefined &&
      !invocationBindingsMatch(authorization.scope, originalScope)) {
    fail('ForeignSalesforceCatalogBinding');
  }
  return authorization.scope;
}

async function scopedGet({authorization, path, maxBytes, credential,
  callResource, signal}: ReadOptions & Readonly<{authorization: SalesforceReadAuthorization; path: string; maxBytes: number}>) {
  return await invokeScopedCredentialOperation({
    authorization, credential, callResource,
    operation: authorization.scope.operation, method: 'GET', path,
    maxResponseBytes: maxBytes,
    signal,
  }) as SalesforceReadResponse;
}

/// Run one bounded catalog observation at the Site. The MoonBit sync owns
/// resource identity and completeness; this adapter only performs scoped I/O.
export async function syncSalesforceCatalog({
  moon,
  apiVersion,
  connectionRevision,
  orgId,
  syncOccurrence,
  maxObservationBytes,
  listAuthorization,
  authorizationForDescribe,
  credential,
  listLimits: requestedListLimits,
  describeLimits: requestedDescribeLimits,
  retainResponses = false,
  maxRetainedBytes = 0,
  callResource = callHttpsCredentialResource,
  signal,
  // Describe only these listed resources. The observation is then marked
  // truncated unless it covers the whole visible listing: a targeted sync is
  // never a complete Catalog. Without it, the first `maxSelected` are
  // described.
  resources,
}: SalesforceCatalogRequest) {
  if (!moon || !versionPattern.test(apiVersion) ||
      typeof connectionRevision !== 'string' ||
      connectionRevision.length === 0 ||
      !matchesSalesforceCredentialOrg(credential, orgId) ||
      typeof syncOccurrence !== 'string' || syncOccurrence.length === 0 ||
      !count(maxObservationBytes) || maxObservationBytes === 0 ||
      typeof retainResponses !== 'boolean' ||
      (retainResponses && (!count(maxRetainedBytes) ||
        maxRetainedBytes === 0)) ||
      typeof authorizationForDescribe !== 'function' ||
      !credential || typeof callResource !== 'function' ||
      (resources !== undefined && (!Array.isArray(resources) ||
        resources.length === 0 ||
        resources.some(name => typeof name !== 'string' ||
          !namePattern.test(name)) ||
        new Set(resources).size !== resources.length ||
        (retainResponses && resources !== undefined)))) {
    fail('InvalidSalesforceCatalogSync');
  }
  validateLimits(requestedListLimits);
  validateLimits({...requestedDescribeLimits,
    maxResources: requestedDescribeLimits?.maxFields,
    maxSelected: requestedDescribeLimits?.maxFields,
  });
  const context = ownInvocationContext({
    authorization: listAuthorization, credential,
    limits: requestedListLimits,
    callbacks: {authorizationForDescribe, callResource},
  }) as Context;
  const listLimits = context.limits;
  const describeLimits = ownInvocationLimits(requestedDescribeLimits) as DescribeLimits;
  const listScope = validateAuthorization(context.authorization, listOperation);
  signal?.throwIfAborted();
  const prefix = `/services/data/${apiVersion}/sobjects/`;
  const listResponse = await scopedGet({
    authorization: context.authorization,
    path: prefix,
    maxBytes: retainResponses
      ? Math.min(listLimits.maxBytes, maxRetainedBytes)
      : listLimits.maxBytes,
    credential: context.credential,
    callResource: context.callbacks.callResource,
    signal,
  });
  if (!listResponse.accepted) {
    const reason = moon.salesforceCatalogHttpFailure(
      listResponse.statusCode, listResponse.body, listLimits.maxBytes);
    throw Object.assign(new Error('SalesforceCatalogListRejected'), {
      code: 'SalesforceCatalogListRejected', reason,
    });
  }
  const listing = checked(resources === undefined
    ? moon.salesforceProjectListing(
      listResponse.body,
      listLimits.maxBytes,
      listLimits.maxNodes,
      listLimits.maxDepth,
      listLimits.maxResources,
      listLimits.maxSelected,
      listLimits.maxNameUnits,
    )
    : moon.salesforceProjectListingFor(
      listResponse.body,
      listLimits.maxBytes,
      listLimits.maxNodes,
      listLimits.maxDepth,
      listLimits.maxResources,
      listLimits.maxSelected,
      listLimits.maxNameUnits,
      [...resources],
    ));
  const sync = moon.salesforceCatalogBegin(listing);
  const selectedNames = moon.salesforceCatalogResourceNames(listing);
  const listBytes = retainResponses ? Buffer.from(listResponse.body) : undefined;
  let retainedBytes = listBytes?.byteLength ?? 0;
  const describeBodies: (string | null)[] = [];
  const describeUseCids: (string | undefined)[] = [];
  const describeResponseSha256: (string | undefined)[] = [];
  let interruptionCode: string | undefined;
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
      const authorization = ownInvocationAuthorization(
        await context.callbacks.authorizationForDescribe(name)) as SalesforceReadAuthorization;
      validateAuthorization(authorization, describeOperation, listScope);
      const remaining = retainResponses
        ? maxRetainedBytes - retainedBytes : describeLimits.maxBytes;
      if (remaining < 1) fail('SalesforceCatalogRetainedLimit');
      const response = await scopedGet({
        authorization,
        path: `${prefix}${name}/describe`,
        maxBytes: Math.min(describeLimits.maxBytes, remaining),
        credential: context.credential,
        callResource: context.callbacks.callResource,
        signal,
      });
      const responseBytes = retainResponses
        ? Buffer.from(response.body) : undefined;
      retainedBytes += responseBytes?.byteLength ?? 0;
      describeBodies.push(responseBytes?.toString('base64') ?? null);
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
      if ((error as CatalogFailure)?.code === 'MoonBitHostFailure' ||
          (error as CatalogFailure)?.code === 'InvalidHostRuntimeResult') throw error;
      interruptionCode = signal?.aborted
        ? 'SalesforceCatalogCancelled'
        : typeof (error as CatalogFailure)?.code === 'string'
          ? (error as {code: string}).code
          : 'SalesforceCatalogInterrupted';
      checked(moon.salesforceCatalogCancel(sync));
      break;
    }
  }
  const complete = checked(moon.salesforceCatalogFinish(sync));
  while (describeUseCids.length < selectedNames.length) {
    describeUseCids.push(undefined);
    describeResponseSha256.push(undefined);
    describeBodies.push(null);
  }
  const observation = checked(moon.salesforcePrepareCatalogObservation(
    sync,
    listScope.namespaceId,
    listScope.principal,
    listScope.environment,
    connectionRevision,
    orgId,
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
    retainedResponses: retainResponses ? Object.freeze({
      observationJson: moon.salesforceCatalogObservationJson(observation),
      listBodyBase64: listBytes!.toString('base64'),
      describeBodyBase64: Object.freeze(describeBodies),
      listLimits: Object.freeze({...listLimits}),
      describeLimits: Object.freeze({...describeLimits}),
      maxObservationBytes,
    }) : undefined,
  });
}

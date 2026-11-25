import {checked} from '../../../host-common/runtime-result.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {matchesSalesforceCredentialOrg} from
  './salesforce-credential-binding.mjs';
import {invokeScopedCredentialOperation, ownInvocationContext} from
  '../../../host-common/owned-invocation-context.mjs';

import type {SalesforceWriteObservation, SalesforceWriteLimits, SalesforceWriteInvocation,
  SalesforceRequestScope, SalesforceWriteScope} from './salesforce-single-write.mjs';

type CollectionLimits = SalesforceWriteLimits & Readonly<{maxRows: number}>;
type Runtime = Readonly<{
  salesforceProjectCollectionWriteResponse(request: unknown, status: number, body: Uint8Array,
    bytes: number, nodes: number, depth: number, rows: number): unknown;
  salesforceCollectionWriteResponseRowCount(response: unknown): number;
  salesforceCollectionWriteRequestRowCount(request: unknown): number;
  salesforceCollectionWriteRequestGrantOperation(request: unknown): string;
  salesforceCollectionWriteRequestOrgId(request: unknown): string;
  salesforceCollectionWriteRequestMethod(request: unknown): string;
  salesforceCollectionWriteRequestPath(request: unknown): string;
  salesforceCollectionWriteRequestBody(request: unknown): string;
  salesforceCollectionWriteRequestScopeMatches(request: unknown, ...scope: SalesforceRequestScope): boolean;
  salesforceRecheckCollectionWriteRequest(request: unknown, current: unknown): unknown;
}>;
type Projection = Readonly<{moon: Runtime; request: unknown; observation: SalesforceWriteObservation; limits: CollectionLimits}>;
type Write = SalesforceWriteInvocation<Runtime, CollectionLimits>;

const count = (value: number) => Number.isSafeInteger(value) && value > 0;
const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};

// The same MoonBit projection is used for a fresh HTTPS observation and a
// durable batch response recovered after restart. It never performs I/O.
export function projectSalesforceCollectionObservation({
  moon, request, observation, limits,
}: Projection) {
  if (!moon || !request || !observation || !limits ||
      !count(limits.maxResponseBytes) || limits.maxResponseBytes > 1_000_000 ||
      !count(limits.maxNodes) || limits.maxNodes > 1000 ||
      !count(limits.maxDepth) || limits.maxDepth > 32 ||
      !count(limits.maxRows) || limits.maxRows > 200 ||
      !Number.isSafeInteger(observation.statusCode) ||
      observation.statusCode! < 100 || observation.statusCode! > 599 ||
      !(observation.body instanceof Uint8Array)) {
    fail('InvalidSalesforceCollectionObservation');
  }
  // A non-success status is typed only as a documented request-level
  // rejection (every row failed); otherwise every row stays unknown.
  const success = observation.statusCode! >= 200 && observation.statusCode! < 300;
  try {
    const projected = checked(moon.salesforceProjectCollectionWriteResponse(
      request, observation.statusCode!, observation.body,
      limits.maxResponseBytes, limits.maxNodes, limits.maxDepth,
      limits.maxRows));
    return Object.freeze({
      kind: 'typed-row-response', observation,
      result: projected,
      rowCount: moon.salesforceCollectionWriteResponseRowCount(projected),
    });
  } catch (cause) {
    return success
      ? Object.freeze({kind: 'unclassified-response', observation, cause})
      : Object.freeze({kind: 'provider-response', observation});
  }
}

// One physical Collections call for rows of one admitted continue member.
// This is not apply admission, a dispatch permit, or an Effect receipt.
export async function sendRawSalesforceContinueCollection({
  moon,
  request,
  currentObservation,
  authorization,
  credential,
  limits,
  signal,
  callResource = callHttpsCredentialResource,
}: Write) {
  if (!moon || !request || !currentObservation || !authorization?.grant ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.scope ||
      !credential || typeof credential !== 'object' ||
      typeof callResource !== 'function' || !limits ||
      !count(limits.maxRequestBytes) || limits.maxRequestBytes > 1_000_000 ||
      !count(limits.maxResponseBytes) ||
      limits.maxResponseBytes > 1_000_000 ||
      !count(limits.maxNodes) || limits.maxNodes > 1000 ||
      !count(limits.maxDepth) || limits.maxDepth > 32 ||
      !count(limits.maxRows) || limits.maxRows > 200) {
    fail('InvalidSalesforceCollectionWrite');
  }
  const context = ownInvocationContext({authorization, credential, limits,
    callbacks: {callResource}});
  const scope = context.scope as SalesforceWriteScope;
  const operation = moon.salesforceCollectionWriteRequestGrantOperation(request);
  const rowCount = moon.salesforceCollectionWriteRequestRowCount(request);
  if (!count(rowCount) || rowCount > (context.limits.maxRows as number)) {
    fail('SalesforceCollectionRowLimitExceeded');
  }
  if (!matchesSalesforceCredentialOrg(credential,
      moon.salesforceCollectionWriteRequestOrgId(request)) ||
      scope.operation !== operation ||
      !moon.salesforceCollectionWriteRequestScopeMatches(
        request, scope.namespaceId, scope.principal, scope.environment,
        scope.siteKey, scope.siteGeneration, scope.connectorRegistration,
        scope.connectorRevision, scope.resourceOrigin, scope.runInvocationCid,
        scope.dispatchRequestCid)) {
    fail('ForeignSalesforceCollectionWrite');
  }
  checked(moon.salesforceRecheckCollectionWriteRequest(
    request, currentObservation));
  signal?.throwIfAborted();
  const response = await invokeScopedCredentialOperation({
    authorization: context.authorization,
    credential: context.credential,
    callResource: context.callbacks.callResource, operation,
    method: moon.salesforceCollectionWriteRequestMethod(request),
    path: moon.salesforceCollectionWriteRequestPath(request),
    body: moon.salesforceCollectionWriteRequestBody(request),
    maxRequestBytes: context.limits.maxRequestBytes as number,
    maxResponseBytes: context.limits.maxResponseBytes as number,
    signal,
  }) as Awaited<ReturnType<typeof callHttpsCredentialResource>>;
  const observation = Object.freeze({
    useCid: response.useCid,
    statusCode: response.statusCode,
    body: response.body,
  });
  return Object.freeze({observation, limits: context.limits as CollectionLimits});
}

export async function writeSalesforceContinueCollection(options: Write) {
  const raw = await sendRawSalesforceContinueCollection(options);
  return projectSalesforceCollectionObservation({
    moon: options.moon, request: options.request,
    observation: raw.observation, limits: raw.limits,
  });
}

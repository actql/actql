import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from './hubspot-object-read.mjs';
import type {HubSpotInvocation, HubSpotObservationCause, HubSpotResourceCall, HubSpotResourceInput, HubSpotResponse}
  from './hubspot-account-read.mjs';

type Native = Readonly<{
  hubspotProjectProperties(bytes: Uint8Array, originalObjectType: string, maxBytes: number, maxNodes: number,
    maxDepth: number, maxProperties: number, maxNameUnits: number): unknown;
  hubspotRecheckPropertyCatalog(original: unknown, current: unknown, maxProperties: number): unknown;
  hubspotPropertyCatalogObjectType(catalog: unknown): string;
  hubspotRecheckAccountIdentityJson(bytes: Uint8Array, originalPortalId: string, maxBytes: number, maxNodes: number,
    maxDepth: number): string;
  hubspotRecordReadBody(request: unknown): string;
  hubspotRecordReadObjectType(request: unknown): string;
  hubspotRecheckRecordReadRequest(request: unknown, current: unknown, maxProperties: number): unknown;
  hubspotProjectRecordRead(request: unknown, bytes: Uint8Array, maxBytes: number, maxNodes: number,
    maxDepth: number, maxRows: number, maxColumns: number, maxCursorUnits: number,
    maxValueNodes: number, maxValueTextBytes: number, maxOutputBytes: number,
    maxOutputNodes: number, maxOutputDepth: number): unknown;
}>;
type Limits = Readonly<Record<(typeof limitFields)[number], number>>;
type Callbacks = Readonly<{authorizationFor(original: Readonly<{operation: string; index: number; objectType: string}>): unknown;
  current(operation: string): unknown; chargeResponse(body: HubSpotResponse['body']): unknown;
  consumeObservation(charge: unknown): unknown; callResource: HubSpotResourceCall}>;
type Options = Omit<Callbacks, 'callResource'> & Readonly<{moon: Native; originalPortalId: string;
  originalCatalog: unknown; initialAuthorization: unknown; credential: {binding?: unknown}; limits: Limits;
  signal?: AbortSignal; callResource?: HubSpotResourceCall; request: unknown}>;

export const HUBSPOT_OBJECT_BATCH_READ_OPERATION = 'hubspot:objects:batch-read';
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const segment = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);
const exports = ['hubspotProjectProperties', 'hubspotRecheckPropertyCatalog',
  'hubspotPropertyCatalogObjectType', 'hubspotRecheckAccountIdentityJson',
  'hubspotRecordReadBody', 'hubspotRecordReadObjectType',
  'hubspotRecheckRecordReadRequest', 'hubspotProjectRecordRead'] as const;
const limitFields = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxProperties', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCursorUnits',
  'maxValueNodes', 'maxValueTextBytes', 'maxOutputBytes', 'maxOutputNodes',
  'maxOutputDepth', 'maxRequests'] as const;

// Original physical observations remain private custody on every later
// projection/current/accounting failure. No retry, absent-target conclusion,
// new grant, approval, write claim or physical cleanup ACK is introduced.
export class HubSpotTargetReadFailure extends Error {
  declare readonly code: unknown;
  declare readonly observations: readonly HubSpotResponse[];

  constructor(cause: HubSpotObservationCause, observations: readonly HubSpotResponse[]) {
    super(typeof cause?.message === 'string' ? cause.message : 'HubSpotTargetReadFailed', {cause});
    this.name = typeof cause?.name === 'string' ? cause.name : 'Error';
    this.code = cause?.code ?? 'HubSpotTargetReadFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// The caller supplies existing independently authorized nominal operations.
// Target read is still a read even though HubSpot uses POST for batch/read;
// identity, schema and records each retain their own current/read authority.
export async function readHubSpotRecordTargets({moon, originalPortalId,
  originalCatalog, request, initialAuthorization, credential, authorizationFor,
  limits, current, chargeResponse, consumeObservation, signal,
  callResource = callHttpsCredentialResource}: Options) {
  if (exports.some(name => typeof moon?.[name] !== 'function') ||
      !limitFields.every(name => positive(limits?.[name])) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidHubSpotTargetRead');
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon[name]]))) as Native;
  const context = ownInvocationContext({authorization: initialAuthorization, credential,
    limits, callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}}) as HubSpotInvocation<Limits, Callbacks>;
  if ((context.scope as {operation?: unknown}).operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) fail('ForeignHubSpotAccountOperation');
  const objectType = provider.hubspotRecordReadObjectType(request);
  if (objectType !== provider.hubspotPropertyCatalogObjectType(originalCatalog) ||
      !objectType || objectType === '.' || objectType === '..' ||
      objectType.length > context.limits.maxNameUnits) fail('ForeignHubSpotTargetCatalog');
  checked(provider.hubspotRecheckRecordReadRequest(request, originalCatalog, context.limits.maxProperties));
  const body = provider.hubspotRecordReadBody(request);
  if (Buffer.byteLength(body) > context.limits.maxRequestBytes) fail('HubSpotTargetRequestLimit');
  const observations: HubSpotResponse[] = [];
  let requests = 0;
  const verify = async (operation: string) => {
    signal?.throwIfAborted(); await context.callbacks.current(operation); signal?.throwIfAborted();
  };
  const slot = () => {
    if (requests >= context.limits.maxRequests) fail('HubSpotTargetRequestLimit');
    return requests++;
  };
  const receive = async (operation: string, path: string, method: 'GET' | 'POST', requestBody?: string) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index: slot(), objectType})));
    if ((authorization.scope as {operation?: unknown}).operation !== operation ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignHubSpotTargetAuthorization');
    await verify(operation);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation, method, path, query: [],
      // The existing HTTP owner selects JSON content-type for string bodies;
      // providers cannot override its reserved credential/request headers.
      headers: [['accept', 'application/json']], body: requestBody,
      responseHeaders: [], maxRequestBytes: context.limits.maxRequestBytes,
      maxResponseBytes: context.limits.maxResponseBytes, signal,
      callResource: (options: HubSpotResourceInput) => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)})}) as HubSpotResponse;
    observations.push(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(operation);
    if (!response.accepted || response.statusCode !== 200) fail('HubSpotTargetReadRejected');
    return {response, charge};
  };
  const recheckProperties = async () => {
    const {response, charge} = await receive(HUBSPOT_PROPERTIES_READ_OPERATION,
      `/crm/v3/properties/${segment(objectType)}`, 'GET');
    const catalog = checked(provider.hubspotProjectProperties(response.body, objectType,
      context.limits.maxResponseBytes, context.limits.maxNodes, context.limits.maxDepth,
      context.limits.maxProperties, context.limits.maxNameUnits));
    checked(provider.hubspotRecheckPropertyCatalog(originalCatalog, catalog, context.limits.maxProperties));
    await context.callbacks.consumeObservation(charge);
    await verify(HUBSPOT_PROPERTIES_READ_OPERATION);
  };
  try {
    slot();
    const account = await observeHubSpotAccount({moon: provider, originalPortalId,
      authorization: context.authorization, credential: context.credential,
      limits: context.limits, current: () => verify(HUBSPOT_ACCOUNT_DETAILS_OPERATION),
      chargeResponse: context.callbacks.chargeResponse,
      consumeObservation: context.callbacks.consumeObservation,
      signal, callResource: context.callbacks.callResource});
    observations.push(account.response);
    await recheckProperties();
    const {response, charge} = await receive(HUBSPOT_OBJECT_BATCH_READ_OPERATION,
      `/crm/v3/objects/${segment(objectType)}/batch/read`, 'POST', body);
    const observation = checked(provider.hubspotProjectRecordRead(request, response.body,
      context.limits.maxResponseBytes, context.limits.maxNodes, context.limits.maxDepth,
      context.limits.maxRows, context.limits.maxColumns, context.limits.maxCursorUnits,
      context.limits.maxValueNodes, context.limits.maxValueTextBytes,
      context.limits.maxOutputBytes, context.limits.maxOutputNodes, context.limits.maxOutputDepth));
    await context.callbacks.consumeObservation(charge);
    await verify(HUBSPOT_OBJECT_BATCH_READ_OPERATION);
    await recheckProperties();
    await verify(HUBSPOT_OBJECT_BATCH_READ_OPERATION);
    return Object.freeze({observation, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if ((cause as HubSpotObservationCause)?.observation && !observations.includes((cause as HubSpotObservationCause)!.observation!)) observations.push((cause as HubSpotObservationCause)!.observation!);
    throw new HubSpotTargetReadFailure(cause as HubSpotObservationCause, observations);
  }
}

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
  hubspotRecheckAccountIdentityJson(bytes: Uint8Array, originalPortalId: string, maxBytes: number, maxNodes: number,
    maxDepth: number): string;
  hubspotRecordBatchBody(request: unknown): string;
  hubspotRecordBatchObjectType(request: unknown): string;
  hubspotRecordBatchEndpoint(request: unknown): string;
  hubspotRecordBatchCount(request: unknown): number;
  hubspotRecheckRecordBatch(request: unknown, current: unknown, maxProperties: number): unknown;
}>;
type Limits = Readonly<Record<(typeof limitFields)[number], number>>;
type Callbacks = Readonly<{authorizationFor(original: Readonly<{operation: string; index: number; objectType: string}>): unknown;
  current(operation: string): unknown; chargeResponse(body: HubSpotResponse['body']): unknown;
  consumeObservation(charge: unknown): unknown; callResource: HubSpotResourceCall}>;
type Options = Omit<Callbacks, 'callResource'> & Readonly<{moon: Native; originalPortalId: string;
  originalCatalog: unknown; initialAuthorization: unknown; credential: {binding?: unknown}; limits: Limits;
  signal?: AbortSignal; callResource?: HubSpotResourceCall; request: unknown}>;
type WriteObservationOptions = Readonly<{moon: Readonly<{hubspotProjectRecordWriteSuccess(request: unknown, status: number, bytes: Uint8Array, maxBytes: number, maxNodes: number,
    maxDepth: number, maxRows: number): unknown}>;
  request: unknown; observation: Readonly<{body: Uint8Array; statusCode: number}>;
  limits: Pick<Limits, 'maxResponseBytes' | 'maxNodes' | 'maxDepth' | 'maxRows'>}>;

export const HUBSPOT_BATCH_WRITE_OPERATIONS = Object.freeze({
  create: 'hubspot:objects:batch-create', update: 'hubspot:objects:batch-update',
  upsert: 'hubspot:objects:batch-upsert'});
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const segment = (value: string) => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);
const exports = ['hubspotProjectProperties', 'hubspotRecheckAccountIdentityJson',
  'hubspotRecordBatchBody', 'hubspotRecordBatchObjectType', 'hubspotRecordBatchEndpoint',
  'hubspotRecordBatchCount', 'hubspotRecheckRecordBatch'] as const;
const limitFields = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxProperties', 'maxNameUnits', 'maxRows'] as const;

export class HubSpotRecordWriteFailure extends Error {
  declare readonly code: unknown;
  declare readonly observations: readonly HubSpotResponse[];

  constructor(cause: HubSpotObservationCause, observations: readonly HubSpotResponse[]) {
    super(typeof cause?.message === 'string' ? cause.message : 'HubSpotRecordWriteFailed', {cause});
    this.name = typeof cause?.name === 'string' ? cause.name : 'Error';
    this.code = cause?.code ?? 'HubSpotRecordWriteFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// Reclassify original retained bytes without any credential lookup or send.
// Non-success and malformed/partial acknowledgements remain unclassified;
// HTTP status and nominal Credential success are not an Effect outcome.
export function projectHubSpotRecordWriteObservation({moon, request, observation, limits}: WriteObservationOptions) {
  if (typeof moon?.hubspotProjectRecordWriteSuccess !== 'function' ||
      !request || !(observation?.body instanceof Uint8Array) ||
      !Number.isInteger(observation.statusCode) ||
      !(['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows'] as const).every(key => positive(limits?.[key]))) {
    fail('InvalidHubSpotWriteObservation');
  }
  try {
    const response = checked(moon.hubspotProjectRecordWriteSuccess(request,
      observation.statusCode, observation.body, limits.maxResponseBytes,
      limits.maxNodes, limits.maxDepth, limits.maxRows));
    return Object.freeze({kind: 'typed-success-response' as const, observation, response});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response' as const, observation, cause});
  }
}

// Raw Site boundary for the existing Row Effect Owner, after its original
// durable claim. It does not create/settle a claim, approve a Preview or retry.
// Identity and schema are separately authorized nominal reads; the write uses
// its own exact operation and the same privately retained Credential binding.
export async function sendRawHubSpotRecordBatch({moon, originalPortalId,
  originalCatalog, request, initialAuthorization, credential, authorizationFor,
  limits, current, chargeResponse, consumeObservation, signal,
  callResource = callHttpsCredentialResource}: Options) {
  if (exports.some(name => typeof moon?.[name] !== 'function') ||
      !limitFields.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidHubSpotRecordWrite');
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon[name]]))) as Native;
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse,
      consumeObservation, callResource}}) as HubSpotInvocation<Limits, Callbacks>;
  if ((context.scope as {operation?: unknown}).operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) fail('ForeignHubSpotAccountOperation');
  const endpoint = provider.hubspotRecordBatchEndpoint(request);
  const operation = HUBSPOT_BATCH_WRITE_OPERATIONS[endpoint as keyof typeof HUBSPOT_BATCH_WRITE_OPERATIONS];
  const objectType = provider.hubspotRecordBatchObjectType(request);
  const body = provider.hubspotRecordBatchBody(request);
  if (!operation || !objectType || objectType === '.' || objectType === '..' ||
      objectType.length > context.limits.maxNameUnits ||
      provider.hubspotRecordBatchCount(request) > context.limits.maxRows ||
      Buffer.byteLength(body) > context.limits.maxRequestBytes) fail('HubSpotWriteRequestLimit');
  checked(provider.hubspotRecheckRecordBatch(request, originalCatalog, context.limits.maxProperties));
  const observations: HubSpotResponse[] = [];
  const verify = async (selected: string) => {
    signal?.throwIfAborted(); await context.callbacks.current(selected); signal?.throwIfAborted();
  };
  const receive = async (selected: string, index: number, path: string, method: 'GET' | 'POST', payload?: string) => {
    await verify(selected);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: selected, index, objectType})));
    if ((authorization.scope as {operation?: unknown}).operation !== selected ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignHubSpotWriteAuthorization');
    await verify(selected);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation: selected, method, path,
      query: [], headers: [['accept', 'application/json']], body: payload,
      responseHeaders: [], maxRequestBytes: context.limits.maxRequestBytes,
      maxResponseBytes: context.limits.maxResponseBytes, signal,
      callResource: (options: HubSpotResourceInput) => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(selected)})}) as HubSpotResponse;
    observations.push(response);
    const charge = await context.callbacks.chargeResponse(response.body);
    await verify(selected);
    return {response, charge};
  };
  try {
    const account = await observeHubSpotAccount({moon: provider, originalPortalId,
      authorization: context.authorization, credential: context.credential,
      limits: context.limits, current: () => verify(HUBSPOT_ACCOUNT_DETAILS_OPERATION),
      chargeResponse: context.callbacks.chargeResponse,
      consumeObservation: context.callbacks.consumeObservation,
      signal, callResource: context.callbacks.callResource});
    observations.push(account.response);
    const {response: schema, charge: schemaCharge} = await receive(
      HUBSPOT_PROPERTIES_READ_OPERATION, 1,
      `/crm/v3/properties/${segment(objectType)}`, 'GET');
    if (!schema.accepted || schema.statusCode !== 200) fail('HubSpotWriteSchemaUnavailable');
    const catalog = checked(provider.hubspotProjectProperties(schema.body, objectType,
      context.limits.maxResponseBytes, context.limits.maxNodes, context.limits.maxDepth,
      context.limits.maxProperties, context.limits.maxNameUnits));
    checked(provider.hubspotRecheckRecordBatch(request, catalog, context.limits.maxProperties));
    await context.callbacks.consumeObservation(schemaCharge);
    await verify(HUBSPOT_PROPERTIES_READ_OPERATION);
    const {response, charge} = await receive(operation, 2,
      `/crm/v3/objects/${segment(objectType)}/batch/${endpoint}`, 'POST', body);
    await context.callbacks.consumeObservation(charge);
    await verify(operation);
    return Object.freeze({observation: response, observations: Object.freeze(observations.slice()),
      limits: context.limits});
  } catch (cause) {
    if ((cause as HubSpotObservationCause)?.observation && !observations.includes((cause as HubSpotObservationCause)!.observation!)) observations.push((cause as HubSpotObservationCause)!.observation!);
    throw new HubSpotRecordWriteFailure(cause as HubSpotObservationCause, observations);
  }
}

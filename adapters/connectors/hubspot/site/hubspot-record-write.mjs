import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {observeHubSpotAccount, HUBSPOT_ACCOUNT_DETAILS_OPERATION} from './hubspot-account-read.mjs';
import {HUBSPOT_PROPERTIES_READ_OPERATION} from './hubspot-object-read.mjs';

export const HUBSPOT_BATCH_WRITE_OPERATIONS = Object.freeze({
  create: 'hubspot:objects:batch-create', update: 'hubspot:objects:batch-update',
  upsert: 'hubspot:objects:batch-upsert'});
const positive = value => Number.isSafeInteger(value) && value > 0 && value < 2147483647;
const fail = code => {throw Object.assign(new Error(code), {code});};
const segment = value => encodeURIComponent(value).replace(/[!'()*]/gu,
  unit => `%${unit.charCodeAt(0).toString(16).toUpperCase()}`);
const exports = ['hubspotProjectProperties', 'hubspotRecheckAccountIdentityJson',
  'hubspotRecordBatchBody', 'hubspotRecordBatchObjectType', 'hubspotRecordBatchEndpoint',
  'hubspotRecordBatchCount', 'hubspotRecheckRecordBatch'];
const limitFields = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxProperties', 'maxNameUnits', 'maxRows'];

export class HubSpotRecordWriteFailure extends Error {
  constructor(cause, observations) {
    super(typeof cause?.message === 'string' ? cause.message : 'HubSpotRecordWriteFailed', {cause});
    this.name = typeof cause?.name === 'string' ? cause.name : 'Error';
    this.code = cause?.code ?? 'HubSpotRecordWriteFailed';
    Object.defineProperty(this, 'observations', {value: Object.freeze(observations.slice())});
  }
}

// Reclassify original retained bytes without any credential lookup or send.
// Non-success and malformed/partial acknowledgements remain unclassified;
// HTTP status and nominal Credential success are not an Effect outcome.
export function projectHubSpotRecordWriteObservation({moon, request, observation, limits}) {
  if (typeof moon?.hubspotProjectRecordWriteSuccess !== 'function' ||
      !request || !(observation?.body instanceof Uint8Array) ||
      !Number.isInteger(observation.statusCode) ||
      !['maxResponseBytes', 'maxNodes', 'maxDepth', 'maxRows'].every(key => positive(limits?.[key]))) {
    fail('InvalidHubSpotWriteObservation');
  }
  try {
    const response = checked(moon.hubspotProjectRecordWriteSuccess(request,
      observation.statusCode, observation.body, limits.maxResponseBytes,
      limits.maxNodes, limits.maxDepth, limits.maxRows));
    return Object.freeze({kind: 'typed-success-response', observation, response});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response', observation, cause});
  }
}

// Raw Site boundary for the existing Row Effect Owner, after its original
// durable claim. It does not create/settle a claim, approve a Preview or retry.
// Identity and schema are separately authorized nominal reads; the write uses
// its own exact operation and the same privately retained Credential binding.
export async function sendRawHubSpotRecordBatch({moon, originalPortalId,
  originalCatalog, request, initialAuthorization, credential, authorizationFor,
  limits, current, chargeResponse, consumeObservation, signal,
  callResource = callHttpsCredentialResource}) {
  if (exports.some(name => typeof moon?.[name] !== 'function') ||
      !limitFields.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidHubSpotRecordWrite');
  const provider = Object.freeze(Object.fromEntries(exports.map(name => [name, moon[name]])));
  const context = ownInvocationContext({authorization: initialAuthorization,
    credential, limits, callbacks: {authorizationFor, current, chargeResponse,
      consumeObservation, callResource}});
  if (context.scope.operation !== HUBSPOT_ACCOUNT_DETAILS_OPERATION) fail('ForeignHubSpotAccountOperation');
  const endpoint = provider.hubspotRecordBatchEndpoint(request);
  const operation = HUBSPOT_BATCH_WRITE_OPERATIONS[endpoint];
  const objectType = provider.hubspotRecordBatchObjectType(request);
  const body = provider.hubspotRecordBatchBody(request);
  if (!operation || !objectType || objectType === '.' || objectType === '..' ||
      objectType.length > context.limits.maxNameUnits ||
      provider.hubspotRecordBatchCount(request) > context.limits.maxRows ||
      Buffer.byteLength(body) > context.limits.maxRequestBytes) fail('HubSpotWriteRequestLimit');
  checked(provider.hubspotRecheckRecordBatch(request, originalCatalog, context.limits.maxProperties));
  const observations = [];
  const verify = async selected => {
    signal?.throwIfAborted(); await context.callbacks.current(selected); signal?.throwIfAborted();
  };
  const receive = async (selected, index, path, method, payload) => {
    await verify(selected);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: selected, index, objectType})));
    if (authorization.scope.operation !== selected ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignHubSpotWriteAuthorization');
    await verify(selected);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation: selected, method, path,
      query: [], headers: [['accept', 'application/json']], body: payload,
      responseHeaders: [], maxRequestBytes: context.limits.maxRequestBytes,
      maxResponseBytes: context.limits.maxResponseBytes, signal,
      callResource: options => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(selected)})});
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
    if (cause?.observation && !observations.includes(cause.observation)) observations.push(cause.observation);
    throw new HubSpotRecordWriteFailure(cause, observations);
  }
}

import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';

export const KINTONE_TARGET_READ_OPERATION = 'kintone:records:target-read';
export const KINTONE_RECORD_DELETE_OPERATION = 'kintone:records:delete';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const required = ['clientProgramKintoneDeleteApp', 'clientProgramKintoneDeleteCount',
  'clientProgramKintoneDeleteBody', 'clientProgramKintoneDeleteObservationBody',
  'clientProgramKintoneDeleteRecheckForm', 'clientProgramKintoneDeleteRecheckRecords',
  'clientProgramKintoneFormLimits', 'clientProgramKintonePageLimits'];
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCells',
  'maxTableRows', 'maxComparisonWork'];

export class KintoneDeleteFailure extends Error {
  constructor(cause, observations, phase) {
    super(cause?.message ?? 'KintoneDeleteFailed', {cause});
    this.code = cause?.code ?? 'KintoneDeleteFailed';
    // Private diagnostic phase, not proof that a request was sent. Only the
    // original credential claim/transport can decide that physical boundary.
    this.phase = phase;
    this.observations = Object.freeze(observations.slice());
  }
}

// Decode retained original bytes only. A typed response observation does not
// publish an applied Effect or resolve an uncertain original attempt.
export function projectKintoneDeleteObservation({moon, request, observation, limits}) {
  if (typeof moon?.clientProgramKintoneDeleteResponse !== 'function' ||
      !(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !['maxResponseBytes', 'maxNodes', 'maxDepth'].every(key => positive(limits?.[key]))) {
    fail('InvalidKintoneDeleteObservation');
  }
  try {
    return Object.freeze({kind: 'typed-delete-response', observation,
      response: checked(moon.clientProgramKintoneDeleteResponse(request,
        observation.statusCode, observation.body, limits.maxResponseBytes,
        limits.maxNodes, limits.maxDepth))});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response', observation, cause});
  }
}

// Raw physical port after the existing Effect Owner's original durable claim.
// The caller retains its original binding and cleanup; this port cannot open
// another secret, claim/settle an Effect, approve a Preview, retry or release it.
export async function sendRawKintoneDelete({moon, originalAppId, request,
  initialAuthorization, credential, authorizationFor, current, limits,
  chargeResponse, consumeObservation, guestSpaceId, signal,
  callResource = callHttpsCredentialResource}) {
  if (required.some(name => typeof moon?.[name] !== 'function') ||
      !limitNames.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      limits.maxFields > 998 || !/^[1-9][0-9]*$/u.test(originalAppId ?? '') ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidKintoneDelete');
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}});
  if (context.scope.connectorRegistration !== 'kintone' ||
      context.scope.operation !== KINTONE_FORM_READ_OPERATION ||
      moon.clientProgramKintoneDeleteApp(request) !== originalAppId) fail('ForeignKintoneDeleteInstallation');
  const body = moon.clientProgramKintoneDeleteBody(request);
  if (moon.clientProgramKintoneDeleteCount(request) > context.limits.maxRows ||
      originalAppId.length > context.limits.maxRequestBytes - 10 ||
      Buffer.byteLength(body) > context.limits.maxRequestBytes) fail('KintoneDeleteRequestLimit');
  const formLimits = moon.clientProgramKintoneFormLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxFields, context.limits.maxNameUnits);
  const pageLimits = moon.clientProgramKintonePageLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxRows,
    context.limits.maxColumns, context.limits.maxCells, context.limits.maxTableRows);
  const targetBody = checked(moon.clientProgramKintoneDeleteObservationBody(request,
    context.limits.maxFields, context.limits.maxRequestBytes, context.limits.maxNodes, context.limits.maxDepth));
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const observations = [];
  let phase = 'preparation';
  const verify = async operation => {
    signal?.throwIfAborted(); await context.callbacks.current(operation); signal?.throwIfAborted();
  };
  const receive = async (operation, index, path, method, payload, headers = []) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index, appId: originalAppId})));
    if (authorization.scope.operation !== operation ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignKintoneDeleteAuthorization');
    await verify(operation);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation, method, path: prefix + path,
      body: payload, query: [], headers, responseHeaders: [],
      maxRequestBytes: context.limits.maxRequestBytes, maxResponseBytes: context.limits.maxResponseBytes,
      signal, callResource: options => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)})});
    observations.push(response);
    // The real original response is charged synchronously before another
    // awaited current check or vendor decode can refuse its retained bytes.
    const charge = context.callbacks.chargeResponse(response.body);
    return {response, charge};
  };
  const observedRead = async (operation, index, path, payload, check) => {
    const {response, charge} = await receive(operation, index, path, 'POST', payload,
      [['x-http-method-override', 'GET']]);
    if (response.statusCode !== 200) {
      context.callbacks.consumeObservation(charge); await verify(operation);
      fail('KintoneDeleteReadRejected');
    }
    check(response.body);
    context.callbacks.consumeObservation(charge); await verify(operation);
  };
  try {
    phase = 'form';
    await observedRead(KINTONE_FORM_READ_OPERATION, 0, 'app/form/fields.json',
      JSON.stringify({app: originalAppId}), bytes => checked(
        moon.clientProgramKintoneDeleteRecheckForm(request, bytes, formLimits)));
    phase = 'target';
    await observedRead(KINTONE_TARGET_READ_OPERATION, 1, 'records.json', targetBody,
      bytes => checked(moon.clientProgramKintoneDeleteRecheckRecords(request, bytes,
        pageLimits, context.limits.maxFields, context.limits.maxComparisonWork)));
    phase = 'delete';
    const {response, charge} = await receive(KINTONE_RECORD_DELETE_OPERATION, 2,
      'records.json', 'DELETE', body);
    context.callbacks.consumeObservation(charge); await verify(KINTONE_RECORD_DELETE_OPERATION);
    return Object.freeze({observation: response, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if (cause?.observation && !observations.includes(cause.observation)) observations.push(cause.observation);
    throw new KintoneDeleteFailure(cause, observations, phase);
  }
}

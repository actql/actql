import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from './kintone-record-delete.mjs';

export const KINTONE_RECORD_CREATE_OPERATION = 'kintone:records:create';
export const KINTONE_RECORD_UPDATE_OPERATION = 'kintone:records:update';
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const commonPorts = ['clientProgramKintoneFormLimits', 'clientProgramKintonePageLimits',
  'clientProgramKintoneMutationLimits'];
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCells',
  'maxTableRows', 'maxComparisonWork', 'maxIdentityBytes'];

function writePorts(moon, kind) {
  if (kind !== 'create' && kind !== 'update') fail('InvalidKintoneWriteKind');
  const prefix = kind === 'create' ? 'Create' : 'Update';
  const ports = Object.fromEntries(['App', 'Count', 'Body', 'Response'].map(name =>
    [name, moon?.[`clientProgramKintone${prefix}${name}`]]));
  if (Object.values(ports).some(port => typeof port !== 'function') ||
      commonPorts.some(name => typeof moon?.[name] !== 'function') ||
      (kind === 'create' && typeof moon?.clientProgramKintoneCreateRecheckForm !== 'function') ||
      (kind === 'update' && ['clientProgramKintoneUpdateObservation',
        'clientProgramKintoneDeleteObservationBody', 'clientProgramKintoneDeleteRecheckForm',
        'clientProgramKintoneDeleteRecheckRecords'].some(name => typeof moon?.[name] !== 'function'))) {
    fail('KintoneWriteRuntimeUnavailable');
  }
  return Object.freeze(ports);
}

export class KintoneWriteFailure extends Error {
  constructor(cause, observations, phase) {
    super(cause?.message ?? 'KintoneWriteFailed', {cause});
    this.code = cause?.code ?? 'KintoneWriteFailed';
    // Diagnostic position is not a send, commit, stop or cleanup decision.
    this.phase = phase;
    this.observations = Object.freeze(observations.slice());
  }
}

export function projectKintoneWriteObservation({moon, kind, request, observation, limits}) {
  const ports = writePorts(moon, kind);
  if (!(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !limitNames.every(key => positive(limits?.[key]))) fail('InvalidKintoneWriteObservation');
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  try {
    return Object.freeze({kind: `typed-${kind}-response`, observation,
      response: checked(ports.Response(request, observation.statusCode, observation.body, bounds))});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response', observation, cause});
  }
}

// This port follows the existing Effect Owner's original durable claim. It
// neither chooses create on absence nor upgrades read permission into a write.
// Caller custody retains every body/ticket and the original binding through
// physical retirement; no retry, new lookup, release or Effect settlement here.
export async function sendRawKintoneWrite({moon, kind, originalAppId, request,
  initialAuthorization, credential, authorizationFor, current, limits,
  chargeResponse, consumeObservation, guestSpaceId, signal,
  callResource = callHttpsCredentialResource}) {
  const ports = writePorts(moon, kind);
  if (!limitNames.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      limits.maxFields > 998 || !/^[1-9][0-9]*$/u.test(originalAppId ?? '') ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidKintoneWrite');
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}});
  if (context.scope.connectorRegistration !== 'kintone' ||
      context.scope.operation !== KINTONE_FORM_READ_OPERATION ||
      ports.App(request) !== originalAppId) fail('ForeignKintoneWriteInstallation');
  const body = ports.Body(request);
  if (ports.Count(request) > context.limits.maxRows ||
      originalAppId.length > context.limits.maxRequestBytes - 10 ||
      Buffer.byteLength(body) > context.limits.maxRequestBytes) fail('KintoneWriteRequestLimit');
  const formLimits = moon.clientProgramKintoneFormLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxFields, context.limits.maxNameUnits);
  const pageLimits = moon.clientProgramKintonePageLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxRows,
    context.limits.maxColumns, context.limits.maxCells, context.limits.maxTableRows);
  const mutationLimits = moon.clientProgramKintoneMutationLimits(context.limits.maxRows,
    context.limits.maxIdentityBytes, context.limits.maxComparisonWork,
    context.limits.maxRequestBytes, context.limits.maxNodes, context.limits.maxDepth);
  const target = kind === 'update'
    ? checked(moon.clientProgramKintoneUpdateObservation(request, mutationLimits)) : undefined;
  const targetBody = kind === 'update' ? checked(moon.clientProgramKintoneDeleteObservationBody(target,
    context.limits.maxFields, context.limits.maxRequestBytes, context.limits.maxNodes, context.limits.maxDepth)) : undefined;
  const operation = kind === 'create' ? KINTONE_RECORD_CREATE_OPERATION : KINTONE_RECORD_UPDATE_OPERATION;
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const observations = [];
  let phase = 'preparation';
  const verify = async selected => {
    signal?.throwIfAborted(); await context.callbacks.current(selected); signal?.throwIfAborted();
  };
  const receive = async (selected, index, path, method, payload, headers = []) => {
    await verify(selected);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: selected, index, appId: originalAppId})));
    if (authorization.scope.operation !== selected ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignKintoneWriteAuthorization');
    await verify(selected);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation: selected, method, path: prefix + path,
      body: payload, query: [], headers, responseHeaders: [],
      maxRequestBytes: context.limits.maxRequestBytes, maxResponseBytes: context.limits.maxResponseBytes,
      signal, callResource: options => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(selected)})});
    observations.push(response);
    // Charge the original received body before another awaited fence or decode.
    const charge = context.callbacks.chargeResponse(response.body);
    return {response, charge};
  };
  const observedRead = async (selected, index, path, payload, check) => {
    const {response, charge} = await receive(selected, index, path, 'POST', payload,
      [['x-http-method-override', 'GET']]);
    if (response.statusCode !== 200) {
      context.callbacks.consumeObservation(charge); await verify(selected);
      fail('KintoneWriteReadRejected');
    }
    check(response.body);
    context.callbacks.consumeObservation(charge); await verify(selected);
  };
  try {
    phase = 'form';
    await observedRead(KINTONE_FORM_READ_OPERATION, 0, 'app/form/fields.json',
      JSON.stringify({app: originalAppId}), bytes => checked(kind === 'create'
        ? moon.clientProgramKintoneCreateRecheckForm(request, bytes, formLimits)
        : moon.clientProgramKintoneDeleteRecheckForm(target, bytes, formLimits)));
    if (kind === 'update') {
      phase = 'target';
      await observedRead(KINTONE_TARGET_READ_OPERATION, 1, 'records.json', targetBody,
        bytes => checked(moon.clientProgramKintoneDeleteRecheckRecords(target, bytes,
          pageLimits, context.limits.maxFields, context.limits.maxComparisonWork)));
    }
    phase = kind;
    const {response, charge} = await receive(operation, kind === 'create' ? 1 : 2,
      'records.json', kind === 'create' ? 'POST' : 'PUT', body);
    context.callbacks.consumeObservation(charge); await verify(operation);
    return Object.freeze({observation: response, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if (cause?.observation && !observations.includes(cause.observation)) observations.push(cause.observation);
    throw new KintoneWriteFailure(cause, observations, phase);
  }
}

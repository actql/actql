import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from './kintone-record-delete.mjs';

const required = ['clientProgramKintoneLookupApp', 'clientProgramKintoneLookupBody',
  'clientProgramKintoneLookupRecheckForm', 'clientProgramKintoneLookupResponse',
  'clientProgramKintoneFormLimits', 'clientProgramKintonePageLimits'];
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const fail = code => {throw Object.assign(new Error(code), {code});};
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCells', 'maxTableRows'];

export class KintoneLookupFailure extends Error {
  constructor(cause, observations, phase) {
    super(cause?.message ?? 'KintoneLookupFailed', {cause});
    this.code = cause?.code ?? 'KintoneLookupFailed';
    this.phase = phase;
    this.observations = Object.freeze(observations.slice());
  }
}

// Borrow the original private binding; never resolve another secret, replace
// the request, create a Run/claim or interpret an empty page as a write grant.
// Form and target reads retain independently counted nominal authorizations.
export async function readRawKintoneKeyLookup({moon, originalAppId, request,
  initialAuthorization, credential, authorizationFor, current, limits,
  chargeResponse, consumeObservation, guestSpaceId, signal,
  callResource = callHttpsCredentialResource}) {
  if (required.some(name => typeof moon?.[name] !== 'function') ||
      !limitNames.every(key => positive(limits?.[key])) ||
      !/^[1-9][0-9]*$/u.test(originalAppId ?? '') ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidKintoneLookup');
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}});
  if (context.scope.connectorRegistration !== 'kintone' ||
      context.scope.operation !== KINTONE_FORM_READ_OPERATION ||
      moon.clientProgramKintoneLookupApp(request) !== originalAppId) fail('ForeignKintoneLookupInstallation');
  const body = moon.clientProgramKintoneLookupBody(request);
  const formBody = JSON.stringify({app: originalAppId});
  if (Buffer.byteLength(body) > context.limits.maxRequestBytes ||
      Buffer.byteLength(formBody) > context.limits.maxRequestBytes) fail('KintoneLookupRequestLimit');
  const formLimits = moon.clientProgramKintoneFormLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxFields, context.limits.maxNameUnits);
  const pageLimits = moon.clientProgramKintonePageLimits(context.limits.maxResponseBytes,
    context.limits.maxNodes, context.limits.maxDepth, context.limits.maxRows,
    context.limits.maxColumns, context.limits.maxCells, context.limits.maxTableRows);
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const observations = [];
  let phase = 'preparation';
  const verify = async operation => {
    signal?.throwIfAborted(); await context.callbacks.current(operation); signal?.throwIfAborted();
  };
  const receive = async (operation, index, path, payload) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index, appId: originalAppId})));
    if (authorization.scope.operation !== operation ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignKintoneLookupAuthorization');
    await verify(operation);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation, method: 'POST', path: prefix + path,
      body: payload, query: [], headers: [['x-http-method-override', 'GET']], responseHeaders: [],
      maxRequestBytes: context.limits.maxRequestBytes, maxResponseBytes: context.limits.maxResponseBytes,
      signal, callResource: options => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)})});
    observations.push(response);
    // Synchronous original response charge precedes every awaited fence and
    // decode. Failure keeps these exact bytes and the original pending ticket.
    const charge = context.callbacks.chargeResponse(response.body);
    return {response, charge};
  };
  const form = async index => {
    const {response, charge} = await receive(KINTONE_FORM_READ_OPERATION, index,
      'app/form/fields.json', formBody);
    await verify(KINTONE_FORM_READ_OPERATION);
    if (response.statusCode !== 200) fail('KintoneLookupReadRejected');
    checked(moon.clientProgramKintoneLookupRecheckForm(request, response.body, formLimits));
    context.callbacks.consumeObservation(charge);
    await verify(KINTONE_FORM_READ_OPERATION);
  };
  try {
    phase = 'initial-form'; await form(0);
    phase = 'lookup';
    const {response, charge} = await receive(KINTONE_TARGET_READ_OPERATION, 1,
      'records.json', body);
    await verify(KINTONE_TARGET_READ_OPERATION);
    if (response.statusCode !== 200) fail('KintoneLookupReadRejected');
    const observation = checked(moon.clientProgramKintoneLookupResponse(request,
      response.statusCode, response.body, pageLimits));
    context.callbacks.consumeObservation(charge);
    await verify(KINTONE_TARGET_READ_OPERATION);
    phase = 'final-form'; await form(2);
    // No disclosure after a later awaited final Form fence can lose current
    // target-read authority. A nominally succeeded call is not current access.
    await verify(KINTONE_TARGET_READ_OPERATION);
    return Object.freeze({observation, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if (cause?.observation && !observations.includes(cause.observation)) observations.push(cause.observation);
    throw new KintoneLookupFailure(cause, observations, phase);
  }
}

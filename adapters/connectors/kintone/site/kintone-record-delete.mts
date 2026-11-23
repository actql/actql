import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';

import type {KintoneFormAndPageRuntime, KintoneInvocation, KintoneObservationCause,
  KintoneResourceInput, KintoneResourceCall, KintoneResponse, KintoneScope} from './kintone-record-read.mjs';

export const KINTONE_TARGET_READ_OPERATION = 'kintone:records:target-read';
export const KINTONE_RECORD_DELETE_OPERATION = 'kintone:records:delete';
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const required = ['clientProgramKintoneDeleteApp', 'clientProgramKintoneDeleteCount',
  'clientProgramKintoneDeleteBody', 'clientProgramKintoneDeleteObservationBody',
  'clientProgramKintoneDeleteRecheckForm', 'clientProgramKintoneDeleteRecheckRecords',
  'clientProgramKintoneFormLimits', 'clientProgramKintonePageLimits'] as const;
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCells',
  'maxTableRows', 'maxComparisonWork'] as const;

type Native = KintoneFormAndPageRuntime & Readonly<{
  clientProgramKintoneDeleteApp(request: unknown): string;
  clientProgramKintoneDeleteCount(request: unknown): number;
  clientProgramKintoneDeleteBody(request: unknown): string;
  clientProgramKintoneDeleteResponse(request: unknown, status: number, body: Uint8Array,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramKintoneDeleteObservationBody(request: unknown, fields: number, bytes: number,
    nodes: number, depth: number): unknown;
  clientProgramKintoneDeleteRecheckForm(request: unknown, body: Uint8Array, form: unknown): unknown;
  clientProgramKintoneDeleteRecheckRecords(request: unknown, body: Uint8Array, page: unknown,
    fields: number, comparison: number): unknown;
}>;
type Observation = Readonly<{moon: Pick<Native, 'clientProgramKintoneDeleteResponse'>;
  request: unknown; observation: KintoneResponse; limits: Pick<Limits, 'maxResponseBytes' | 'maxNodes' | 'maxDepth'>}>;
type Phase = 'preparation' | 'form' | 'target' | 'delete';
type Limits = Readonly<Record<(typeof limitNames)[number], number>>;
type Callbacks = Readonly<{
  authorizationFor(input: Readonly<{operation: string; index: number; appId: string}>): unknown;
  current(operation: string): unknown; chargeResponse(body: Uint8Array): unknown;
  consumeObservation(charge: unknown): unknown; callResource: KintoneResourceCall;
}>;
type PhysicalMutation = Omit<Callbacks, 'callResource'> & Readonly<{
  moon: Native; request: unknown; originalAppId: string; limits: Limits;
  initialAuthorization: unknown; credential: Readonly<{binding?: unknown}>;
  guestSpaceId?: string; signal?: AbortSignal; callResource?: KintoneResourceCall;
}>;
type HeaderPairs = readonly (readonly [name: string, value: string])[];

export class KintoneDeleteFailure extends Error {
  declare readonly code: unknown;
  declare readonly phase: Phase;
  declare readonly observations: readonly KintoneResponse[];

  constructor(cause: KintoneObservationCause, observations: readonly KintoneResponse[], phase: Phase) {
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
export function projectKintoneDeleteObservation({moon, request, observation, limits}: Observation) {
  if (typeof moon?.clientProgramKintoneDeleteResponse !== 'function' ||
      !(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !(['maxResponseBytes', 'maxNodes', 'maxDepth'] as const).every(key => positive(limits?.[key]))) {
    fail('InvalidKintoneDeleteObservation');
  }
  try {
    return Object.freeze({kind: 'typed-delete-response' as const, observation,
      response: checked(moon.clientProgramKintoneDeleteResponse(request,
        observation.statusCode!, observation.body, limits.maxResponseBytes,
        limits.maxNodes, limits.maxDepth))});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response' as const, observation, cause});
  }
}

// Raw physical port after the existing Effect Owner's original durable claim.
// The caller retains its original binding and cleanup; this port cannot open
// another secret, claim/settle an Effect, approve a Preview, retry or release it.
export async function sendRawKintoneDelete({moon, originalAppId, request,
  initialAuthorization, credential, authorizationFor, current, limits,
  chargeResponse, consumeObservation, guestSpaceId, signal,
  callResource = callHttpsCredentialResource}: PhysicalMutation) {
  if (required.some(name => typeof moon?.[name] !== 'function') ||
      !limitNames.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      limits.maxFields > 998 || !/^[1-9][0-9]*$/u.test(originalAppId ?? '') ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidKintoneDelete');
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}}) as KintoneInvocation<Limits, Callbacks>;
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
    context.limits.maxFields, context.limits.maxRequestBytes, context.limits.maxNodes, context.limits.maxDepth)) as string;
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const observations: KintoneResponse[] = [];
  let phase: Phase = 'preparation';
  const verify = async (operation: string) => {
    signal?.throwIfAborted(); await context.callbacks.current(operation); signal?.throwIfAborted();
  };
  const receive = async (operation: string, index: number, path: string, method: string, payload: string | undefined, headers: HeaderPairs = []) => {
    await verify(operation);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation, index, appId: originalAppId}))) as
      ReturnType<typeof ownInvocationAuthorization> & {scope: KintoneScope};
    if (authorization.scope.operation !== operation ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignKintoneDeleteAuthorization');
    await verify(operation);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation, method, path: prefix + path,
      body: payload, query: [], headers, responseHeaders: [],
      maxRequestBytes: context.limits.maxRequestBytes, maxResponseBytes: context.limits.maxResponseBytes,
      signal, callResource: (options: KintoneResourceInput) => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(operation)})}) as KintoneResponse;
    observations.push(response);
    // The real original response is charged synchronously before another
    // awaited current check or vendor decode can refuse its retained bytes.
    const charge = context.callbacks.chargeResponse(response.body);
    return {response, charge};
  };
  const observedRead = async (operation: string, index: number, path: string, payload: string | undefined, check: (bytes: Uint8Array) => unknown) => {
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
    // Kintone explicitly supports POST with this exact override on every
    // REST route. Preserve the ordinary transport's bodyless DELETE policy.
    const {response, charge} = await receive(KINTONE_RECORD_DELETE_OPERATION, 2,
      'records.json', 'POST', body, [['x-http-method-override', 'DELETE']]);
    context.callbacks.consumeObservation(charge); await verify(KINTONE_RECORD_DELETE_OPERATION);
    return Object.freeze({observation: response, observations: Object.freeze(observations.slice())});
  } catch (cause) {
    if ((cause as KintoneObservationCause)?.observation &&
        !observations.includes((cause as NonNullable<KintoneObservationCause>).observation!))
      observations.push((cause as NonNullable<KintoneObservationCause>).observation!);
    throw new KintoneDeleteFailure(cause as KintoneObservationCause, observations, phase);
  }
}

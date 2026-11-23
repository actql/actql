import {checked} from '../../../host-common/runtime-result.mjs';
import {ownInvocationContext, ownInvocationAuthorization, invocationBindingsMatch,
  invokeScopedCredentialOperation} from '../../../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from '../../../site-node/https-credential-resource.mjs';
import {KINTONE_FORM_READ_OPERATION} from './kintone-record-read.mjs';
import {KINTONE_TARGET_READ_OPERATION} from './kintone-record-delete.mjs';

import type {KintoneFormAndPageRuntime, KintoneInvocation, KintoneObservationCause,
  KintoneResourceInput, KintoneResourceCall, KintoneResponse, KintoneScope} from './kintone-record-read.mjs';

export const KINTONE_RECORD_CREATE_OPERATION = 'kintone:records:create';
export const KINTONE_RECORD_UPDATE_OPERATION = 'kintone:records:update';
const fail: (code: string) => never = code => {throw Object.assign(new Error(code), {code});};
const positive = (value: number) => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const commonPorts = ['clientProgramKintoneFormLimits', 'clientProgramKintonePageLimits',
  'clientProgramKintoneMutationLimits'] as const;
const limitNames = ['maxResponseBytes', 'maxRequestBytes', 'maxNodes', 'maxDepth',
  'maxFields', 'maxNameUnits', 'maxRows', 'maxColumns', 'maxCells',
  'maxTableRows', 'maxComparisonWork', 'maxIdentityBytes'] as const;

type Ports = Readonly<{App(request: unknown): string; Count(request: unknown): number;
  Body(request: unknown): string; Response(request: unknown, status: number, body: Uint8Array, bounds: unknown): unknown}>;
type PortBindings<Kind extends 'Create' | 'Update'> =
  {readonly [Name in keyof Ports as `clientProgramKintone${Kind}${Name}`]: Ports[Name]};
type Native = KintoneFormAndPageRuntime & PortBindings<'Create' | 'Update'> & Readonly<{
  clientProgramKintoneMutationLimits(rows: number, identity: number, comparison: number,
    bytes: number, nodes: number, depth: number): unknown;
  clientProgramKintoneCreateRecheckForm(request: unknown, body: Uint8Array, form: unknown): unknown;
  clientProgramKintoneUpdateObservation(request: unknown, bounds: unknown): unknown;
  clientProgramKintoneDeleteObservationBody(request: unknown, fields: number, bytes: number,
    nodes: number, depth: number): unknown;
  clientProgramKintoneDeleteRecheckForm(request: unknown, body: Uint8Array, form: unknown): unknown;
  clientProgramKintoneDeleteRecheckRecords(request: unknown, body: Uint8Array, page: unknown,
    fields: number, comparison: number): unknown;
}>;
type Kind = 'create' | 'update';
type Observation = Readonly<{moon: Native; kind: Kind; request: unknown; observation: KintoneResponse; limits: Limits}>;
type Phase = 'preparation' | 'form' | 'target' | Kind;
type Limits = Readonly<Record<(typeof limitNames)[number], number>>;
type Callbacks = Readonly<{
  authorizationFor(input: Readonly<{operation: string; index: number; appId: string}>): unknown;
  current(operation: string): unknown; chargeResponse(body: Uint8Array): unknown;
  consumeObservation(charge: unknown): unknown; callResource: KintoneResourceCall;
}>;
type PhysicalMutation = Omit<Callbacks, 'callResource'> & Readonly<{
  moon: Native; kind: Kind; request: unknown; originalAppId: string; limits: Limits;
  initialAuthorization: unknown; credential: Readonly<{binding?: unknown}>;
  guestSpaceId?: string; signal?: AbortSignal; callResource?: KintoneResourceCall;
}>;
type HeaderPairs = readonly (readonly [name: string, value: string])[];

function writePorts(moon: Native, kind: Kind) {
  if (kind !== 'create' && kind !== 'update') fail('InvalidKintoneWriteKind');
  const prefix = kind === 'create' ? 'Create' : 'Update';
  const ports = Object.fromEntries((['App', 'Count', 'Body', 'Response'] as const).map(name =>
    [name, moon?.[`clientProgramKintone${prefix}${name}`]]));
  if (Object.values(ports).some(port => typeof port !== 'function') ||
      commonPorts.some(name => typeof moon?.[name] !== 'function') ||
      (kind === 'create' && typeof moon?.clientProgramKintoneCreateRecheckForm !== 'function') ||
      (kind === 'update' && (['clientProgramKintoneUpdateObservation',
        'clientProgramKintoneDeleteObservationBody', 'clientProgramKintoneDeleteRecheckForm',
        'clientProgramKintoneDeleteRecheckRecords'] as const).some(name => typeof moon?.[name] !== 'function'))) {
    fail('KintoneWriteRuntimeUnavailable');
  }
  return Object.freeze(ports) as Ports;
}

export class KintoneWriteFailure extends Error {
  declare readonly code: unknown;
  declare readonly phase: Phase;
  declare readonly observations: readonly KintoneResponse[];

  constructor(cause: KintoneObservationCause, observations: readonly KintoneResponse[], phase: Phase) {
    super(cause?.message ?? 'KintoneWriteFailed', {cause});
    this.code = cause?.code ?? 'KintoneWriteFailed';
    // Diagnostic position is not a send, commit, stop or cleanup decision.
    this.phase = phase;
    this.observations = Object.freeze(observations.slice());
  }
}

export function projectKintoneWriteObservation({moon, kind, request, observation, limits}: Observation) {
  const ports = writePorts(moon, kind);
  if (!(observation?.body instanceof Uint8Array) || !Number.isInteger(observation.statusCode) ||
      !limitNames.every(key => positive(limits?.[key]))) fail('InvalidKintoneWriteObservation');
  const bounds = moon.clientProgramKintoneMutationLimits(limits.maxRows,
    limits.maxIdentityBytes, limits.maxComparisonWork, limits.maxResponseBytes,
    limits.maxNodes, limits.maxDepth);
  try {
    return Object.freeze({kind: `typed-${kind}-response` as const, observation,
      response: checked(ports.Response(request, observation.statusCode!, observation.body, bounds))});
  } catch (cause) {
    return Object.freeze({kind: 'unclassified-response' as const, observation, cause});
  }
}

// This port follows the existing Effect Owner's original durable claim. It
// neither chooses create on absence nor upgrades read permission into a write.
// Caller custody retains every body/ticket and the original binding through
// physical retirement; no retry, new lookup, release or Effect settlement here.
export async function sendRawKintoneWrite({moon, kind, originalAppId, request,
  initialAuthorization, credential, authorizationFor, current, limits,
  chargeResponse, consumeObservation, guestSpaceId, signal,
  callResource = callHttpsCredentialResource}: PhysicalMutation) {
  const ports = writePorts(moon, kind);
  if (!limitNames.every(key => positive(limits?.[key])) || limits.maxRows > 100 ||
      limits.maxFields > 998 || !/^[1-9][0-9]*$/u.test(originalAppId ?? '') ||
      (guestSpaceId !== undefined && !/^[1-9][0-9]*$/u.test(guestSpaceId)) ||
      [authorizationFor, current, chargeResponse, consumeObservation, callResource]
        .some(value => typeof value !== 'function') ||
      !credential?.binding || typeof credential.binding !== 'object') fail('InvalidKintoneWrite');
  const context = ownInvocationContext({authorization: initialAuthorization, credential, limits,
    callbacks: {authorizationFor, current, chargeResponse, consumeObservation, callResource}}) as KintoneInvocation<Limits, Callbacks>;
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
    context.limits.maxFields, context.limits.maxRequestBytes, context.limits.maxNodes, context.limits.maxDepth)) as string : undefined;
  const operation = kind === 'create' ? KINTONE_RECORD_CREATE_OPERATION : KINTONE_RECORD_UPDATE_OPERATION;
  const prefix = guestSpaceId === undefined ? '/k/v1/' : `/k/guest/${guestSpaceId}/v1/`;
  const observations: KintoneResponse[] = [];
  let phase: Phase = 'preparation';
  const verify = async (selected: string) => {
    signal?.throwIfAborted(); await context.callbacks.current(selected); signal?.throwIfAborted();
  };
  const receive = async (selected: string, index: number, path: string, method: string, payload: string | undefined, headers: HeaderPairs = []) => {
    await verify(selected);
    const authorization = ownInvocationAuthorization(await context.callbacks.authorizationFor(
      Object.freeze({operation: selected, index, appId: originalAppId}))) as
      ReturnType<typeof ownInvocationAuthorization> & {scope: KintoneScope};
    if (authorization.scope.operation !== selected ||
        !invocationBindingsMatch(authorization.scope, context.scope)) fail('ForeignKintoneWriteAuthorization');
    await verify(selected);
    const response = await invokeScopedCredentialOperation({authorization,
      credential: context.credential, operation: selected, method, path: prefix + path,
      body: payload, query: [], headers, responseHeaders: [],
      maxRequestBytes: context.limits.maxRequestBytes, maxResponseBytes: context.limits.maxResponseBytes,
      signal, callResource: (options: KintoneResourceInput) => context.callbacks.callResource({...options,
        currentBeforeSend: () => verify(selected)})}) as KintoneResponse;
    observations.push(response);
    // Charge the original received body before another awaited fence or decode.
    const charge = context.callbacks.chargeResponse(response.body);
    return {response, charge};
  };
  const observedRead = async (selected: string, index: number, path: string, payload: string | undefined, check: (bytes: Uint8Array) => unknown) => {
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
    if ((cause as KintoneObservationCause)?.observation &&
        !observations.includes((cause as NonNullable<KintoneObservationCause>).observation!))
      observations.push((cause as NonNullable<KintoneObservationCause>).observation!);
    throw new KintoneWriteFailure(cause as KintoneObservationCause, observations, phase);
  }
}

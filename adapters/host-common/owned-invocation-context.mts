import {types as nodeTypes} from 'node:util';
import {credentialInvocationBindingKeys as bindingKeys} from './credential-scope-fields.generated.mjs';
import {exchangeLimits, ownHttpRequest, ownHttpByteRequest, ownResponseHeaderNames} from './http-exchange.mjs';

type UncheckedControl = {kind?: unknown; scopeFields(scope: unknown): unknown; subjectFields(): unknown};
type UncheckedAuthorization = {useId?: unknown; scope?: unknown; grant?: unknown};
type ContextInput = {authorization: unknown; credential: unknown; limits: unknown; callbacks?: unknown};
type InvocationPorts = {authorization: unknown; credential?: unknown; callResource: unknown; signal?: AbortSignal};
type TransportRequest = Parameters<typeof ownHttpRequest>[0] & {
  operation?: unknown; responseHeaders?: unknown; maxRequestBytes?: unknown; maxResponseBytes?: unknown;
  bodyBytes?: unknown; bodyMediaType?: unknown; responseCustody?: unknown;
};
type ScopedOperation = TransportRequest & InvocationPorts;
type InstalledLimits = Readonly<{maxRequestBytes: number; maxResponseBytes: number; maxTargetBytes?: number}>;
type TargetSlot = InstalledLimits & Readonly<{slot: string}>;
type WriteSlot = InstalledLimits & Readonly<{phase: string}>;
type RowAuthorization = Readonly<{grant: unknown; useId: string}>;
type TargetProject = (response: unknown) => unknown;
type TargetRead = (rowIndex: number, request: TransportRequest, project: TargetProject,
  currentBeforeSend: () => unknown) => Promise<unknown>;
type AdmittedHttp = ReturnType<typeof ownHttpRequest> & {method: string; body?: string};
type TargetOperations = Map<string, Readonly<{method: string; path: string;
  headers: ReturnType<typeof ownHttpRequest>['headers']; body?: string}>>;
type TargetReadPlan = Readonly<{
  slot: TargetSlot; rowCount: number; operation: string; assertCurrent?: () => unknown; signal?: AbortSignal;
  authorizationForRow(index: number): RowAuthorization | PromiseLike<RowAuthorization>;
  readChild(original: RowAuthorization, input: RowAuthorization & Readonly<{
    operations?: TargetOperations; maxRequestBytes: number; maxResponseBytes: number;
    returnRejectedResponse: true; signal?: AbortSignal; currentBeforeSend(): unknown;
  }>, rowIndex: number, slot: 'target', project: TargetProject,
    prepareOperations?: () => TargetOperations): unknown;
}>;
type UpdateInvocation = InvocationPorts & Readonly<{member?: unknown; request?: unknown; current?: unknown}>;
type UpdateDeclaration = Readonly<{prepareUpdateWrite(member: unknown, request: unknown,
  current: unknown, resourceOrigin: unknown, registration: unknown, signal?: AbortSignal): unknown}>;
type UpdateResponse = Readonly<{useCid: unknown; statusCode: unknown; body: unknown}>;

const fail: () => never = () => {
  throw Object.assign(new Error('InvalidOwnedInvocationContext'), {
    code: 'InvalidOwnedInvocationContext',
  });
};

const primitive = (value: unknown) => value === null || value === undefined ||
  ['string', 'number', 'boolean', 'bigint'].includes(typeof value);

const metadataControl = (control: unknown) => {
  const kind = control === null || typeof control !== 'object' ? undefined
    : Object.getOwnPropertyDescriptor(control, 'kind');
  if (kind === undefined) return false;
  if (!Object.hasOwn(kind, 'value') || kind.value !== 'installation-metadata' ||
      !Object.isFrozen(control) || typeof (control as UncheckedControl).scopeFields !== 'function' ||
      typeof (control as UncheckedControl).subjectFields !== 'function') fail();
  return true;
};

// Only the original Common control can project an installation Scope. This
// DATA view does not replace its token, authorize a use or supply Host custody.
export function invocationScopeFields(scope: unknown, control?: unknown) {
  return metadataControl(control) ? (control as UncheckedControl).scopeFields(scope) : scope;
}

// Own only the JS envelope. Opaque MoonBit values, grants, journals and
// callbacks retain their exact identity; current authorization is still
// rechecked by the physical credential boundary for every operation.
export function ownInvocationAuthorization(authorization: unknown, control?: unknown) {
  if (!authorization || typeof authorization !== 'object' ||
      Array.isArray(authorization) ||
      typeof (authorization as UncheckedAuthorization).useId !== 'string' ||
      ((authorization as UncheckedAuthorization).useId as string).length === 0 || !(authorization as UncheckedAuthorization).scope ||
      typeof (authorization as UncheckedAuthorization).scope !== 'object' ||
      Array.isArray((authorization as UncheckedAuthorization).scope)) fail();
  if (metadataControl(control)) {
    (control as UncheckedControl).subjectFields();
    (control as UncheckedControl).scopeFields((authorization as UncheckedAuthorization).scope);
    return Object.freeze({grant: (authorization as UncheckedAuthorization).grant,
      useId: (authorization as UncheckedAuthorization).useId, scope: (authorization as UncheckedAuthorization).scope});
  }
  const scope: Record<string, unknown> = Object.create(null);
  for (const key of Object.keys((authorization as UncheckedAuthorization).scope as object)) {
    const value = ((authorization as UncheckedAuthorization).scope as Record<string, unknown>)[key];
    if (!primitive(value)) fail();
    scope[key] = value;
  }
  return Object.freeze({
    grant: (authorization as UncheckedAuthorization).grant,
    useId: (authorization as UncheckedAuthorization).useId,
    scope: Object.freeze(scope),
  });
}

export function invocationBindingsMatch(scope: unknown, original: unknown, control?: unknown) {
  if (metadataControl(control)) {
    // Both lookups enforce this same original Subject. Equal fields or CID
    // cannot turn a foreign/copied Scope into the acquisition's original.
    (control as UncheckedControl).subjectFields();
    (control as UncheckedControl).scopeFields(scope);
    (control as UncheckedControl).scopeFields(original);
    return true;
  }
  return bindingKeys.every(key => (scope as Record<string, unknown> | null | undefined)?.[key] === (original as Record<string, unknown> | null | undefined)?.[key]);
}

export function ownInvocationLimits(limits: unknown) {
  if (!limits || typeof limits !== 'object' || Array.isArray(limits)) fail();
  const ownedLimits = {...limits} as Record<string, unknown>;
  if (Object.values(ownedLimits).some(value => !primitive(value))) fail();
  return Object.freeze(ownedLimits);
}

export function ownInvocationContext({authorization, credential, limits,
  callbacks = {}}: ContextInput) {
  if (!credential || typeof credential !== 'object' ||
      Array.isArray(credential) || !callbacks || typeof callbacks !== 'object' ||
      Array.isArray(callbacks)) fail();
  const ownedCredential = {...credential} as Record<string, unknown>;
  const ownedAuthorization = ownInvocationAuthorization(authorization,
    ownedCredential.control);
  return Object.freeze({
    authorization: ownedAuthorization,
    scope: ownedAuthorization.scope,
    credential: Object.freeze(ownedCredential),
    limits: ownInvocationLimits(limits),
    callbacks: Object.freeze({...callbacks}) as Readonly<Record<string, unknown>>,
  });
}

// Providers select an operation and immutable request: method, exact path,
// ordered query pairs, allowed non-secret request headers, body, and the
// response header names their installation declared. The common boundary
// assembles one scoped physical invocation without interpreting its outcome.
export function invokeScopedCredentialOperation(request: ScopedOperation) {
  return invokeCredentialRequest(request, request);
}

function invokeCredentialRequest({
  operation,
  method,
  path,
  query,
  headers,
  body,
  bodyBytes,
  bodyMediaType,
  responseHeaders,
  maxRequestBytes,
  maxResponseBytes,
  responseCustody,
}: TransportRequest, {authorization, credential, callResource, signal}: InvocationPorts,
  installedOperation?: string, installedLimits?: InstalledLimits) {
  if (installedLimits !== undefined) {
    operation = installedOperation;
    ({maxRequestBytes, maxResponseBytes} = installedLimits);
  }
  if (typeof callResource !== 'function' ||
      typeof operation !== 'string' || operation.length === 0 ||
      typeof method !== 'string' || typeof path !== 'string' ||
      (body !== undefined && typeof body !== 'string')) fail();
  const binary = bodyBytes !== undefined || bodyMediaType !== undefined;
  const request = binary
    ? ownHttpByteRequest({method, path, query, headers, body, bodyBytes,
      bodyMediaType, maxBodyBytes: maxRequestBytes})
    : ownHttpRequest({method, path, query, headers, body}, installedLimits === undefined ? undefined
      : {maxTargetBytes: installedLimits.maxTargetBytes});
  const observed = ownResponseHeaderNames(responseHeaders);
  const context = ownInvocationContext({
    authorization, credential,
    limits: {maxRequestBytes, maxResponseBytes},
    callbacks: {callResource},
  });
  if ((invocationScopeFields(context.scope, context.credential.control) as {operation?: unknown} | null | undefined)?.operation !== operation) fail();
  return (context.callbacks.callResource as (value: unknown) => unknown)({
    ...context.credential,
    ...context.authorization,
    operations: new Map([[operation, Object.freeze({
      method: request.method, path: request.target,
      ...((request as ReturnType<typeof ownHttpRequest>).body === undefined ? {} : {body: (request as ReturnType<typeof ownHttpRequest>).body}),
      ...(binary ? {bodyBytes: (request as ReturnType<typeof ownHttpByteRequest>).bodyBytes, bodyMediaType: (request as ReturnType<typeof ownHttpByteRequest>).bodyMediaType,
        maxBodyBytes: (request as ReturnType<typeof ownHttpByteRequest>).maxBodyBytes} : {}),
      ...(request.headers.length === 0 ? {} : {headers: request.headers}),
      ...(observed.length === 0 ? {} : {responseHeaders: observed}),
    })]]),
    maxRequestBytes: context.limits.maxRequestBytes,
    maxResponseBytes: context.limits.maxResponseBytes,
    // Forward the SAME Source-owned holder. The physical Resource validates
    // and retains it before its late current/Journal/outcome boundaries.
    ...(responseCustody === undefined ? {} : {responseCustody}),
    returnRejectedResponse: true,
    signal,
  });
}

// The Row Effect retains this exact observation for classification and
// settlement. Receiving a response takes precedence over a late abort.
export function rowUpdateTransportObservation(response: UpdateResponse) {
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    statusCode: response.statusCode, body: response.body})});
}

// The two built-in UPDATE declarations share this closed kind inventory.
// It neither selects a target nor grants an operation.
export const declaredRowUpdateKinds = Object.freeze(['update']);

// Keep the original target-read grants and their physical children within
// this observation. An omitted, failed or detached read cannot supply Preview.
export async function withDeclaredUpdateTargetReads<Value>({readChild, authorizationForRow, operation,
  slot, rowCount, assertCurrent, signal}: TargetReadPlan, observe: (read: TargetRead) => Value | PromiseLike<Value>) {
  if (typeof readChild !== 'function' || typeof authorizationForRow !== 'function' ||
      typeof operation !== 'string' || !operation || slot?.slot !== 'target' ||
      !Number.isSafeInteger(rowCount) || rowCount < 0 || typeof observe !== 'function') fail();
  let next = 0, open = true, active = false, failed = false;
  let drain: Promise<void> | undefined, firstFailure: unknown;
  const requireOpen = () => {if (!open) fail();};
  const refuse = async () => fail();
  const read: TargetRead = (rowIndex, request, project, currentBeforeSend) => {
    if (!open || active || failed || rowIndex !== next || rowIndex >= rowCount ||
        typeof project !== 'function' || typeof currentBeforeSend !== 'function') return refuse();
    active = true;
    const pending = (async () => {
      try {
        assertCurrent?.();
        signal?.throwIfAborted();
        const method = request !== null && typeof request === 'object' && !nodeTypes.isProxy(request)
          ? Object.getOwnPropertyDescriptor(request, 'method')?.value : undefined;
        if (method !== 'GET' && method !== 'POST') fail();
        const bounded = slot.maxTargetBytes !== undefined;
        const operationFor = (http: AdmittedHttp): TargetOperations => {
          if (http.body !== undefined && (http.body.length > slot.maxRequestBytes ||
              Buffer.byteLength(http.body) > slot.maxRequestBytes)) fail();
          return new Map([[operation, Object.freeze({method: http.method, path: http.target,
            headers: http.headers, ...(http.body === undefined ? {} : {body: http.body})})]]);
        };
        // Capture only a fixed DATA envelope before acquisition. Encoding the
        // author's bounded target belongs inside its original physical child.
        const original = bounded ? captureDeclaredUpdateTransport(request, slot.maxRequestBytes, 'target-read') : undefined;
        const operations = bounded ? undefined : operationFor(ownHttpRequest(request) as AdmittedHttp);
        const prepareOperations = bounded ? () => {
          requireOpen();
          assertCurrent?.();
          signal?.throwIfAborted();
          return operationFor(ownHttpRequest(original!, {maxTargetBytes: slot.maxTargetBytes}) as AdmittedHttp);
        } : undefined;
        const authorization = await authorizationForRow(rowIndex);
        requireOpen();
        assertCurrent?.();
        signal?.throwIfAborted();
        if (authorization === null || typeof authorization !== 'object' ||
            nodeTypes.isProxy(authorization) || typeof authorization.useId !== 'string' ||
            !authorization.useId) fail();
        const value = await readChild(authorization, {grant: authorization.grant, useId: authorization.useId,
          ...(operations === undefined ? {} : {operations}),
          maxRequestBytes: slot.maxRequestBytes, maxResponseBytes: slot.maxResponseBytes,
          returnRejectedResponse: true, signal, currentBeforeSend: () => {
            requireOpen();
            return currentBeforeSend();
          }}, rowIndex, 'target', project, prepareOperations);
        assertCurrent?.();
        next++;
        return value;
      } catch (cause) {
        failed = true;
        firstFailure = cause;
        throw cause;
      } finally { active = false; }
    })();
    // Joined again on exit even if a provider did not await the child.
    drain = pending.then(() => undefined, () => undefined);
    return pending;
  };
  try {
    const value = await observe(read);
    if (failed) throw firstFailure;
    if (active || next !== rowCount) fail();
    return value;
  } catch (cause) {
    // Choose the primary before draining: a later child failure must not
    // replace an independent failure that already ended the observation.
    throw failed ? firstFailure : cause;
  } finally {
    open = false;
    await drain;
  }
}

const updateTransportFields = Object.freeze(['method', 'path', 'query', 'headers', 'body', 'responseHeaders']);
const updateHostFields = Object.freeze(['operation', 'maxRequestBytes', 'maxResponseBytes', 'maxTargetBytes',
  'bodyBytes', 'bodyMediaType', 'responseCustody', 'authorization', 'credential', 'callResource', 'then']);
const updateMethods = Object.freeze(['POST', 'PATCH', 'PUT']);
const stringData = (value: unknown) => typeof value === 'string';

// Check the declaration's arrays before the shared HTTP canonicalizer reads
// them. It can then use their ordinary Array operations without invoking a
// provider-supplied getter, iterator, constructor or array method.
function checkTransportList(values: unknown, max: number, element: (value: unknown) => boolean): values is unknown[] {
  if (!Array.isArray(values) || nodeTypes.isProxy(values) || Object.getPrototypeOf(values) !== Array.prototype ||
      values.length > max || Object.hasOwn(values, 'map') ||
      Object.hasOwn(values, 'constructor') || Object.hasOwn(values, Symbol.iterator)) fail();
  for (let index = 0; index < values.length; index++) {
    const field = Object.getOwnPropertyDescriptor(values, index);
    if (!field || !Object.hasOwn(field, 'value') || !element(field.value)) fail();
  }
  return true;
}

function transportPair(value: unknown) {
  return checkTransportList(value, 2, stringData) && value.length === 2;
}

function captureDeclaredUpdateTransport(transport: unknown, maxRequestBytes: number, purpose = 'write'): TransportRequest {
  const write = purpose === 'write';
  if (transport === null || typeof transport !== 'object' || nodeTypes.isProxy(transport) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(transport))) fail();
  if (updateHostFields.some(key => Object.hasOwn(transport, key))) fail();
  // A finite projection does not enumerate or retain arbitrary author fields.
  const request = Object.create(null) as TransportRequest;
  for (const key of updateTransportFields) {
    const field = Object.getOwnPropertyDescriptor(transport, key);
    if (field === undefined) continue;
    if (!Object.hasOwn(field, 'value')) fail();
    (request as unknown as Record<string, unknown>)[key] = field.value;
  }
  const {method, path, body, query, headers, responseHeaders} = request;
  if ((write ? !updateMethods.includes(method as string) : method !== 'GET' && method !== 'POST') ||
      typeof path !== 'string' || (write && body === undefined) ||
      (body !== undefined && (typeof body !== 'string' || body.length > maxRequestBytes ||
        Buffer.byteLength(body) > maxRequestBytes)) || (!write && responseHeaders !== undefined)) fail();
  const pair = write ? transportPair : (value: unknown) => transportPair(value) && Object.isFrozen(value);
  for (const [list, limit] of [[query, exchangeLimits.maxQueryPairs], [headers, exchangeLimits.maxRequestHeaders]] as const) {
    if (list === undefined) continue;
    checkTransportList(list, limit, pair);
    if (!write && !Object.isFrozen(list)) fail();
  }
  if (responseHeaders !== undefined) {
    checkTransportList(responseHeaders, exchangeLimits.maxObservedHeaders, stringData);
  }
  return request;
}

// The existing Row Effect dispatch supplies the original scoped invocation.
// Author transport code receives identity DATA and the original cancellation
// signal. It has no physical send callback or credential.
export async function invokeDeclaredRowUpdate(declaration: UpdateDeclaration, invocation: UpdateInvocation,
  operation: string, writeSlot: WriteSlot) {
  if (writeSlot?.phase !== 'write' ||
      ![writeSlot.maxRequestBytes, writeSlot.maxTargetBytes].every(value =>
        Number.isSafeInteger(value) && value! > 0 && value! <= 2147483647)) fail();
  const {member, request, current, authorization, credential, signal} = invocation;
  const scope = invocationScopeFields((authorization as UncheckedAuthorization | null | undefined)?.scope,
    (credential as {control?: unknown} | null | undefined)?.control) as
    {operation?: unknown; resourceOrigin?: unknown; connectorRegistration?: unknown} | null | undefined;
  if (scope?.operation !== operation) fail();
  signal?.throwIfAborted();
  const transport = declaration.prepareUpdateWrite(member, request, current,
    scope?.resourceOrigin, scope?.connectorRegistration, signal);
  // A synchronous callback returning a genuine Promise violates the
  // declaration. Keep its settlement in the original physical child.
  if (nodeTypes.isPromise(transport)) {
    await transport;
    fail();
  }
  const requestData = captureDeclaredUpdateTransport(transport, writeSlot.maxRequestBytes);
  signal?.throwIfAborted();
  return rowUpdateTransportObservation(await invokeCredentialRequest(requestData, invocation, operation, writeSlot) as UpdateResponse);
}

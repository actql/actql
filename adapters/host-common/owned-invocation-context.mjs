import {types as nodeTypes} from 'node:util';
import {credentialInvocationBindingKeys as bindingKeys} from './credential-scope-fields.generated.mjs';
import {exchangeLimits, ownHttpRequest, ownHttpByteRequest, ownResponseHeaderNames} from './http-exchange.mjs';

const fail = () => {
  throw Object.assign(new Error('InvalidOwnedInvocationContext'), {
    code: 'InvalidOwnedInvocationContext',
  });
};

const primitive = value => value === null || value === undefined ||
  ['string', 'number', 'boolean', 'bigint'].includes(typeof value);

const metadataControl = control => {
  const kind = control === null || typeof control !== 'object' ? undefined
    : Object.getOwnPropertyDescriptor(control, 'kind');
  if (kind === undefined) return false;
  if (!Object.hasOwn(kind, 'value') || kind.value !== 'installation-metadata' ||
      !Object.isFrozen(control) || typeof control.scopeFields !== 'function' ||
      typeof control.subjectFields !== 'function') fail();
  return true;
};

// Only the original Common control can project an installation Scope. This
// DATA view does not replace its token, authorize a use or supply Host custody.
export function invocationScopeFields(scope, control) {
  return metadataControl(control) ? control.scopeFields(scope) : scope;
}

// Own only the JS envelope. Opaque MoonBit values, grants, journals and
// callbacks retain their exact identity; current authorization is still
// rechecked by the physical credential boundary for every operation.
export function ownInvocationAuthorization(authorization, control) {
  if (!authorization || typeof authorization !== 'object' ||
      Array.isArray(authorization) ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.scope ||
      typeof authorization.scope !== 'object' ||
      Array.isArray(authorization.scope)) fail();
  if (metadataControl(control)) {
    control.subjectFields();
    control.scopeFields(authorization.scope);
    return Object.freeze({grant: authorization.grant,
      useId: authorization.useId, scope: authorization.scope});
  }
  const scope = Object.create(null);
  for (const key of Object.keys(authorization.scope)) {
    const value = authorization.scope[key];
    if (!primitive(value)) fail();
    scope[key] = value;
  }
  return Object.freeze({
    grant: authorization.grant,
    useId: authorization.useId,
    scope: Object.freeze(scope),
  });
}

export function invocationBindingsMatch(scope, original, control) {
  if (metadataControl(control)) {
    // Both lookups enforce this same original Subject. Equal fields or CID
    // cannot turn a foreign/copied Scope into the acquisition's original.
    control.subjectFields();
    control.scopeFields(scope);
    control.scopeFields(original);
    return true;
  }
  return bindingKeys.every(key => scope?.[key] === original?.[key]);
}

export function ownInvocationLimits(limits) {
  if (!limits || typeof limits !== 'object' || Array.isArray(limits)) fail();
  const ownedLimits = {...limits};
  if (Object.values(ownedLimits).some(value => !primitive(value))) fail();
  return Object.freeze(ownedLimits);
}

export function ownInvocationContext({authorization, credential, limits,
  callbacks = {}}) {
  if (!credential || typeof credential !== 'object' ||
      Array.isArray(credential) || !callbacks || typeof callbacks !== 'object' ||
      Array.isArray(callbacks)) fail();
  const ownedCredential = {...credential};
  const ownedAuthorization = ownInvocationAuthorization(authorization,
    ownedCredential.control);
  return Object.freeze({
    authorization: ownedAuthorization,
    scope: ownedAuthorization.scope,
    credential: Object.freeze(ownedCredential),
    limits: ownInvocationLimits(limits),
    callbacks: Object.freeze({...callbacks}),
  });
}

// Providers select an operation and immutable request: method, exact path,
// ordered query pairs, allowed non-secret request headers, body, and the
// response header names their installation declared. The common boundary
// assembles one scoped physical invocation without interpreting its outcome.
export function invokeScopedCredentialOperation(request) {
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
}, {authorization, credential, callResource, signal}, installedOperation, installedLimits) {
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
  if (invocationScopeFields(context.scope, context.credential.control)?.operation !== operation) fail();
  return context.callbacks.callResource({
    ...context.credential,
    ...context.authorization,
    operations: new Map([[operation, Object.freeze({
      method: request.method, path: request.target,
      ...(request.body === undefined ? {} : {body: request.body}),
      ...(binary ? {bodyBytes: request.bodyBytes, bodyMediaType: request.bodyMediaType,
        maxBodyBytes: request.maxBodyBytes} : {}),
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
export function rowUpdateTransportObservation(response) {
  return Object.freeze({observation: Object.freeze({useCid: response.useCid,
    statusCode: response.statusCode, body: response.body})});
}

// The two built-in UPDATE declarations share this closed kind inventory.
// It neither selects a target nor grants an operation.
export const declaredRowUpdateKinds = Object.freeze(['update']);

// Keep the original target-read grants and their physical children within
// this observation. An omitted, failed or detached read cannot supply Preview.
export async function withDeclaredUpdateTargetReads({readChild, authorizationForRow, operation,
  slot, rowCount, assertCurrent, signal}, observe) {
  if (typeof readChild !== 'function' || typeof authorizationForRow !== 'function' ||
      typeof operation !== 'string' || !operation || slot?.slot !== 'target' ||
      !Number.isSafeInteger(rowCount) || rowCount < 0 || typeof observe !== 'function') fail();
  let next = 0, open = true, active = false, failed = false;
  let drain, firstFailure;
  const requireOpen = () => {if (!open) fail();};
  const refuse = async () => fail();
  const read = (rowIndex, request, project, currentBeforeSend) => {
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
        const operationFor = http => {
          if (http.body !== undefined && (http.body.length > slot.maxRequestBytes ||
              Buffer.byteLength(http.body) > slot.maxRequestBytes)) fail();
          return new Map([[operation, Object.freeze({method: http.method, path: http.target,
            headers: http.headers, ...(http.body === undefined ? {} : {body: http.body})})]]);
        };
        // Capture only a fixed DATA envelope before acquisition. Encoding the
        // author's bounded target belongs inside its original physical child.
        const original = bounded ? captureDeclaredUpdateTransport(request, slot.maxRequestBytes, 'target-read') : undefined;
        const operations = bounded ? undefined : operationFor(ownHttpRequest(request));
        const prepareOperations = bounded ? () => {
          requireOpen();
          assertCurrent?.();
          signal?.throwIfAborted();
          return operationFor(ownHttpRequest(original, {maxTargetBytes: slot.maxTargetBytes}));
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
const stringData = value => typeof value === 'string';

// Check the declaration's arrays before the shared HTTP canonicalizer reads
// them. It can then use their ordinary Array operations without invoking a
// provider-supplied getter, iterator, constructor or array method.
function checkTransportList(values, max, element) {
  if (!Array.isArray(values) || nodeTypes.isProxy(values) || Object.getPrototypeOf(values) !== Array.prototype ||
      values.length > max || Object.hasOwn(values, 'map') ||
      Object.hasOwn(values, 'constructor') || Object.hasOwn(values, Symbol.iterator)) fail();
  for (let index = 0; index < values.length; index++) {
    const field = Object.getOwnPropertyDescriptor(values, index);
    if (!field || !Object.hasOwn(field, 'value') || !element(field.value)) fail();
  }
  return true;
}

function transportPair(value) {
  return checkTransportList(value, 2, stringData) && value.length === 2;
}

function captureDeclaredUpdateTransport(transport, maxRequestBytes, purpose = 'write') {
  const write = purpose === 'write';
  if (transport === null || typeof transport !== 'object' || nodeTypes.isProxy(transport) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(transport))) fail();
  if (updateHostFields.some(key => Object.hasOwn(transport, key))) fail();
  // A finite projection does not enumerate or retain arbitrary author fields.
  const request = Object.create(null);
  for (const key of updateTransportFields) {
    const field = Object.getOwnPropertyDescriptor(transport, key);
    if (field === undefined) continue;
    if (!Object.hasOwn(field, 'value')) fail();
    request[key] = field.value;
  }
  const {method, path, body, query, headers, responseHeaders} = request;
  if ((write ? !updateMethods.includes(method) : method !== 'GET' && method !== 'POST') ||
      typeof path !== 'string' || (write && body === undefined) ||
      (body !== undefined && (typeof body !== 'string' || body.length > maxRequestBytes ||
        Buffer.byteLength(body) > maxRequestBytes)) || (!write && responseHeaders !== undefined)) fail();
  const pair = write ? transportPair : value => transportPair(value) && Object.isFrozen(value);
  for (const [list, limit] of [[query, exchangeLimits.maxQueryPairs], [headers, exchangeLimits.maxRequestHeaders]]) {
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
export async function invokeDeclaredRowUpdate(declaration, invocation, operation, writeSlot) {
  if (writeSlot?.phase !== 'write' ||
      ![writeSlot.maxRequestBytes, writeSlot.maxTargetBytes].every(value =>
        Number.isSafeInteger(value) && value > 0 && value <= 2147483647)) fail();
  const {member, request, current, authorization, credential, signal} = invocation;
  const scope = invocationScopeFields(authorization?.scope, credential?.control);
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
  return rowUpdateTransportObservation(await invokeCredentialRequest(requestData, invocation, operation, writeSlot));
}

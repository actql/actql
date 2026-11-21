import {credentialInvocationBindingKeys as bindingKeys} from './credential-scope-fields.generated.mjs';
import {ownHttpRequest, ownHttpByteRequest, ownResponseHeaderNames} from './http-exchange.mjs';

type UncheckedControl = {kind?: unknown; scopeFields(scope: unknown): unknown; subjectFields(): unknown};
type UncheckedAuthorization = {useId?: unknown; scope?: unknown; grant?: unknown};
type ContextInput = {authorization: unknown; credential: unknown; limits: unknown; callbacks?: unknown};
type ScopedOperation = {authorization: unknown; credential: unknown; callResource: unknown; operation: unknown;
  method: unknown; path: unknown; query?: unknown; headers?: unknown; body?: unknown; bodyBytes?: unknown;
  bodyMediaType?: unknown; responseHeaders?: unknown; maxRequestBytes?: unknown; maxResponseBytes?: unknown;
  responseCustody?: unknown; signal?: unknown};

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
export function invokeScopedCredentialOperation({
  authorization,
  credential,
  callResource,
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
  signal,
}: ScopedOperation) {
  if (typeof callResource !== 'function' ||
      typeof operation !== 'string' || operation.length === 0 ||
      typeof method !== 'string' || typeof path !== 'string' ||
      (body !== undefined && typeof body !== 'string')) fail();
  const binary = bodyBytes !== undefined || bodyMediaType !== undefined;
  const request = binary
    ? ownHttpByteRequest({method, path, query, headers, body, bodyBytes,
      bodyMediaType, maxBodyBytes: maxRequestBytes})
    : ownHttpRequest({method, path, query, headers, body});
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

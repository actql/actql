import {credentialInvocationBindingKeys as bindingKeys} from './credential-scope-fields.generated.mjs';
import {ownHttpRequest, ownHttpByteRequest, ownResponseHeaderNames} from './http-exchange.mjs';

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
}) {
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

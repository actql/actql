const fail = () => {
  throw Object.assign(new Error('InvalidOwnedInvocationContext'), {
    code: 'InvalidOwnedInvocationContext',
  });
};

const bindingKeys = Object.freeze([
  'issuerAuthority', 'principal', 'tenant', 'environment',
  'siteKey', 'siteGeneration', 'runtimeBundleCid',
  'connectorRegistration', 'connectorRevision', 'resourceOrigin',
  'runInvocationCid', 'taskAttempt', 'dispatchRequestCid',
]);

const primitive = value => value === null || value === undefined ||
  ['string', 'number', 'boolean', 'bigint'].includes(typeof value);

// Own only the JS envelope. Opaque MoonBit values, grants, journals and
// callbacks retain their exact identity; current authorization is still
// rechecked by the physical credential boundary for every operation.
export function ownInvocationAuthorization(authorization) {
  if (!authorization || typeof authorization !== 'object' ||
      Array.isArray(authorization) ||
      typeof authorization.useId !== 'string' ||
      authorization.useId.length === 0 || !authorization.scope ||
      typeof authorization.scope !== 'object' ||
      Array.isArray(authorization.scope)) fail();
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

export function invocationBindingsMatch(scope, original) {
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
  const ownedAuthorization = ownInvocationAuthorization(authorization);
  return Object.freeze({
    authorization: ownedAuthorization,
    scope: ownedAuthorization.scope,
    credential: Object.freeze(ownedCredential),
    limits: ownInvocationLimits(limits),
    callbacks: Object.freeze({...callbacks}),
  });
}

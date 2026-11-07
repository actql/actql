import {request as httpsRequest} from 'node:https';
import {maxHeaderSize} from 'node:http';
import {createHash} from 'node:crypto';
import {types} from 'node:util';
import {prepareGoogleServiceAccountAssertion, googleServiceAccountAssertionRequest}
  from './google-service-account-assertion.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeIsBoxedSome, runtimeIsBoxedNone, runtimeField}
  from '../host-common/compiler-binding.generated.mjs';
import {credentialInvocationBindingKeys} from
  '../host-common/credential-scope-fields.generated.mjs';
import {installationPreparationSubjectKeys} from
  '../host-common/installation-preparation-fields.generated.mjs';
import {checkHttpRequestMethodBody, observeResponseHeaders, ownHttpByteRequest, ownRequestHeaders,
  ownResponseHeaderNames} from '../host-common/http-exchange.mjs';
import {captureSourceResponseCustody} from '../host-common/source-response-custody.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

// The original Node process's existing default, also passed to its actual
// parser below. This is an implementation bound, never a caller allowance.
export const httpsCredentialResponseHeaderByteLimit = maxHeaderSize;

// The actual bearer-header constructor and its logical backing quote use
// the same fixed prefix. No credential material is exposed by this DATA.
export const httpsCredentialAuthorizationPrefix = 'Bearer ';

// The unchanged default of the original request constructor below. Installed
// recipe assembly consumes this same bound instead of copying its number.
export const httpsCredentialDefaultRequestBytes = 1_048_576;

// Acquisition custody stays in the Credential Owner, not in Connector-visible
// fields. Scope equality is only identity; each operation still claims and
// authorizes its own nominal use in the original journal.
const bindings = new WeakMap();

// Optional original-response correspondence remains in this Credential Owner.
// The exact returned response is the key; bytes/CIDs or a replayed Journal row
// cannot construct the original physical claim. This contains no secret.
const runResponseOriginals = new WeakMap();
const compareBodyBytes = Buffer.compare;
const nativePromiseThen = Promise.prototype.then;

// Private synchronous consumer for an original legacy Run response. This is
// historical DATA, not current authority, a new use, Store custody or an ACK.
// Consumer exceptions never reclassify the already confirmed Journal outcome.
export function withHttpsCredentialRunResponseOriginal(response, control,
  journal, consume) {
  const original = runResponseOriginals.get(response);
  if (original === undefined || !original.confirmed ||
      original.control !== control || original.journal !== journal ||
      typeof consume !== 'function') {
    fail('RemoteCredentialRunResponseOriginalUnavailable');
  }
  if (original.failure !== undefined) throw original.failure;
  const body = response.body;
  if (body !== original.body || body.byteLength !== original.byteLength ||
      compareBodyBytes(body, original.bodySnapshot) !== 0) {
    original.failure = Object.assign(new Error('RemoteCredentialRunResponseChanged'),
      {code: 'RemoteCredentialRunResponseChanged'});
    throw original.failure;
  }
  const result = consume(original.facts);
  if (result !== null && result !== undefined && typeof result.then === 'function') {
    void Promise.resolve(result).catch(() => {});
    fail('InvalidRemoteCredentialRunResponseConsumer');
  }
  return result;
}

// Private trusted installation input, never a Program/wire-selected dependency.
// Vendor claim/signature validation remains in the original signer.
function ownAuthenticationRegistration(value) {
  if (value === undefined) return undefined;
  if (value === null || typeof value !== 'object' || types.isProxy(value)) {
    fail('InvalidRemoteCredentialAuthenticationRegistration');
  }
  const {resolveMaterial, assertCurrentMaterial, clientEmail, keyGeneration,
    scopes: inputScopes, delegate, lifetimeSeconds, signingLimits,
    tokenRuntime, responseLimits} = value;
  const limits = signingLimits !== null && typeof signingLimits === 'object' &&
    !types.isProxy(signingLimits) ? Object.freeze({...signingLimits}) : undefined;
  const requiredLimits = ['maxScopes', 'maxScopeBytes', 'maxIdentityBytes',
    'maxClaimBytes', 'maxAssertionBytes', 'maxRequestBytes', 'maxKeyBits'];
  if (typeof resolveMaterial !== 'function' || typeof assertCurrentMaterial !== 'function' ||
      !text(clientEmail) || !text(keyGeneration) ||
      !Array.isArray(inputScopes) || types.isProxy(inputScopes) || inputScopes.length === 0 ||
      !Number.isSafeInteger(lifetimeSeconds) || lifetimeSeconds <= 0 || lifetimeSeconds > 3600 ||
      limits === undefined || Object.keys(limits).length !== requiredLimits.length ||
      requiredLimits.some(name => !Number.isSafeInteger(limits[name]) ||
        limits[name] <= 0 || limits[name] > 2147483647) ||
      Buffer.byteLength(keyGeneration) > limits.maxIdentityBytes) {
    fail('InvalidRemoteCredentialAuthenticationRegistration');
  }
  const scopes = inputScopes.slice();
  if (scopes.some(scope => !text(scope)) || scopes.length !== Object.keys(scopes).length) {
    fail('InvalidRemoteCredentialAuthenticationRegistration');
  }
  return Object.freeze({resolveMaterial, assertCurrentMaterial,
    clientEmail, keyGeneration, scopes: Object.freeze(scopes), delegate,
    lifetimeSeconds, signingLimits: limits, tokenRuntime,
    responseLimits: responseLimits === undefined ? undefined : Object.freeze({...responseLimits})});
}

export function openHttpsCredentialBinding({scope, control, journal,
  resolveSecret, maxSecretBytes, authentication, assertCurrent,
  secretPresentation = 'bearer'}) {
  const purpose = control === null || typeof control !== 'object' ? undefined
    : Object.getOwnPropertyDescriptor(control, 'kind');
  if (purpose !== undefined && (!Object.hasOwn(purpose, 'value') ||
      purpose.value !== 'installation-metadata')) fail('InvalidRemoteCredentialBinding');
  const metadata = purpose?.value === 'installation-metadata';
  if (!scope || typeof scope !== 'object' ||
      typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' ||
      (assertCurrent !== undefined && typeof assertCurrent !== 'function') ||
      !count(maxSecretBytes) ||
      maxSecretBytes === 0 || (!metadata && credentialInvocationBindingKeys.some(key =>
        !['string', 'number', 'bigint'].includes(typeof scope[key])))) {
    fail('InvalidRemoteCredentialBinding');
  }
  if (metadata && (!Object.isFrozen(control) ||
      typeof control.subjectFields !== 'function' ||
      typeof control.scopeFields !== 'function' ||
      typeof assertCurrent !== 'function')) fail('InvalidRemoteCredentialBinding');
  // The Run authentication pair does not admit a metadata Subject. An explicit
  // dependency must not silently fall back to a static bearer acquisition.
  if (metadata && authentication !== undefined) fail('RemoteCredentialAuthenticationUnavailable');
  const originalScope = metadata ? control.subjectFields() : scope;
  if (metadata) control.scopeFields(scope);
  const original = Object.freeze(Object.fromEntries(
    (metadata ? installationPreparationSubjectKeys : credentialInvocationBindingKeys)
      .map(key => [key, originalScope[key]])));
  // Installation selects a closed presentation inside this original binding.
  // It grants no operation and cannot expose a secret to the provider driver.
  if (secretPresentation !== 'bearer' &&
      (secretPresentation !== 'kintone-api-token' ||
        original.connectorRegistration !== 'kintone' || authentication !== undefined)) {
    fail('InvalidRemoteCredentialSecretPresentation');
  }
  const binding = Object.freeze(Object.create(null));
  bindings.set(binding, {original, control, journal, resolveSecret,
    metadata, assertCurrent,
    pendingOutcome: undefined, receivedResponse: undefined, unjoinedResponseCustody: undefined,
    maxSecretBytes, secretPresentation, secret: undefined, active: false, retiring: false,
    closed: false, changed: false, request: undefined,
    authentication: ownAuthenticationRegistration(authentication),
    authenticationAttempted: false, authenticationMaterial: undefined,
    authenticationExchangeAttempted: false, authenticationExchange: undefined,
    authenticationToken: undefined});
  return binding;
}

function bindingQuiescent(state) {
  return !state.active && state.request === undefined && state.unjoinedResponseCustody === undefined;
}

function retireBinding(state) {
  if (state.retiring && state.borrow === undefined && bindingQuiescent(state)) {
    state.secret = undefined;
    state.authenticationMaterial = undefined;
    state.authenticationExchange = undefined;
    state.authenticationToken = undefined;
    state.receivedResponse = undefined;
    state.closed = true;
  }
}

// One exclusive read child of this SAME physical owner. The original binding
// remains the key; the opaque borrow is only an association, not another
// binding, grant, resolver, Journal, Ledger or authentication dependency.
export function retainHttpsCredentialBindingReadChild(binding) {
  const state = bindings.get(binding);
  if (state === undefined || state.metadata) fail('InvalidRemoteCredentialBindingBorrow');
  if (state.borrow !== undefined || !bindingQuiescent(state)) fail('RemoteCredentialBindingBorrowBusy');
  if (state.retiring || state.closed) fail('RemoteCredentialBindingRetiring');
  if (state.changed) fail('RemoteCredentialBindingChanged');
  if (state.pendingOutcome !== undefined) throw state.pendingOutcome;
  if (state.authentication !== undefined && state.authenticationToken === undefined) fail('RemoteCredentialAuthenticationUnavailable');
  const original = {token: undefined, closing: false, retired: false};
  const borrow = Object.freeze({
    available() {
      if (this !== borrow) fail('ForeignRemoteCredentialBindingBorrow');
      return !original.closing && !original.retired && state.borrow === original &&
        !state.retiring && !state.changed && state.pendingOutcome === undefined;
    },
    close() {
      if (this !== borrow) fail('ForeignRemoteCredentialBindingBorrow');
      if (original.retired) return 'closed';
      original.closing = true;
      state.request?.destroy(Object.assign(new Error('RemoteCredentialBindingBorrowRetiring'),
        {code: 'RemoteCredentialBindingBorrowRetiring'}));
      return bindingQuiescent(state) ? 'closed' : 'pending';
    },
    retire() {
      if (this !== borrow) fail('ForeignRemoteCredentialBindingBorrow');
      if (original.retired) return true;
      if (!original.closing || !bindingQuiescent(state)) return false;
      if (state.borrow !== original) fail('ForeignRemoteCredentialBindingBorrow');
      original.retired = true;state.borrow = undefined;
      retireBinding(state);
      return true;
    },
  });
  original.token = borrow;state.borrow = original;
  return borrow;
}

// The original native material never leaves this Credential binding. The
// selected resolver owns its generation/current observation; a key ID, equal
// key bytes or Site generation cannot supply missing material membership.
function checkAuthenticationSelection(state, original) {
  const registration = state.authentication;
  const selected = original.selected;
  if (selected.privateKey !== original.privateKey ||
      selected.keyGeneration !== registration.keyGeneration ||
      selected.clientEmail !== registration.clientEmail ||
      selected.delegate !== registration.delegate ||
      !Array.isArray(selected.scopes) ||
      selected.scopes.length !== registration.scopes.length ||
      selected.scopes.some((scope, index) => scope !== registration.scopes[index]) ||
      selected.expiresUnixMilliseconds !== original.expiresUnixMilliseconds) {
    fail('RemoteCredentialAuthenticationMaterialChanged');
  }
  // This is the original supplier's synchronous physical-current check, not
  // Account/Checkpoint authority or a successful grant inferred from equality.
  if (registration.assertCurrentMaterial(selected) !== undefined) {
    fail('RemoteCredentialAuthenticationCurrentUnavailable');
  }
}

function authenticationDependency(state, parentScope, grant, scope, control, journal, trustedNow) {
  if (grant === undefined && scope === undefined) return undefined;
  const selectedScope = Object.freeze({...scope});
  if (selectedScope.resourceOrigin !== 'https://oauth2.googleapis.com' ||
      !text(selectedScope.operation) || selectedScope.operation === parentScope.operation ||
      credentialInvocationBindingKeys.some(name => name !== 'resourceOrigin' &&
        selectedScope[name] !== state.original[name]) || typeof journal.checkGrant !== 'function') {
    fail('ForeignRemoteCredentialAuthenticationScope');
  }
  const grantCid = control.identity(grant);
  const original = journal.checkGrant(grantCid, BigInt(trustedNow), selectedScope, control);
  // Prospective signed admission supplies metadata/current only. The later
  // actual claim's own grant, never this separate object, binds the Common pair.
  const expires = BigInt(JSON.parse(control.json(original)).expires_unix_ms);
  return Object.freeze({grantCid, scope: selectedScope, expires});
}

// Prepare one bounded native-key assertion inside the existing binding. The
// caller's original current/capacity boundary is required before resolution
// and after its await. This does not send, claim an auth use or return secret
// request bytes; the separate original authentication operation remains next.
export async function prepareHttpsCredentialAuthenticationMaterial({binding,
  scope, control, journal, resolveSecret, parentClaim, currentBeforeSign,
  authenticationGrant, authenticationScope, now = Date.now, signal}) {
  const state = acquireBinding(binding, {scope, control, journal, resolveSecret});
  if (state === undefined) fail('InvalidRemoteCredentialBinding');
  try {
    const registration = state.authentication;
    if (registration === undefined) fail('RemoteCredentialAuthenticationUnavailable');
    if (state.authenticationAttempted) fail('RemoteCredentialAuthenticationAlreadyPrepared');
    if (typeof currentBeforeSign !== 'function' || typeof now !== 'function' ||
        parentClaim?.replayed !== false || parentClaim?.record?.outcome !== 'claimed') {
      fail('InvalidRemoteCredentialAuthenticationParent');
    }
    state.authenticationAttempted = true;
    const time = () => {
      const value = now();
      if (!Number.isSafeInteger(value) || value < 0) fail('InvalidRemoteCredentialAuthenticationTime');
      return value;
    };
    const current = () => {
      if (state.retiring) fail('RemoteCredentialBindingRetiring');
      signal?.throwIfAborted();
      const observed = journal.authorize(parentClaim.use, BigInt(time()), scope, control);
      if (observed.useCid !== parentClaim.record.useCid || observed.outcome !== 'claimed' ||
          observed.grantCid !== control.identity(parentClaim.grant)) {
        fail('InvalidRemoteCredentialAuthenticationParent');
      }
    };
    signal?.throwIfAborted();
    await currentBeforeSign();
    current();
    const dependency = authenticationDependency(state, scope, authenticationGrant,
      authenticationScope, control, journal, time());
    const selected = await registration.resolveMaterial(Object.freeze({
      ...state.original, operation: scope.operation,
      grantCid: parentClaim.record.grantCid}), signal);
    if (selected === null || typeof selected !== 'object' || types.isProxy(selected) ||
        typeof selected.expiresUnixMilliseconds !== 'bigint') {
      fail('RemoteCredentialAuthenticationMaterialUnavailable');
    }
    const material = Object.freeze(Object.create(null));
    const original = {material, selected, privateKey: selected.privateKey,
      expiresUnixMilliseconds: selected.expiresUnixMilliseconds,
      parentClaim, parentScope: Object.freeze({...scope}), dependency, assertion: undefined};
    // Retain the same original material through a failed later fence until the
    // binding retires. Resolver failures propagate with their original custody.
    state.authenticationMaterial = original;
    if (state.retiring) fail('RemoteCredentialBindingRetiring');
    signal?.throwIfAborted();
    checkAuthenticationSelection(state, original);
    await currentBeforeSign();
    current();
    checkAuthenticationSelection(state, original);
    const trustedNow = time(), issuedAt = Math.floor(trustedNow / 1000);
    // Read only metadata of the same signed claim grant; never re-admit or
    // manufacture an original from this canonical public grant projection.
    const parentExpiry = BigInt(JSON.parse(control.json(parentClaim.grant)).expires_unix_ms);
    const currentDependency = dependency === undefined ? undefined :
      authenticationDependency(state, original.parentScope, authenticationGrant,
        dependency.scope, control, journal, trustedNow);
    const proposedExpiry = BigInt(issuedAt + registration.lifetimeSeconds) * 1000n;
    const deadline = [parentExpiry, original.expiresUnixMilliseconds, proposedExpiry,
      currentDependency?.expires ?? parentExpiry]
      .reduce((minimum, value) => value < minimum ? value : minimum);
    const lifetime = deadline / 1000n - BigInt(issuedAt);
    if (deadline <= BigInt(trustedNow) || lifetime <= 0n) {
      fail('RemoteCredentialAuthenticationMaterialExpired');
    }
    // The supplier's current callback and metadata readers may reenter the
    // original Journal. Re-authorize after them, immediately before signing.
    current();
    // No await separates this final original authorization and signing.
    original.assertion = prepareGoogleServiceAccountAssertion({
      privateKey: original.privateKey, clientEmail: registration.clientEmail,
      scopes: registration.scopes, delegate: registration.delegate,
      issuedAtUnixSeconds: issuedAt, lifetimeSeconds: Number(lifetime),
      limits: registration.signingLimits});
    return material;
  } finally {
    state.active = false;
    retireBinding(state);
  }
}

function authenticationTokenReader(registration, maxSecretBytes) {
  const runtime = registration.tokenRuntime, limits = registration.responseLimits;
  if (!types.isModuleNamespaceObject(runtime) || limits === undefined ||
      !['maxBytes', 'maxNodes', 'maxDepth', 'maxTokenBytes', 'maxLifetimeSeconds',
        'maxScopes', 'maxScopeBytes'].every(name => Number.isSafeInteger(limits[name]) &&
          limits[name] > 0 && limits[name] <= 2147483647)) {
    fail('RemoteCredentialAuthenticationUnavailable');
  }
  const read = runtime.googleServiceAccountReadTokenResponse;
  const token = runtime.googleServiceAccountTokenResponseAccessToken;
  const lifetime = runtime.googleServiceAccountTokenResponseLifetimeSeconds;
  const scopes = runtime.googleServiceAccountTokenResponseScopes;
  if ([read, token, lifetime, scopes].some(value => typeof value !== 'function')) {
    fail('RemoteCredentialAuthenticationUnavailable');
  }
  return Object.freeze({maxBytes: limits.maxBytes, read(response) {
    const original = checked(read(response.statusCode, response.body, limits.maxBytes,
      limits.maxNodes, limits.maxDepth, Math.min(maxSecretBytes, limits.maxTokenBytes),
      limits.maxLifetimeSeconds, limits.maxScopes, limits.maxScopeBytes));
    const observed = scopes(original);
    if (!runtimeIsBoxedSome(observed) && !runtimeIsBoxedNone(observed)) {
      fail('RemoteCredentialAuthenticationResponseUnavailable');
    }
    // These observations never issue permissions. A present response scope may
    // narrow the declaration, but cannot enlarge the original selected set.
    if (runtimeIsBoxedSome(observed) &&
        runtimeField(observed, 0).some(scope => !registration.scopes.includes(scope))) {
      fail('RemoteCredentialAuthenticationScopeMismatch');
    }
    return Object.freeze({original, value: token(original), lifetimeSeconds: lifetime(original)});
  }});
}

function authenticationCurrent(state, original, scope, control, journal, now, signal) {
  if (state.retiring) fail('RemoteCredentialBindingRetiring');
  signal?.throwIfAborted();
  checkAuthenticationSelection(state, original);
  const time = now();
  if (!Number.isSafeInteger(time) || time < 0) fail('InvalidRemoteCredentialAuthenticationTime');
  // Both original supplier and trusted-clock callbacks may synchronously
  // retire/cancel this very binding. Their return is not a physical permit.
  if (state.retiring) fail('RemoteCredentialBindingRetiring');
  signal?.throwIfAborted();
  const parent = journal.authorize(original.parentClaim.use, BigInt(time),
    original.parentScope, control);
  if (parent.outcome !== 'claimed' && parent.outcome !== 'succeeded') {
    fail('InvalidRemoteCredentialAuthenticationParent');
  }
  if (state.authenticationExchange !== undefined) {
    const exchange = state.authenticationExchange;
    journal.authorize(exchange.claim.use, BigInt(time), exchange.scope, control);
    control.checkAuthenticationOperation(exchange.operation, exchange.request,
      original.parentClaim.use, exchange.claim.use, original.material,
      'POST', '/token', 'application/x-www-form-urlencoded', exchange.body, BigInt(time));
  }
  return time;
}

function authenticationOutcomeFailure(originalFailure, outcomeFailure, useCid) {
  // Keep the original physical failure in the established cause position; its
  // original cleanup handle/receiver must not disappear behind a data record.
  return Object.assign(new Error('RemoteCredentialAuthenticationOutcomeUnknown',
    {cause: originalFailure}), {code: 'RemoteCredentialAuthenticationOutcomeUnknown',
    outcomeFailure, useCid});
}

// This fixed form placement belongs only to the original registered Google
// dependency. It is not a general unauthenticated transport or a token getter.
export async function exchangeHttpsCredentialAuthentication({binding, material,
  scope, control, journal, resolveSecret, authGrant, authScope, useId,
  currentBeforeSend, now = Date.now, signal, ca, cert, key}) {
  const state = acquireBinding(binding, {scope, control, journal, resolveSecret});
  if (state === undefined) fail('InvalidRemoteCredentialBinding');
  let started = false, finishing = false, claimedHere;
  try {
    const original = state.authenticationMaterial, registration = state.authentication;
    if (registration === undefined || original === undefined ||
        original.material !== material || original.assertion === undefined || original.dependency === undefined ||
        typeof currentBeforeSend !== 'function' || typeof now !== 'function' ||
        !text(useId) || typeof journal.checkGrant !== 'function' ||
        ['prepareAuthenticationRequest', 'bindAuthenticationUse', 'checkAuthenticationOperation']
          .some(name => typeof control[name] !== 'function')) {
      fail('RemoteCredentialAuthenticationUnavailable');
    }
    if (state.authenticationExchangeAttempted) fail('RemoteCredentialAuthenticationAlreadyClaimed');
    if (control.identity(authGrant) !== original.dependency.grantCid) {
      fail('ForeignRemoteCredentialAuthenticationScope');
    }
    const reader = authenticationTokenReader(registration, state.maxSecretBytes);
    const selectedScope = Object.freeze({...authScope});
    if (selectedScope.resourceOrigin !== 'https://oauth2.googleapis.com' ||
        !text(selectedScope.operation) || selectedScope.operation === original.parentScope.operation ||
        credentialInvocationBindingKeys.some(name => name !== 'resourceOrigin' &&
          selectedScope[name] !== state.original[name]) ||
        credentialInvocationBindingKeys.some(name => selectedScope[name] !== original.dependency.scope[name]) ||
        selectedScope.operation !== original.dependency.scope.operation) {
      fail('ForeignRemoteCredentialAuthenticationScope');
    }
    await currentBeforeSend();
    const trustedNow = authenticationCurrent(state, original, scope, control, journal, now, signal);
    const request = googleServiceAccountAssertionRequest(original.assertion);
    // Own the exact already bounded form before claiming; never encode it into
    // a Bearer header or accept replacement bytes from the Connector caller.
    const body = Buffer.from(request.body, 'utf8');
    if (body.byteLength !== request.requestBytes ||
        body.byteLength > registration.signingLimits.maxRequestBytes) {
      fail('RemoteCredentialAuthenticationBodyLimitExceeded');
    }
    journal.checkGrant(control.identity(authGrant), BigInt(trustedNow), selectedScope, control);
    // Neither a fallible COMMIT nor a lost response may trigger another claim
    // or a replacement assertion on this original binding.
    state.authenticationExchangeAttempted = true;
    const claim = journal.claim(control.identity(authGrant), useId,
      BigInt(trustedNow), selectedScope, control);
    if (claim.replayed) fail('RemoteCredentialUseAlreadyClaimed');
    // Capture the original claimed responsibility before a fallible pure pair
    // check. A failed pair still belongs to this original Journal/use.
    const exchange = {claim, scope: selectedScope, body};
    state.authenticationExchange = exchange;
    claimedHere = exchange;
    const grantExpiry = BigInt(JSON.parse(control.json(claim.grant)).expires_unix_ms);
    const deadline = grantExpiry < BigInt(request.expiresAtUnixSeconds) * 1000n
      ? grantExpiry : BigInt(request.expiresAtUnixSeconds) * 1000n;
    const paired = control.prepareAuthenticationRequest(original.parentClaim.use,
      claim.grant, material, 'POST', '/token', 'application/x-www-form-urlencoded',
      body, registration.signingLimits.maxRequestBytes, deadline);
    const operation = control.bindAuthenticationUse(paired, original.parentClaim.use,
      claim.use, material, 'POST', '/token', 'application/x-www-form-urlencoded',
      body, BigInt(trustedNow));
    Object.assign(exchange, {request: paired, operation, deadline});
    await currentBeforeSend();
    // The server generates its response after this trusted sample. Starting
    // expires_in here is conservative: transport/current-check delay must not
    // renew a token whose original response has already consumed its lifetime.
    const sentAt = authenticationCurrent(state, original, scope, control, journal, now, signal);
    started = true;
    const response = await receive({hostname: 'oauth2.googleapis.com', path: '/token',
      method: 'POST', body, bodyMediaType: 'application/x-www-form-urlencoded',
      requestBytes: body.byteLength, authenticationForm: true, headers: [],
      ca, cert, key, signal, maxResponseBytes: reader.maxBytes, binding: state});
    // Observe the original current authority after the actual response/socket
    // await and before exposing any use of the private token.
    await currentBeforeSend();
    authenticationCurrent(state, original, scope, control, journal, now, signal);
    const decoded = reader.read(response);
    const advertised = BigInt(sentAt) + BigInt(decoded.lifetimeSeconds) * 1000n;
    const expires = [advertised, deadline, original.expiresUnixMilliseconds]
      .reduce((minimum, value) => value < minimum ? value : minimum);
    const finalNow = authenticationCurrent(state, original, scope, control, journal, now, signal);
    if (expires <= BigInt(finalNow)) fail('RemoteCredentialAuthenticationMaterialExpired');
    finishing = true;
    journal.finish(claim.record.useCid, 'succeeded');
    state.authenticationToken = {value: decoded.value, response: decoded.original,
      physicalResponse: response, expires, parentAvailable: true};
    return Object.freeze({useCid: claim.record.useCid});
  } catch (error) {
    // A refusal before this invocation acquired a claim must not settle an
    // earlier completed/Unknown operation retained by the same binding.
    const exchange = claimedHere;
    if (exchange !== undefined && !finishing) {
      finishing = true;
      try {
        journal.finish(exchange.claim.record.useCid, started ? 'unknown' : 'failed');
      } catch (outcomeFailure) {
        throw authenticationOutcomeFailure(error, outcomeFailure, exchange.claim.record.useCid);
      }
    }
    throw error;
  } finally {
    state.active = false;
    retireBinding(state);
  }
}

// Pending is the same original custody, never a close ACK. No timer, resolver
// lookup or new nominal use is started by cleanup. The active call observes
// request/socket retirement before relinquishing its original material.
export function closeHttpsCredentialBinding(binding) {
  const state = bindings.get(binding);
  if (!state) fail('InvalidRemoteCredentialBinding');
  state.retiring = true;
  state.request?.destroy(Object.assign(
    new Error('RemoteCredentialBindingRetiring'),
    {code: 'RemoteCredentialBindingRetiring'}));
  retireBinding(state);
  return state.closed ? 'closed' : 'pending';
}

function acquireBinding(binding, {scope, control, journal, resolveSecret, bindingBorrow}) {
  if (binding === undefined) {
    if (bindingBorrow !== undefined) fail('ForeignRemoteCredentialBindingBorrow');
    if (control?.kind === 'installation-metadata') fail('InvalidRemoteCredentialBinding');
    return undefined;
  }
  const state = bindings.get(binding);
  if (!state || state.control !== control || state.journal !== journal ||
      state.resolveSecret !== resolveSecret) {
    fail('ForeignRemoteCredentialBinding');
  }
  if (state.metadata) {
    control.scopeFields(scope);
    const subject = control.subjectFields();
    if (installationPreparationSubjectKeys.some(key => subject[key] !== state.original[key])) {
      fail('ForeignRemoteCredentialBinding');
    }
  } else if (credentialInvocationBindingKeys.some(key => scope?.[key] !== state.original[key])) {
    fail('ForeignRemoteCredentialBinding');
  }
  if (state.retiring) fail('RemoteCredentialBindingRetiring');
  if (state.borrow === undefined ? bindingBorrow !== undefined : state.borrow.token !== bindingBorrow) {
    fail('ForeignRemoteCredentialBindingBorrow');
  }
  if (state.borrow?.closing) fail('RemoteCredentialBindingBorrowRetiring');
  if (state.changed) fail('RemoteCredentialBindingChanged');
  if (state.pendingOutcome !== undefined) throw state.pendingOutcome;
  // A completed call/socket cannot retire an unjoined callback's original.
  // This applies to unfenced bindings too, before another claim or send.
  if (state.active || state.unjoinedResponseCustody !== undefined) fail('RemoteCredentialBindingBusy');
  state.active = true;
  return state;
}

function credentialBindingCurrent(binding, scope, signal) {
  if (binding.retiring) fail('RemoteCredentialBindingRetiring');
  if (binding.borrow?.closing) fail('RemoteCredentialBindingBorrowRetiring');
  if (binding.changed) fail('RemoteCredentialBindingChanged');
  signal?.throwIfAborted();
  if (binding.metadata) binding.control.scopeFields(scope);
  // Captured from the original private Host/Site preparation. It must finish
  // synchronously after the awaited current observation, before claim/send or
  // disclosure. A Promise/boolean is not a current authorization certificate.
  const result = Reflect.apply(binding.assertCurrent, undefined, []);
  if (result !== undefined) {
    if (typeof result?.then === 'function') void Promise.resolve(result).catch(() => {});
    fail(binding.metadata ? 'InvalidInstallationMetadataCurrentFence'
      : 'InvalidRemoteCredentialCurrentFence');
  }
  if (binding.retiring) fail('RemoteCredentialBindingRetiring');
  if (binding.changed) fail('RemoteCredentialBindingChanged');
  signal?.throwIfAborted();
}

function exactRequestTarget(path) {
  if (!text(path) || !path.startsWith('/') || path.startsWith('//') ||
      path.includes('\\') || path.includes('#')) {
    fail('InvalidRemoteCredentialOperation');
  }
  for (let index = 0; index < path.length; index++) {
    const code = path.charCodeAt(index);
    if (code < 0x21 || code > 0x7e) {
      fail('InvalidRemoteCredentialOperation');
    }
    if (code === 0x25) {
      if (index + 2 >= path.length ||
          !/^[0-9A-Fa-f]{2}$/.test(path.slice(index + 1, index + 3))) {
        fail('InvalidRemoteCredentialOperation');
      }
      index += 2;
    }
  }
  return path;
}

function operationFor(operations, scope, maxRequestBytes) {
  if (!(operations instanceof Map) || !text(scope?.operation) ||
      !text(scope?.resourceOrigin)) {
    fail('InvalidRemoteCredentialOperation');
  }
  const operation = operations.get(scope.operation);
  if (operation === undefined || operation === null ||
      typeof operation !== 'object' ||
      !text(operation.path)) {
    fail('UnsupportedRemoteCredentialOperation');
  }
  const {method} = operation;
  const binary = operation.bodyBytes !== undefined || operation.bodyMediaType !== undefined ||
    operation.maxBodyBytes !== undefined;
  let body = operation.body, bodyMediaType = 'application/json';
  try {
    if (binary) {
      // Reject the outer call mismatch before allocating the physical copy.
      // This is an independent transport ceiling, not proof of funding.
      if (!Number.isSafeInteger(operation.maxBodyBytes) ||
          operation.maxBodyBytes > maxRequestBytes) fail('InvalidRemoteCredentialOperation');
      const request = ownHttpByteRequest({method, path: operation.path,
        body, bodyBytes: operation.bodyBytes, bodyMediaType: operation.bodyMediaType,
        maxBodyBytes: operation.maxBodyBytes});
      body = request.bodyBytes;
      bodyMediaType = request.bodyMediaType;
    } else {
      checkHttpRequestMethodBody(method, body, {requireBody: true});
    }
  } catch (error) {
    fail(error?.code === 'InvalidHttpRequestMethod'
      ? 'UnsupportedRemoteCredentialOperation'
      : 'InvalidRemoteCredentialOperation', error);
  }
  const requestBytes = body === undefined ? 0 : Buffer.byteLength(body);
  if (requestBytes > maxRequestBytes) {
    fail('InvalidRemoteCredentialOperation');
  }
  // Allowed non-secret request headers and the declared response header
  // names travel with the registered operation; the typed exchange refuses
  // reserved names and over-long values before anything is sent.
  const headers = ownRequestHeaders(operation.headers);
  const responseHeaders = ownResponseHeaderNames(operation.responseHeaders);
  let origin;
  try {
    origin = new URL(scope.resourceOrigin);
  } catch (error) {
    fail('InvalidRemoteCredentialOperation', error);
  }
  if (origin.protocol !== 'https:' || origin.origin !== scope.resourceOrigin ||
      origin.username !== '' || origin.password !== '') {
    fail('InvalidRemoteCredentialOperation');
  }
  return Object.freeze({
    method,
    hostname: origin.hostname,
    port: origin.port || undefined,
    path: exactRequestTarget(operation.path),
    body,
    bodyMediaType,
    requestBytes,
    headers,
    responseHeaders,
  });
}

// One selected original binary reader may consume ONE extra byte to observe
// refusal. This is an implementation extent, never an observed byte count,
// transfer permission, protocol body-cap increase or all-wire/RSS claim.
export function httpsCredentialResponseWindowBytes(maxResponseBytes) {
  if (!count(maxResponseBytes) || maxResponseBytes === 0) fail('InvalidRemoteCredentialResponseWindow');
  return BigInt(maxResponseBytes) + 1n;
}

// Implementation geometry of this original observed binary reader, not a
// configurable body cap, transfer allowance or authority.
export const httpsCredentialResponseReadQuantum = 16_384;

function receive({hostname, port, path, method, body, bodyMediaType, requestBytes, secret,
  authenticationForm = false,
  headers, ca, cert, key, signal, maxResponseBytes, binding,
  retainRunResponseOriginal = false, observeResponseBytes}) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let socket;
    let socketClosed = false;
    let requestClosed = false;
    let complete, observerPending = false;
    const release = () => {
      if (!binding || !requestClosed || (socket && !socketClosed) || observerPending) return;
      binding.request = undefined;
      complete?.();
    };
    const finish = (handler, value) => {
      if (settled) return;
      settled = true;
      if (!binding) {
        handler(value);
        return;
      }
      complete = () => handler(value);
      // Only this new acquisition port owns a one-request connection. A full
      // response is retained until its actual request and socket close events.
      socket?.destroy();
      release();
    };
    const physicalHeaders = Object.freeze({
      accept: 'application/json',
      ...Object.fromEntries(headers),
      ...(authenticationForm ? {} : binding?.secretPresentation === 'kintone-api-token'
        ? {'x-cybozu-api-token': secret}
        : {authorization: httpsCredentialAuthorizationPrefix + secret}),
      ...(body === undefined ? {} : {
        'content-type': bodyMediaType,
        'content-length': requestBytes,
      }),
    });
    // Only these non-secret primitive values describe the original physical
    // representation. Never expose the credential-bearing header dictionary.
    const requestRepresentation = !retainRunResponseOriginal ? undefined :
      Object.freeze({
        accept: typeof physicalHeaders.accept === 'string' ? physicalHeaders.accept : undefined,
        acceptEncoding: typeof physicalHeaders['accept-encoding'] === 'string'
          ? physicalHeaders['accept-encoding'] : undefined,
        ifMatch: typeof physicalHeaders['if-match'] === 'string'
          ? physicalHeaders['if-match'] : undefined,
      });
    const request = httpsRequest({
      protocol: 'https:',
      ...(binding ? {agent: false} : {}),
      hostname,
      port,
      path,
      method,
      maxHeaderSize: httpsCredentialResponseHeaderByteLimit,
      ca,
      cert,
      key,
      // A provider may replace `accept`; the credential and body framing
      // headers are this adapter's own.
      headers: physicalHeaders,
      signal,
    }, response => {
      // Node's normalized header object can discard duplicate singleton
      // headers. Conditional evidence needs the actual received multiplicity,
      // kept only in the existing private original-response projection.
      let etagCount = 0;
      let contentEncodingCount = 0;
      if (retainRunResponseOriginal) {
        for (let index = 0; index < response.rawHeaders.length; index += 2) {
          const name = response.rawHeaders[index].toLowerCase();
          if (name === 'etag') etagCount++;
          if (name === 'content-encoding') contentEncodingCount++;
        }
      }
      const responseRepresentation = !retainRunResponseOriginal ? undefined :
        Object.freeze({etagCount, contentEncodingCount});
      let chunks = [];
      let detachReader;
      let received = 0;
      if (observeResponseBytes === undefined) {
        const readResponseChunk = chunk => {
          received += chunk.byteLength;
          if (received > maxResponseBytes) {
            response.destroy(Object.assign(
              new Error('RemoteCredentialResponseLimitExceeded'),
              {code: 'RemoteCredentialResponseLimitExceeded'},
            ));
            return;
          }
          chunks.push(Buffer.from(chunk));
        };
        response.on('data', readResponseChunk);
        detachReader = () => response.off('data', readResponseChunk);
      } else {
        // Capture the original method and receiver before an external observer
        // can replace read. Binary read(size) waits for size bytes until EOF,
        // permitting one final partial copy rather than arbitrary tiny copies.
        let readOriginal;
        // Bound the SAME
        // reader's selected representation to B+1 even when its protocol body
        // cap is B. Charge each actual read BEFORE limit refusal/copy; the last
        // offending byte is included, never silently counted as zero.
        const readObservedResponse = () => {
          if (settled || observerPending || response.destroyed) return;
          try {
            // Capture once under the SAME original error fence. A throwing
            // getter (including thrown undefined) destroys this response and
            // follows its existing binding/socket retirement path.
            readOriginal ??= response.read;
            let chunk;
            while ((chunk = Reflect.apply(readOriginal, response, [Math.min(httpsCredentialResponseReadQuantum,
              maxResponseBytes - received + 1)])) !== null) {
              const observed = observeResponseBytes(chunk.byteLength);
              if (observed !== undefined) {
                if (types.isPromise(observed)) {
                  // Invalid async borrowing remains joined to this SAME
                  // request/socket promise until settlement. Cleanup cannot
                  // ACK or drop the callback's original child in the meantime.
                  observerPending = true;
                  const finishObserver = () => { observerPending = false; release(); };
                  try {
                    // Register on the native original before observing a
                    // replaceable public getter/method. A rejected wrapper
                    // around that method cannot settle the original task.
                    Reflect.apply(nativePromiseThen, observed, [finishObserver, finishObserver]);
                  } catch (cause) {
                    // Constructor/species can refuse before native registration.
                    // Keep that unresolved original under this existing binding;
                    // a socket close or failed join is not its cleanup ACK.
                    binding.unjoinedResponseCustody ??= {original: observed, cause};
                    observerPending = false;
                    throw cause;
                  }
                  void observed.then;
                } else {
                  const then = observed !== null && (typeof observed === 'object' || typeof observed === 'function')
                    ? observed.then : undefined;
                  if (typeof then === 'function') {
                    observerPending = true;
                    const joined = new Promise((yes, no) => Reflect.apply(then, observed, [yes, no]));
                    const finishObserver = () => { observerPending = false; release(); };
                    joined.then(finishObserver, finishObserver);
                  }
                }
                fail('InvalidRemoteCredentialResponseByteObserver');
              }
              received += chunk.byteLength;
              if (received > maxResponseBytes) fail('RemoteCredentialResponseLimitExceeded');
              chunks.push(Buffer.from(chunk));
            }
          } catch (error) {
            // Native destroy(undefined/null/other falsey values) can close
            // without an error event. Enter the SAME completion fence with
            // the original throwable first; it still waits for this binding's
            // actual request/socket close and any borrowed observer task.
            finish(reject, error);
            response.destroy(error);
          }
        };
        response.on('readable', readObservedResponse);
        detachReader = () => response.off('readable', readObservedResponse);
      }
      response.once('error', error => finish(reject, error));
      response.once('end', () => {
        let body;
        try { body = Buffer.concat(chunks, received); }
        catch (error) { finish(reject, error); return; }
        // Only successful concatenation retires the copied receive prefix.
        // Sever the listener and its original Array, not the response/headers
        // or the request/socket/invalid-observer cleanup responsibilities.
        detachReader();
        detachReader = undefined;
        chunks.length = 0;
        chunks = undefined;
        finish(resolve, Object.freeze({
          statusCode: response.statusCode,
          headers: response.headers,
          body,
          requestRepresentation,
          responseRepresentation,
        }));
      });
    });
    if (binding) {
      binding.request = request;
      request.once('socket', original => {
        socket = original;
        socket.once('close', () => {
          socketClosed = true;
          release();
        });
      });
      request.once('close', () => {
        requestClosed = true;
        release();
      });
    }
    request.once('error', error => finish(reject, error));
    request.end(body);
  });
}

/// Execute one pre-registered HTTPS operation. Credential material is resolved
/// and applied inside this adapter and is never returned to Connector code.
/// An operation is `{method, path, body?, headers?, responseHeaders?}`: the
/// optional entries are the typed exchange's allowed request headers and the
/// declared response header names (`adapters/host-common/http-exchange.mjs`).
async function callCredentialResource({
  grant,
  useId,
  scope,
  control,
  journal,
  operations,
  resolveSecret,
  ca,
  cert,
  key,
  now = Date.now,
  maxRequestBytes = httpsCredentialDefaultRequestBytes,
  maxResponseBytes = 1_048_576,
  returnRejectedResponse = false,
  retainRunResponseOriginal = false,
  currentBeforeSend,
  responseCustody,
  observeResponseBytes,
  signal,
}, binding) {
  if (typeof control?.identity !== 'function' ||
      typeof journal?.claim !== 'function' ||
      typeof journal?.authorize !== 'function' ||
      typeof journal?.finish !== 'function' ||
      typeof resolveSecret !== 'function' || typeof now !== 'function' ||
      !text(useId) || !count(maxRequestBytes) || maxRequestBytes === 0 ||
      !count(maxResponseBytes) || maxResponseBytes === 0 ||
      typeof returnRejectedResponse !== 'boolean' ||
      typeof retainRunResponseOriginal !== 'boolean' ||
      (currentBeforeSend !== undefined && typeof currentBeforeSend !== 'function')) {
    fail('InvalidRemoteCredentialCall');
  }
  const retainResponse = captureSourceResponseCustody(responseCustody, () =>
    Object.assign(new Error('InvalidRemoteCredentialResponseCustody'), {code: 'InvalidRemoteCredentialResponseCustody'}),
  (original, cause) => {
    // No join exists to observe this task's retirement. Keep it and its body
    // on this SAME binding; another close attempt cannot infer an ACK from the
    // primary error, a later Promise resolution or the socket's termination.
    if (binding) binding.unjoinedResponseCustody ??= {original, cause};
  });
  if (observeResponseBytes !== undefined &&
      (typeof observeResponseBytes !== 'function' || binding === undefined)) {
    fail('InvalidRemoteCredentialResponseByteObserver');
  }
  if (observeResponseBytes !== undefined) httpsCredentialResponseWindowBytes(maxResponseBytes);
  const metadata = binding?.metadata === true;
  const fenced = binding?.assertCurrent !== undefined;
  if (!metadata && fenced && typeof currentBeforeSend !== 'function') {
    fail('InvalidRemoteCredentialCall');
  }
  // The installation-metadata alternative has its own opaque Subject/Scope.
  // It must not be interpreted as the existing Run-purpose grant/use pair.
  if (retainRunResponseOriginal && (metadata || Object.hasOwn(control, 'kind') ||
      types.isProxy(scope) || !Object.isFrozen(scope))) {
    fail('InvalidRemoteCredentialRunResponseCapture');
  }
  const selectedScope = metadata ? control.scopeFields(scope) : scope;
  const operation = operationFor(operations, selectedScope, maxRequestBytes);
  if (metadata && (typeof currentBeforeSend !== 'function' ||
      selectedScope.requestMethod !== 'GET' || operation.method !== 'GET' ||
      selectedScope.requestPath !== operation.path || operation.requestBytes !== 0 ||
      selectedScope.requestBodyCid !== 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')) {
    fail('InvalidRemoteCredentialOperation');
  }
  signal?.throwIfAborted();
  const authenticated = binding?.authentication !== undefined;
  const original = authenticated ? binding.authenticationMaterial : undefined;
  const token = authenticated ? binding.authenticationToken : undefined;
  if (authenticated) {
    if (token === undefined || typeof currentBeforeSend !== 'function') {
      fail('RemoteCredentialAuthenticationUnavailable');
    }
    if (token.pendingOutcome !== undefined) throw token.pendingOutcome;
    const trustedNow = authenticationCurrent(binding, original, scope, control, journal, now, signal);
    if (token.expires <= BigInt(trustedNow)) fail('RemoteCredentialAuthenticationMaterialExpired');
  }
  if (fenced) {
    credentialBindingCurrent(binding, scope, signal);
    await currentBeforeSend();
    credentialBindingCurrent(binding, scope, signal);
  }
  // The first API call consumes the already claimed original parent use. It
  // must not claim a second use or turn a replay into permission to send.
  let claimed;
  if (authenticated && token.parentAvailable) {
    claimed = original.parentClaim;
    if (useId !== claimed.record.useId || control.identity(grant) !== claimed.record.grantCid) {
      fail('ForeignRemoteCredentialAuthenticationParent');
    }
    token.parentAvailable = false;
  } else claimed = journal.claim(control.identity(grant), useId, BigInt(now()), scope, control);
  if (claimed.replayed) fail('RemoteCredentialUseAlreadyClaimed');
  let requestStarted = false, finishing = false;
  try {
    const currentSecret = authenticated ? token.value : await resolveSecret(Object.freeze(metadata ? {
      grantCid: claimed.record.grantCid, ...binding.original, ...selectedScope,
    } : {
      grantCid: claimed.record.grantCid,
      principal: scope.principal,
      namespaceId: scope.namespaceId,
      environment: scope.environment,
      operation: scope.operation,
      resourceOrigin: scope.resourceOrigin,
      siteKey: scope.siteKey,
      siteGeneration: scope.siteGeneration,
      connectorRegistration: scope.connectorRegistration,
    }), signal);
    if (!text(currentSecret)) fail('RemoteCredentialSecretUnavailable');
    if (binding && (currentSecret.length > binding.maxSecretBytes ||
        Buffer.byteLength(currentSecret) > binding.maxSecretBytes)) {
      fail('RemoteCredentialSecretLimitExceeded');
    }
    // The original Host's current read check may require an asynchronous
    // configuration read. Run it after the resolver await, without passing
    // credential material or manufacturing a grant from its return value.
    // Recheck the original binding and journal after this await as well.
    if (currentBeforeSend !== undefined) {
      // Preserve the original refusal before starting another Host read when
      // retirement, cancellation or a replacement credential is already known.
      if (binding?.retiring) fail('RemoteCredentialBindingRetiring');
      if (binding?.borrow?.closing) fail('RemoteCredentialBindingBorrowRetiring');
      if (binding?.secret !== undefined && binding.secret !== currentSecret) {
        binding.changed = true;
        fail('RemoteCredentialBindingChanged');
      }
      signal?.throwIfAborted();
      await currentBeforeSend();
    }
    if (binding?.retiring) fail('RemoteCredentialBindingRetiring');
    if (binding?.borrow?.closing) fail('RemoteCredentialBindingBorrowRetiring');
    if (binding?.secret !== undefined && binding.secret !== currentSecret) {
      binding.changed = true;
      fail('RemoteCredentialBindingChanged');
    }
    signal?.throwIfAborted();
    if (fenced) credentialBindingCurrent(binding, scope, signal);
    if (authenticated) {
      const trustedNow = authenticationCurrent(binding, original, scope, control, journal, now, signal);
      if (token.expires <= BigInt(trustedNow)) fail('RemoteCredentialAuthenticationMaterialExpired');
    }
    journal.authorize(
      claimed.use,
      BigInt(now()),
      scope,
      control,
    );
    // No await separates the current authority fence, retained-material
    // selection and physical request construction. A later resolver result
    // cannot replace the original acquisition's privately retained secret.
    if (binding && binding.secret === undefined) binding.secret = currentSecret;
    const secret = binding ? binding.secret : currentSecret;
    requestStarted = true;
    const response = await receive({
      ...operation,
      secret,
      ca,
      cert,
      key,
      signal,
      maxResponseBytes,
      binding,
      retainRunResponseOriginal,
      observeResponseBytes,
    });
    // A response awaiting its original current check remains in this binding's
    // custody. A refusal or unconfirmed outcome cannot publish it or discard it
    // before the caller has retired this original binding. This is not durable
    // publication storage or evidence of resource reclamation.
    if (fenced) binding.receivedResponse = response;
    // The same Source owns the actual bounded body even when the following
    // current/Journal/outcome check refuses. Retention is DATA, not authority
    // or a response outcome. Its original caller still owns the real charge.
    if (retainResponse !== undefined) {
      // Borrow only the SAME native body. Unselected response headers and
      // credential/outcome correspondence remain in this physical Owner.
      const retained = retainResponse(Object.freeze({body: response.body}));
      if (retained !== undefined) await retained;
    }
    if (fenced) {
      // Known retirement/cancellation closes even further configuration reads.
      credentialBindingCurrent(binding, scope, signal);
      await currentBeforeSend();
      credentialBindingCurrent(binding, scope, signal);
      journal.authorize(claimed.use, BigInt(now()), scope, control);
    }
    if (authenticated) {
      if (!fenced) await currentBeforeSend();
      const trustedNow = authenticationCurrent(binding, original, scope, control, journal, now, signal);
      if (token.expires <= BigInt(trustedNow)) fail('RemoteCredentialAuthenticationMaterialExpired');
      journal.authorize(claimed.use, BigInt(trustedNow), scope, control);
    }
    if (response.statusCode === 401 &&
        authenticated) binding.changed = true;
    else if (response.statusCode === 401 && typeof resolveSecret.invalidate === 'function') {
      resolveSecret.invalidate(secret);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      fail('RemoteCredentialRedirectRejected');
    }
    const accepted = response.statusCode >= 200 && response.statusCode < 300;
    if (!accepted && !returnRejectedResponse) {
      fail('RemoteCredentialResourceRejected');
    }
    // Only the declared response headers are observed, as bounded pairs; an
    // observation beyond the caps is a refusal of this exchange, recorded
    // below like any other failure after the request started.
    const headers = observeResponseHeaders(response.headers,
      operation.responseHeaders);
    if (!retainRunResponseOriginal) {
      finishing = true;
      journal.finish(claimed.record.useCid, accepted ? 'succeeded' : 'failed');
      if (fenced) binding.receivedResponse = undefined;
      return Object.freeze({useCid: claimed.record.useCid, accepted,
        statusCode: response.statusCode, headers, body: response.body});
    }
    const result = Object.freeze({
      useCid: claimed.record.useCid,
      accepted,
      statusCode: response.statusCode,
      headers,
      body: response.body,
    });
    // All fallible allocation/hash work precedes the outcome COMMIT. No
    // receiver runs here, and a failed COMMIT publishes no original response.
    const retained = {control, journal, body: response.body,
      // This bounded copy has its own backing buffer, never exposed to a
      // consumer. Later checks compare bytes instead of rehashing the response.
      bodySnapshot: new Uint8Array(response.body),
      byteLength: response.body.byteLength, confirmed: false,
      failure: undefined, facts: Object.freeze({grant: claimed.grant,
        use: claimed.use, scope, response: result, method: operation.method,
        path: operation.path, requestBodyBytes: operation.requestBytes,
        // Retain only the actual immutable text sent by this original operation.
        // This private historical projection is not a request reconstructed from
        // a byte count, CID or provider result; binary bodies remain unprojected.
        requestBodyText: typeof operation.body === 'string' ? operation.body : undefined,
        requestRepresentation: response.requestRepresentation,
        responseRepresentation: response.responseRepresentation,
        responseSha256: createHash('sha256').update(response.body).digest('hex')})};
    runResponseOriginals.set(result, retained);
    finishing = true;
    journal.finish(claimed.record.useCid, accepted ? 'succeeded' : 'failed');
    retained.confirmed = true;
    if (fenced) binding.receivedResponse = undefined;
    return result;
  } catch (error) {
    // Do not repeat a fallible outcome COMMIT on the protected typed paths. The
    // existing Journal and its original unknown claim retain responsibility.
    if ((authenticated || fenced || retainRunResponseOriginal) && finishing) {
      if (fenced) binding.pendingOutcome = error;
      else if (authenticated) token.pendingOutcome = error;
      throw error;
    }
    const outcome = requestStarted &&
        (operation.method !== 'GET' ||
          error?.code !== 'RemoteCredentialRedirectRejected') &&
        error?.code !== 'RemoteCredentialResourceRejected'
        ? 'unknown'
        : 'failed';
    if (authenticated || fenced) {
      try { journal.finish(claimed.record.useCid, outcome); }
      catch (outcomeFailure) {
        const pending = authenticationOutcomeFailure(error, outcomeFailure, claimed.record.useCid);
        if (fenced) binding.pendingOutcome = pending;
        else token.pendingOutcome = pending;
        throw pending;
      }
    } else journal.finish(claimed.record.useCid, outcome);
    // A later current result cannot authorize a different request in place of
    // this acquisition's unresolved original physical attempt. Cleanup may
    // retire the binding; only the original Journal owns reconciliation.
    if (fenced && outcome === 'unknown') binding.pendingOutcome = error;
    throw error;
  }
}

export async function callHttpsCredentialResource(options) {
  const binding = acquireBinding(options.binding, options);
  try {
    // An explicitly registered auth dependency cannot fall back to a static
    // Bearer resolver while its separate original exchange is not connected.
    if (binding?.authentication !== undefined && binding.authenticationToken === undefined) {
      fail('RemoteCredentialAuthenticationUnavailable');
    }
    return await callCredentialResource(options, binding);
  } finally {
    if (binding) {
      binding.active = false;
      retireBinding(binding);
    }
  }
}

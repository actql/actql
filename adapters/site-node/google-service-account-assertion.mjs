// Physical Google credential protocol preparation only. The existing Site,
// Credential, Account and acquisition owners retain permission/current/uses,
// I/O accounting, original materials, token custody and cleanup.
import {constants, sign} from 'node:crypto';
import {types} from 'node:util';

const tokenEndpoint = 'https://oauth2.googleapis.com/token';
const grantType = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
const assertions = new WeakMap();
const fail = code => {throw Object.assign(new Error(code), {code});};
const positive = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const limitKeys = ['maxScopes', 'maxScopeBytes', 'maxIdentityBytes', 'maxClaimBytes',
  'maxAssertionBytes', 'maxRequestBytes', 'maxKeyBits'];
const optionKeys = ['privateKey', 'clientEmail', 'privateKeyId', 'scopes',
  'delegate', 'issuedAtUnixSeconds', 'lifetimeSeconds', 'limits'];
const requiredOptions = ['privateKey', 'clientEmail', 'scopes',
  'issuedAtUnixSeconds', 'lifetimeSeconds', 'limits'];
const exactKeys = (object, keys, required = keys) => object !== null && typeof object === 'object' &&
  !types.isProxy(object) && !Array.isArray(object) &&
  required.every(key => Object.hasOwn(object, key)) && Object.keys(object).every(key => keys.includes(key));
const identityText = (value, maxBytes) => typeof value === 'string' && value.length > 0 &&
  value.isWellFormed() && !/[\s\u0000-\u001f\u007f]/u.test(value) && Buffer.byteLength(value) <= maxBytes;
const scopeToken = value => typeof value === 'string' && value.length > 0 && /^[\x21\x23-\x5b\x5d-\x7e]+$/u.test(value);
const base64 = value => Buffer.from(value).toString('base64url');

// Caller supplies an already-owned native private KeyObject and its original
// declared identity/subject/scopes. This does not load JSON/key files or mint a
// Google/ActQL permission. Values or a public-key fingerprint cannot substitute
// for that existing owner's checked original relationship.
export function prepareGoogleServiceAccountAssertion(options) {
  if (!exactKeys(options, optionKeys, requiredOptions)) fail('InvalidGoogleAssertionPreparation');
  const {privateKey, clientEmail, privateKeyId, scopes, delegate,
    issuedAtUnixSeconds, lifetimeSeconds, limits} = Object.fromEntries(
      optionKeys.filter(key => Object.hasOwn(options, key)).map(key => [key, options[key]]));
  if (!exactKeys(limits, limitKeys)) fail('InvalidGoogleAssertionLimits');
  const bound = Object.freeze(Object.fromEntries(limitKeys.map(name => [name, limits[name]])));
  if (!limitKeys.every(name => positive(bound[name]))) fail('InvalidGoogleAssertionLimits');
  if (types.isProxy(privateKey) || !types.isKeyObject(privateKey) || privateKey.type !== 'private' ||
      privateKey.asymmetricKeyType !== 'rsa' ||
      !Number.isSafeInteger(privateKey.asymmetricKeyDetails?.modulusLength) ||
      privateKey.asymmetricKeyDetails.modulusLength > bound.maxKeyBits) fail('InvalidGoogleAssertionKey');
  if (!identityText(clientEmail, bound.maxIdentityBytes) ||
      !clientEmail.includes('@') ||
      (privateKeyId !== undefined && !identityText(privateKeyId, bound.maxIdentityBytes)) ||
      (delegate !== undefined && (!identityText(delegate, bound.maxIdentityBytes) || !delegate.includes('@')))) {
    fail('InvalidGoogleAssertionIdentity');
  }
  if (!Number.isSafeInteger(issuedAtUnixSeconds) || issuedAtUnixSeconds < 0 ||
      !Number.isSafeInteger(lifetimeSeconds) || lifetimeSeconds < 1 || lifetimeSeconds > 3600 ||
      !Number.isSafeInteger(issuedAtUnixSeconds + lifetimeSeconds)) fail('InvalidGoogleAssertionLifetime');
  if (types.isProxy(scopes) || !Array.isArray(scopes) || scopes.length === 0 || scopes.length > bound.maxScopes) fail('InvalidGoogleAssertionScopes');
  const selectedScopes = [], seen = new Set();
  let scopeBytes = 0;
  for (let index = 0; index < scopes.length; index++) {
    const value = scopes[index];
    if (!scopeToken(value) || seen.has(value)) fail('InvalidGoogleAssertionScopes');
    scopeBytes += Buffer.byteLength(value) + (index === 0 ? 0 : 1);
    if (scopeBytes > bound.maxScopeBytes) fail('GoogleAssertionScopeLimit');
    seen.add(value); selectedScopes.push(value);
  }
  const header = {alg: 'RS256', typ: 'JWT', ...(privateKeyId === undefined ? {} : {kid: privateKeyId})};
  const claims = {iss: clientEmail, scope: selectedScopes.join(' '), aud: tokenEndpoint,
    exp: issuedAtUnixSeconds + lifetimeSeconds, iat: issuedAtUnixSeconds,
    ...(delegate === undefined ? {} : {sub: delegate})};
  const headerText = JSON.stringify(header), claimText = JSON.stringify(claims);
  if (Buffer.byteLength(headerText) + Buffer.byteLength(claimText) > bound.maxClaimBytes) fail('GoogleAssertionClaimLimit');
  const message = `${base64(headerText)}.${base64(claimText)}`;
  const signatureBytes = Math.ceil(privateKey.asymmetricKeyDetails.modulusLength / 8);
  const signatureUnits = Math.ceil(signatureBytes * 8 / 6);
  if (message.length + 1 + signatureUnits > bound.maxAssertionBytes) fail('GoogleAssertionSizeLimit');
  let signature;
  try {
    signature = sign('sha256', Buffer.from(message), {key: privateKey, padding: constants.RSA_PKCS1_PADDING});
  } catch {
    // No external action occurred; do not expose native key/error material.
    fail('GoogleAssertionSigningFailed');
  }
  const assertion = `${message}.${signature.toString('base64url')}`;
  if (Buffer.byteLength(assertion) > bound.maxAssertionBytes) fail('GoogleAssertionSizeLimit');
  const body = new URLSearchParams([['grant_type', grantType], ['assertion', assertion]]).toString();
  if (Buffer.byteLength(body) > bound.maxRequestBytes) fail('GoogleAssertionRequestLimit');
  const original = Object.freeze({});
  assertions.set(original, Object.freeze({privateKey, clientEmail, privateKeyId,
    scopes: Object.freeze(selectedScopes), delegate, issuedAtUnixSeconds,
    expiresAtUnixSeconds: claims.exp, body,
    requestBytes: Buffer.byteLength(body)}));
  return original;
}

// Only original preparation produces this request material. It is a sensitive
// assertion-bearing body, not a Ref, grant, execution or evidence of token mint.
// The eventual physical Credential caller must bind it to its original use and
// account the token exchange; do not send it via the Bearer-resource shortcut.
export function googleServiceAccountAssertionRequest(original) {
  const state = assertions.get(original);
  if (!state) fail('ForeignGoogleAssertionPreparation');
  return Object.freeze({url: tokenEndpoint, method: 'POST',
    headers: Object.freeze([Object.freeze(['content-type', 'application/x-www-form-urlencoded'])]),
    body: state.body, requestBytes: state.requestBytes,
    issuedAtUnixSeconds: state.issuedAtUnixSeconds,
    expiresAtUnixSeconds: state.expiresAtUnixSeconds});
}

// Only a same-original native key comparison. This does not check current
// installation, scope, issuer ownership or permission and does not issue them.
export function googleServiceAccountAssertionMatchesKey(original, privateKey) {
  const state = assertions.get(original);
  return state !== undefined && !types.isProxy(privateKey) &&
    types.isKeyObject(privateKey) && state.privateKey === privateKey;
}

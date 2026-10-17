import assert from 'node:assert/strict';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from './runtime-core.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteCredentialControl;

const grantRequest = () => Object.freeze({
  issuerAuthority: 'credential-authority-a',
  principal: 'principal-a',
  namespaceId: 'namespace-a',
  environment: 'production',
  siteKey: 'site-a',
  siteGeneration: 4,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'http-source',
  connectorRevision: 'http-source/1',
  resourceOrigin: 'https://resource.example',
  operation: 'records:read',
  runInvocationCid: cid('b'),
  taskAttempt: 2,
  dispatchRequestCid: cid('c'),
  expiresUnixMilliseconds: 2_000_000_000_000n,
  maxUses: 2,
});

test('Remote Credential identity is canonical and contains no secret', () => {
  const grant = control.prepare(grantRequest());
  const body = control.json(grant);
  assert.equal(
    control.identity(grant),
    'sha256:06e4af5fa870fbe558c30211879440b84757b52e5d761cdb80f65c4b0eeb6d1c',
  );
  assert.equal(body.includes('secret'), false);
  const admitted = control.admitJson(body, control.identity(grant));
  assert.equal(control.json(admitted), body);
  assert.throws(() => control.admitJson(`${body} `, control.identity(grant)));
});

test('Remote Credential use admits only the exact active scope', () => {
  const scope = grantRequest();
  const grant = control.prepare(scope);
  const first = control.prepareUse(grant, Object.freeze({
    useId: 'credential-use-a',
    trustedNowMilliseconds: 1_999_999_999_999n,
    usedCount: 0,
    revoked: false,
    scope,
  }));
  assert.deepEqual(control.useProjection(first).slice(2), [
    'credential-use-a',
    '1',
  ]);
  assert.equal(JSON.parse(control.useJson(first)).grant_cid,
    control.identity(grant));
  assert.doesNotThrow(() => control.authorizeUse(first, Object.freeze({
    trustedNowMilliseconds: 1_999_999_999_999n,
    revoked: false,
    scope,
  })));
  assert.throws(() => control.authorizeUse(first, Object.freeze({
    trustedNowMilliseconds: 2_000_000_000_000n,
    revoked: false,
    scope,
  })));
  assert.throws(() => control.prepareUse(grant, Object.freeze({
    useId: 'credential-use-b',
    trustedNowMilliseconds: 2_000_000_000_000n,
    usedCount: 1,
    revoked: false,
    scope,
  })));
  assert.throws(() => control.prepareUse(grant, Object.freeze({
    useId: 'credential-use-b',
    trustedNowMilliseconds: 1_999_999_999_999n,
    usedCount: 1,
    revoked: false,
    scope: Object.freeze({...scope, resourceOrigin: 'https://other.example'}),
  })));
});

// The subject projection is generated from the Owner; operation remains a
// separate use scope, and issuer trust comes from the signed grant admission.
for (const field of ['principal', 'namespaceId', 'environment', 'siteKey',
  'siteGeneration', 'runtimeBundleCid', 'connectorRegistration', 'connectorRevision',
  'resourceOrigin', 'operation', 'runInvocationCid', 'taskAttempt', 'dispatchRequestCid']) {
  test(`actual credential Owner refuses missing ${field} both before use and at final authorization`, () => {
    const original = grantRequest();
    const grant = control.prepare(original);
    const use = control.prepareUse(grant, {useId: `missing-${field}`,
      trustedNowMilliseconds: 1_999_999_999_999n, usedCount: 0, revoked: false, scope: original});
    const missing = {...original}; delete missing[field];
    assert.throws(() => control.prepareUse(grant, {useId: `foreign-${field}`,
      trustedNowMilliseconds: 1_999_999_999_999n, usedCount: 0, revoked: false, scope: missing}));
    assert.throws(() => control.authorizeUse(use, {
      trustedNowMilliseconds: 1_999_999_999_999n, revoked: false, scope: missing}));
  });
}

function authenticationOriginals() {
  const parentScope = grantRequest();
  const parentGrant = control.prepare(parentScope);
  const use = (grant, scope) => control.prepareUse(grant, {
    useId: 'original-authentication-use', trustedNowMilliseconds: 1n,
    usedCount: 0, revoked: false, scope,
  });
  const parent = use(parentGrant, parentScope);
  const scope = Object.freeze({...parentScope,
    resourceOrigin: 'https://oauth2.googleapis.com',
    operation: 'service-account:authenticate', maxUses: 1,
    expiresUnixMilliseconds: 1_999_999_999_999n});
  const grant = control.prepare(scope), material = Object.freeze({});
  // An opaque physical-supplier fixture, not an actual secret/key issuer.
  const bytes = Buffer.from('bounded-private-form');
  const request = control.prepareAuthenticationRequest(parent, grant, material,
    'POST', '/token', 'application/x-www-form-urlencoded', bytes, bytes.length, 100n);
  const credentialUse = use(grant, scope);
  const operation = control.bindAuthenticationUse(request, parent, credentialUse, material,
    'POST', '/token', 'application/x-www-form-urlencoded', bytes, 1n);
  const check = (op = operation, req = request, p = parent, u = credentialUse,
    m = material, body = bytes, now = 1n) => control.checkAuthenticationOperation(
      op, req, p, u, m, 'POST', '/token', 'application/x-www-form-urlencoded', body, now);
  return {parentScope, parentGrant, parent, scope, grant, material, bytes,
    request, credentialUse, operation, use, check};
}

test('actual authentication bridge retains the original pair without changing canonical grants', () => {
  const original = authenticationOriginals();
  assert.doesNotThrow(() => original.check());
  assert.equal(control.identity(original.parentGrant),
    'sha256:06e4af5fa870fbe558c30211879440b84757b52e5d761cdb80f65c4b0eeb6d1c');
  assert.equal(JSON.parse(control.json(original.parentGrant)).resource_origin,
    'https://resource.example');
  assert.equal(JSON.parse(control.json(original.grant)).resource_origin,
    'https://oauth2.googleapis.com');
  assert.doesNotThrow(() => control.authorizeUse(original.credentialUse, {
    scope: original.scope, trustedNowMilliseconds: 1n, revoked: false}));
  assert.throws(() => control.authorizeUse(original.credentialUse, {
    scope: original.scope, trustedNowMilliseconds: 1n, revoked: true}));
  // Correspondence does not remove the existing independent current refusal.
  assert.doesNotThrow(() => original.check());
});

test('actual authentication bridge rejects equal-data original substitution', () => {
  const o = authenticationOriginals();
  const parentCopy = o.use(o.parentGrant, o.parentScope);
  const useCopy = o.use(o.grant, o.scope);
  assert.equal(control.useJson(parentCopy), control.useJson(o.parent));
  assert.equal(control.useJson(useCopy), control.useJson(o.credentialUse));
  assert.throws(() => o.check(o.operation, o.request, parentCopy));
  assert.throws(() => o.check(o.operation, o.request, o.parent, useCopy));
  assert.throws(() => o.check(o.operation, o.request, o.parent, o.credentialUse, Object.freeze({})));
  const requestCopy = control.prepareAuthenticationRequest(o.parent, o.grant, o.material,
    'POST', '/token', 'application/x-www-form-urlencoded', o.bytes, o.bytes.length, 100n);
  assert.throws(() => o.check(o.operation, requestCopy));
  const grantCopy = control.admitJson(control.json(o.grant), control.identity(o.grant));
  assert.throws(() => control.bindAuthenticationUse(o.request, o.parent, o.use(grantCopy, o.scope),
    o.material, 'POST', '/token', 'application/x-www-form-urlencoded', o.bytes, 1n));
});

test('actual authentication bridge refuses changed body expiry and pre-hash limits', () => {
  const o = authenticationOriginals();
  const changed = Buffer.from(o.bytes); changed[0] ^= 1;
  assert.throws(() => o.check(o.operation, o.request, o.parent, o.credentialUse, o.material, changed));
  assert.throws(() => o.check(o.operation, o.request, o.parent, o.credentialUse, o.material, o.bytes, 100n));
  assert.throws(() => control.prepareAuthenticationRequest(o.parent, o.grant, o.material,
    'POST', '/token', 'application/x-www-form-urlencoded', o.bytes, o.bytes.length - 1, 100n));
  assert.throws(() => control.prepareAuthenticationRequest(o.parent, o.grant, o.material,
    'GET', '/token', 'application/x-www-form-urlencoded', o.bytes, o.bytes.length, 100n));
  assert.throws(() => control.prepareAuthenticationRequest(o.parent, o.grant, o.material,
    'POST', '/other', 'application/x-www-form-urlencoded', o.bytes, o.bytes.length, 100n));
});

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

import assert from 'node:assert/strict';
import test from 'node:test';
import {invocationBindingsMatch, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  './owned-invocation-context.mjs';

test('owned invocation context snapshots scalar bindings and limits', () => {
  const grant = {};
  const journal = {};
  const resolveSecret = () => {};
  const authorize = () => {};
  const scope = {namespaceId: 'first', principal: 'reader',
    siteGeneration: 4, operation: 'read',
    expiresUnixMilliseconds: 2000n};
  const limits = {maxBytes: 100};
  const credential = {journal, resolveSecret};
  const context = ownInvocationContext({
    authorization: {grant, useId: 'use-1', scope},
    credential, limits, callbacks: {authorize},
  });
  scope.namespaceId = 'second';
  scope.siteGeneration = 5;
  limits.maxBytes = 0;
  credential.resolveSecret = () => {};
  assert.equal(context.scope.namespaceId, 'first');
  assert.equal(context.scope.siteGeneration, 4);
  assert.equal(context.scope.expiresUnixMilliseconds, 2000n);
  assert.equal(context.limits.maxBytes, 100);
  assert.equal(context.authorization.grant, grant);
  assert.equal(context.credential.journal, journal);
  assert.equal(context.credential.resolveSecret, resolveSecret);
  assert.equal(context.callbacks.authorize, authorize);
  assert.equal(invocationBindingsMatch(context.scope, scope), false);
  assert.equal(invocationBindingsMatch(context.scope,
    {...scope, namespaceId: 'first', siteGeneration: 4}), true);
  assert(Object.isFrozen(context.scope));
  assert(Object.isFrozen(context.limits));
});

test('scope ownership rejects nested caller data instead of retaining it',
  () => {
    assert.throws(() => ownInvocationAuthorization({
      grant: {}, useId: 'use-1', scope: {namespaceId: {value: 'foreign'}},
    }), {code: 'InvalidOwnedInvocationContext'});
  });

test('scoped invoker owns the call and rejects a foreign operation',
  async () => {
    const scope = {namespaceId: 'namespace-a', operation: 'read'};
    const calls = [];
    const callResource = async call => {
      calls.push(call);
      scope.namespaceId = 'namespace-b';
      return {statusCode: 200};
    };
    await invokeScopedCredentialOperation({
      authorization: {grant: {}, useId: 'use-1', scope},
      credential: {resolveSecret: () => {}}, callResource,
      operation: 'read', method: 'GET', path: '/records',
      maxResponseBytes: 64,
    });
    assert.equal(calls[0].scope.namespaceId, 'namespace-a');
    assert.deepEqual(calls[0].operations.get('read'), {
      method: 'GET', path: '/records',
    });
    await assert.rejects(async () => invokeScopedCredentialOperation({
      authorization: {grant: {}, useId: 'use-2', scope},
      credential: {}, callResource,
      operation: 'write', method: 'POST', path: '/records', body: '{}',
      maxRequestBytes: 64, maxResponseBytes: 64,
    }), {code: 'InvalidOwnedInvocationContext'});
    assert.equal(calls.length, 1);
  });

test('explicit binary invocation snapshots the view and forwards no fabricated JSON body', async () => {
  const original = Buffer.from([88, 0, 255, 192, 13, 10, 89]);
  let call;
  await invokeScopedCredentialOperation({
    authorization: {grant: {}, useId: 'original-content-use', scope: {operation: 'upload'}},
    credential: {journal: {counterOnly: true}}, operation: 'upload', method: 'PUT',
    path: '/upload', bodyBytes: original.subarray(1, 6),
    bodyMediaType: 'application/octet-stream', maxRequestBytes: 5, maxResponseBytes: 128,
    callResource: async value => { call = value; original.fill(0x77); return {}; },
  });
  const request = call.operations.get('upload');
  assert.deepEqual([...request.bodyBytes], [0, 255, 192, 13, 10]);
  assert.equal(request.bodyBytes.buffer.byteLength, 5);
  assert.equal(request.bodyMediaType, 'application/octet-stream');
  assert.equal(request.maxBodyBytes, 5);
  assert.equal(request.body, undefined);
  assert.equal(call.maxRequestBytes, 5);
  assert.equal(call.useId, 'original-content-use');
});

test('malformed or one-short binary calls do not reach the physical callback', async () => {
  let calls = 0;
  const input = {authorization: {grant: {}, useId: 'u', scope: {operation: 'upload'}},
    credential: {}, operation: 'upload', method: 'POST', path: '/upload',
    bodyBytes: new Uint8Array([0, 255]), bodyMediaType: 'application/octet-stream',
    maxRequestBytes: 2, maxResponseBytes: 16, callResource: async () => { calls++; }};
  for (const change of [{maxRequestBytes: 1}, {maxRequestBytes: undefined},
    {body: '{}'}, {bodyMediaType: undefined}, {bodyBytes: undefined},
    {method: 'GET'}, {operation: 'foreign'}]) {
    await assert.rejects(async () => invokeScopedCredentialOperation({...input, ...change}));
  }
  assert.equal(calls, 0);
});

test('scoped Source invocation forwards its exact original response custody before a physical late refusal', async () => {
  const primary = new Error('original physical post-response current refusal'), body = Buffer.from('original');
  let observed, retained = 0;
  const responseCustody = Object.freeze({retain(value) {assert.equal(this, responseCustody); observed = value; retained++;}});
  await assert.rejects(async () => invokeScopedCredentialOperation({
    authorization: {grant: {}, useId: 'original-source-use', scope: {operation: 'read'}},
    credential: {}, operation: 'read', method: 'GET', path: '/records', maxResponseBytes: 64, responseCustody,
    callResource(input) {
      assert.strictEqual(input.responseCustody, responseCustody);
      input.responseCustody.retain(Object.freeze({body}));
      throw primary;
    }}), error => error === primary);
  assert.equal(retained, 1); assert.strictEqual(observed.body, body);
});

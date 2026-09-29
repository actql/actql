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

import assert from 'node:assert/strict';
import test from 'node:test';
import {bindDeclaredUpdateTargetRead, invocationBindingsMatch, invokeDeclaredRowUpdate, invokeScopedCredentialOperation,
  ownInvocationAuthorization, ownInvocationContext} from
  './owned-invocation-context.mjs';

test('declared UPDATE target reads retain the original row grant and refuse a repeated occurrence', async () => {
  const authority = Object.freeze({grant: {}, useId: 'original-target-use'});
  const request = {method: 'POST', path: '/target', query: [], headers: [['accept', 'application/json']], body: '{}'};
  const facts = Object.freeze({before: 'original'}), selected = [];
  const fence = () => selected.push('send-current');
  const projector = response => {
    assert.strictEqual(response, facts);
    return response.before;
  };
  let read;
  read = bindDeclaredUpdateTargetRead({rowCount: 2, operation: 'original-read',
    slot: {slot: 'target', maxRequestBytes: 2, maxResponseBytes: 16},
    assertCurrent() {selected.push('current');},
    authorizationForRow(index) {selected.push(index); return authority;},
    async readChild(original, input, index, slot, project) {
      assert.strictEqual(original, authority);
      assert.strictEqual(input.grant, authority.grant);
      assert.strictEqual(input.useId, authority.useId);
      assert.strictEqual(input.currentBeforeSend, fence);
      assert.strictEqual(project, projector);
      assert.equal(input.maxRequestBytes, 2);
      assert.equal(input.maxResponseBytes, 16);
      assert.deepEqual([...input.operations], [['original-read', {
        method: 'POST', path: '/target', headers: [['accept', 'application/json']], body: '{}',
      }]]);
      assert.equal(slot, 'target');
      assert.equal(index, 0);
      await assert.rejects(read(1, request, projector, fence), {code: 'InvalidOwnedInvocationContext'});
      await input.currentBeforeSend();
      return project(facts);
    }});
  await assert.rejects(read(1, request, projector, fence), {code: 'InvalidOwnedInvocationContext'});
  assert.equal(await read(0, request, projector, fence), 'original');
  await assert.rejects(read(0, request, projector, fence), {code: 'InvalidOwnedInvocationContext'});
  await assert.rejects(read(1, {...request, body: 'éa'}, projector, fence), {code: 'InvalidOwnedInvocationContext'});
  assert.deepEqual(selected, ['current', 0, 'current', 'send-current', 'current', 'current']);
});

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

test('declared row UPDATE admits only bounded HTTP DATA under the original Host authority', async () => {
  const member = {}, request = {}, current = {}, grant = {}, journal = {};
  const origin = 'https://records.example', registration = 'fixture';
  const signal = new AbortController().signal;
  const body = Buffer.from('original response');
  const invocations = [];
  const invocation = {member, request, current, signal, credential: {journal},
    authorization: {grant, useId: 'original-use', scope: {
      operation: 'update-record', resourceOrigin: origin, connectorRegistration: registration}},
    callResource: async call => {
      invocations.push(call);
      return {useCid: 'original-reply', statusCode: 200, body};
    }};
  const transport = {method: 'PUT', path: '/records', body: '{}',
    query: [['id', '東京']], headers: [['accept', 'application/json']], responseHeaders: ['etag']};
  const exactTarget = '/records?id=%E6%9D%B1%E4%BA%AC';
  const writeSlot = Object.freeze({phase: 'write', maxRequestBytes: 2, maxResponseBytes: 32,
    maxTargetBytes: exactTarget.length});
  const update = {prepareUpdateWrite(...data) {
    assert.deepEqual(data, [member, request, current, origin, registration, signal]);
    return transport;
  }};
  const {observation} = await invokeDeclaredRowUpdate(update, invocation, 'update-record', writeSlot);
  assert.equal(observation.body, body);
  assert.equal(observation.useCid, 'original-reply');
  assert.equal(invocations.length, 1);
  assert.equal(invocations[0].grant, grant);
  assert.equal(invocations[0].journal, journal);
  assert.equal(invocations[0].signal, signal);
  assert.equal(invocations[0].useId, 'original-use');
  assert.deepEqual(invocations[0].operations.get('update-record'), {method: 'PUT',
    path: exactTarget, body: '{}',
    headers: [['accept', 'application/json']], responseHeaders: ['etag']});
  assert.equal(invocations[0].maxRequestBytes, 2);
  assert.equal(invocations[0].maxResponseBytes, 32);
  const preEncoded = '/' + '%20'.repeat(writeSlot.maxTargetBytes);
  for (const [prepared, code] of [
    [{...transport, path: preEncoded, query: []}, 'InvalidHttpRequestTarget'],
    [{...transport, query: [['id', '東京a']]}, 'InvalidHttpRequestQuery'],
    [{...transport, path: '/records/' + '界'.repeat(10), query: []}, 'InvalidHttpRequestTarget'],
  ]) {
    await assert.rejects(invokeDeclaredRowUpdate({prepareUpdateWrite: () => prepared},
      invocation, 'update-record', writeSlot), {code});
  }
  await assert.rejects(invokeDeclaredRowUpdate(update, invocation, 'update-record',
    {...writeSlot, maxTargetBytes: undefined}), {code: 'InvalidOwnedInvocationContext'});
  for (const replacement of [{operation: 'foreign'}, {maxRequestBytes: 3}, {maxResponseBytes: 64}, {maxTargetBytes: 4096},
    {responseCustody: {}}, {bodyBytes: new Uint8Array()}, {authorization: {}}, {credential: {}},
    {callResource() {assert.fail('Codec tried to replace the Host transport');}},
    {method: 'DELETE', body: undefined}, {body: '€'}, {body: undefined},
    {headers: [, ['accept', 'application/json']]},
    {headers: [['accept', 'application/json', 'extra']]},
    {responseHeaders: Object.assign(['etag'], {map() {assert.fail('Ran provider map');}})},
    {responseHeaders: new Proxy([], {get() {assert.fail('Read proxy');}})}]) {
    await assert.rejects(invokeDeclaredRowUpdate({prepareUpdateWrite: () => ({...transport, ...replacement})},
      invocation, 'update-record', writeSlot), {code: 'InvalidOwnedInvocationContext'});
  }
  const getter = () => assert.fail('Read provider accessor during transport admission');
  for (const invalid of [
    Object.defineProperty({...transport}, 'path', {get: getter}),
    Object.create(transport),
    {...transport, query: [Object.defineProperty(['id', 'r1'], '1', {get: getter})]},
    {...transport, responseHeaders: Object.defineProperty(['etag'], Symbol.iterator, {get: getter})},
    {...transport, then: getter},
  ]) {
    await assert.rejects(invokeDeclaredRowUpdate({prepareUpdateWrite: () => invalid},
      invocation, 'update-record', writeSlot), {code: 'InvalidOwnedInvocationContext'});
  }
  await assert.rejects(invokeDeclaredRowUpdate({
    prepareUpdateWrite() {assert.fail('A foreign operation reached the write codec');},
  }, invocation, 'foreign', writeSlot),
    {code: 'InvalidOwnedInvocationContext'});
  await assert.rejects(invokeDeclaredRowUpdate({
    prepareUpdateWrite() {assert.fail('A read slot reached the write codec');},
  }, invocation, 'update-record', {...writeSlot, phase: 'capture-target'}),
  {code: 'InvalidOwnedInvocationContext'});
  assert.equal(invocations.length, 1);
});

test('invalid async UPDATE encoding settles inside its original invocation without a physical send', async () => {
  const refusal = new Error('original provider encoder rejected');
  const invocation = {
    authorization: {scope: {operation: 'update-record'}},
    callResource() {assert.fail('Invalid async encoder reached physical send');},
  };
  const slot = {phase: 'write', maxRequestBytes: 2, maxResponseBytes: 32, maxTargetBytes: 8};
  let reject;
  const encoded = new Promise((_resolve, refuse) => {reject = refuse;});
  const result = invokeDeclaredRowUpdate({prepareUpdateWrite: () => encoded},
    invocation, 'update-record', slot);
  let rejected = false;
  const observed = assert.rejects(result, cause => {rejected = true; return cause === refusal;});
  await Promise.resolve();
  assert.equal(rejected, false);
  reject(refusal);
  await observed;
  await assert.rejects(invokeDeclaredRowUpdate({
    prepareUpdateWrite: () => Promise.resolve({method: 'PUT', path: '/records', body: '{}'}),
  }, invocation, 'update-record', slot), {code: 'InvalidOwnedInvocationContext'});
});

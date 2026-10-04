import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {invokeScopedCredentialOperation} from
  '../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource} from './https-credential-resource.mjs';
import {linkHeader, openHttpsExchangeFixture, pagedListing} from
  './https-exchange-fixture.mjs';
import {openSqliteCredentialJournal} from './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from './remote-credential-signature.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

// A signed grant for `operation` at the fixture's origin, and the credential
// the product's resource boundary applies: the fixture sees a Bearer header
// and the test never sees its value again.
async function credential(t, origin, operation) {
  const root = await mkdtemp(join(tmpdir(), 'actql-exchange-journal-'));
  const authority = generateKeyPairSync('ed25519');
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([['authority-a',
      new Map([['key-a', authority.publicKey]])]]),
  });
  t.after(async () => {
    journal.close();
    await rm(root, {recursive: true, force: true});
  });
  const scope = Object.freeze({
    issuerAuthority: 'authority-a', principal: 'principal-a',
    namespaceId: 'namespace-a', environment: 'production', siteKey: 'site-a',
    siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'example', connectorRevision: 'example/0.1',
    resourceOrigin: origin, operation, runInvocationCid: cid('b'),
    taskAttempt: 1, dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 8,
  });
  const grant = control.prepare(scope);
  journal.acceptGrant(signRemoteCredentialGrant(grant, control,
    {keyId: 'key-a', privateKey: authority.privateKey}), control);
  let uses = 0;
  return Object.freeze({
    journal,
    authorization: () => ({grant, useId: `use-${uses++}`, scope}),
    resource: Object.freeze({control, journal,
      resolveSecret: async () => 'provider-secret',
      now: () => 1_999_999_999_999}),
  });
}

test('the fixture answers routes, logs requests without credentials and consumes faults once',
  async t => {
    const fixture = await openHttpsExchangeFixture(t, {
      routes: [{method: 'GET', pathname: '/items',
        handle: exchange => ({body: {state: exchange.query.state}})}],
      faults: [{kind: 'lose-reply', method: 'POST', pathname: '/items'},
        {kind: 'reply', method: 'GET', pathname: '/items', reply: {
          status: 429, headers: {'retry-after': '1',
            'x-ratelimit-remaining': '0'}, body: {message: 'rate limited'}}}],
    });
    const {authorization, resource} = await credential(t, fixture.origin,
      'items:read');
    const limited = await callHttpsCredentialResource({...resource,
      ...authorization(), operations: new Map([['items:read',
        {method: 'GET', path: '/items?state=open',
          responseHeaders: ['retry-after', 'x-ratelimit-remaining']}]]),
      ca: fixture.ca, returnRejectedResponse: true});
    assert.equal(limited.statusCode, 429);
    assert.deepEqual(limited.headers, [['retry-after', '1'],
      ['x-ratelimit-remaining', '0']]);
    const answered = await callHttpsCredentialResource({...resource,
      ...authorization(), operations: new Map([['items:read',
        {method: 'GET', path: '/items?state=open'}]]), ca: fixture.ca});
    assert.equal(answered.statusCode, 200);
    assert.deepEqual(JSON.parse(answered.body.toString('utf8')), {state: 'open'});
    assert.deepEqual(answered.headers, []);
    const {authorization: write, resource: writer} = await credential(t,
      fixture.origin, 'items:create');
    await assert.rejects(callHttpsCredentialResource({...writer, ...write(),
      operations: new Map([['items:create', {method: 'POST', path: '/items',
        body: '{"body":"x"}'}]]), ca: fixture.ca}));
    // The mutation's reply was lost after the request started: unknown.
    assert.equal(writer.journal.recover().at(-1).outcome, 'unknown');
    const seen = fixture.seen();
    assert.equal(seen.length, 3);
    assert.deepEqual(seen.map(entry => [entry.method, entry.path,
      entry.authorized, 'authorization' in entry.headers]),
    [['GET', '/items?state=open', true, false],
      ['GET', '/items?state=open', true, false],
      ['POST', '/items', true, false]]);
    assert.equal(seen[2].body, '{"body":"x"}');
    assert.equal(fixture.remainingFaults(), 0);
  });

test('allowed request headers reach the resource; reserved ones never leave the Host',
  async t => {
    const fixture = await openHttpsExchangeFixture(t, {
      routes: [{pathname: '/echo', handle: exchange => ({body: {
        accept: exchange.headers.accept,
        version: exchange.headers['x-example-api-version'],
        agent: exchange.headers['user-agent'],
        type: exchange.headers['content-type']}})}],
    });
    const {authorization, resource} = await credential(t, fixture.origin,
      'echo:write');
    const response = await invokeScopedCredentialOperation({
      authorization: authorization(), credential: {...resource, ca: fixture.ca},
      callResource: callHttpsCredentialResource, operation: 'echo:write',
      method: 'POST', path: '/echo', query: [['q', 'a b']],
      headers: [['accept', 'application/vnd.example+json'],
        ['x-example-api-version', '2026-03-10'], ['user-agent', 'actql/0.1']],
      body: '{}', maxRequestBytes: 1024, maxResponseBytes: 4096,
    });
    assert.deepEqual(JSON.parse(response.body.toString('utf8')), {
      accept: 'application/vnd.example+json', version: '2026-03-10',
      agent: 'actql/0.1', type: 'application/json'});
    assert.equal(fixture.seen()[0].path, '/echo?q=a%20b');
    for (const reserved of [['authorization', 'Bearer forged'],
      ['content-type', 'text/plain'], ['host', 'other.example']]) {
      await assert.rejects(async () => invokeScopedCredentialOperation({
        authorization: authorization(), credential: {...resource, ca: fixture.ca},
        callResource: callHttpsCredentialResource, operation: 'echo:write',
        method: 'POST', path: '/echo', headers: [reserved], body: '{}',
        maxRequestBytes: 1024, maxResponseBytes: 4096,
      }), {code: 'ReservedHttpRequestHeader'});
    }
    assert.equal(fixture.seen().length, 1);
  });

test('a reserved response header declaration is refused before any credential use or request',
  async t => {
    const fixture = await openHttpsExchangeFixture(t, {
      routes: [{pathname: '/items', handle: () => ({status: 201, body: {}})}],
    });
    const {authorization, resource} = await credential(t, fixture.origin,
      'items:create');
    let resolved = 0;
    const counted = {...resource, ca: fixture.ca,
      resolveSecret: async () => { resolved++; return 'provider-secret'; }};
    for (const call of [
      () => invokeScopedCredentialOperation({authorization: authorization(),
        credential: counted, callResource: callHttpsCredentialResource,
        operation: 'items:create', method: 'POST', path: '/items', body: '{}',
        responseHeaders: ['set-cookie'], maxRequestBytes: 1024,
        maxResponseBytes: 4096}),
      () => callHttpsCredentialResource({...counted, ...authorization(),
        operations: new Map([['items:create', {method: 'POST', path: '/items',
          body: '{}', responseHeaders: ['set-cookie']}]])}),
    ]) {
      await assert.rejects(async () => call(),
        {code: 'InvalidHttpResponseHeaderNames'});
    }
    assert.equal(resolved, 0);
    assert.equal(fixture.seen().length, 0);
    assert.deepEqual(resource.journal.recover(), []);
  });

test('an over-long declared header refuses the exchange instead of shortening it',
  async t => {
    const fixture = await openHttpsExchangeFixture(t, {
      routes: [{pathname: '/wide', handle: () => ({
        headers: {link: `<${'x'.repeat(1100)}>; rel="next"`}, body: []})}],
    });
    const {authorization, resource} = await credential(t, fixture.origin,
      'wide:read');
    await assert.rejects(invokeScopedCredentialOperation({
      authorization: authorization(), credential: {...resource, ca: fixture.ca},
      callResource: callHttpsCredentialResource, operation: 'wide:read',
      method: 'GET', path: '/wide', responseHeaders: ['link'],
      maxResponseBytes: 4096,
    }), {code: 'HttpHeaderObservationExceeded'});
    // A response arrived but its observation was refused: the credential use
    // is recorded unknown, like every failure after the request started, and
    // the provider infers neither success nor failure from it.
    assert.equal(resource.journal.recover().at(-1).outcome, 'unknown');
    const undeclared = await invokeScopedCredentialOperation({
      authorization: authorization(), credential: {...resource, ca: fixture.ca},
      callResource: callHttpsCredentialResource, operation: 'wide:read',
      method: 'GET', path: '/wide', maxResponseBytes: 4096,
    });
    assert.deepEqual(undeclared.headers, []);
  });

test('paged listings link pages and the last page carries no next relation',
  async t => {
    const items = Array.from({length: 5}, (_, index) => ({number: index + 1}));
    const fixture = await openHttpsExchangeFixture(t);
    const route = pagedListing({items, origin: fixture.origin,
      pathname: '/repos/o/r/issues', maxSize: 2, query: {state: 'open'}});
    const page = (number, size = 2) => route.handle({query: {state: 'open',
      per_page: String(size), page: String(number)}});
    assert.deepEqual(page(1).body, items.slice(0, 2));
    assert.equal(page(1).headers.link, linkHeader({
      next: `${fixture.origin}/repos/o/r/issues?state=open&per_page=2&page=2`,
      last: `${fixture.origin}/repos/o/r/issues?state=open&per_page=2&page=3`}));
    assert.match(page(2).headers.link, /rel="next".*rel="prev"/s);
    assert.deepEqual(page(3).body, items.slice(4));
    assert.doesNotMatch(page(3).headers.link, /rel="next"/);
    assert.deepEqual(page(1, 500).body, items.slice(0, 2),
      'page size is bounded by the listing, not the caller');
    assert.equal(route.handle({query: {state: 'closed'}}).status, 404);
    assert.equal(route.handle({query: {state: 'open', page: '0'}}).status, 422);
  });

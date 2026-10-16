import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, mkdtemp, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
// The typed exchange and its HTTPS fixture run with this boundary's tests.
import '../host-common/http-exchange.test.mjs';
import './https-exchange-fixture.test.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {invokeScopedCredentialOperation} from
  '../host-common/owned-invocation-context.mjs';
import {callHttpsCredentialResource, closeHttpsCredentialBinding,
  openHttpsCredentialBinding} from
  './https-credential-resource.mjs';
import {openSqliteCredentialJournal} from
  './sqlite-credential-journal.mjs';
import {signRemoteCredentialGrant} from
  './remote-credential-signature.mjs';

const control = runtimeCore(moon).remoteCredentialControl;
const cid = digit => `sha256:${digit.repeat(64)}`;

function openssl(root, ...arguments_) {
  execFileSync('openssl', arguments_, {cwd: root, stdio: 'ignore'});
}

async function fixture(t, {onRequest, retain = false} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-credential-resource-'));
  openssl(root, 'genrsa', '-out', 'ca.key', '2048');
  openssl(
    root,
    'req',
    '-x509',
    '-new',
    '-key', 'ca.key',
    '-out', 'ca.crt',
    '-subj', '/CN=ActQL Credential Test CA',
    '-days', '1',
  );
  openssl(root, 'genrsa', '-out', 'resource.key', '2048');
  openssl(
    root,
    'req',
    '-new',
    '-key', 'resource.key',
    '-out', 'resource.csr',
    '-subj', '/CN=localhost',
  );
  await writeFile(
    join(root, 'resource.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\n',
  );
  openssl(
    root,
    'x509',
    '-req',
    '-in', 'resource.csr',
    '-CA', 'ca.crt',
    '-CAkey', 'ca.key',
    '-CAcreateserial',
    '-out', 'resource.crt',
    '-days', '1',
    '-extfile', 'resource.ext',
  );
  const [ca, cert, key] = await Promise.all([
    readFile(join(root, 'ca.crt')),
    readFile(join(root, 'resource.crt')),
    readFile(join(root, 'resource.key')),
  ]);
  let requests = 0;
  let redirected = 0;
  const mutationBodies = [];
  const exactTargets = [];
  const server = createServer({cert, key}, (request, response) => {
    requests++;
    if (onRequest?.(request, response)) return;
    if (request.url === '/redirected') redirected++;
    if (request.headers.authorization !== 'Bearer provider-secret') {
      response.writeHead(401).end();
    } else if (request.url === '/records') {
      response.writeHead(200, {'content-type': 'application/json'});
      response.end('{"records":[1,2]}');
    } else if (request.url === '/redirect') {
      response.writeHead(302, {location: '/redirected'}).end();
    } else if (request.url === '/limit') {
      response.writeHead(429, {'content-type': 'application/json'});
      response.end('[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]');
    } else if (request.url === '/mutate' && request.method === 'POST') {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.once('end', () => {
        mutationBodies.push(Buffer.concat(chunks).toString('utf8'));
        response.writeHead(201, {'content-type': 'application/json'});
        response.end('{"id":"record-1","success":true,"errors":[]}');
      });
    } else if (request.url === '/mutation-redirect' &&
        request.method === 'POST') {
      response.writeHead(302, {location: '/redirected'}).end();
    } else if (request.url.startsWith('/exact/') &&
        ['GET', 'POST', 'PATCH'].includes(request.method)) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.once('end', () => {
        exactTargets.push({method: request.method, path: request.url,
          body: Buffer.concat(chunks).toString('utf8')});
        response.writeHead(200, {'content-type': 'application/json'});
        response.end('{}');
      });
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  const origin = `https://127.0.0.1:${address.port}`;
  const authority = generateKeyPairSync('ed25519');
  if (retain) await Promise.all([
    writeFile(join(root, 'credential-authority.key'), authority.privateKey.export({
      format: 'pem', type: 'pkcs8'}), {mode: 0o600}),
    writeFile(join(root, 'credential-authority.pub'), authority.publicKey.export({
      format: 'pem', type: 'spki'})),
  ]);
  const journal = openSqliteCredentialJournal(join(root, 'journal'), {
    credentialAuthorities: new Map([
      [
        'credential-authority-a',
        new Map([['credential-key-a', authority.publicKey]]),
      ],
    ]),
  });
  t.after(async () => {
    journal.close();
    await new Promise(resolve => server.close(resolve));
    if (retain) t.diagnostic(`Retained owned fixture: ${root}`);
    else await rm(root, {recursive: true, force: true});
  });
  return Object.freeze({
    ca,
    origin,
    journal,
    sign: grant => signRemoteCredentialGrant(grant, control, {
      keyId: 'credential-key-a',
      privateKey: authority.privateKey,
    }),
    requests: () => requests,
    redirected: () => redirected,
    mutationBodies: () => [...mutationBodies],
    exactTargets: () => [...exactTargets],
  });
}

function scope(origin, operation = 'records:read') {
  return Object.freeze({
    issuerAuthority: 'credential-authority-a',
    principal: 'principal-a',
    namespaceId: 'namespace-a',
    environment: 'production',
    siteKey: 'site-a',
    siteGeneration: 4,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'http-source',
    connectorRevision: 'http-source/1',
    resourceOrigin: origin,
    operation,
    runInvocationCid: cid('b'),
    taskAttempt: 2,
    dispatchRequestCid: cid('c'),
    expiresUnixMilliseconds: 2_000_000_000_000n,
    maxUses: 4,
  });
}

const operations = Object.freeze(new Map([
  ['records:read', Object.freeze({method: 'GET', path: '/records'})],
  ['records:redirect', Object.freeze({method: 'GET', path: '/redirect'})],
  ['records:limit', Object.freeze({method: 'GET', path: '/limit'})],
  ['records:create', Object.freeze({method: 'POST', path: '/mutate',
    body: '{"Name":"new"}'})],
  ['records:mutation-redirect', Object.freeze({method: 'POST',
    path: '/mutation-redirect', body: '{"Name":"new"}'})],
]));

async function call(setup, grant, grantScope, useId, overrides = {}) {
  return await callHttpsCredentialResource({
    grant,
    useId,
    scope: grantScope,
    control,
    journal: setup.journal,
    operations,
    resolveSecret: async () => 'provider-secret',
    ca: setup.ca,
    now: () => 1_999_999_999_999,
    maxResponseBytes: 1024,
    ...overrides,
  });
}

test('scoped credential is claimed before an authenticated HTTPS request',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin);
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const result = await call(setup, grant, grantScope, 'use-a');
    assert.equal(result.body.toString('utf8'), '{"records":[1,2]}');
    assert.equal(setup.journal.inspect(result.useCid).outcome, 'succeeded');
    assert.equal(setup.requests(), 1);
    await assert.rejects(
      call(setup, grant, grantScope, 'use-a'),
      {code: 'RemoteCredentialUseAlreadyClaimed'},
    );
    assert.equal(setup.requests(), 1);
  });

test('HTTPS request-target is sent exactly as admitted before the use claim',
  async t => {
    const setup = await fixture(t);
    const targets = [
      '/exact/.',
      '/exact/..',
      '/exact/a.b',
      '/exact/%2E',
      '/exact/a%2Fb',
      '/exact/100%25',
      '/exact/%C3%A9',
      '/exact/a%3Fb%23c',
    ];
    for (let index = 0; index < targets.length; index++) {
      const operation = `records:exact:${index}`;
      const grantScope = scope(setup.origin, operation);
      const grant = control.prepare(grantScope);
      setup.journal.acceptGrant(setup.sign(grant), control);
      const body = JSON.stringify({index});
      const result = await call(setup, grant, grantScope, `exact-use-${index}`, {
        operations: new Map([[operation,
          {method: 'PATCH', path: targets[index], body}]]),
      });
      assert.equal(result.accepted, true);
      assert.deepEqual(setup.exactTargets()[index],
        {method: 'PATCH', path: targets[index], body});
    }
    const priorRequests = setup.requests();
    const priorUses = setup.journal.recover().length;
    for (const [index, path] of [
      '/exact/raw#fragment',
      '/exact/raw space',
      '/exact/\\backslash',
      '/exact/é',
      '/exact/%2',
    ].entries()) {
      const operation = `records:invalid:${index}`;
      const grantScope = scope(setup.origin, operation);
      const grant = control.prepare(grantScope);
      setup.journal.acceptGrant(setup.sign(grant), control);
      await assert.rejects(
        call(setup, grant, grantScope, `invalid-use-${index}`, {
          operations: new Map([[operation,
            {method: 'PATCH', path, body: '{}'}]]),
        }),
        {code: 'InvalidRemoteCredentialOperation'},
      );
    }
    assert.equal(setup.requests(), priorRequests);
    assert.equal(setup.journal.recover().length, priorUses);
  });

test('expiry during secret resolution consumes use without external I/O',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin);
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    let observed = 1_999_999_999_999;
    await assert.rejects(call(setup, grant, grantScope, 'use-a', {
      resolveSecret: async () => {
        observed = 2_000_000_000_000;
        return 'provider-secret';
      },
      now: () => observed,
    }));
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover()[0].outcome, 'failed');
  });

test('revocation during secret resolution fences the final request and retains the original use',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin);
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    let original;
    await assert.rejects(call(setup, grant, grantScope, 'revoked-after-await', {
      resolveSecret: async () => {
        original = setup.journal.recover()[0];
        assert.equal(original.outcome, 'claimed');
        setup.journal.revoke(control.identity(grant));
        await Promise.resolve();
        return 'provider-secret';
      },
    }));
    assert.equal(setup.requests(), 0);
    const retained = setup.journal.recover();
    assert.equal(retained.length, 1);
    assert.equal(retained[0].useCid, original.useCid);
    assert.equal(retained[0].outcome, 'failed');
    await assert.rejects(call(setup, grant, grantScope, 'revoked-after-await'));
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover().length, 1);
  });

test('redirect is rejected without forwarding the provider credential',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin, 'records:redirect');
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    await assert.rejects(
      call(setup, grant, grantScope, 'use-a'),
      {code: 'RemoteCredentialRedirectRejected'},
    );
    assert.equal(setup.requests(), 1);
    assert.equal(setup.redirected(), 0);
  });

test('scoped reads can inspect a rejected response without claiming success',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin, 'records:limit');
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const result = await call(setup, grant, grantScope, 'use-limit', {
      returnRejectedResponse: true,
    });
    assert.equal(result.accepted, false);
    assert.equal(result.statusCode, 429);
    assert.equal(result.body.toString('utf8'),
      '[{"errorCode":"REQUEST_LIMIT_EXCEEDED"}]');
    assert.equal(setup.journal.inspect(result.useCid).outcome, 'failed');
    assert.equal(setup.requests(), 1);
    await assert.rejects(
      call(setup, grant, grantScope, 'use-limit', {
        returnRejectedResponse: true,
      }),
      {code: 'RemoteCredentialUseAlreadyClaimed'},
    );
    assert.equal(setup.requests(), 1);
  });

test('401 invalidates only the used credential and never retries the request',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin);
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const invalidated = [];
    const resolveSecret = async () => 'revoked-secret';
    resolveSecret.invalidate = token => invalidated.push(token);
    const response = await call(setup, grant, grantScope, 'use-unauthorized', {
      resolveSecret, returnRejectedResponse: true,
    });
    assert.equal(response.accepted, false);
    assert.equal(response.statusCode, 401);
    assert.deepEqual(invalidated, ['revoked-secret']);
    assert.equal(setup.requests(), 1);
    assert.equal(setup.journal.inspect(response.useCid).outcome, 'failed');
  });

test('scoped mutation sends exact bounded body once with a durable use',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin, 'records:create');
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const response = await call(setup, grant, grantScope, 'create-a', {
      maxRequestBytes: 14,
    });
    assert.equal(response.statusCode, 201);
    assert.deepEqual(setup.mutationBodies(), ['{"Name":"new"}']);
    assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
    await assert.rejects(call(setup, grant, grantScope, 'create-a'), {
      code: 'RemoteCredentialUseAlreadyClaimed',
    });
    assert.equal(setup.requests(), 1);
  });

test('mutation bound and redirect preserve uncertain-send distinction',
  async t => {
    const setup = await fixture(t);
    const scopeCreate = scope(setup.origin, 'records:create');
    const grantCreate = control.prepare(scopeCreate);
    setup.journal.acceptGrant(setup.sign(grantCreate), control);
    await assert.rejects(call(setup, grantCreate, scopeCreate, 'too-large', {
      maxRequestBytes: 1,
    }), {code: 'InvalidRemoteCredentialOperation'});
    assert.equal(setup.requests(), 0);
    const redirectScope = scope(setup.origin,
      'records:mutation-redirect');
    const redirectGrant = control.prepare(redirectScope);
    setup.journal.acceptGrant(setup.sign(redirectGrant), control);
    await assert.rejects(call(setup, redirectGrant, redirectScope,
      'redirected-write'), {code: 'RemoteCredentialRedirectRejected'});
    assert.equal(setup.requests(), 1);
    assert.equal(setup.redirected(), 0);
    assert.equal(setup.journal.recover().at(-1).outcome, 'unknown');
  });

test('resource operation attempt and revocation scope stop before HTTPS I/O',
  async t => {
    const setup = await fixture(t);
    const grantScope = scope(setup.origin);
    const grant = control.prepare(grantScope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const rejected = [
      {...grantScope, resourceOrigin: 'https://127.0.0.1:1'},
      {...grantScope, operation: 'records:redirect'},
      {...grantScope, taskAttempt: 3},
      {...grantScope, siteGeneration: 5},
    ];
    for (let index = 0; index < rejected.length; index++) {
      await assert.rejects(call(
        setup,
        grant,
        Object.freeze(rejected[index]),
        `rejected-${index}`,
      ));
    }
    setup.journal.revoke(control.identity(grant));
    await assert.rejects(call(setup, grant, grantScope, 'revoked'));
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover().length, 0);
  });


function boundFixture(setup, grantScope, resolveSecret, maxSecretBytes = 64) {
  const binding = openHttpsCredentialBinding({scope: grantScope, control,
    journal: setup.journal, resolveSecret, maxSecretBytes});
  const invoke = (scope, useId, overrides = {}) => {
    const grant = control.prepare(scope);
    setup.journal.acceptGrant(setup.sign(grant), control);
    return call(setup, grant, scope, useId,
      {binding, resolveSecret, ...overrides});
  };
  return {binding, invoke};
}

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return {promise, resolve};
}

test('bound identity and page are separate authorized uses without exposing credential material',
  async t => {
    const seen = [];
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      seen.push([request.url, request.headers.authorization]);
      response.end(request.url === '/identity' ? '{"portal":7}' : '{"rows":[1]}');
      return true;
    }});
    const identity = scope(setup.origin, 'account:identity');
    const page = scope(setup.origin, 'objects:read');
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding, invoke} = boundFixture(setup, identity, resolveSecret);
    assert.deepEqual(Reflect.ownKeys(binding), []);
    assert.equal(resolutions, 0);
    assert.equal(setup.journal.recover().length, 0);
    for (const [selected, path] of [[identity, '/identity'], [page, '/page']]) {
      const grant = control.prepare(selected);
      setup.journal.acceptGrant(setup.sign(grant), control);
      const response = await invokeScopedCredentialOperation({
        authorization: {grant, scope: selected, useId: `bound-${path}`},
        credential: {binding, control, journal: setup.journal, resolveSecret,
          ca: setup.ca, now: () => 1_999_999_999_999},
        callResource: callHttpsCredentialResource, operation: selected.operation,
        method: 'GET', path, maxRequestBytes: 1, maxResponseBytes: 1024,
      });
      assert.equal(response.accepted, true);
    }
    assert.deepEqual(seen, [['/identity', 'Bearer provider-secret'],
      ['/page', 'Bearer provider-secret']]);
    assert.equal(resolutions, 2);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome),
      ['succeeded', 'succeeded']);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(resolutions, 2);
    await assert.rejects(invoke(page, 'after-close'),
      {code: 'RemoteCredentialBindingRetiring'});
    assert.equal(setup.requests(), 2);
  });

test('rotation after identity refuses a replacement token before a page send or re-probe',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin);
    let current = 'provider-secret';
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return current; };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret);
    await invoke(original, 'identity');
    current = 'foreign-portal-secret';
    await assert.rejects(invoke(original, 'page'),
      {code: 'RemoteCredentialBindingChanged'});
    assert.equal(setup.requests(), 1);
    assert.equal(resolutions, 2);
    const retained = setup.journal.recover();
    assert.deepEqual(retained.map(use => use.outcome), ['succeeded', 'failed']);
    await assert.rejects(invoke(original, 'page'),
      {code: 'RemoteCredentialBindingChanged'});
    assert.equal(resolutions, 2);
    assert.equal(setup.requests(), 1);
    assert.equal(setup.journal.recover()[1].useCid, retained[1].useCid);
    current = 'provider-secret';
    await assert.rejects(invoke(original, 'fresh-after-change'),
      {code: 'RemoteCredentialBindingChanged'});
    assert.equal(resolutions, 2);
    assert.equal(setup.journal.recover().length, 2);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('rotation across the current resolver await cannot replace the retained material',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin);
    const entered = deferred();
    const released = deferred();
    let current = 'provider-secret';
    let calls = 0;
    const resolveSecret = async () => {
      if (++calls === 2) { entered.resolve(); await released.promise; }
      return current;
    };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret);
    await invoke(original, 'identity');
    const page = invoke(original, 'page');
    await entered.promise;
    current = 'foreign-portal-secret';
    released.resolve();
    await assert.rejects(page, {code: 'RemoteCredentialBindingChanged'});
    assert.equal(setup.requests(), 1);
    assert.equal(calls, 2);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('rotation during an awaited response keeps its original request and refuses the next page',
  async t => {
    let current = 'provider-secret';
    const seen = [];
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      seen.push(request.headers.authorization);
      current = 'foreign-portal-secret';
      response.end('{"portal":7}');
      return true;
    }});
    const original = scope(setup.origin);
    const {binding, invoke} = boundFixture(setup, original, async () => current);
    await invoke(original, 'identity');
    await assert.rejects(invoke(original, 'page'),
      {code: 'RemoteCredentialBindingChanged'});
    assert.deepEqual(seen, ['Bearer provider-secret']);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('equal bound material never substitutes for post-await revocation or expiry checks',
  async t => {
    for (const mode of ['revoked', 'expired']) {
      const setup = await fixture(t, {retain: true});
      const original = scope(setup.origin);
      const grant = control.prepare(original);
      setup.journal.acceptGrant(setup.sign(grant), control);
      let observed = 1_999_999_999_999;
      let resolutions = 0;
      const resolveSecret = async () => {
        if (++resolutions === 2) {
          if (mode === 'revoked') setup.journal.revoke(control.identity(grant));
          else observed = 2_000_000_000_000;
          await Promise.resolve();
        }
        return 'provider-secret';
      };
      const binding = openHttpsCredentialBinding({scope: original, control,
        journal: setup.journal, resolveSecret, maxSecretBytes: 64});
      const options = {binding, resolveSecret, now: () => observed};
      await call(setup, grant, original, 'identity', options);
      await assert.rejects(call(setup, grant, original, 'page', options));
      assert.equal(setup.requests(), 1);
      assert.deepEqual(setup.journal.recover().map(use => use.outcome),
        ['succeeded', 'failed']);
      assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    }
  });

test('bound scope includes every generated subject field and the actual original Owners',
  async t => {
    const {credentialInvocationBindingKeys} = await import(
      '../host-common/credential-scope-fields.generated.mjs');
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin);
    const resolveSecret = async () => 'provider-secret';
    const {binding} = boundFixture(setup, original, resolveSecret);
    const grant = control.prepare(original);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const invoke = (scope, useId, overrides = {}) => call(setup, grant, scope,
      useId, {binding, resolveSecret, ...overrides});
    for (const key of credentialInvocationBindingKeys) {
      const value = original[key];
      const foreign = {...original, [key]: typeof value === 'number'
        ? value + 1 : `${value}-foreign`};
      await assert.rejects(invoke(foreign, `foreign-${key}`),
        {code: 'ForeignRemoteCredentialBinding'});
      const missing = {...original};
      delete missing[key];
      await assert.rejects(invoke(missing, `missing-${key}`),
        {code: 'ForeignRemoteCredentialBinding'});
    }
    await assert.rejects(invoke(original, 'foreign-resolver',
      {resolveSecret: async () => 'provider-secret'}),
      {code: 'ForeignRemoteCredentialBinding'});
    await assert.rejects(invoke(original, 'fabricated', {binding: Object.freeze({})}),
      {code: 'ForeignRemoteCredentialBinding'});
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover().length, 0);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('cleanup during resolution retains the same binding until the original call retires',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin);
    const entered = deferred();
    const released = deferred();
    let resolutions = 0;
    const resolveSecret = async () => {
      resolutions++;
      entered.resolve();
      await released.promise;
      return 'provider-secret';
    };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret);
    const active = invoke(original, 'identity');
    await entered.promise;
    await assert.rejects(invoke(original, 'overlap'),
      {code: 'RemoteCredentialBindingBusy'});
    assert.equal(closeHttpsCredentialBinding(binding), 'pending');
    assert.equal(closeHttpsCredentialBinding(binding), 'pending');
    released.resolve();
    await assert.rejects(active, {code: 'RemoteCredentialBindingRetiring'});
    assert.equal(setup.requests(), 0);
    assert.equal(resolutions, 1);
    assert.equal(setup.journal.recover().length, 1);
    assert.equal(setup.journal.recover()[0].outcome, 'failed');
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    await assert.rejects(invoke(original, 'new'),
      {code: 'RemoteCredentialBindingRetiring'});
  });

test('cleanup of a sent bound request waits for real socket retirement and preserves Unknown',
  async t => {
    const entered = deferred();
    const serverClosed = deferred();
    const setup = await fixture(t, {retain: true, onRequest(request) {
      request.socket.once('close', serverClosed.resolve);
      entered.resolve();
      return true;
    }});
    const original = scope(setup.origin);
    let resolutions = 0;
    const {binding, invoke} = boundFixture(setup, original, async () => {
      resolutions++; return 'provider-secret';
    });
    const active = invoke(original, 'identity');
    await entered.promise;
    assert.equal(closeHttpsCredentialBinding(binding), 'pending');
    await assert.rejects(active, {code: 'RemoteCredentialBindingRetiring'});
    await serverClosed.promise;
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(setup.journal.recover()[0].outcome, 'unknown');
    assert.equal(setup.requests(), 1);
    assert.equal(resolutions, 1);
  });

test('bound response loss preserves the same nominal Unknown without retry or re-resolution',
  async t => {
    const setup = await fixture(t, {retain: true, onRequest(request) {
      request.socket.destroy();
      return true;
    }});
    const original = scope(setup.origin);
    let resolutions = 0;
    const {binding, invoke} = boundFixture(setup, original, async () => {
      resolutions++; return 'provider-secret';
    });
    await assert.rejects(invoke(original, 'identity'), {code: 'ECONNRESET'});
    const use = setup.journal.recover()[0];
    assert.equal(use.outcome, 'unknown');
    await assert.rejects(invoke(original, 'identity'),
      {code: 'RemoteCredentialUseAlreadyClaimed'});
    assert.equal(setup.journal.recover()[0].useCid, use.useCid);
    assert.equal(setup.requests(), 1);
    assert.equal(resolutions, 1);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('private material ceiling is positive and applies to the complete UTF8 secret',
  async t => {
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      assert.equal(request.headers.authorization, 'Bearer é');
      response.end('{}');
      return true;
    }});
    const original = scope(setup.origin);
    for (const ceiling of [0, -1, NaN]) {
      assert.throws(() => boundFixture(setup, original, async () => 'é', ceiling),
        {code: 'InvalidRemoteCredentialBinding'});
    }
    const exact = boundFixture(setup, original, async () => 'é', 2);
    await exact.invoke(original, 'exact');
    assert.equal(closeHttpsCredentialBinding(exact.binding), 'closed');
    const over = boundFixture(setup, original, async () => 'é', 1);
    await assert.rejects(over.invoke(original, 'over'),
      {code: 'RemoteCredentialSecretLimitExceeded'});
    assert.equal(closeHttpsCredentialBinding(over.binding), 'closed');
    assert.equal(setup.requests(), 1);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome),
      ['succeeded', 'failed']);
  });


test('a private binding supplies no implicit identity operation or permission',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin);
    const identity = scope(setup.origin, 'account:identity');
    const grant = control.prepare(original);
    setup.journal.acceptGrant(setup.sign(grant), control);
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding} = boundFixture(setup, original, resolveSecret);
    await assert.rejects(call(setup, grant, identity, 'unregistered',
      {binding, resolveSecret}), {code: 'UnsupportedRemoteCredentialOperation'});
    await assert.rejects(call(setup, grant, identity, 'not-authorized', {
      binding, resolveSecret,
      operations: new Map([[identity.operation, {method: 'GET', path: '/identity'}]]),
    }));
    assert.equal(resolutions, 0);
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover().length, 0);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('revocation while awaiting identity response refuses the next page before resolving again',
  async t => {
    let revoke;
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      revoke();
      response.end('{"portal":7}');
      return true;
    }});
    const original = scope(setup.origin);
    const grant = control.prepare(original);
    setup.journal.acceptGrant(setup.sign(grant), control);
    revoke = () => setup.journal.revoke(control.identity(grant));
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding} = boundFixture(setup, original, resolveSecret);
    await call(setup, grant, original, 'identity', {binding, resolveSecret});
    await assert.rejects(call(setup, grant, original, 'page',
      {binding, resolveSecret}));
    assert.equal(resolutions, 1);
    assert.equal(setup.requests(), 1);
    assert.equal(setup.journal.recover().length, 1);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('physical current callback follows the resolver without receiving credential material', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const order = [];
  const resolveSecret = async () => { order.push('resolver'); return 'provider-secret'; };
  const {binding, invoke} = boundFixture(setup, original, resolveSecret);
  const cause = Object.assign(new Error('OriginalHostCurrentDenied'),
    {code: 'OriginalHostCurrentDenied'});
  await assert.rejects(invoke(original, 'host-denied', {
    currentBeforeSend: async (...args) => {
      assert.deepEqual(args, []); order.push('current'); throw cause;
    },
  }), error => error === cause);
  assert.deepEqual(order, ['resolver', 'current']);
  assert.equal(setup.requests(), 0);
  assert.equal(setup.journal.recover()[0].outcome, 'failed');
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('physical current callback cannot replace the final original journal authorization', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const grant = control.prepare(original);
  setup.journal.acceptGrant(setup.sign(grant), control);
  let resolutions = 0, current = 0;
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const {binding} = boundFixture(setup, original, resolveSecret);
  await assert.rejects(call(setup, grant, original, 'revoke-during-current', {
    binding, resolveSecret,
    currentBeforeSend: async () => {
      current++; await Promise.resolve(); setup.journal.revoke(control.identity(grant));
    },
  }));
  assert.equal(resolutions, 1); assert.equal(current, 1);
  assert.equal(setup.requests(), 0);
  assert.equal(setup.journal.recover()[0].outcome, 'failed');
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('physical current callback retains cleanup pending across its await without a send', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const entered = deferred(), released = deferred();
  let resolutions = 0;
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const {binding, invoke} = boundFixture(setup, original, resolveSecret);
  const result = invoke(original, 'close-during-current', {
    currentBeforeSend: async () => { entered.resolve(); await released.promise; },
  });
  await entered.promise;
  await assert.rejects(invoke(original, 'nested-current'),
    {code: 'RemoteCredentialBindingBusy'});
  assert.equal(setup.journal.recover().length, 1);
  assert.equal(closeHttpsCredentialBinding(binding), 'pending');
  assert.equal(setup.requests(), 0);
  released.resolve();
  await assert.rejects(result, {code: 'RemoteCredentialBindingRetiring'});
  assert.equal(resolutions, 1); assert.equal(setup.requests(), 0);
  assert.equal(setup.journal.recover()[0].outcome, 'failed');
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('physical current callback shape fails before a nominal claim or resolver lookup', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  let resolutions = 0;
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const {binding, invoke} = boundFixture(setup, original, resolveSecret);
  await assert.rejects(invoke(original, 'invalid-current', {currentBeforeSend: true}),
    {code: 'InvalidRemoteCredentialCall'});
  assert.equal(resolutions, 0); assert.equal(setup.requests(), 0);
  assert.equal(setup.journal.recover().length, 0);
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('physical current callback cancellation cannot send after its awaited check', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const controller = new AbortController();
  let resolutions = 0;
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const {binding, invoke} = boundFixture(setup, original, resolveSecret);
  await assert.rejects(invoke(original, 'cancel-during-current', {
    signal: controller.signal,
    currentBeforeSend: async () => {
      await Promise.resolve(); controller.abort();
    },
  }), error => error === controller.signal.reason);
  assert.equal(resolutions, 1); assert.equal(setup.requests(), 0);
  assert.equal(setup.journal.recover()[0].outcome, 'failed');
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('known changed binding refuses before a subsequent Host current callback', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  let material = 'provider-secret', resolutions = 0, currentChecks = 0;
  const resolveSecret = async () => { resolutions++; return material; };
  const {binding, invoke} = boundFixture(setup, original, resolveSecret);
  const currentBeforeSend = async () => { currentChecks++; };
  await invoke(original, 'original-identity', {currentBeforeSend});
  material = 'foreign-portal-secret';
  await assert.rejects(invoke(original, 'changed-before-current', {currentBeforeSend}),
    {code: 'RemoteCredentialBindingChanged'});
  assert.equal(currentChecks, 1); assert.equal(resolutions, 2);
  assert.equal(setup.requests(), 1);
  assert.deepEqual(setup.journal.recover().map(use => use.outcome), ['succeeded', 'failed']);
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('bounded binary invocation sends exact non-UTF8 bytes after the original current credential fence',
  async t => {
    const received = [];
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.once('end', () => {
        received.push({bytes: Buffer.concat(chunks), type: request.headers['content-type'],
          length: request.headers['content-length'], path: request.url});
        response.writeHead(201).end('{}');
      });
      return true;
    }});
    const original = scope(setup.origin, 'content:upload');
    const grant = control.prepare(original);
    setup.journal.acceptGrant(setup.sign(grant), control);
    const entered = deferred(), release = deferred();
    const resolveSecret = async () => { entered.resolve(); await release.promise; return 'provider-secret'; };
    const binding = openHttpsCredentialBinding({scope: original, control,
      journal: setup.journal, resolveSecret, maxSecretBytes: 64});
    const backing = Buffer.from([99, 0, 255, 192, 128, 13, 10, 98]);
    const invoke = () => invokeScopedCredentialOperation({
      authorization: {grant, scope: original, useId: 'original-binary-use'},
      credential: {binding, control, journal: setup.journal, resolveSecret,
        ca: setup.ca, now: () => 1_999_999_999_999},
      callResource: callHttpsCredentialResource, operation: original.operation,
      method: 'POST', path: '/upload', query: [['name', 'é%2F.bin']],
      bodyBytes: backing.subarray(1, 7), bodyMediaType: 'multipart/related; boundary="original"',
      maxRequestBytes: 6, maxResponseBytes: 128,
    });
    const pending = invoke();
    await entered.promise;
    backing.fill(77);
    assert.equal(setup.requests(), 0);
    release.resolve();
    const result = await pending;
    assert.equal(result.accepted, true);
    assert.equal(received.length, 1);
    assert.deepEqual([...received[0].bytes], [0, 255, 192, 128, 13, 10]);
    assert.equal(received[0].type, 'multipart/related; boundary="original"');
    assert.equal(received[0].length, '6');
    assert.equal(received[0].path, '/upload?name=e%CC%81%252F.bin');
    assert.equal(setup.journal.inspect(result.useCid).outcome, 'succeeded');
    await assert.rejects(invoke(), {code: 'RemoteCredentialUseAlreadyClaimed'});
    assert.equal(setup.requests(), 1);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('invalid binary limits and framing refuse before the real journal claim or secret resolution',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin, 'content:upload');
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret);
    const request = {method: 'PUT', path: '/upload', bodyBytes: Buffer.from([0, 255]),
      bodyMediaType: 'application/octet-stream', maxBodyBytes: 2};
    for (const [index, change] of [
      {maxBodyBytes: undefined}, {maxBodyBytes: 1}, {maxBodyBytes: -1},
      {maxBodyBytes: 3}, {body: '{}'}, {bodyMediaType: 'text/plain\r\nx-secret: value'},
      {bodyBytes: new Uint8Array(new SharedArrayBuffer(2))}, {method: 'DELETE'},
      {headers: [['content-type', 'text/plain']]},
    ].entries()) {
      await assert.rejects(invoke(original, `invalid-binary-${index}`, {
        maxRequestBytes: 2,
        operations: new Map([[original.operation, {...request, ...change}]]),
      }));
    }
    assert.equal(resolutions, 0);
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover().length, 0);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('binary response loss retains the original unknown use and never resends it',
  async t => {
    const received = [];
    const setup = await fixture(t, {retain: true, onRequest(request, response) {
      const chunks = [];
      request.on('data', chunk => chunks.push(chunk));
      request.once('end', () => {
        received.push(Buffer.concat(chunks));
        response.destroy();
      });
      return true;
    }});
    const original = scope(setup.origin, 'content:upload');
    const {binding, invoke} = boundFixture(setup, original, async () => 'provider-secret');
    const request = {method: 'PUT', path: '/upload', bodyBytes: Buffer.from([0, 255, 13, 10]),
      bodyMediaType: 'application/octet-stream', maxBodyBytes: 4};
    const options = {maxRequestBytes: 4,
      operations: new Map([[original.operation, request]])};
    await assert.rejects(invoke(original, 'binary-lost-reply', options));
    assert.equal(received.length, 1);
    assert.deepEqual([...received[0]], [0, 255, 13, 10]);
    const unknown = setup.journal.recover();
    assert.equal(unknown.length, 1);
    assert.equal(unknown[0].outcome, 'unknown');
    await assert.rejects(invoke(original, 'binary-lost-reply', options),
      {code: 'RemoteCredentialUseAlreadyClaimed'});
    assert.equal(setup.requests(), 1);
    assert.equal(setup.journal.recover()[0].useCid, unknown[0].useCid);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('retiring a binary request during secret resolution keeps pending custody and sends nothing',
  async t => {
    const setup = await fixture(t, {retain: true});
    const original = scope(setup.origin, 'content:upload');
    const entered = deferred(), released = deferred();
    const resolveSecret = async () => { entered.resolve(); await released.promise; return 'provider-secret'; };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret);
    const pending = invoke(original, 'retiring-binary', {maxRequestBytes: 2,
      operations: new Map([[original.operation, {method: 'POST', path: '/upload',
        bodyBytes: Buffer.from([0, 255]), bodyMediaType: 'application/octet-stream', maxBodyBytes: 2}]])});
    await entered.promise;
    assert.equal(closeHttpsCredentialBinding(binding), 'pending');
    assert.equal(setup.requests(), 0);
    released.resolve();
    await assert.rejects(pending, {code: 'RemoteCredentialBindingRetiring'});
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(setup.requests(), 0);
    assert.equal(setup.journal.recover()[0].outcome, 'failed');
  });

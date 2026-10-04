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
import {callHttpsCredentialResource} from
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

async function fixture(t) {
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
    await rm(root, {recursive: true, force: true});
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

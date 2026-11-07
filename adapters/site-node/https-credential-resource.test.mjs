import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
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
  openHttpsCredentialBinding, withHttpsCredentialRunResponseOriginal} from
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

async function fixture(t, {onRequest,
  retain = process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1'} = {}) {
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

test('Run response original retains the actual physical claim, request and bytes', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const prepared = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(prepared), control);
  let claimed;
  const journal = Object.freeze({...setup.journal, claim(...args) {
    claimed = setup.journal.claim(...args);
    return claimed;
  }});
  const response = await call({...setup, journal}, prepared, selected, 'captured',
    {retainRunResponseOriginal: true});
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  const digest = createHash('sha256').update('{"records":[1,2]}').digest('hex');
  const useCid = withHttpsCredentialRunResponseOriginal(response, control, journal, original => {
    assert.equal(original.grant, claimed.grant);
    assert.notEqual(original.grant, prepared);
    assert.equal(original.use, claimed.use);
    assert.equal(original.scope, selected);
    assert.equal(original.response, response);
    assert.equal(original.method, 'GET');
    assert.equal(original.path, '/records');
    assert.equal(original.requestBodyBytes, 0);
    assert.equal(original.responseSha256, digest);
    assert.equal(Object.hasOwn(original, 'secret'), false);
    return control.useIdentity(original.use);
  });
  assert.equal(useCid, response.useCid);
  assert.equal(setup.requests(), 1);
});

test('Run response original retains the exact immutable physical POST text without deriving it from length', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin, 'records:create');
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const body = '{"Name":" é 漢 ","order":["b","a","b"]}';
  const response = await call(setup, grant, selected, 'original-post', {
    retainRunResponseOriginal: true,
    operations: new Map([['records:create', Object.freeze({method: 'POST', path: '/mutate', body})]]),
  });
  withHttpsCredentialRunResponseOriginal(response, control, setup.journal, original => {
    assert.equal(original.requestBodyText, body);
    assert.equal(original.requestBodyBytes, Buffer.byteLength(body));
    assert.equal(original.method, 'POST');
    assert.equal(original.path, '/mutate');
    assert.equal(original.response, response);
    assert.equal(Object.isFrozen(original), true);
    assert.equal(Object.hasOwn(original, 'secret'), false);
  });
  assert.deepEqual(setup.mutationBodies(), [body]);
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  assert.equal(setup.requests(), 1);
});

test('Run response original retains the physical conditional request representation after caller mutation', async t => {
  let received;
  const setup = await fixture(t, {onRequest(request, response) {
    received = {accept: request.headers.accept,
      acceptEncoding: request.headers['accept-encoding'],
      ifMatch: request.headers['if-match']};
    response.writeHead(200, {etag: '"original-response"',
      'content-encoding': 'identity'});
    response.end('{}');
    return true;
  }});
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const headers = [['accept', 'application/json'],
    ['accept-encoding', 'identity'], ['if-match', '"original-target"']];
  const response = await call(setup, grant, selected, 'representation', {
    retainRunResponseOriginal: true,
    operations: new Map([['records:read', {method: 'GET', path: '/records',
      headers, responseHeaders: ['etag', 'content-encoding']}]]),
    resolveSecret: async () => {
      headers[0][1] = 'text/plain';
      headers[1][1] = 'gzip';
      headers[2][1] = '*';
      return 'provider-secret';
    },
  });
  const expected = {accept: 'application/json', acceptEncoding: 'identity',
    ifMatch: '"original-target"'};
  assert.deepEqual(received, expected);
  withHttpsCredentialRunResponseOriginal(response, control, setup.journal, facts => {
    assert.deepEqual(facts.requestRepresentation, expected);
    assert.equal(Object.isFrozen(facts.requestRepresentation), true);
    assert.throws(() => { facts.requestRepresentation.ifMatch = '*'; }, TypeError);
    assert.deepEqual(facts.response.headers, [['etag', '"original-response"'],
      ['content-encoding', 'identity']]);
    assert.equal(Object.isFrozen(facts.response.headers), true);
    assert.equal(Object.isFrozen(facts.response.headers[0]), true);
    assert.equal(Object.hasOwn(facts.requestRepresentation, 'authorization'), false);
    assert.equal(Object.hasOwn(facts.requestRepresentation, 'secret'), false);
  });
  assert.equal(Object.hasOwn(response, 'requestRepresentation'), false);
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  assert.equal(setup.requests(), 1);
});

test('Run response original retains the actual default Accept without inventing absent conditions', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const response = await call(setup, grant, selected, 'default-representation',
    {retainRunResponseOriginal: true});
  withHttpsCredentialRunResponseOriginal(response, control, setup.journal, facts => {
    assert.deepEqual(facts.requestRepresentation, {accept: 'application/json',
      acceptEncoding: undefined, ifMatch: undefined});
    assert.equal(Object.isFrozen(facts.requestRepresentation), true);
  });
  assert.equal(setup.requests(), 1);
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
});

test('Run response original retains representation on the original fenced acquisition', async t => {
  let received;
  const setup = await fixture(t, {onRequest(request, response) {
    received = {accept: request.headers.accept,
      acceptEncoding: request.headers['accept-encoding'],
      ifMatch: request.headers['if-match']};
    response.end('{}');
    return true;
  }});
  const selected = scope(setup.origin);
  const {binding, invoke} = boundFixture(setup, selected,
    async () => 'provider-secret');
  try {
    const response = await invoke(selected, 'fenced-representation', {
      retainRunResponseOriginal: true,
      operations: new Map([['records:read', {method: 'GET', path: '/records',
        headers: [['accept', 'application/json'], ['accept-encoding', 'identity'],
          ['if-match', '"fenced-original"']]}]]),
    });
    const expected = {accept: 'application/json', acceptEncoding: 'identity',
      ifMatch: '"fenced-original"'};
    assert.deepEqual(received, expected);
    withHttpsCredentialRunResponseOriginal(response, control, setup.journal, facts => {
      assert.deepEqual(facts.requestRepresentation, expected);
      assert.equal(Object.isFrozen(facts.requestRepresentation), true);
    });
    assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
    assert.equal(setup.requests(), 1);
  } finally {
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  }
});

test('Run response original refuses copies, foreign owners and default uncaptured responses', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const captured = await call(setup, grant, selected, 'captured',
    {retainRunResponseOriginal: true});
  const uncaptured = await call(setup, grant, selected, 'ordinary');
  const absent = {code: 'RemoteCredentialRunResponseOriginalUnavailable'};
  for (const [response, ownerControl, ownerJournal] of [
    [{...captured}, control, setup.journal],
    [captured, {...control}, setup.journal],
    [captured, control, {...setup.journal}],
    [uncaptured, control, setup.journal],
  ]) assert.throws(() => withHttpsCredentialRunResponseOriginal(response,
    ownerControl, ownerJournal, () => assert.fail('foreign receiver')), absent);
  assert.deepEqual(Object.keys(captured), Object.keys(uncaptured));
  assert.equal(setup.requests(), 2);
});

test('Run response original permanently refuses changed bytes without changing the Journal', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const response = await call(setup, grant, selected, 'mutated',
    {retainRunResponseOriginal: true});
  const byte = response.body[0];
  response.body[0] ^= 1;
  const read = () => withHttpsCredentialRunResponseOriginal(response,
    control, setup.journal, () => assert.fail('changed receiver'));
  assert.throws(read, {code: 'RemoteCredentialRunResponseChanged'});
  response.body[0] = byte;
  assert.throws(read, {code: 'RemoteCredentialRunResponseChanged'});
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  assert.equal(setup.requests(), 1);
});

test('Run response original consumer failure cannot reclassify or resend a confirmed response', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const response = await call(setup, grant, selected, 'observer',
    {retainRunResponseOriginal: true});
  const failure = new Error('OriginalConsumerFailure');
  assert.throws(() => withHttpsCredentialRunResponseOriginal(response, control,
    setup.journal, () => {throw failure;}), error => error === failure);
  assert.throws(() => withHttpsCredentialRunResponseOriginal(response, control,
    setup.journal, async () => undefined), {code: 'InvalidRemoteCredentialRunResponseConsumer'});
  assert.equal(withHttpsCredentialRunResponseOriginal(response, control,
    setup.journal, original => control.useIdentity(original.use)), response.useCid);
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  await assert.rejects(call(setup, grant, selected, 'observer',
    {retainRunResponseOriginal: true}), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(setup.requests(), 1);
});

test('Run response original lost reply retains Unknown and provides no replacement original', async t => {
  const setup = await fixture(t, {onRequest(request) {request.socket.destroy(); return true;}});
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  await assert.rejects(call(setup, grant, selected, 'lost-original',
    {retainRunResponseOriginal: true}), {code: 'ECONNRESET'});
  assert.equal(setup.journal.recover().length, 1);
  assert.equal(setup.journal.recover()[0].outcome, 'unknown');
  await assert.rejects(call(setup, grant, selected, 'lost-original',
    {retainRunResponseOriginal: true}), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.throws(() => withHttpsCredentialRunResponseOriginal({}, control,
    setup.journal, () => assert.fail('lost response receiver')),
  {code: 'RemoteCredentialRunResponseOriginalUnavailable'});
  assert.equal(setup.requests(), 1);
});

test('Run response original unconfirmed outcome COMMIT is not repeated or published', async t => {
  const setup = await fixture(t);
  const selected = scope(setup.origin);
  const grant = control.prepare(selected);
  setup.journal.acceptGrant(setup.sign(grant), control);
  let finishes = 0;
  const failure = new Error('OriginalOutcomeCommitUnknown');
  const journal = Object.freeze({...setup.journal, finish() {finishes++; throw failure;}});
  await assert.rejects(call({...setup, journal}, grant, selected, 'commit-unknown',
    {retainRunResponseOriginal: true}), error => error === failure);
  assert.equal(finishes, 1);
  const retained = setup.journal.recover();
  assert.equal(retained.length, 1);
  assert.equal(retained[0].outcome, 'claimed');
  await assert.rejects(call({...setup, journal}, grant, selected, 'commit-unknown',
    {retainRunResponseOriginal: true}), {code: 'RemoteCredentialUseAlreadyClaimed'});
  assert.equal(finishes, 1);
  assert.equal(setup.requests(), 1);
});

test('Run response original refuses the actual installation-metadata purpose before claim or I/O', async t => {
  const setup = await fixture(t);
  // Actual Common DATA fixtures, not an operational metadata issuer.
  const metadata = runtimeCore(moon).installationPreparationMetadata();
  const subject = metadata.prepareSubject({accountConfigurationCid: cid('1'),
    accountId: 'account-a', connection: 'crm', connectorRegistration: 'salesforce',
    connectorRevision: 'salesforce/0.1', declarationSourceCid: cid('2'),
    installationRequestId: 'publication-original', principal: 'principal-a',
    runtimeBundleCid: cid('a'), siteGeneration: 4, siteKey: 'site-a'});
  const selected = metadata.prepareScope(subject, {metadataOccurrenceId: 'describe-a',
    operation: 'salesforce:catalog:describe', resourceOrigin: setup.origin,
    requestMethod: 'GET', requestPath: '/records',
    requestBodyCid: `sha256:${createHash('sha256').update('').digest('hex')}`});
  const metadataControl = metadata.forSubject(subject);
  const grant = metadataControl.prepare({issuerAuthority: 'credential-authority-a',
    scope: selected, expiresUnixMilliseconds: 2_000_000_000_000n, maxUses: 1});
  const resolveSecret = async () => 'provider-secret';
  const binding = openHttpsCredentialBinding({scope: selected,
    control: metadataControl, journal: setup.journal, resolveSecret,
    maxSecretBytes: 64, assertCurrent() {}});
  try {
    // The existing missing-binding refusal still precedes purpose admission.
    await assert.rejects(call(setup, grant, selected, 'wrong-purpose',
      {control: metadataControl, retainRunResponseOriginal: true}),
    {code: 'InvalidRemoteCredentialBinding'});
    await assert.rejects(call(setup, grant, selected, 'bound-wrong-purpose',
      {control: metadataControl, binding, resolveSecret, retainRunResponseOriginal: true}),
    {code: 'InvalidRemoteCredentialRunResponseCapture'});
    assert.equal(setup.journal.recover().length, 0);
    assert.equal(setup.requests(), 0);
  } finally {
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    metadata.retireMetadataView();
  }
});

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


function boundFixture(setup, grantScope, resolveSecret, maxSecretBytes = 64,
  secretPresentation) {
  const binding = openHttpsCredentialBinding({scope: grantScope, control,
    journal: setup.journal, resolveSecret, maxSecretBytes, secretPresentation});
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

test('kintone token presentation uses the retained secret for separately authorized form and page requests',
  async t => {
    const seen = [];
    const setup = await fixture(t, {onRequest(request, response) {
      const originalToken = request.headers['x-cybozu-api-token'] === 'provider-secret';
      const otherCredential = request.headers.authorization !== undefined ||
        request.headers['x-cybozu-authorization'] !== undefined;
      seen.push({path: request.url, originalToken, otherCredential});
      response.writeHead(originalToken && !otherCredential ? 200 : 401,
        {'content-type': 'application/json'});
      response.end('{"records":[]}');
      return true;
    }});
    const original = Object.freeze({...scope(setup.origin, 'form:read'),
      connectorRegistration: 'kintone', connectorRevision: 'kintone/1'});
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const binding = openHttpsCredentialBinding({scope: original, control,
      journal: setup.journal, resolveSecret, maxSecretBytes: 64,
      secretPresentation: 'kintone-api-token'});
    t.after(() => assert.equal(closeHttpsCredentialBinding(binding), 'closed'));
    assert.deepEqual(Reflect.ownKeys(binding), []);
    for (const [operation, path] of [['form:read', '/k/v1/app/form/fields.json?app=7'],
      ['records:read', '/k/v1/records.json?app=7']]) {
      const selected = Object.freeze({...original, operation});
      const grant = control.prepare(selected);
      setup.journal.acceptGrant(setup.sign(grant), control);
      const response = await call(setup, grant, selected, `kintone-${operation}`, {
        binding, resolveSecret,
        operations: new Map([[operation, {method: 'GET', path}]]),
      });
      assert.equal(response.accepted, true);
      assert.equal(response.body.toString(), '{"records":[]}');
      assert.equal(JSON.stringify(response).includes('provider-secret'), false);
    }
    assert.deepEqual(seen, [
      {path: '/k/v1/app/form/fields.json?app=7', originalToken: true, otherCredential: false},
      {path: '/k/v1/records.json?app=7', originalToken: true, otherCredential: false},
    ]);
    assert.equal(resolutions, 2);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome),
      ['succeeded', 'succeeded']);
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
  });

test('kintone presentation refuses foreign registration and unknown presentation before resolution or claim',
  async t => {
    const setup = await fixture(t);
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    for (const overrides of [
      {scope: scope(setup.origin)},
      {secretPresentation: 'x-cybozu-authorization'},
      {secretPresentation: 'KINTONE-API-TOKEN'},
      {secretPresentation: null},
      {authentication: {}},
    ]) {
      assert.throws(() => openHttpsCredentialBinding({scope: original, control,
        journal: setup.journal, resolveSecret, maxSecretBytes: 64,
        secretPresentation: 'kintone-api-token', ...overrides}),
      {code: 'InvalidRemoteCredentialSecretPresentation'});
    }
    assert.equal(resolutions, 0);
    assert.equal(setup.requests(), 0);
    assert.deepEqual(setup.journal.recover(), []);
  });

test('kintone credential headers cannot be supplied or observed by the provider before claim',
  async t => {
    const setup = await fixture(t);
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret, 64,
      'kintone-api-token');
    t.after(() => assert.equal(closeHttpsCredentialBinding(binding), 'closed'));
    for (const name of ['x-cybozu-api-token', 'x-cybozu-authorization']) {
      for (const [field, value, code] of [
        ['headers', [[name, 'replacement-secret']], 'ReservedHttpRequestHeader'],
        ['responseHeaders', [name], 'InvalidHttpResponseHeaderNames'],
      ]) {
        await assert.rejects(invoke(original, `${name}-${field}`, {
          operations: new Map([[original.operation,
            {method: 'GET', path: '/records', [field]: value}]]),
        }), {code});
      }
    }
    assert.equal(resolutions, 0);
    assert.equal(setup.requests(), 0);
    assert.deepEqual(setup.journal.recover(), []);
  });

test('kintone rotation across resolver await refuses replacement and permanently retains the original binding',
  async t => {
    const seen = [];
    const setup = await fixture(t, {onRequest(request, response) {
      seen.push(request.headers['x-cybozu-api-token'] === 'provider-secret');
      response.end('{}');
      return true;
    }});
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    const entered = deferred(), released = deferred();
    let current = 'provider-secret', resolutions = 0;
    const resolveSecret = async () => {
      if (++resolutions === 2) { entered.resolve(); await released.promise; }
      return current;
    };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret, 64,
      'kintone-api-token');
    t.after(() => assert.equal(closeHttpsCredentialBinding(binding), 'closed'));
    await invoke(original, 'form');
    const pending = invoke(original, 'page');
    await entered.promise;
    current = 'other-app-token';
    released.resolve();
    await assert.rejects(pending, {code: 'RemoteCredentialBindingChanged'});
    await assert.rejects(invoke(original, 'no-reprobe'),
      {code: 'RemoteCredentialBindingChanged'});
    assert.deepEqual(seen, [true]);
    assert.equal(resolutions, 2);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome),
      ['succeeded', 'failed']);
  });

test('kintone retained token cannot bypass current revocation or expiry after the Host await',
  async t => {
    const setup = await fixture(t);
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    for (const mode of ['revoked', 'expired']) {
      const selected = {...original, operation: mode};
      const grant = control.prepare(selected);
      setup.journal.acceptGrant(setup.sign(grant), control);
      const resolveSecret = async () => 'provider-secret';
      const {binding, invoke} = boundFixture(setup, selected, resolveSecret, 64,
        'kintone-api-token');
      let observed = 1_999_999_999_999;
      await assert.rejects(invoke(selected, mode, {
        operations: new Map([[mode, {method: 'GET', path: '/records'}]]),
        now: () => observed,
        currentBeforeSend: async () => {
          await Promise.resolve();
          if (mode === 'revoked') setup.journal.revoke(control.identity(grant));
          else observed = 2_000_000_000_000;
        },
      }));
      assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    }
    assert.equal(setup.requests(), 0);
    assert.deepEqual(setup.journal.recover().map(use => use.outcome), ['failed', 'failed']);
  });

test('kintone lost response retains the original Unknown use and refuses same-use resend',
  async t => {
    const setup = await fixture(t, {onRequest(request) {
      request.socket.destroy();
      return true;
    }});
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    let resolutions = 0;
    const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
    const {binding, invoke} = boundFixture(setup, original, resolveSecret, 64,
      'kintone-api-token');
    t.after(() => assert.equal(closeHttpsCredentialBinding(binding), 'closed'));
    await assert.rejects(invoke(original, 'lost-page'), {code: 'ECONNRESET'});
    const [unknown] = setup.journal.recover();
    assert.equal(unknown.outcome, 'unknown');
    await assert.rejects(invoke(original, 'lost-page'),
      {code: 'RemoteCredentialUseAlreadyClaimed'});
    assert.equal(setup.journal.recover()[0].useCid, unknown.useCid);
    assert.equal(setup.journal.recover()[0].outcome, 'unknown');
    assert.equal(setup.requests(), 1);
    assert.equal(resolutions, 1);
  });

test('kintone cleanup remains pending until the original sent request and socket close',
  async t => {
    const entered = deferred(), serverClosed = deferred();
    const setup = await fixture(t, {onRequest(request) {
      request.socket.once('close', serverClosed.resolve);
      entered.resolve();
      return true;
    }});
    const original = {...scope(setup.origin), connectorRegistration: 'kintone'};
    const resolveSecret = async () => 'provider-secret';
    const {binding, invoke} = boundFixture(setup, original, resolveSecret, 64,
      'kintone-api-token');
    const active = invoke(original, 'held-page');
    await entered.promise;
    assert.equal(closeHttpsCredentialBinding(binding), 'pending');
    await assert.rejects(active, {code: 'RemoteCredentialBindingRetiring'});
    await serverClosed.promise;
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(closeHttpsCredentialBinding(binding), 'closed');
    assert.equal(setup.journal.recover()[0].outcome, 'unknown');
    await assert.rejects(invoke(original, 'after-close'),
      {code: 'RemoteCredentialBindingRetiring'});
    assert.equal(setup.requests(), 1);
  });

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

test('Run binding current fence refuses stale originals before claim or secret lookup', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const grant = control.prepare(original);
  setup.journal.acceptGrant(setup.sign(grant), control);
  let resolutions = 0, observations = 0;
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const cause = Object.assign(new Error('OriginalRunSiteStale'), {code: 'OriginalRunSiteStale'});
  const binding = openHttpsCredentialBinding({scope: original, control,
    journal: setup.journal, resolveSecret, maxSecretBytes: 64,
    assertCurrent() { throw cause; }});
  t.after(() => assert.equal(closeHttpsCredentialBinding(binding), 'closed'));
  await assert.rejects(call(setup, grant, original, 'stale-before-claim', {
    binding, resolveSecret, currentBeforeSend: async () => { observations++; },
  }), error => error === cause);
  assert.equal(resolutions, 0); assert.equal(observations, 0);
  assert.equal(setup.requests(), 0); assert.equal(setup.journal.recover().length, 0);
});

function fencedRun(setup, original, assertCurrent, resolveSecret = async () => 'provider-secret') {
  const grant = control.prepare(original);
  setup.journal.acceptGrant(setup.sign(grant), control);
  const binding = openHttpsCredentialBinding({scope: original, control,
    journal: setup.journal, resolveSecret, maxSecretBytes: 64, assertCurrent});
  return {grant, binding, invoke: (useId, currentBeforeSend, overrides = {}) =>
    call(setup, grant, original, useId, {binding, resolveSecret,
      currentBeforeSend, ...overrides})};
}

test('Run binding current fence preserves original callback and confirmed claim correspondence', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin), order = [];
  const f = fencedRun(setup, original, function (...args) {
    assert.equal(this, undefined); assert.deepEqual(args, []); order.push('fence');
  }, async () => { order.push('resolver'); return 'provider-secret'; });
  t.after(() => assert.equal(closeHttpsCredentialBinding(f.binding), 'closed'));
  const response = await f.invoke('fenced-success', async function (...args) {
    assert.equal(this, undefined); assert.deepEqual(args, []); order.push('observe');
  }, {retainRunResponseOriginal: true});
  assert.deepEqual(order, ['fence', 'observe', 'fence', 'resolver', 'observe',
    'fence', 'fence', 'observe', 'fence']);
  assert.equal(setup.requests(), 1);
  assert.equal(setup.journal.inspect(response.useCid).outcome, 'succeeded');
  withHttpsCredentialRunResponseOriginal(response, control, setup.journal, facts => {
    assert.notEqual(facts.grant, f.grant);
    assert.equal(control.useIdentity(facts.use), response.useCid);
    assert.equal(facts.scope, original); assert.equal(facts.response, response);
  });
});

test('Run binding current fence requires synchronous void and the awaited original observation', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin);
  const resolveSecret = async () => { assert.fail('No secret lookup'); };
  assert.throws(() => openHttpsCredentialBinding({scope: original, control,
    journal: setup.journal, resolveSecret, maxSecretBytes: 64, assertCurrent: true}),
  {code: 'InvalidRemoteCredentialBinding'});
  for (const assertCurrent of [() => true, async () => {}, () => Promise.reject(new Error('OriginalFence'))]) {
    const f = fencedRun(setup, original, assertCurrent, resolveSecret);
    await assert.rejects(f.invoke('invalid-fence', async () => {}),
      {code: 'InvalidRemoteCredentialCurrentFence'});
    assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  }
  const f = fencedRun(setup, original, () => {}, resolveSecret);
  await assert.rejects(f.invoke('missing-observation'), {code: 'InvalidRemoteCredentialCall'});
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(setup.requests(), 0); assert.equal(setup.journal.recover().length, 0);
});

test('Run binding current fence observes revocation during admission and resolver awaits', async t => {
  for (const revokedAt of [1, 2]) {
    const setup = await fixture(t, {retain: true});
    let current = true, observations = 0, resolutions = 0;
    const cause = Object.assign(new Error('OriginalRunAuthorityRevoked'), {code: 'OriginalRunAuthorityRevoked'});
    const f = fencedRun(setup, scope(setup.origin), () => { if (!current) throw cause; },
      async () => { resolutions++; return 'provider-secret'; });
    await assert.rejects(f.invoke(`revoked-${revokedAt}`, async () => {
      await Promise.resolve(); if (++observations === revokedAt) current = false;
    }), error => error === cause);
    assert.equal(resolutions, revokedAt - 1); assert.equal(setup.requests(), 0);
    assert.deepEqual(setup.journal.recover().map(row => row.outcome), revokedAt === 1 ? [] : ['failed']);
    assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  }
});

test('Run binding current fence refuses response disclosure after the final awaited revocation', async t => {
  const setup = await fixture(t, {retain: true});
  let current = true, observations = 0, resolutions = 0;
  const cause = Object.assign(new Error('OriginalResponseAuthorityRevoked'), {code: 'OriginalResponseAuthorityRevoked'});
  const f = fencedRun(setup, scope(setup.origin), () => { if (!current) throw cause; },
    async () => { resolutions++; return 'provider-secret'; });
  const observe = async () => { await Promise.resolve(); if (++observations === 3) current = false; };
  await assert.rejects(f.invoke('response-revoked', observe, {retainRunResponseOriginal: true}),
    error => error === cause);
  current = true; // Restored DATA cannot clear the original unknown attempt.
  await assert.rejects(f.invoke('no-replacement', observe), error => error === cause);
  assert.equal(setup.requests(), 1); assert.equal(resolutions, 1); assert.equal(observations, 3);
  assert.deepEqual(setup.journal.recover().map(row => row.outcome), ['unknown']);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
});

test('Run binding current fence keeps original Journal authorization after the response await', async t => {
  const setup = await fixture(t, {retain: true});
  const f = fencedRun(setup, scope(setup.origin), () => {});
  let observations = 0;
  await assert.rejects(f.invoke('journal-revoked', async () => {
    if (++observations === 3) setup.journal.revoke(control.identity(f.grant));
  }));
  assert.equal(observations, 3); assert.equal(setup.requests(), 1);
  assert.deepEqual(setup.journal.recover().map(row => row.outcome), ['unknown']);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
});

test('Run binding current fence holds cleanup pending through the original response observation', async t => {
  const setup = await fixture(t, {retain: true});
  const f = fencedRun(setup, scope(setup.origin), () => {});
  const entered = deferred(), released = deferred();
  let observations = 0;
  const result = f.invoke('response-held', async () => {
    if (++observations === 3) { entered.resolve(); await released.promise; }
  });
  await entered.promise;
  assert.equal(setup.requests(), 1); assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  assert.equal(closeHttpsCredentialBinding(f.binding), 'pending');
  await assert.rejects(f.invoke('no-resend', async () => {}), {code: 'RemoteCredentialBindingRetiring'});
  released.resolve();
  await assert.rejects(result, {code: 'RemoteCredentialBindingRetiring'});
  assert.deepEqual(setup.journal.recover().map(row => row.outcome), ['unknown']);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
  assert.equal(observations, 3); assert.equal(setup.requests(), 1);
});

test('Run binding current fence retains an unconfirmed original outcome without another claim or COMMIT', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin), prepared = control.prepare(original);
  setup.journal.acceptGrant(setup.sign(prepared), control);
  let claims = 0, finishes = 0, resolutions = 0;
  const cause = Object.assign(new Error('OriginalOutcomeCommitUnconfirmed'), {code: 'OriginalOutcomeCommitUnconfirmed'});
  const journal = Object.freeze({...setup.journal,
    claim(...args) { claims++; return setup.journal.claim(...args); },
    finish() { finishes++; throw cause; },
  });
  const resolveSecret = async () => { resolutions++; return 'provider-secret'; };
  const binding = openHttpsCredentialBinding({scope: original, control, journal,
    resolveSecret, maxSecretBytes: 64, assertCurrent: () => {}});
  const invoke = useId => call({...setup, journal}, prepared, original, useId,
    {binding, resolveSecret, currentBeforeSend: async () => {}});
  await assert.rejects(invoke('commit-unconfirmed'), error => error === cause);
  await assert.rejects(invoke('no-new-attempt'), error => error === cause);
  assert.equal(claims, 1); assert.equal(finishes, 1); assert.equal(resolutions, 1);
  assert.equal(setup.requests(), 1);
  assert.deepEqual(setup.journal.recover().map(row => row.outcome), ['claimed']);
  assert.equal(closeHttpsCredentialBinding(binding), 'closed');
});

test('Run binding current fence cannot replace retained material during a later resolver await', async t => {
  const setup = await fixture(t, {retain: true});
  const original = scope(setup.origin), entered = deferred(), released = deferred();
  let material = 'provider-secret', resolutions = 0, observations = 0;
  const f = fencedRun(setup, original, () => {}, async () => {
    if (++resolutions === 2) { entered.resolve(); await released.promise; }
    return material;
  });
  const observe = async () => { observations++; };
  await f.invoke('original-material', observe);
  const result = f.invoke('rotating-material', observe);
  await entered.promise;
  material = 'other-account-secret'; released.resolve();
  await assert.rejects(result, {code: 'RemoteCredentialBindingChanged'});
  await assert.rejects(f.invoke('no-relookup', observe), {code: 'RemoteCredentialBindingChanged'});
  assert.equal(resolutions, 2); assert.equal(observations, 4); assert.equal(setup.requests(), 1);
  assert.deepEqual(setup.journal.recover().map(row => row.outcome), ['succeeded', 'failed']);
  assert.equal(closeHttpsCredentialBinding(f.binding), 'closed');
});


test('same-original Resource bindings reject replacement secret before the first data send', async t => {
  const setup = await fixture(t, {retain:true});
  const parentScope=scope(setup.origin),childScope=scope(setup.origin,'metadata:read');
  const parentGrant=control.prepare(parentScope),childGrant=control.prepare(childScope);
  for(const grant of [parentGrant,childGrant])setup.journal.acceptGrant(setup.sign(grant),control);
  let material='provider-secret',resolutions=0;
  const resolveSecret=async()=>{resolutions++;return material;};
  const parent=openHttpsCredentialBinding({scope:parentScope,control,journal:setup.journal,
    resolveSecret,maxSecretBytes:64,assertCurrent(){}});
  const child=openHttpsCredentialBinding({scope:childScope,control,journal:setup.journal,
    resolveSecret,maxSecretBytes:64,assertCurrent(){},originalSecretBinding:parent});
  try {
    const metadataOperations=new Map([['metadata:read',Object.freeze({method:'GET',path:'/records'})]]);
    await call(setup,childGrant,childScope,'original-metadata',{binding:child,resolveSecret,
      operations:metadataOperations,currentBeforeSend:async()=>{}});
    material='foreign-account-secret';
    await assert.rejects(call(setup,parentGrant,parentScope,'refused-data',
      {binding:parent,resolveSecret,currentBeforeSend:async()=>{}}),{code:'RemoteCredentialBindingChanged'});
    assert.equal(setup.requests(),1);assert.equal(resolutions,2);
  } finally {
    assert.equal(closeHttpsCredentialBinding(child),'closed');
    assert.equal(closeHttpsCredentialBinding(parent),'closed');
  }
});

test('same-original secret association keeps independent close/current and refuses foreign binding provenance', async t => {
  const setup=await fixture(t,{retain:true}),original=scope(setup.origin);
  const resolveSecret=async()=>{assert.fail('No secret lookup in custody-only control');};
  const options={scope:original,control,journal:setup.journal,resolveSecret,maxSecretBytes:64,assertCurrent(){}};
  const parent=openHttpsCredentialBinding(options);
  assert.throws(()=>openHttpsCredentialBinding({...options,originalSecretBinding:{}}),{code:'ForeignRemoteCredentialSecretOriginal'});
  assert.throws(()=>openHttpsCredentialBinding({...options,scope:{...original,namespaceId:'other'},
    originalSecretBinding:parent}),{code:'ForeignRemoteCredentialSecretOriginal'});
  const child=openHttpsCredentialBinding({...options,originalSecretBinding:parent});
  assert.equal(closeHttpsCredentialBinding(parent),'pending');
  assert.equal(closeHttpsCredentialBinding(child),'closed');
  assert.equal(closeHttpsCredentialBinding(parent),'closed');
  assert.equal(setup.requests(),0);assert.equal(setup.journal.recover().length,0);
});


test('same-original secret association requires both original current fences without resolving a secret', async t => {
  const setup=await fixture(t,{retain:true}),original=scope(setup.origin);
  const resolveSecret=async()=>{assert.fail('No resolver during original association');};
  const options={scope:original,control,journal:setup.journal,resolveSecret,maxSecretBytes:64};
  const unfenced=openHttpsCredentialBinding(options);
  assert.throws(()=>openHttpsCredentialBinding({...options,assertCurrent(){},originalSecretBinding:unfenced}),
    {code:'ForeignRemoteCredentialSecretOriginal'});
  assert.equal(closeHttpsCredentialBinding(unfenced),'closed');
  const parent=openHttpsCredentialBinding({...options,assertCurrent(){}});
  assert.throws(()=>openHttpsCredentialBinding({...options,originalSecretBinding:parent}),
    {code:'ForeignRemoteCredentialSecretOriginal'});
  assert.equal(closeHttpsCredentialBinding(parent),'closed');
  assert.equal(setup.requests(),0);assert.equal(setup.journal.recover().length,0);
});

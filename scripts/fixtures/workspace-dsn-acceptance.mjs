// The same independent public-path fixture is used from repository source and
// an external packed installation. Product imports are supplied by that entry.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';

const program = {version: 'actql/0.1', id: 'workspace-connection-values',
  stages: [{id: 'source', inputs: {}, steps: [{values: {
    schema: {id: {type: 'number', nullable: false}}, rows: [{id: 1}, {id: 2}]},
  as: 'selected'}], results: {rows: {from: 'selected', fields: ['id']}}}],
  results: {answer: {from: {stage: 'source', result: 'rows'}}}};

export async function exerciseWorkspaceConnection({directory, sdk, node, openHost}) {
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: directory, stdio: 'ignore'});
  const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(directory, name))));
  const originalCAs = getCACertificates('default');
  setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
  const keys = generateKeyPairSync('ed25519');
  const principal = userInfo().username;
  const counts = {A: 0, B: 0};
  const credentials = new Map([
    ['fixture-A:+/@?#%', 'A'], ['fixture-A-refreshed', 'A'], ['fixture-B', 'B'],
  ]);
  const clients = [], hosts = [];
  let server;
  const authorization = label => ({
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
      account_id: 'workspace-fixture', entries: [{entry_id: 'values-write', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer', principalId: principal,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
    observe(event) {if (event === 'computed') counts[label]++;},
  });
  try {
    for (const label of ['A', 'B']) {
      hosts.push(await openHost({directory: join(directory, `host-${label}`),
        workspaceId: `workspace-${label}`, authorization: authorization(label),
        authenticate: header => credentials.get(header?.slice('Bearer '.length)) === label
          ? principal : undefined}));
    }
    server = createServer({key, cert}, (request, response) => {
      // Select the existing installed owner from the verified fixture
      // credential's immutable scope, never from the submitted assertion.
      const label = credentials.get(request.headers.authorization?.slice('Bearer '.length));
      return hosts[label === 'B' ? 1 : 0].handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const endpoint = `https://localhost:${server.address().port}/`;
    const uri = label => `actql://localhost:${server.address().port}/workspace-${label}`;
    const secretDsn = `actql://token:${encodeURIComponent('fixture-A:+/@?#%')}@localhost:${server.address().port}/workspace-A`;
    const a = await node.connect(secretDsn); clients.push(a);
    let refreshed = 'fixture-A-refreshed';
    const rotating = await sdk.connect(uri('A'), {token: async () => refreshed}); clients.push(rotating);
    const b = await sdk.connect(uri('B'), {token: 'fixture-B'}); clients.push(b);
    assert.equal(a.profile.workspaceId, 'workspace-A');
    assert.equal(b.profile.workspaceId, 'workspace-B');
    // Legacy Local profile scopeRef can name the principal; do not invent
    // a Workspace-to-scope conversion. Actual Run refs retain owner scopes.
    const [runA, runB] = await Promise.all([
      a.start(program, {requestId: 'same-business-id'}),
      b.start(program, {requestId: 'same-business-id'}),
    ]);
    assert.equal((await runA.wait()).status, 'succeeded');
    assert.equal((await runB.wait()).status, 'succeeded');
    assert.notEqual(runA.ref.authorityScopeCid, runB.ref.authorityScopeCid);
    assert.equal(runA.ref.namespaceId, 'local'); // Not the service Workspace ID.
    assert.deepEqual(await runA.result('answer').all(), [{id: 1}, {id: 2}]);
    assert.deepEqual(await runB.result('answer').all(), [{id: 1}, {id: 2}]);
    assert.deepEqual(counts, {A: 1, B: 1});
    const original = sdk.getSubmissionInput(runA);
    assert.equal(original.lookupContext.endpoint, endpoint);
    assert.equal(original.connection.workspaceId, 'workspace-A');
    assert.equal(JSON.stringify(original).includes('fixture-A'), false);
    assert.deepEqual((await rotating.lookupRequest('same-business-id')).ref, runA.ref);
    assert.deepEqual((await rotating.attach(runA.ref)).ref, runA.ref);
    // A refreshed credential for the same authenticated principal but another
    // Workspace cannot retarget a new submit, request lookup or saved Run.
    refreshed = 'fixture-B';
    for (const operation of [
      () => rotating.start(program, {requestId: 'must-not-start'}),
      () => rotating.lookupRequest('same-business-id'),
      () => rotating.attach(runB.ref),
    ]) await assert.rejects(operation(), {code: 'ClientConnectionDenied'});
    assert.deepEqual(counts, {A: 1, B: 1});
    refreshed = 'fixture-A-refreshed';
    const restored = await rotating.attach(runA.ref);
    assert.deepEqual(await restored.result('answer').all(), [{id: 1}, {id: 2}]);
    const replay = await rotating.start(program, {requestId: 'same-business-id'});
    assert.deepEqual(replay.ref, runA.ref);
    assert.deepEqual(counts, {A: 1, B: 1});
    await assert.rejects(sdk.connect(uri('B'), {token: 'fixture-A-refreshed'}),
      {code: 'ClientConnectionDenied'});
    // The original endpoint API remains usable without an unsolicited echo.
    const legacy = await sdk.connect({mode: 'remote', endpoint, token: 'fixture-A-refreshed'});
    clients.push(legacy);
    assert.equal(Object.hasOwn(legacy.profile, 'workspaceId'), false);
    assert.deepEqual((await legacy.attach(runA.ref)).ref, runA.ref);
    return {counts: {...counts}, rows: [{id: 1}, {id: 2}],
      distinctScopes: true, originalRunReused: true, unexpectedDispatches: 0};
  } finally {
    for (const client of clients) await client.close();
    if (server !== undefined) {
      server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    }
    for (const host of hosts) {
      const closed = await host.close();
      assert.equal(closed.storeCleanupPending, false);
      assert.equal(closed.authorizationCleanupPending, false);
      assert.deepEqual(closed.pendingRetention, []);
    }
    setDefaultCACertificates(originalCAs);
  }
}

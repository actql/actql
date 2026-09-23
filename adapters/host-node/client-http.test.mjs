import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createClientHttpHandler} from './client-http.mjs';

const ref = {tenantId: 'tenant-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};

async function withServer(handler, run) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    return await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('Client Host rejects missing authentication before touching state', async () => {
  let authorized = 0;
  const handler = createClientHttpHandler({
    authenticate: () => undefined,
    authorizeConnection: () => { authorized++; return true; },
    maxRequestBytes: 512,
  });
  await withServer(handler, async base => {
    const response = await fetch(`${base}/actql/client/0.1/status`, {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
        runners: [], consentRefs: []}, ref: {}}),
    });
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), {code: 'ClientAuthenticationDenied'});
  });
  assert.equal(authorized, 0);
});

test('Client Host rejects missing movement consent and oversized bodies', async () => {
  const handler = createClientHttpHandler({
    authenticate: () => 'principal-a',
    authorizeConnection: () => false,
    maxRequestBytes: 1024,
  });
  await withServer(handler, async base => {
    const path = `${base}/actql/client/0.1/status`;
    const denied = await fetch(path, {method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'hybrid', owner: 'cloud',
        runners: ['runner-a'], consentRefs: [],
        movementPolicyRef: 'metadata-only'}, ref})});
    assert.equal(denied.status, 403);
    assert.deepEqual(await denied.json(), {code: 'ClientConnectionDenied'});
    const large = await fetch(path, {method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({payload: 'x'.repeat(2000)})});
    assert.equal(large.status, 413);
  });
});

test('malformed wire is rejected before connection authorization', async () => {
  let authorized = 0;
  const handler = createClientHttpHandler({
    authenticate: () => 'principal-a',
    authorizeConnection: () => { authorized++; return true; },
  });
  await withServer(handler, async base => {
    const send = body => fetch(`${base}/actql/client/0.1/status`, {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify(body),
    });
    const badModes = [
      {mode: 'remote', owner: 'cloud', runners: [], consentRefs: []},
      {mode: 'local', owner: 'local', runners: ['unapproved'],
        consentRefs: []},
      {mode: 'hybrid', owner: 'cloud', runners: ['runner-a'],
        consentRefs: []},
      {mode: 'remote', owner: 'remote', runners: [], consentRefs: [],
        unexpected: true},
    ];
    for (const connection of badModes) {
      const response = await send({connection, ref});
      assert.equal(response.status, 400);
      assert.deepEqual(await response.json(), {code: 'InvalidClientRequest'});
    }
    assert.equal((await send({connection: {mode: 'remote',
      owner: 'remote', runners: [], consentRefs: []},
    ref: {...ref, runDefinitionCid: 'opaque-handle'}})).status, 400);
  });
  assert.equal(authorized, 0);
});

test('Client Host negotiates a profile only after authentication and consent', async () => {
  const observed = [];
  const handler = createClientHttpHandler({
    authenticate: authorization => authorization === 'Bearer scoped-token'
      ? 'principal-a' : undefined,
    authorizeConnection: facts => {
      observed.push(facts);
      return facts.connection.mode === 'remote';
    },
    negotiate: ({principalId, connection}) => ({
      version: 'actql-client-host/0.1', mode: connection.mode,
      owner: connection.owner, durability: 'volatile',
      scopeRef: principalId, capabilities: [],
      limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
        maxRowRetainedValueBytes: 1024,
        maxRetainedValueBytes: 4096, maxRows: 10,
        maxBatchRows: 3, maxBatchRetainedValueBytes: 1024},
    }),
  });
  await withServer(handler, async base => {
    const response = await fetch(`${base}/actql/client/0.1/connect`, {
      method: 'POST', headers: {authorization: 'Bearer scoped-token',
        'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
        runners: [], consentRefs: []}}),
    });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).scopeRef, 'principal-a');
  });
  assert.equal(observed.length, 1);
  assert.equal(observed[0].principalId, 'principal-a');
});

test('Client Host binds a found request reply before sending its Run ref',
  async () => {
    let reply = {kind: 'found', requestId: 'saved-id', ref,
      durability: 'volatile',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'};
    const handler = createClientHttpHandler({
      authenticate: () => 'principal-a',
      authorizeConnection: () => true,
      lookupRequest: () => reply,
    });
    await withServer(handler, async base => {
      const send = () => fetch(`${base}/actql/client/0.1/lookup-request`, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection: {mode: 'remote', owner: 'remote',
          runners: [], consentRefs: []}, requestId: 'saved-id'}),
      });
      assert.deepEqual(await (await send()).json(), reply);
      reply = {...reply, requestId: 'OTHER'};
      const foreign = await send();
      assert.equal(foreign.status, 500);
      assert.deepEqual(await foreign.json(), {code: 'ClientHostFailure'});
      reply = {kind: 'not_found'};
      assert.deepEqual(await (await send()).json(), reply);
      reply = {kind: 'unknown', reason: 'store_query_failed'};
      assert.deepEqual(await (await send()).json(), reply);
    });
  });

test('Client Host rejects foreign admissions and invalid attempt evidence',
  async () => {
    const connection = {mode: 'remote', owner: 'remote',
      runners: [], consentRefs: []};
    let admission = {ref, durability: 'volatile', revision: 1};
    let attempt = {kind: 'not_found'};
    const handler = createClientHttpHandler({
      authenticate: () => 'principal-a',
      authorizeConnection: () => true,
      submit: () => admission,
      attach: () => admission,
      deliveryAttempt: () => attempt,
    });
    await withServer(handler, async base => {
      const send = (operation, fields) => fetch(
        `${base}/actql/client/0.1/${operation}`, {
          method: 'POST', headers: {'content-type': 'application/json'},
          body: JSON.stringify({connection, ...fields}),
        });
      const submit = () => send('submit', {requestId: 'saved-id',
        kind: 'program', input: {version: 'actql/0.1'}, parameters: null});
      assert.deepEqual(await (await submit()).json(), admission);
      admission = {...admission, ref: {...ref,
        runDefinitionCid: `sha256:${'c'.repeat(64)}`}};
      assert.deepEqual(await (await submit()).json(), admission);
      const foreignAttach = await send('attach', {ref});
      assert.equal(foreignAttach.status, 500);
      assert.deepEqual(await foreignAttach.json(),
        {code: 'ClientHostFailure'});
      admission = {...admission, revision: -1};
      const malformedSubmit = await submit();
      assert.equal(malformedSubmit.status, 500);
      assert.deepEqual(await malformedSubmit.json(),
        {code: 'ClientHostFailure'});
      assert.deepEqual(await (await send('delivery-attempt', {ref,
        resultName: 'answer', attemptId: 'read-a'})).json(), attempt);
      attempt = {kind: 'found', attempt: {attempt_id: 'OTHER'},
        record: {}, hostReleaseReceipt: {}};
      const foreignAttempt = await send('delivery-attempt', {ref,
        resultName: 'answer', attemptId: 'read-a'});
      assert.equal(foreignAttempt.status, 500);
      assert.deepEqual(await foreignAttempt.json(),
        {code: 'ClientHostFailure'});
    });
  });

test('local-owned Hybrid Cloud ref reaches Host authorization before use',
  async () => {
    const authorized = [];
    const handler = createClientHttpHandler({
      authenticate: () => 'principal-a',
      authorizeConnection: facts => {
        authorized.push(facts.connection.cloudConnectionRef);
        return facts.connection.cloudConnectionRef === 'registered-cloud-a';
      },
      negotiate: ({connection}) => ({
        version: 'actql-client-host/0.1', mode: connection.mode,
        owner: connection.owner, durability: 'volatile',
        scopeRef: 'principal-a', capabilities: [],
        limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
          maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
          maxRows: 10, maxBatchRows: 3,
          maxBatchRetainedValueBytes: 1024},
      }),
    });
    await withServer(handler, async base => {
      const send = connection => fetch(`${base}/actql/client/0.1/connect`, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection}),
      });
      const connection = {mode: 'hybrid', owner: 'local',
        consentRefs: ['grant-a'], runners: [],
        movementPolicyRef: 'movement-a',
        cloudConnectionRef: 'registered-cloud-a'};
      assert.equal((await send(connection)).status, 200);
      assert.equal((await send({...connection,
        cloudConnectionRef: undefined})).status, 400);
      assert.equal((await send({...connection,
        cloudConnectionRef: 'foreign-cloud'})).status, 403);
    });
    assert.deepEqual(authorized,
      ['registered-cloud-a', 'foreign-cloud']);
  });

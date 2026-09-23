import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createClientHttpHandler} from './client-http.mjs';

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
        movementPolicyRef: 'metadata-only'}, ref: {}})});
    assert.equal(denied.status, 403);
    assert.deepEqual(await denied.json(), {code: 'ClientConnectionDenied'});
    const large = await fetch(path, {method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({payload: 'x'.repeat(2000)})});
    assert.equal(large.status, 413);
  });
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
      limits: {maxReadWireBytes: 4096, maxRowBytes: 1024,
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

import test from 'node:test';
import assert from 'node:assert/strict';
import {connect} from './index.mjs';

const profile = {
  version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'volatile', scopeRef: 'resource-protocol', capabilities: [],
  limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 3, maxBatchRetainedValueBytes: 1024,
  },
};
const operations = [
  ['resources', client => client.resources('connection'), 'InvalidHostResourceListing'],
  ['resource-inspect', client => client.inspectResource('connection', 'resource'),
    'InvalidHostResourceInspection'],
  ['resource-peek', client => client.peekResource('connection', 'resource', {fields: ['id']}),
    'InvalidHostResourcePeek'],
];

for (const [operation, invoke, malformedCode] of operations) {
  for (const asynchronous of [false, true]) {
    test(`${operation} preserves ${asynchronous ? 'asynchronous' : 'synchronous'} credential provider errors before fetch`, async t => {
      const refusal = new Error('Synthetic resource credential provider refusal');
      const requests = [];
      let credentials = 0;
      t.mock.method(globalThis, 'fetch', async url => {
        requests.push(url.pathname);
        assert.equal(url.pathname, '/actql/client/0.1/connect');
        return Response.json(profile);
      });
      const client = await connect({mode: 'remote', endpoint: 'https://host.example/',
        token() {
          credentials++;
          if (credentials === 1) return 'synthetic-connect-token';
          if (asynchronous) return Promise.reject(refusal);
          throw refusal;
        }});
      let rejected;
      try { await invoke(client); }
      catch (error) { rejected = error; }
      assert.equal(credentials, 2);
      assert.deepEqual(requests, ['/actql/client/0.1/connect'],
        '[resource-protocol:no-operation-fetch]');
      assert.equal(rejected, refusal, '[resource-protocol:provider-identity]');
    });
  }

  test(`${operation} still classifies malformed received JSON after successful credentials`, async t => {
    const requests = [];
    let credentials = 0;
    t.mock.method(globalThis, 'fetch', async url => {
      requests.push(url.pathname);
      if (url.pathname === '/actql/client/0.1/connect') return Response.json(profile);
      assert.equal(url.pathname, `/actql/client/0.1/${operation}`);
      return new Response('{', {headers: {'content-type': 'application/json'}});
    });
    const client = await connect({mode: 'remote', endpoint: 'https://host.example/',
      token() { credentials++; return 'synthetic-resource-token'; }});
    await assert.rejects(invoke(client), error => {
      assert.equal(error.code, malformedCode, '[resource-protocol:received-json]');
      assert.ok(error.cause instanceof SyntaxError);
      return true;
    });
    assert.equal(credentials, 2);
    assert.deepEqual(requests,
      ['/actql/client/0.1/connect', `/actql/client/0.1/${operation}`]);
  });
}

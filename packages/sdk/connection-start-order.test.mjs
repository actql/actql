import assert from 'node:assert/strict';
import test from 'node:test';
import {connect, connectInProcess} from './index.mjs';

const profile = mode => ({version: 'actql-client-host/0.1', mode, owner: mode,
  durability: 'durable', scopeRef: 'start-order', capabilities: [], limits: {
    maxReadWireBytes: 4096, maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 2,
    maxBatchRetainedValueBytes: 2048}});

test('in-process connection invokes its original port before yielding', async () => {
  const calls = [];
  const pending = connectInProcess({mode: 'local', owner: 'local'}, {
    perform(operation) { calls.push(operation); return profile('local'); },
  });
  // Observe the scheduling contract before awaiting the connection result.
  const beforeYield = [...calls];
  const client = await pending;
  try { assert.deepEqual(beforeYield, ['connect']); }
  finally { await client.close(); }
});

test('Remote connection invokes its original credential provider before yielding', async t => {
  let credential = 'original', observed = [];
  const sent = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    sent.push(options.headers.authorization);
    return Response.json(profile('remote'));
  });
  const pending = connect({mode: 'remote', endpoint: 'https://host.example/',
    token() { observed.push(credential); return credential; }});
  credential = 'replacement';
  const beforeYield = [...observed];
  const client = await pending;
  try {
    assert.deepEqual(beforeYield, ['original']);
    assert.deepEqual(sent, ['Bearer original']);
  } finally { await client.close(); }
});

test('Remote connection with a fixed credential dispatches before yielding', async t => {
  const calls = [];
  t.mock.method(globalThis, 'fetch', async url => {
    calls.push(url.pathname);
    return Response.json(profile('remote'));
  });
  const pending = connect({mode: 'remote', endpoint: 'https://host.example/', token: 'original'});
  const beforeYield = [...calls];
  const client = await pending;
  try { assert.deepEqual(beforeYield, ['/actql/client/0.1/connect']); }
  finally { await client.close(); }
});

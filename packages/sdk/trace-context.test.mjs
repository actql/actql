import test from 'node:test';
import assert from 'node:assert/strict';
import {connect} from './index.mjs';
import {submissionEpoch} from './submission-fixture.mjs';

const parent = {traceId: 'a'.repeat(32), spanId: 'b'.repeat(16), traceFlags: 255,
  baggage: {secret: 'SECRET_SENTINEL'}, tracestate: 'SECRET_SENTINEL'};
const profile = {version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'scope', workspaceId: 'workspace',
  submissionEpoch, capabilities: [], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
test('SDK propagation changes only traceparent, not authority or semantic body', async t => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    requests.push(options);
    return Response.json(profile);
  });
  const plain = await connect('actql://host.invalid/workspace', {token: 'credential'});
  const observed = await connect('actql://host.invalid/workspace', {
    token: 'credential', traceContext: () => parent});
  await plain.close(); await observed.close();
  assert.equal(requests[1].headers.traceparent, `00-${parent.traceId}-${parent.spanId}-01`);
  assert.equal(requests[1].headers.authorization, requests[0].headers.authorization);
  assert.equal(requests[1].body, requests[0].body);
  assert.equal(requests[1].headers.baggage, undefined);
  assert.equal(requests[1].headers.tracestate, undefined);
  assert.equal(JSON.stringify(requests[1]).includes('SECRET_SENTINEL'), false);
});
test('invalid or failing correlation is omitted without failing connection', async t => {
  const requests = [];
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    requests.push(options); return Response.json(profile);
  });
  for (const traceContext of [() => { throw new Error('SECRET_SENTINEL'); },
    () => ({...parent, traceId: '0'.repeat(32)}), () => ({...parent, spanId: '\r\nHeader: injection'})]) {
    const client = await connect('actql://host.invalid/workspace', {token: 'credential', traceContext});
    await client.close();
  }
  assert.equal(requests.length, 3);
  for (const request of requests) assert.equal(request.headers.traceparent, undefined);
});

test('SDK snapshots correlation getters once before constructing the header', async t => {
  let reads = 0;
  let headers;
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    headers = options.headers; return Response.json(profile);
  });
  const client = await connect('actql://host.invalid/workspace', {
    token: 'credential', traceContext: () => ({...parent,
      get traceId() { return ++reads === 1 ? parent.traceId : '\r\nSECRET_SENTINEL'; },
    }),
  });
  await client.close();
  assert.equal(reads, 1);
  assert.equal(headers.traceparent, `00-${parent.traceId}-${parent.spanId}-01`);
});

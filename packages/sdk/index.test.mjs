import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {connect, ClientError} from './index.mjs';

const ref = Object.freeze({tenantId: 'tenant-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});
const profile = Object.freeze({version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'scope-a', capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10,
    maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}});
const admission = Object.freeze({ref, durability: 'durable', revision: 4});
const options = {mode: 'remote', endpoint: 'https://host.example/',
  token: () => 'scoped-token'};

test('document submit, attach and reads use one reference without replay', async t => {
  const requests = [];
  const state = {outcome: 'succeeded', publication: 'publication_unknown',
    availability: {answer: 'unknown'}, revision: 4};
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push({operation, body: JSON.parse(init.body), headers: init.headers});
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'submit' || operation === 'attach') {
      return Response.json(admission);
    }
    if (operation === 'status') return Response.json(state);
    if (operation === 'read') {
      return new Response('{"n":1}\n{"n":2}\n\x1e',
        {headers: {'content-type': 'application/x-ndjson'}});
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.equal(client.profile.durability, 'durable');
  const execution = await client.aql('{"version":"actql/0.1"}',
    {format: 'json', requestId: 'request-a'});
  assert.deepEqual(execution.ref, ref);
  assert.deepEqual(await execution.status(), state);
  const result = execution.result('answer');
  const reader = result.rows();
  assert.equal(reader.state(), 'not_started');
  assert.deepEqual(await Array.fromAsync(reader), [{n: 1}, {n: 2}]);
  assert.equal(reader.state(), 'complete');
  assert.deepEqual(await result.all(), [{n: 1}, {n: 2}]);
  const restored = await client.attach(ref);
  assert.deepEqual(await restored.status(), state);
  const reads = requests.filter(value => value.operation === 'read');
  assert.equal(requests.filter(value => value.operation === 'submit').length, 1);
  assert.equal(reads.length, 2);
  assert.notEqual(reads[0].body.attemptId, reads[1].body.attemptId);
  assert.equal(reads[0].headers.authorization, 'Bearer scoped-token');
  assert.deepEqual(requests.find(value => value.operation === 'submit').body,
    {connection: {mode: 'remote', owner: 'remote', consentRefs: [],
      runners: []}, requestId: 'request-a', kind: 'aql',
    input: {text: '{"version":"actql/0.1"}', format: 'json'},
    parameters: null});
});

test('unknown submit carries one fixed request ID and lookup never submits', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push({operation, body: JSON.parse(init.body)});
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'submit') throw new Error('ACK lost');
    if (operation === 'lookup-request') {
      return Response.json({kind: 'unknown', reason: 'query_failed'});
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  let requestId;
  await assert.rejects(client.start({version: 'actql/0.1'}), error => {
    assert.equal(error.code, 'SubmissionUnknown');
    assert.ok(error.requestId);
    assert.equal(error.lookupContext.scopeRef, 'scope-a');
    requestId = error.requestId;
    return true;
  });
  assert.equal(requests[1].body.requestId, requestId);
  assert.deepEqual(await client.lookupRequest(requestId),
    {kind: 'unknown', reason: 'query_failed'});
  assert.deepEqual(requests.map(value => value.operation),
    ['connect', 'submit', 'lookup-request']);
});

test('read limits reject complete collection without cancelling the Run', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n{"n":2}\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  const result = (await client.attach(ref)).result('answer');
  await assert.rejects(result.all({maxRows: 1}), error =>
    error.code === 'ResultRetainedLimit' && !!error.attemptId);
  assert.deepEqual(requests, ['connect', 'attach', 'read']);
});

test('hybrid options are snapshotted and durable requests cannot downgrade', async t => {
  let sent;
  mock.method(globalThis, 'fetch', async (_url, init) => {
    sent = JSON.parse(init.body);
    return Response.json({...profile, mode: 'hybrid', owner: 'cloud',
      durability: 'volatile'});
  });
  t.after(() => mock.restoreAll());
  const selected = {mode: 'hybrid', owner: 'cloud',
    endpoint: 'https://host.example/', token: 'token',
    movementPolicyRef: 'policy-a', runners: ['runner-a'],
    consentRefs: ['grant-a'], durability: 'durable'};
  await assert.rejects(connect(selected), {code: 'InvalidHostProfile'});
  selected.runners.push('runner-b');
  assert.deepEqual(sent.connection.runners, ['runner-a']);
  assert.deepEqual(sent.connection.consentRefs, ['grant-a']);
});

test('invalid refs and unsafe endpoints are rejected before transport', async t => {
  for (const endpoint of ['http://host.example/',
    'https://user:secret@host.example/',
    'https://host.example/?token=secret']) {
    await assert.rejects(connect({...options, endpoint}), ClientError);
  }
  mock.method(globalThis, 'fetch', async () => Response.json(profile));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.attach({...ref, authorityScopeCid: 'bad'}),
    {code: 'InvalidRunReference'});
});

test('a complete row prefix without the end marker remains incomplete', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  const seen = [];
  await assert.rejects(async () => {
    for await (const row of reader) seen.push(row);
  }, error => error.code === 'IncompleteResultStream' &&
    error.attemptId === reader.attemptId);
  assert.deepEqual(seen, [{n: 1}]);
  assert.equal(reader.state(), 'prefix');
});

test('malformed acceptance is unknown and preserves the original ID', async t => {
  mock.method(globalThis, 'fetch', async url =>
    url.pathname.endsWith('/connect')
      ? Response.json(profile) : Response.json({bad: true}));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.equal(client.requestedDurability, null);
  await assert.rejects(client.start({version: 'actql/0.1'},
    {requestId: 'saved-id'}), error =>
    error.code === 'SubmissionUnknown' && error.requestId === 'saved-id');
});

test('an unserializable Program is rejected before submit', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async url => {
    requests.push(url.pathname.split('/').at(-1));
    return Response.json(profile);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.start({value: 1n}),
    {code: 'InvalidClientPayload'});
  assert.deepEqual(requests, ['connect']);
});

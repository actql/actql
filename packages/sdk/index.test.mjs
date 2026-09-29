import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {connect, ClientError} from './index.mjs';

const ref = Object.freeze({namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});
const profile = Object.freeze({version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'scope-a', capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10,
    maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}});
const admission = Object.freeze({ref, durability: 'durable', revision: 4});
const state = Object.freeze({version: 'actql-run-state/0.1',
  run_id: 'run-a', status: 'succeeded',
  updated_at: '2026-09-24T00:00:00.000Z',
  next_action: {kind: 'refresh_availability', results: ['answer']},
  result_available: false,
  result_availability: {answer: {
    state: 'unknown', observed_at: '2026-09-24T00:00:00.000Z',
    reason: 'verification_pending'}}});
const options = {mode: 'remote', endpoint: 'https://host.example/',
  token: () => 'scoped-token'};
const oversizedControl = cancelled => new Response(new ReadableStream({
  start(controller) {
    controller.enqueue(new Uint8Array(1024 * 1024));
    controller.enqueue(new Uint8Array([123]));
  },
  cancel() { cancelled.push(true); },
}));

test('review wire budget covers maximum base64 without relaxing body limits',
  async t => {
    const maximum = 1024 * 1024;
    let content = Buffer.alloc(maximum, 97);
    const checkpointCid = `sha256:${'c'.repeat(64)}`;
    mock.method(globalThis, 'fetch', async url => {
      if (url.pathname.endsWith('/connect')) return Response.json(profile);
      return Response.json({kind: 'review', checkpointCid,
        artifactCid: `sha256:${createHash('sha256').update(content).digest('hex')}`,
        byteLength: content.length, contentBase64: content.toString('base64')});
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    const result = await client.reviewCheckpoint(checkpointCid,
      {maxBytes: maximum});
    assert.deepEqual(Buffer.from(result.bytes), content);
    assert.ok(content.toString('base64').length > maximum);
    content = Buffer.alloc(maximum + 1, 97);
    await assert.rejects(client.reviewCheckpoint(checkpointCid,
      {maxBytes: maximum}), {code: 'InvalidHostCheckpointReview'});
  });

test('peek bounds decoded JSON independently of escaped wire size', async t => {
  const maximum = 4 * 1024 * 1024;
  const prefix = JSON.stringify([{value: '\\"日本語'.repeat(120000)}]);
  let rowsJson = prefix.slice(0, -3) +
    'a'.repeat(maximum - Buffer.byteLength(prefix)) + prefix.slice(-3);
  assert.equal(Buffer.byteLength(rowsJson), maximum);
  assert.ok(Buffer.byteLength(JSON.stringify(rowsJson)) > maximum);
  mock.method(globalThis, 'fetch', async url =>
    url.pathname.endsWith('/connect') ? Response.json(profile) :
      Response.json({resourceConnection: 'connection', resource: 'resource',
        observationCid: `sha256:${'c'.repeat(64)}`, fields: ['value'],
        rowsJson, limited: false}));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.deepEqual((await client.peekResource('connection', 'resource',
    {fields: ['value'], maxBytes: maximum})).rows, JSON.parse(rowsJson));
  rowsJson = rowsJson.slice(0, -3) + 'a' + rowsJson.slice(-3);
  await assert.rejects(client.peekResource('connection', 'resource',
    {fields: ['value'], maxBytes: maximum}), {code: 'InvalidHostResourcePeek'});
});

test('review wire cap cancels an oversized stream despite a short length header',
  async t => {
    let cancelled = 0;
    mock.method(globalThis, 'fetch', async url => {
      if (url.pathname.endsWith('/connect')) return Response.json(profile);
      return new Response(new ReadableStream({
        start(controller) { controller.enqueue(new Uint8Array(4096)); },
        cancel() { cancelled++; },
      }), {headers: {'content-length': '1'}});
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    await assert.rejects(client.reviewCheckpoint(`sha256:${'c'.repeat(64)}`,
      {maxBytes: 1}), error => error.code === 'ReviewReadUnknown' &&
        error.cause.message === 'HostControlResponseLimit');
    assert.equal(cancelled, 1);
  });

test('control responses are bounded and uncertain submit keeps its ID',
  async t => {
    const cancelled = [];
    let reply = oversizedControl(cancelled);
    const requests = [];
    mock.method(globalThis, 'fetch', async url => {
      requests.push(url.pathname.split('/').at(-1));
      return requests.at(-1) === 'connect' && requests.length > 1
        ? Response.json(profile) : reply;
    });
    t.after(() => mock.restoreAll());
    await assert.rejects(connect(options), {code: 'InvalidHostProfile'});
    assert.equal(cancelled.length, 1);
    reply = oversizedControl(cancelled);
    const client = await connect(options);
    await assert.rejects(client.start({version: 'actql/0.1'},
      {requestId: 'saved-control-id'}), error =>
      error.code === 'SubmissionUnknown' &&
      error.requestId === 'saved-control-id');
    assert.equal(cancelled.length, 2);
    assert.deepEqual(requests, ['connect', 'connect', 'submit']);
  });

test('bounded control reads cover attach, status and error responses',
  async t => {
    const cancelled = [];
    let operationReply = Response.json(admission);
    mock.method(globalThis, 'fetch', async url => {
      const operation = url.pathname.split('/').at(-1);
      return operation === 'connect' ? Response.json(profile) : operationReply;
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    operationReply = oversizedControl(cancelled);
    await assert.rejects(client.attach(ref), {code: 'InvalidHostAdmission'});
    operationReply = Response.json(admission);
    const execution = await client.attach(ref);
    operationReply = oversizedControl(cancelled);
    await assert.rejects(execution.status(), {code: 'InvalidHostResponse'});
    operationReply = new Response(oversizedControl(cancelled).body,
      {status: 503});
    await assert.rejects(client.start({version: 'actql/0.1'},
      {requestId: 'saved-error-id'}), error =>
      error.code === 'SubmissionUnknown' &&
      error.requestId === 'saved-error-id');
    assert.equal(cancelled.length, 3);
  });

test('document submit, attach and reads use one reference without replay', async t => {
  const requests = [];
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

test('status and wait reject malformed Host state replies', async t => {
  let reply = state;
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'status' || operation === 'wait') {
      return Response.json(reply);
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const execution = await (await connect(options)).attach(ref);
  assert.deepEqual(await execution.status(), state);
  assert.deepEqual(await execution.wait(), state);
  reply = {...state, status: 'not_an_engine_state'};
  await assert.rejects(execution.status(), {code: 'InvalidHostRunState'});
  await assert.rejects(execution.wait(), {code: 'InvalidHostRunState'});
});

test('Run reconciliation validates state without submitting computation', async t => {
  const requests = [];
  let reply = {...state, status: 'needs_reconciliation',
    next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}};
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'reconcile') return Response.json(reply);
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const execution = await (await connect(options)).attach(ref);
  assert.deepEqual(await execution.reconcile(), reply);
  reply = {...reply, next_action: {kind: 'reconcile_run'}};
  await assert.rejects(execution.reconcile(), {code: 'InvalidHostRunState'});
  reply = {...state, status: 'needs_reconciliation',
    next_action: {kind: 'reconcile', effects: ['write']}};
  assert.deepEqual(await execution.reconcile(), reply);
  assert.deepEqual(requests, ['connect', 'attach', 'reconcile',
    'reconcile', 'reconcile']);
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

test('stopping a row reader releases only its delivery stream', async t => {
  const requests = [];
  const cancelled = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new TextEncoder().encode('{"n":1}\n')); },
      cancel() { cancelled.push(true); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  for await (const row of reader) {
    assert.deepEqual(row, {n: 1});
    break;
  }
  assert.equal(reader.state(), 'prefix');
  assert.deepEqual(cancelled, [true]);
  assert.deepEqual(requests, ['connect', 'attach', 'read']);
});

test('a wire-limit failure releases the unfinished delivery stream', async t => {
  const cancelled = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new Uint8Array(32).fill(120)); },
      cancel() { cancelled.push(true); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxWireBytes: 16});
  await assert.rejects(Array.fromAsync(reader), error =>
    error.code === 'ResultWireLimit' &&
    error.attemptId === reader.attemptId);
  assert.equal(reader.state(), 'prefix');
  assert.deepEqual(cancelled, [true]);
});

test('a failed stream cancellation does not erase the read failure', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new Uint8Array(32).fill(120)); },
      cancel() { throw new Error('physical cleanup failed'); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxWireBytes: 16});
  await assert.rejects(Array.fromAsync(reader), error =>
    error.code === 'ResultWireLimit' &&
    error.attemptId === reader.attemptId &&
    error.cleanupError?.message === 'physical cleanup failed');
});

test('row wire and retained-value limits are independent', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  await assert.rejects(result.all({maxRowWireBytes: 6}), error =>
    error.code === 'ResultRowWireLimit' && !!error.attemptId);
  await assert.rejects(result.all({maxRowRetainedValueBytes: 7}), error =>
    error.code === 'ResultRowRetainedLimit' && !!error.attemptId);
  assert.deepEqual(await result.all({maxRowWireBytes: 7,
    maxRowRetainedValueBytes: 1024}), [{n: 1}]);
  assert.deepEqual(requests, ['connect', 'attach', 'read', 'read', 'read']);
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

test('local-owned Hybrid identifies Cloud assistance without changing owner',
  async t => {
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      requests.push({operation: url.pathname.split('/').at(-1),
        body: JSON.parse(init.body)});
      return Response.json({...profile, mode: 'hybrid', owner: 'local'});
    });
    t.after(() => mock.restoreAll());
    const selected = {mode: 'hybrid', owner: 'local',
      endpoint: 'https://local-host.example/', token: 'local-token',
      movementPolicyRef: 'movement-a',
      cloudConnectionRef: 'registered-cloud-a',
      consentRefs: ['grant-a']};
    const client = await connect(selected);
    assert.equal(client.profile.owner, 'local');
    assert.deepEqual(requests[0].body.connection, {
      mode: 'hybrid', owner: 'local', consentRefs: ['grant-a'],
      runners: [], movementPolicyRef: 'movement-a',
      cloudConnectionRef: 'registered-cloud-a',
    });
    await assert.rejects(connect({...selected,
      cloudConnectionRef: undefined}), {code: 'InvalidHybridConnection'});
    await assert.rejects(connect({...selected, mode: 'remote',
      owner: undefined}), {code: 'InvalidHybridConnection'});
    await assert.rejects(connect({...selected, owner: 'cloud'}),
      {code: 'InvalidHybridConnection'});
  });

test('one query and Result path serves each connected ownership profile',
  async t => {
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      const body = JSON.parse(init.body);
      requests.push({operation, body});
      if (operation === 'connect') return Response.json({...profile,
        mode: body.connection.mode, owner: body.connection.owner});
      if (operation === 'submit') return Response.json(admission);
      if (operation === 'read') return new Response('{"id":1}\n\x1e');
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const connected = [
      options,
      {mode: 'local', owner: 'local',
        endpoint: 'https://local.example/', token: 'token'},
      {mode: 'hybrid', owner: 'cloud',
        endpoint: 'https://cloud.example/', token: 'token',
        runners: ['runner-a'], movementPolicyRef: 'movement-a'},
      {mode: 'hybrid', owner: 'local',
        endpoint: 'https://local.example/', token: 'token',
        cloudConnectionRef: 'registered-cloud-a',
        movementPolicyRef: 'movement-a'},
    ];
    const query = async connection => {
      const client = await connect(connection);
      const execution = await client.aql('{"version":"actql/0.1"}',
        {format: 'json'});
      const values = await execution.result('answer').all();
      client.close();
      return values;
    };
    for (const connection of connected) {
      assert.deepEqual(await query(connection), [{id: 1}]);
    }
    assert.equal(requests.filter(item => item.operation === 'submit').length,
      connected.length);
    assert.equal(requests.filter(item => item.operation === 'read').length,
      connected.length);
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

test('attach rejects each foreign Run reference before status or read',
  async t => {
    let returned = ref;
    const operations = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      operations.push(operation);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json({
        ...admission, ref: returned});
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    for (const field of ['namespaceId', 'authorityScopeCid',
      'runDefinitionCid']) {
      returned = {...ref, [field]: field === 'namespaceId' ? 'namespace-b' :
        `sha256:${'c'.repeat(64)}`};
      await assert.rejects(client.attach(ref),
        {code: 'ForeignHostAdmission'});
    }
    returned = ref;
    assert.deepEqual((await client.attach(ref)).ref, ref);
    assert.deepEqual(operations,
      ['connect', 'attach', 'attach', 'attach', 'attach']);
  });

test('attach snapshots the requested reference before async credentials',
  async t => {
    let releaseCredential;
    let credentialCalls = 0;
    let sent;
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') {
        sent = JSON.parse(init.body).ref;
        return Response.json(admission);
      }
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const client = await connect({...options, token: () => {
      credentialCalls++;
      return credentialCalls === 1 ? 'scoped-token' :
        new Promise(resolve => { releaseCredential = resolve; });
    }});
    const mutable = {...ref};
    const attached = client.attach(mutable);
    mutable.runDefinitionCid = `sha256:${'c'.repeat(64)}`;
    releaseCredential('scoped-token');
    assert.deepEqual((await attached).ref, ref);
    assert.deepEqual(sent, ref);
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

test('a blank JSONL record fails after the delivered prefix', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  const seen = [];
  await assert.rejects(async () => {
    for await (const row of reader) seen.push(row);
  }, error => error.code === 'InvalidResultStream' &&
    error.attemptId === reader.attemptId);
  assert.deepEqual(seen, [{n: 1}]);
  assert.equal(reader.state(), 'prefix');
});

test('one transport chunk can contain many bounded rows', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(
      `${Array.from({length: 40}, (_, n) => JSON.stringify({n}))
        .join('\n')}\n\x1e`);
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxRowWireBytes: 8});
  assert.deepEqual(await Array.fromAsync(reader),
    Array.from({length: 40}, (_, n) => ({n})));
  assert.equal(reader.state(), 'complete');
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

test('submit fixes Program and parameters before asynchronous token lookup',
  async t => {
    let releaseToken;
    const delayedToken = new Promise(resolve => { releaseToken = resolve; });
    let tokenCalls = 0;
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      return Response.json(operation === 'connect' ? profile : admission);
    });
    t.after(() => mock.restoreAll());
    const client = await connect({...options,
      token: () => ++tokenCalls === 1 ? 'token' : delayedToken});
    const program = {version: 'actql/0.1', marker: 'original'};
    const parameters = {value: 'original'};
    const submitted = client.start(program, {
      requestId: 'saved-id', parameters,
    });
    program.marker = 'changed';
    parameters.value = 'changed';
    releaseToken('token');
    await submitted;
    assert.deepEqual(requests[1].body, {
      connection: {mode: 'remote', owner: 'remote',
        consentRefs: [], runners: []},
      requestId: 'saved-id', kind: 'program',
      input: {version: 'actql/0.1', marker: 'original'},
      parameters: {value: 'original'},
    });
  });

test('request lookup distinguishes retained Run, absence and malformed Host reply',
  async t => {
    let reply = {kind: 'found', requestId: 'saved-id', ref,
      durability: 'durable',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'};
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      return Response.json(operation === 'connect' ? profile : reply);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    assert.deepEqual(await client.lookupRequest('saved-id'), reply);
    reply = {kind: 'not_found'};
    assert.deepEqual(await client.lookupRequest('missing'), reply);
    reply = {kind: 'found', requestId: 'other-id', ref,
      durability: 'durable',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'};
    await assert.rejects(client.lookupRequest('saved-id'),
      {code: 'InvalidHostRequestLookup'});
    reply = {kind: 'found', ref: {...ref, runDefinitionCid: 'bad'},
      durability: 'durable', lookupExpiresAt: 'tomorrow'};
    await assert.rejects(client.lookupRequest('saved-id'),
      {code: 'InvalidHostRequestLookup'});
    assert.deepEqual(requests.map(item => item.operation),
      ['connect', 'lookup-request', 'lookup-request',
        'lookup-request', 'lookup-request']);
  });

test('delivery attempt lookup binds the existing Host evidence to the request',
  async t => {
    const found = JSON.parse(readFileSync(new URL(
      '../client-wire/fixtures/delivery-attempt.found.json', import.meta.url),
    'utf8'));
    let reply = found;
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json(admission);
      return Response.json(reply);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    const result = (await client.attach(ref)).result('answer');
    assert.deepEqual(await result.deliveryAttempt('read-a'), reply);
    reply = {kind: 'not_found'};
    assert.deepEqual(await result.deliveryAttempt('read-b'), reply);
    for (const update of [
      answer => { answer.attempt.attempt_id = 'OTHER'; },
      answer => { answer.attempt.run_definition_cid =
        `sha256:${'9'.repeat(64)}`; },
      answer => { answer.attempt.result_name = 'foreign'; },
      answer => { answer.hostReleaseReceipt = {}; },
      answer => { answer.record.state = 'failed'; },
      answer => { answer.hostReleaseReceipt.serialization_contract_cid =
        `sha256:${'9'.repeat(64)}`; },
    ]) {
      reply = structuredClone(found);
      update(reply);
      await assert.rejects(result.deliveryAttempt('read-a'),
        {code: 'InvalidHostAttemptLookup'});
    }
    assert.deepEqual(requests.slice(2).map(item => item.body.attemptId),
      ['read-a', 'read-b', ...Array(6).fill('read-a')]);
    assert(requests.slice(2).every(item =>
      item.body.resultName === 'answer'));
    assert(requests.every(item => item.operation !== 'read'));
  });


test('cancel validates the response and exact requested Run', async t => {
  let reply = {ref, kind: 'accepted', revision: 5};
  t.mock.method(globalThis, 'fetch', async url => Response.json(
    String(url).endsWith('/connect') ? profile :
      String(url).endsWith('/attach') ? admission : reply));
  const client = await connect(options);
  t.after(() => client.close());
  const execution = await client.attach(ref);
  assert.deepEqual(await execution.cancel(), reply);
  for (const invalid of [{}, {...reply, kind: 'stopped'},
    {...reply, revision: -1},
    ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(key =>
      ({...reply, ref: {...ref, [key]: key === 'namespaceId' ? 'foreign' :
        `sha256:${'c'.repeat(64)}`}}))]) {
    reply = invalid;
    await assert.rejects(execution.cancel(), {code: 'InvalidHostCancellation'});
  }
});

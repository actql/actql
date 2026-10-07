import test from 'node:test';
import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {ClientError, connect, getSubmissionInput, explainSubmission} from './index.mjs';

const fetchContexts = new WeakSet();
function stubFetch(t, implementation) {
  if (!fetchContexts.has(t)) {
    fetchContexts.add(t);
    const original = globalThis.fetch;
    t.after(() => {globalThis.fetch = original;});
  }
  globalThis.fetch = implementation;
}

const secret = 'DSN_CANARY_SECRET:+/@?#%';
const dsn = `actql://token:${encodeURIComponent(secret)}@example.test/workspace-A`;
const profile = () => ({version: 'actql-client-host/0.1', mode: 'remote', owner: 'remote',
  durability: 'durable', scopeRef: 'unchanged-scope', workspaceId: 'workspace-A', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}});
const ref = {namespaceId: 'not-the-workspace-id', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const noSecret = value => {
  for (const output of [JSON.stringify(value), inspect(value, {depth: 20, showHidden: true})]) {
    assert.equal(output.includes('DSN_CANARY_SECRET'), false);
    assert.equal(output.includes(encodeURIComponent(secret)), false);
    assert.equal(output.includes(dsn), false);
  }
};

test('SDK DSNs carry a fixed Workspace without exposing the connection secret', async t => {
  const calls = [];
  stubFetch(t, async (url, options) => {
    assert.equal(url.origin, 'https://example.test');
    assert.equal(url.username, ''); assert.equal(url.password, '');
    assert.equal(options.headers.authorization, `Bearer ${secret}`);
    assert.equal(options.redirect, 'error');
    const body = JSON.parse(options.body), operation = url.pathname.split('/').at(-1);
    noSecret(body); noSecret(url.href);
    assert.equal(body.connection.workspaceId, 'workspace-A'); calls.push(operation);
    if (operation === 'connect') return Response.json(profile());
    if (operation === 'submit' || operation === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
    if (operation === 'lookup-request') return Response.json({kind: 'not_found'});
    throw new Error('UnexpectedOperation');
  });
  for (const factory of [connect]) {
    const client = await factory(dsn);
    try {
      const run = await client.start({version: 'actql/0.1'}, {requestId: 'saved-dsn'});
      noSecret(client); noSecret(run); noSecret(getSubmissionInput(run));
      assert.equal(getSubmissionInput(run).lookupContext.endpoint, 'https://example.test/');
      assert.equal(getSubmissionInput(run).connection.workspaceId, 'workspace-A');
      assert.deepEqual((await client.attach(run.ref)).ref, ref);
      await client.lookupRequest('saved-dsn');
    } finally {client.close();}
  }
  assert.deepEqual(calls, ['connect', 'submit', 'attach', 'lookup-request']);
});

test('conflicting, absent and malformed credentials fail before a getter or fetch', async t => {
  let getterCalls = 0, requests = 0;
  stubFetch(t, () => {requests++; throw new Error('NoRequestExpected');});
  const token = () => {getterCalls++; return secret;};
  for (const options of [{token: secret}, {token}, {token: undefined}, Object.create({token})]) {
    await assert.rejects(connect(dsn, options), {code: 'ConflictingConnectionCredentials'});
  }
  await assert.rejects(connect('actql://example.test/workspace-A'), {code: 'InvalidConnectionOptions'});
  await assert.rejects(connect(`${dsn}?token=extra`), {code: 'InvalidConnectionString'});
  await assert.rejects(connect(dsn, {endpoint: 'https://other.test'}), {code: 'InvalidConnectionOptions'});
  await assert.rejects(connect('actql://example.test/workspace-A', {
    get token() {throw new ClientError('PrivateOptionFailure', {cause: new Error(dsn)});},
  }), error => {assert.equal(error.code, 'InvalidConnectionOptions'); noSecret(error); return true;});
  assert.equal(getterCalls, 0); assert.equal(requests, 0);
});

test('missing or different Workspace echoes fail without retry or fallback', async t => {
  let requests = 0;
  for (const workspaceId of [null, 'workspace-B']) {
    const answer = profile();
    if (workspaceId === null) delete answer.workspaceId;
    else answer.workspaceId = workspaceId;
    stubFetch(t, async () => {requests++; return Response.json(answer);});
    await assert.rejects(connect(dsn), {code: 'InvalidHostProfile'});
  }
  assert.equal(requests, 2);
});

test('separate DSN credentials use the same header bounds before any fetch', async t => {
  let requests = 0;
  stubFetch(t, () => {requests++; throw new Error('NoRequestExpected');});
  for (const value of ['', 'has space', 'control\r\n', '東京', 'a'.repeat(8193)]) {
    for (const token of [value, async () => value]) {
      await assert.rejects(connect('actql://example.test/workspace-A', {token}),
        {code: 'InvalidConnectionToken'});
    }
  }
  assert.equal(requests, 0);
});

test('separate providers refresh credentials without changing the asserted Workspace', async t => {
  let token = 'token-A-first'; const observed = [];
  stubFetch(t, async (url, options) => {
    assert.equal(JSON.parse(options.body).connection.workspaceId, 'workspace-A');
    observed.push(options.headers.authorization);
    return Response.json(url.pathname.endsWith('/connect') ? profile() : {kind: 'not_found'});
  });
  const client = await connect('actql://example.test/workspace-A', {token: async () => token});
  try {token = 'token-A-refreshed'; await client.lookupRequest('saved');}
  finally {client.close();}
  assert.deepEqual(observed, ['Bearer token-A-first', 'Bearer token-A-refreshed']);
});

test('DSN getter, transport and control-body failures omit borrowed secret-bearing causes', async t => {
  const privateFailure = () => new Error(dsn, {cause: new Error(secret)});
  await assert.rejects(connect('actql://example.test/workspace-A', {token: () => {throw privateFailure();}}),
    error => {assert.equal(error.code, 'ClientCredentialUnavailable'); noSecret(error); return true;});
  stubFetch(t, async () => {throw privateFailure();});
  await assert.rejects(connect(dsn), error => {
    assert.equal(error.code, 'ClientTransportUnknown'); noSecret(error); return true;
  });
  for (const response of [
    () => new Response(`{"secret":"${secret}" broken`),
    () => new Response(new ReadableStream({start(controller) {controller.error(privateFailure());}})),
  ]) {
    stubFetch(t, async () => response());
    await assert.rejects(connect(dsn), error => {
      assert.equal(error.code, 'InvalidHostProfile'); noSecret(error); return true;
    });
  }
});

test('lost DSN submission retains unknown acceptance and safe context without resending', async t => {
  const calls = [];
  stubFetch(t, async url => {
    const operation = url.pathname.split('/').at(-1); calls.push(operation);
    if (operation === 'connect') return Response.json(profile());
    throw new Error(dsn, {cause: new Error(secret)});
  });
  const client = await connect(dsn);
  try {
    await assert.rejects(client.start({version: 'actql/0.1'}, {requestId: 'saved'}), error => {
      assert.equal(error.code, 'SubmissionUnknown'); assert.equal(error.requestId, 'saved');
      assert.equal(explainSubmission(error).observation, 'acceptance_unknown');
      noSecret(error); noSecret(getSubmissionInput(error)); noSecret(explainSubmission(error));
      assert.equal(error.lookupContext.endpoint, 'https://example.test/'); return true;
    });
  } finally {client.close();}
  assert.deepEqual(calls, ['connect', 'submit']);
});

test('DSN read failures retain attempt and prefix facts without a borrowed private error code', async t => {
  stubFetch(t, async url => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile());
    if (url.pathname.endsWith('/attach')) return Response.json({ref, durability: 'durable', revision: 1});
    return new Response(new ReadableStream({start(controller) {
      controller.error(Object.assign(new ClientError('DSN_CANARY_SECRET', {cause: new Error(dsn)}),
        {cleanupError: new Error(secret)}));
    }}));
  });
  const client = await connect(dsn);
  try {
    const run = await client.attach(ref), reader = run.result('answer').rows();
    await assert.rejects(Array.fromAsync(reader), error => {
      assert.equal(error.code, 'ResultReadUnknown'); assert.equal(error.attemptId, reader.attemptId);
      assert.equal(error.rowsYielded, 0); noSecret(error); return true;
    });
  } finally {client.close();}
});

for (const property of ['code', 'cleanupError']) {
  test(`DSN reads do not evaluate a borrowed ${property} getter`, async t => {
    let getterCalls = 0;
    const borrowed = Object.defineProperty({}, property, {get() {
      getterCalls++; throw new Error(dsn);
    }});
    stubFetch(t, async url => {
      if (url.pathname.endsWith('/connect')) return Response.json(profile());
      if (url.pathname.endsWith('/attach')) return Response.json({ref, durability: 'durable', revision: 1});
      return new Response(new ReadableStream({start(controller) {controller.error(borrowed);}}));
    });
    const client = await connect(dsn);
    try {
      const run = await client.attach(ref);
      await assert.rejects(run.result('answer').all(), error => {
        assert.equal(error.code, 'ResultReadUnknown'); noSecret(error); return true;
      });
      assert.equal(getterCalls, 0);
    } finally {client.close();}
  });
}

test('unasserted endpoint connections retain their original profile and request shape', async t => {
  stubFetch(t, async (_url, options) => {
    assert.equal(Object.hasOwn(JSON.parse(options.body).connection, 'workspaceId'), false);
    const answer = profile(); delete answer.workspaceId; return Response.json(answer);
  });
  const client = await connect({mode: 'remote', endpoint: 'https://example.test', token: 'legacy'});
  assert.equal(Object.hasOwn(client.profile, 'workspaceId'), false); client.close();
});

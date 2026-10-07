import test from 'node:test';
import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {ClientError, connect, getSubmissionInput, explainSubmission,
  explainDeliveryAttempt, explainReadFailure} from './index.mjs';
import {createServer} from 'node:http';

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

for (const validationKind of ['issues', 'exception']) {
  test(`DSN typed ${validationKind} preserves validation and sanitized cleanup uncertainty`, async t => {
    const calls = [];
    let cancelled = 0;
    stubFetch(t, async (url, options) => {
      const operation = url.pathname.split('/').at(-1);
      calls.push(operation);
      if (operation === 'connect') return Response.json(profile());
      if (operation === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
      assert.equal(operation, 'read');
      assert.equal(options.headers.authorization, `Bearer ${secret}`);
      return new Response(new ReadableStream({
        start(controller) {controller.enqueue(new TextEncoder().encode('{"n":1}\n'));},
        cancel() {cancelled++; throw new Error(secret);},
      }));
    });
    const client = await connect(dsn);
    t.after(() => client.close());
    const result = (await client.attach(ref)).result('answer');
    const issues = [{message: 'Expected a different row', path: ['n']}];
    const schema = {'~standard': {version: 1, vendor: 'dsn-integration', validate() {
      if (validationKind === 'exception') throw new Error(secret);
      return {issues};
    }}};
    await assert.rejects(result.all(schema), error => {
      assert.equal(error.code, 'ResultValidationFailed');
      assert.equal(error.validationKind, validationKind);
      assert.equal(error.rowIndex, 0);
      assert.equal(error.rowsYielded, 0);
      assert.deepEqual(error.resultRef, result.ref);
      assert.equal(explainReadFailure(error).cleanup, 'unknown');
      assert.equal(error.cleanupError.message, 'ResultReadCleanupUnknown');
      if (validationKind === 'issues') assert.equal(error.issues, issues);
      noSecret(error);
      return true;
    });
    assert.equal(cancelled, 1);
    assert.deepEqual(calls, ['connect', 'attach', 'read']);
  });
}

test('invalid HTTP DSNs and guessed object flags cannot retrieve credentials or select plaintext', async t => {
  let credentials = 0, requests = 0;
  const token = () => {credentials++; return secret;};
  stubFetch(t, () => {requests++; throw new Error('UnexpectedFetch');});
  for (const uri of ['actql://example.test/workspace-A?transport=http',
    'actql://localhost:0/workspace-A?transport=http',
    'actql://localhost/workspace-A?transport=http&transport=http']) {
    await assert.rejects(connect(uri, {token}), {code: 'InvalidConnectionString'});
  }
  for (const extra of [{}, {directLoopbackHttp: true}, {transport: 'http'}, {allowInsecure: true}]) {
    await assert.rejects(connect({mode: 'remote', endpoint: 'http://127.0.0.1:8080/',
      workspaceId: 'workspace-A', token, ...extra}), {code: 'InvalidConnectionEndpoint'});
  }
  assert.deepEqual({credentials, requests}, {credentials: 0, requests: 0});
});

test('bare localhost remains HTTPS and does not retry as HTTP after a TLS failure', async t => {
  let requests = 0;
  stubFetch(t, async url => {
    requests++;
    assert.equal(url.protocol, 'https:');
    throw new Error(`TLS failure with ${secret}`);
  });
  await assert.rejects(connect('actql://localhost:8080/workspace-A', {token: secret}),
    error => {noSecret(error); return error.code === 'ClientTransportUnknown';});
  assert.equal(requests, 1);
});

for (const phase of ['before-headers', 'wire-limit', 'truncated']) {
  test(`HTTP DSN read ${phase} preserves one attempt and closes its original socket`, {timeout: 5000}, async t => {
    let entered, disconnected;
    const started = new Promise(resolve => {entered = resolve;});
    const ended = new Promise(resolve => {disconnected = resolve;});
    const calls = [];
    const server = createServer(async (request, response) => {
      const operation = request.url.split('/').at(-1); calls.push(operation);
      assert.equal(request.headers.authorization, `Bearer ${secret}`);
      let text = ''; for await (const chunk of request) text += chunk;
      assert.equal(JSON.parse(text).connection.workspaceId, 'workspace-A');
      if (operation === 'connect' || operation === 'attach') {
        response.writeHead(200, {'content-type': 'application/json'});
        response.end(JSON.stringify(operation === 'connect' ? profile() : {ref, durability: 'durable', revision: 1}));
        return;
      }
      assert.equal(operation, 'read'); response.once('close', disconnected); entered();
      if (phase === 'before-headers') return;
      response.writeHead(200, {'content-type': 'application/jsonl'});
      if (phase === 'wire-limit') response.write('{"value":123456789}\n');
      else response.end('{"value":1}\n');
    });
    await new Promise((resolve, reject) => {server.once('error', reject);
      server.listen({host: '127.0.0.1', port: 0}, () => {server.off('error', reject); resolve();});});
    t.after(() => new Promise(resolve => {server.closeAllConnections(); server.close(resolve);}));
    const client = await connect(`actql://localhost:${server.address().port}/workspace-A?transport=http`, {token: secret});
    const controller = new AbortController();
    const reader = (await client.attach(ref)).result('answer').rows({signal: controller.signal,
      ...(phase === 'wire-limit' ? {maxWireBytes: 8} : {})});
    const reading = Array.fromAsync(reader);
    const rejected = assert.rejects(reading, error => {
      noSecret(error);
      assert.equal(error.attemptId, reader.attemptId);
      assert.equal(error.rowsYielded, phase === 'truncated' ? 1 : 0);
      if (phase !== 'before-headers') assert.equal(error.code,
        phase === 'wire-limit' ? 'ResultWireLimit' : 'IncompleteResultStream');
      return true;
    });
    await started;
    if (phase === 'before-headers') controller.abort();
    await rejected; await ended; await client.close();
    assert.deepEqual(calls, ['connect', 'attach', 'read']);
  });
}

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
    } finally {await client.close();}
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
  finally {await client.close();}
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
  } finally {await client.close();}
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
  } finally {await client.close();}
});

test('DSN delivery lookup preserves the original candidate without a secret-bearing body failure', async t => {
  const operations = [];
  stubFetch(t, async url => {
    const operation = url.pathname.split('/').at(-1); operations.push(operation);
    if (operation === 'connect') return Response.json(profile());
    if (operation === 'attach') return Response.json({ref, durability: 'durable', revision: 1});
    assert.equal(operation, 'delivery-attempt');
    return new Response(new ReadableStream({start(controller) {
      controller.error(new Error(dsn, {cause: new Error(secret)}));
    }}));
  });
  const client = await connect(dsn);
  try {
    const result = (await client.attach(ref)).result('answer');
    await assert.rejects(result.deliveryAttempt('original-read'), error => {
      assert.equal(error.code, 'InvalidHostAttemptLookup');
      assert.equal(Object.hasOwn(error, 'cause'), false);
      const explanation = explainDeliveryAttempt(error);
      assert.equal(explanation.observation, 'lookup_uninterpretable');
      assert.deepEqual(explanation.next.ref, ref);
      assert.equal(explanation.next.resultName, 'answer');
      assert.equal(explanation.next.attemptId, 'original-read');
      noSecret(error); noSecret(explanation); return true;
    });
    assert.deepEqual(operations, ['connect', 'attach', 'delivery-attempt']);
  } finally {await client.close();}
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
    } finally {await client.close();}
  });
}

test('unasserted endpoint connections retain their original profile and request shape', async t => {
  stubFetch(t, async (_url, options) => {
    assert.equal(Object.hasOwn(JSON.parse(options.body).connection, 'workspaceId'), false);
    const answer = profile(); delete answer.workspaceId; return Response.json(answer);
  });
  const client = await connect({mode: 'remote', endpoint: 'https://example.test', token: 'legacy'});
  assert.equal(Object.hasOwn(client.profile, 'workspaceId'), false); await client.close();
});

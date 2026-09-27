import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {ClientError, connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {createDiagnosticObserver, diagnosticObserver} from
  '../host-common/diagnostic-observer.mjs';

const ref = {tenantId: 'tenant-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const state = {version: 'actql-run-state/0.1', run_id: 'run-a',
  status: 'succeeded', updated_at: '2026-09-24T00:00:00.000Z',
  next_action: {kind: 'refresh_availability', results: ['answer']},
  result_available: false, result_availability: {answer: {
    state: 'unknown', observed_at: '2026-09-24T00:00:00.000Z',
    reason: 'verification_pending'}}};

async function withServer(handler, run) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    return await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('submit has one outcome contract over HTTP and in-process', async () => {
  const profile = {version: 'actql-client-host/0.1', mode: 'local',
    owner: 'local', durability: 'durable', scopeRef: 'local-scope',
    capabilities: [], limits: {maxReadWireBytes: 4096,
      maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
      maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
      maxBatchRetainedValueBytes: 2048}};
  for (const scenario of ['accepted', 'held', 'refused', 'prepare-refused',
    'accepted-throw', 'accepted-client-error', 'accepted-public-code',
    'invalid-reply', 'foreign-held']) {
    for (const explicitId of [false, true]) {
      const outcomes = [];
      for (const transport of ['http', 'in-process']) {
        let sentId;
        let accepts = 0;
        const retained = new Map();
        const options = {
          authenticate: () => 'local-principal',
          authorizeConnection: () => true,
          negotiate: () => profile,
          maxRowBytes: 1024,
          prepareSubmit: () => {
            if (scenario === 'prepare-refused') {
              throw Object.assign(new Error('Invalid program'),
                {code: 'ClientProgramRejected'});
            }
            return Object.freeze({prepared: true});
          },
          submit: ({requestId}) => {
            sentId = requestId;
            if (scenario === 'refused') {
              throw Object.assign(new Error('Denied'),
                {code: 'ClientRunStartDenied'});
            }
            accepts++;
            const admission = {ref, durability: 'durable', revision: 1};
            retained.set(requestId, admission);
            if (scenario === 'accepted-throw') throw new Error('DiskFailure');
            if (scenario === 'accepted-client-error') {
              throw new ClientError('ClientHostFailure');
            }
            if (scenario === 'accepted-public-code') {
              throw Object.assign(new Error('Late failure'),
                {code: 'ClientAdmissionJournalUnavailable'});
            }
            if (scenario === 'invalid-reply') return {revision: 1};
            if (scenario === 'held' || scenario === 'foreign-held') {
              return {kind: 'held', requestId: scenario === 'held' ? requestId :
                'another-request', prepareAttemptId: 'prepare-a',
              state: 'waiting_checkpoint', durability: 'durable',
              lookupExpiresAt: '2026-10-03T00:00:00.000Z',
              checkpoint: {checkpointId: 'prepare-a-preflight',
                checkpointCid: `sha256:${'c'.repeat(64)}`, kind: 'run_scope',
                expiresAt: '2026-10-02T00:00:00.000Z'}};
            }
            return admission;
          },
        };
        const exercise = async (client, endpoint) => {
          try {
            const execution = await client.start({version: 'actql/0.1'},
              explicitId ? {requestId: 'saved-id'} : {});
            assert.deepEqual(execution.ref, ref);
            outcomes.push('accepted');
          } catch (error) {
            outcomes.push(error.code);
            if (['SubmissionUnknown', 'RequestHeld'].includes(error.code)) {
              assert.equal(error.requestId, sentId);
              assert.ok(typeof sentId === 'string' && sentId.length > 0);
              assert.deepEqual(error.lookupContext,
                {endpoint, scopeRef: profile.scopeRef});
              assert.ok(retained.has(error.requestId));
            }
          } finally { client.close(); }
          assert.equal(accepts,
            ['refused', 'prepare-refused'].includes(scenario) ? 0 : 1);
        };
        if (transport === 'http') {
          await withServer(createClientHttpHandler(options), async base => {
            await exercise(await connect({mode: 'local', owner: 'local',
              endpoint: `${base}/`, token: 'local-token'}), `${base}/`);
          });
        } else {
          await exercise(await connectInProcess({mode: 'local', owner: 'local'},
            createNodeInProcessClientHost(options)), 'actql:embedded');
        }
      }
      const expected = scenario === 'accepted' ? 'accepted' :
        scenario === 'held' ? 'RequestHeld' :
        scenario === 'refused' ? 'ClientRunStartDenied' :
        scenario === 'prepare-refused' ? 'ClientProgramRejected' :
        'SubmissionUnknown';
      assert.deepEqual(outcomes, [expected, expected], scenario);
    }
  }
});

test('unsettled authentication diagnostics do not block refusal or grow forever',
  async () => {
    let calls = 0;
    let finish;
    const observe = () => {
      calls++;
      return new Promise(resolve => { finish = resolve; });
    };
    const options = {authenticate: () => { throw new Error('Unavailable'); },
      authorizeConnection: () => true, negotiate: () => {}, observe,
      maxRowBytes: 1024};
    const body = {connection: {mode: 'remote', owner: 'remote',
      runners: [], consentRefs: []}, ref};
    const port = createNodeInProcessClientHost(options);
    for (let request = 0; request < 50; request++) {
      await assert.rejects(port.perform('status', body),
        {code: 'ClientAuthenticationDenied'});
    }
    await withServer(createClientHttpHandler(options), async base => {
      const response = await fetch(`${base}/actql/client/0.1/status`, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify(body), signal: AbortSignal.timeout(2000),
      });
      assert.equal(response.status, 403);
      assert.deepEqual(await response.json(), {code: 'ClientAuthenticationDenied'});
    });
    assert.equal(calls, 1);
    const sink = diagnosticObserver(observe);
    assert.equal(sink.status().active, 1);
    assert.equal(sink.status().queued, 32);
    assert.equal(sink.status().dropped, 18);
    sink.close();
    assert.equal(sink.status().queued, 0);
    assert.equal(sink.status().active, 1);
    finish();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(sink.status().active, 0);
  });

test('diagnostic delivery consumes throw and rejection without changing callers',
  async () => {
    for (const observe of [() => { throw new Error('SinkFailed'); },
      () => Promise.reject(new Error('SinkFailed'))]) {
      const sink = createDiagnosticObserver(observe, {maxQueued: 1});
      assert.equal(sink('event', {}), undefined);
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(sink.status().failures, 1);
      assert.equal(sink.status().active, 0);
      sink.close();
    }
  });

test('closing one diagnostic owner does not poison a later installation',
  async () => {
    let calls = 0;
    const observe = () => { calls++; };
    const first = diagnosticObserver(observe);
    first('before-close', {});
    first.close();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 0);
    const later = diagnosticObserver(observe);
    assert.notEqual(later, first);
    later('later-host', {});
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(calls, 1);
    later.close();
  });

for (const boundary of ['authenticate', 'authorize_connection']) {
  test(`authorization faults stay private at ${boundary} on both ports`,
    async () => {
      for (const fault of [false, true]) {
        const cause = new Error('private authentication service detail');
        const observations = [];
        let invoked = 0;
        const deny = () => {
          if (fault) throw cause;
          return false;
        };
        const options = {
          authenticate: boundary === 'authenticate' ? deny : () => 'owner',
          authorizeConnection: boundary === 'authorize_connection'
            ? deny : () => true,
          observe: async (name, detail) => {
            observations.push({name, detail});
            throw new Error('DiagnosticSinkFailed');
          },
          negotiate: () => { invoked++; },
          observeRun: () => { invoked++; },
          maxRowBytes: 1024,
        };
        const body = {connection: {mode: 'remote', owner: 'remote',
          runners: [], consentRefs: []}, ref};
        const code = boundary === 'authenticate'
          ? 'ClientAuthenticationDenied' : 'ClientConnectionDenied';
        await withServer(createClientHttpHandler(options), async base => {
          const response = await fetch(`${base}/actql/client/0.1/status`, {
            method: 'POST', headers: {'content-type': 'application/json'},
            body: JSON.stringify(body),
          });
          assert.equal(response.status, 403);
          assert.deepEqual(await response.json(), {code});
        });
        await assert.rejects(
          createNodeInProcessClientHost(options).perform('status', body),
          error => error.code === code && error.cause === undefined);
        assert.equal(invoked, 0);
        assert.equal(observations.length, fault ? 2 : 0);
        for (const {name, detail} of observations) {
          assert.equal(name, 'client_authorization_failed');
          assert.deepEqual(Object.keys(detail), ['failure']);
          assert.equal(detail.failure.cause, cause);
          assert.equal(detail.failure.operation, 'status');
          assert.equal(detail.failure.boundary, boundary);
        }
      }
    });
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

test('installed preparation cannot disappear before Run acceptance', async () => {
  let admissions = 0;
  const handler = createClientHttpHandler({
    authenticate: () => 'principal-a', authorizeConnection: () => true,
    prepareSubmit: () => undefined,
    submit: () => { admissions++; return undefined; },
  });
  await withServer(handler, async base => {
    const response = await fetch(`${base}/actql/client/0.1/submit`, {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify({connection: {mode: 'local', owner: 'local',
        runners: [], consentRefs: []}, requestId: 'saved-id', kind: 'aql',
      input: {text: '{}', format: 'json'}, parameters: null}),
    });
    assert.equal(response.status, 500);
    assert.deepEqual(await response.json(), {code: 'ClientHostFailure'});
  });
  assert.equal(admissions, 0);
});

test('Run start denial and changed request intent keep distinct HTTP errors',
  async () => {
    let code = 'ClientRunStartDenied';
    const handler = createClientHttpHandler({
      authenticate: () => 'principal-a', authorizeConnection: () => true,
      submit: () => { throw Object.assign(new Error(code), {code}); },
    });
    await withServer(handler, async base => {
      const send = () => fetch(`${base}/actql/client/0.1/submit`, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection: {mode: 'local', owner: 'local',
          runners: [], consentRefs: []}, requestId: 'saved-id', kind: 'aql',
        input: {text: '{}', format: 'json'}, parameters: null}),
      });
      const denied = await send();
      assert.equal(denied.status, 403);
      assert.deepEqual(await denied.json(), {code: 'ClientRunStartDenied'});
      code = 'ClientRequestIntentConflict';
      const conflict = await send();
      assert.equal(conflict.status, 409);
      assert.deepEqual(await conflict.json(),
        {code: 'ClientRequestIntentConflict'});
    });
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
    const body = Buffer.from(JSON.stringify({connection: {
      mode: 'remote', owner: 'remote', runners: [], consentRefs: [],
    }, requestId: 'badé', kind: 'program',
    input: {version: 'actql/0.1'}, parameters: null}), 'utf8');
    const accented = body.indexOf(Buffer.from('é'));
    assert.notEqual(accented, -1);
    body[accented + 1] = 0x28;
    const invalidUtf8 = await fetch(`${base}/actql/client/0.1/submit`, {
      method: 'POST', headers: {'content-type': 'application/json'},
      body,
    });
    assert.equal(invalidUtf8.status, 400);
    assert.deepEqual(await invalidUtf8.json(), {code: 'InvalidClientRequest'});
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
      lookupRequest: () => {
        if (reply instanceof Error) throw reply;
        return reply;
      },
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
      reply = Object.assign(new Error('ClientRequestLookupDenied'),
        {code: 'ClientRequestLookupDenied'});
      const denied = await send();
      assert.equal(denied.status, 403);
      assert.deepEqual(await denied.json(),
        {code: 'ClientRequestLookupDenied'});
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

test('Client Host validates custom status and wait replies', async () => {
  const connection = {mode: 'remote', owner: 'remote',
    runners: [], consentRefs: []};
  let reply = state;
  const handler = createClientHttpHandler({
    authenticate: () => 'principal-a',
    authorizeConnection: () => true,
    observeRun: () => reply,
    wait: () => reply,
  });
  await withServer(handler, async base => {
    const send = operation => fetch(
      `${base}/actql/client/0.1/${operation}`, {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection, ref,
          ...(operation === 'wait' ? {until: null} : {})}),
      });
    for (const operation of ['status', 'wait']) {
      assert.deepEqual(await (await send(operation)).json(), state);
    }
    reply = {...state, status: 'not_an_engine_state'};
    for (const operation of ['status', 'wait']) {
      const response = await send(operation);
      assert.equal(response.status, 500);
      assert.deepEqual(await response.json(), {code: 'ClientHostFailure'});
    }
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

test('wait disconnect ends only its observation and releases its listener',
  {timeout: 10000}, async () => {
    const connection = {mode: 'remote', owner: 'remote',
      runners: [], consentRefs: []};
    const responses = [];
    let entered;
    const waiting = new Promise(resolve => { entered = resolve; });
    let released;
    const release = new Promise(resolve => { released = resolve; });
    let active = 0;
    let waitCalls = 0;
    let cancelCalls = 0;
    let normal = false;
    const observedSignals = [];
    const handler = createClientHttpHandler({
      authenticate: () => 'principal-a',
      authorizeConnection: () => true,
      attach: () => ({ref, durability: 'volatile', revision: 1}),
      cancel: () => { cancelCalls++; return {accepted: true}; },
      wait: ({signal}) => {
        waitCalls++;
        observedSignals.push(signal);
        if (normal) return state;
        return new Promise((resolve, reject) => {
          active++;
          const onAbort = () => {
            active--;
            released();
            reject(new Error('WaitObservationAborted'));
          };
          signal.addEventListener('abort', onAbort, {once: true});
          entered();
          if (signal.aborted) onAbort();
        });
      },
    });
    await withServer((request, response) => {
      responses.push(response);
      return handler(request, response);
    }, async base => {
      const path = operation => `${base}/actql/client/0.1/${operation}`;
      const send = (operation, fields, signal) => fetch(path(operation), {
        method: 'POST', headers: {'content-type': 'application/json'},
        body: JSON.stringify({connection, ...fields}), signal,
      });
      const controller = new AbortController();
      const pending = send('wait', {ref, until: null}, controller.signal);
      await waiting;
      assert.equal(active, 1);
      controller.abort();
      await assert.rejects(pending, {name: 'AbortError'});
      await release;
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(active, 0);
      assert.equal(responses[0].listenerCount('close'), 0);
      assert.equal(observedSignals[0].aborted, true);
      assert.equal(cancelCalls, 0);

      const alreadyAborted = AbortSignal.abort();
      await assert.rejects(send('wait', {ref, until: null},
        alreadyAborted), {name: 'AbortError'});
      assert.equal(waitCalls, 1);
      assert.deepEqual(await (await send('attach', {ref})).json(),
        {ref, durability: 'volatile', revision: 1});
      normal = true;
      const normalController = new AbortController();
      const completed = await send('wait', {ref, until: null},
        normalController.signal);
      assert.deepEqual(await completed.json(), state);
      normalController.abort();
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(observedSignals[1].aborted, false);
      assert.equal(responses.at(-1).listenerCount('close'), 0);
      assert.equal(waitCalls, 2);
      assert.equal(cancelCalls, 0);
    });
  });

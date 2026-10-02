// Public SDK/installed-ingress acceptance, with the real request journal and
// common Run/control issuers. This does not define a cancellation-operation
// identity or simulate provider execution. The existing Run is unstarted.
import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueInstalledRunControlObservation,
  issueInstalledUnpublishedRunState} from
  '../host-common/run-state-observation.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
const requestId = 'saved-request';
const publicationControl = runtimeCore(moon).publicationControl;
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'durable', scopeRef: 'local-principal',
  capabilities: [], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
    maxBatchRetainedValueBytes: 2048}};

async function fixture(t, transport, loss) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-cancel-loss-'));
  const journal = openClientRequestJournal(directory);
  let database, server, client;
  t.after(async () => {
    client?.close();
    if (server !== undefined) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
    database?.close();
    journal.close();
    await rm(directory, {recursive: true, force: true});
  });
  // The journal's existing independently authored request identity vector.
  const identity = moon.clientRequestAdmitRecord(scope.authorityScopeCid,
    requestId,
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'),
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  const runDefinition = publicationControl.seal('run_definition',
    JSON.stringify({version: 'actql-run-definition/0.1',
      scope_id: 'namespace-a-scope', run_id: 'saved-run',
      compiled_plan_cid: cid('1'), invocation_template_cid: cid('2'),
      authorization_context_cid: cid('3'), input_artifact_set_cid: cid('4'),
      created_at: '2026-09-24T00:00:00.000Z',
      valid_until: '2098-01-01T00:00:00.000Z'}),
    {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});
  const accepted = journal.acceptDefinition(identity, {
    namespaceId: scope.namespaceId, runDefinition,
    lookupExpiresAt: '2099-01-01T00:00:00.000Z', resultNames: ['answer'],
  }, moon, publicationControl);
  journal.reserveDispatch(identity, {namespaceId: scope.namespaceId,
    currentAuthorization: true}, moon, publicationControl);
  // A separate SQLite connection observes committed facts, not a handler's
  // answer, SDK state, or the fixture's in-memory counters.
  database = new DatabaseSync(join(directory, 'client-requests.sqlite3'),
    {readOnly: true});
  const stored = () => database.prepare(`SELECT caller_request_id,
    namespace_id, authority_scope_cid, run_definition_cid, revision,
    cancellation_requested, dispatch_reserved, physical_start_reserved,
    physical_close_confirmed FROM client_requests ORDER BY caller_request_id`)
    .all().map(row => ({...row}));
  const before = stored();
  assert.equal(before.length, 1);
  assert.equal(before[0].cancellation_requested, 0);
  assert.equal(before[0].physical_start_reserved, 0);
  let authorized = true, cancelAllowed = true, cancelCalls = 0, submits = 0;
  const operations = [];
  const options = {
    authenticate: () => 'local-principal',
    authorizeConnection: ({principalId}) =>
      authorized && principalId === 'local-principal',
    negotiate: () => profile,
    attach: installNodeClientRunAttach({journal, requestControl: moon,
      publicationControl, authorizedScope: () => scope,
      authorizeRun: () => authorized}),
    lookupRequest: installNodeClientRequestLookup({journal, control: moon,
      authorizedScope: () => authorized ? scope : undefined}),
    submit() { submits++; assert.fail('observation must never submit a Run'); },
    cancel({ref}) {
      cancelCalls++;
      return journal.requestCancellation(ref, {
        currentAuthorization: cancelAllowed, publicationCommitted: false,
      }, moon, publicationControl);
    },
    observeRun({ref}) {
      const retained = journal.lookupRunDefinition(ref, moon,
        publicationControl);
      assert.ok(retained);
      return {...issueInstalledUnpublishedRunState(moon, {
        runId: publicationControl.runDefinitionRunId(retained.runDefinition),
        observedAt: '2026-10-02T00:00:00.000Z',
        resultNames: retained.resultNames,
        dispatchReserved: retained.dispatchReserved,
        preDispatchFailureConfirmed: retained.preDispatchFailureConfirmed,
        cancelledBeforeStart: retained.cancellationRequested &&
          retained.physicalStartReserved === false,
        observedTerminalOutcome: retained.observedTerminalOutcome ?? 'none',
        executionUnknown: false,
      }), control: issueInstalledRunControlObservation(moon, {
        revision: retained.revision,
        cancellationRequested: retained.cancellationRequested,
        physicallyUnstarted: retained.physicalStartReserved === false,
        preDispatchFailureConfirmed: retained.preDispatchFailureConfirmed,
        physicalCloseConfirmed: retained.physicalCloseConfirmed,
      })};
    },
    maxRowBytes: 1024,
  };
  let pendingLoss = loss;
  if (transport === 'in-process') {
    const port = createNodeInProcessClientHost(options);
    client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body, signal) {
        operations.push(operation);
        const phase = operation === 'cancel' ? pendingLoss : undefined;
        if (phase !== undefined) pendingLoss = undefined;
        if (phase === 'before-dispatch') throw new Error('LostCancelTransport');
        const reply = await port.perform(operation, body, signal);
        if (phase === 'after-commit') throw new Error('LostCancelTransport');
        return reply;
      },
    });
  } else {
    const handler = createClientHttpHandler(options);
    server = createServer((request, response) => {
      const operation = request.url.split('/').at(-1);
      operations.push(operation);
      const phase = operation === 'cancel' ? pendingLoss : undefined;
      if (phase !== undefined) pendingLoss = undefined;
      if (phase === 'before-dispatch') {
        request.resume();
        response.destroy();
        return;
      }
      if (phase === 'after-commit') {
        // sendJson is reached only after the actual cancellation committed.
        // Drop the successful response before any headers/body are delivered.
        response.end = () => {
          assert.equal(response.statusCode, 200);
          response.destroy();
          return response;
        };
      }
      void handler(request, response);
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'local', owner: 'local',
      endpoint: `http://127.0.0.1:${server.address().port}/`, token: 'test-token'});
  }
  const execution = await client.attach(accepted.ref);
  return {client, execution, before, stored, operations,
    counts: () => ({cancelCalls, submits}),
    authorize: value => { authorized = value; },
    authorizeCancel: value => { cancelAllowed = value; }};
}

for (const transport of ['in-process', 'http']) {
  for (const phase of ['before-dispatch', 'after-commit']) {
    test(`${transport} cancel loss ${phase} preserves same-Run observation`,
      async t => {
        const f = await fixture(t, transport, phase);
        const ref = {...f.execution.ref};
        await assert.rejects(f.execution.cancel(), {code: 'ClientTransportUnknown'});
        assert.deepEqual(f.execution.ref, ref);
        assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
        const committed = phase === 'after-commit';
        const expected = [{...f.before[0],
          cancellation_requested: committed ? 1 : 0,
          revision: f.before[0].revision + (committed ? 1 : 0)}];
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});

        // A retained handle or request ID cannot bypass current authorization.
        f.authorize(false);
        for (const operation of [() => f.execution.status(),
          () => f.client.attach(ref), () => f.client.lookupRequest(requestId),
          () => f.execution.cancel()]) {
          await assert.rejects(operation(), {code: 'ClientConnectionDenied'});
        }
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
        f.authorize(true);
        const found = await f.client.lookupRequest(requestId);
        assert.equal(found.kind, 'found');
        assert.equal(found.requestId, requestId);
        assert.deepEqual(found.ref, ref);
        const attached = await f.client.attach(found.ref);
        assert.deepEqual(attached.ref, ref);
        for (const handle of [f.execution, attached]) {
          const state = await handle.status();
          assert.equal(state.run_id, 'saved-run');
          assert.equal(state.status, committed ? 'cancelled' : 'running');
          assert.deepEqual(state.control, {
            revision: expected[0].revision,
            cancellation_requested: committed,
            physical_stop: committed ? 'confirmed' : 'unknown'});
        }
        // Read-only recovery changes neither the journal nor the write count.
        assert.deepEqual(f.stored(), expected);
        assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
        assert.equal(f.operations.filter(op => op === 'cancel').length, 2);
        assert.equal(f.operations.includes('submit'), false);
        assert.equal(f.operations.includes('reconcile'), false);
      });
  }
  test(`${transport} cancel refusal stays definitive and does not commit`,
    async t => {
      const f = await fixture(t, transport);
      f.authorizeCancel(false);
      await assert.rejects(f.execution.cancel(), error => {
        assert.equal(error.code, 'ClientRunCancellationDenied');
        assert.equal(error.status, 403);
        return true;
      });
      assert.deepEqual(f.stored(), f.before);
      assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
      assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
      assert.equal((await f.execution.status()).control.cancellation_requested,
        false);
      assert.deepEqual(f.stored(), f.before);
    });
}

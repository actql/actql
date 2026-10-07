// Public SDK/installed-ingress acceptance, with the real request journal and
// common Run/control issuers. This does not define a cancellation-operation
// identity or simulate provider execution. Physical-start/close facts in the
// explanation cases are recorded through the existing control owner only.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createServer as createTlsServer} from 'node:https';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test, {after} from 'node:test';
import * as sdk from '../../packages/sdk/index.mjs';
const {connect} = sdk;
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

const scratch = new URL('../../_build/client-cancel-tests/', import.meta.url).pathname;
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=actql-cancel-fixture', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'remote.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'remote.crt'));
setDefaultCACertificates([...getCACertificates('default'), tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));

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

async function fixture(t, transport, loss, {physicalStart = false, terminal = false,
  reply = null, runId = 'saved-run', targetOperation = 'cancel', cancelResponseCache, transformCancelReply, transformRunReply} = {}) {
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
      scope_id: 'namespace-a-scope', run_id: runId,
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
  if (physicalStart) {
    assert.equal(journal.reservePhysicalStart(identity, {namespaceId: scope.namespaceId,
      ref: accepted.ref, currentAuthorization: true}, moon, publicationControl), true);
  }
  if (terminal) journal.markPhysicalClose(accepted.ref, 'failed');
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
  assert.equal(before[0].physical_start_reserved, physicalStart ? 1 : 0);
  let authorized = true, cancelAllowed = true, cancelCalls = 0, submits = 0, credentialFailure;
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
    // This fixture connects the actual request journal and existing Run
    // cancellation owner to both installed ingress adapters. It does not
    // replace the production held-preparation cancellation or dispatch owner.
    cancelRequest({requestId: requested}) {
      const existing = journal.lookupDefinition({...scope, requestId: requested},
        moon, publicationControl);
      assert.ok(existing);
      return {requestId: requested, ...options.cancel({ref: existing.ref})};
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
  const alterReply = value => transformCancelReply !== undefined
    ? transformCancelReply(value) : cancelResponseCache !== undefined
    ? Object.assign(cancelResponseCache, value) : reply === 'foreign_ref'
    ? {...value, ref: {...value.ref, runDefinitionCid: cid('f')}}
    : reply === 'malformed' ? {}
    : reply === 'response_object' ? new Response('{}') : value;
  let pendingLoss = loss;
  if (transport === 'in-process') {
    const port = createNodeInProcessClientHost(options);
    client = await connectInProcess({mode: 'local', owner: 'local'}, {
      async perform(operation, body, signal) {
        operations.push(operation);
        const phase = operation === targetOperation ? pendingLoss : undefined;
        if (phase !== undefined) pendingLoss = undefined;
        if (phase === 'before-dispatch') throw new Error('LostCancelTransport');
        const reply = await port.perform(operation, body, signal);
        if (phase === 'after-commit') throw new Error('LostCancelTransport');
        return operation === targetOperation ? alterReply(reply) : operation === 'status' && transformRunReply ? transformRunReply(reply) : reply;
      },
    });
  } else {
    const handler = createClientHttpHandler(options);
    const serve = (request, response) => {
      const operation = request.url.split('/').at(-1);
      operations.push(operation);
      const phase = operation === targetOperation ? pendingLoss : undefined;
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
      if (operation === targetOperation && (reply !== null || cancelResponseCache !== undefined || transformCancelReply !== undefined)) {
        const end = response.end;
        response.end = function(data, ...args) {
          assert.equal(response.statusCode, 200);
          const value = JSON.parse(data.toString());
          return end.call(this, JSON.stringify(alterReply(value)), ...args);
        };
      }
      if (operation === 'status' && transformRunReply) {
        const end = response.end;
        response.end = function(data, ...args) {
          if (response.statusCode !== 200) return end.call(this, data, ...args);
          return end.call(this, JSON.stringify(transformRunReply(JSON.parse(data.toString()))), ...args);
        };
      }
      void handler(request, response);
    };
    server = transport === 'https'
      ? createTlsServer({key: tlsKey, cert: tlsCertificate}, serve) : createServer(serve);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'local', owner: 'local',
      endpoint: `${transport === 'https' ? 'https' : 'http'}://127.0.0.1:${server.address().port}/`,
      token: async () => { if (credentialFailure) throw credentialFailure; return 'test-token'; }});
  }
  const execution = await client.attach(accepted.ref);
  return {client, execution, before, stored, operations,
    counts: () => ({cancelCalls, submits}),
    authorize: value => { authorized = value; },
    authorizeCancel: value => { cancelAllowed = value; },
    rejectCredentials: value => { credentialFailure = value; }};
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


for (const [scenario, transformCancelReply] of [
  ['clone erases fields', value => Object.assign(new Date(0), value)],
  ['clone throws', value => new Proxy(value, {})],
  ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(field =>
    [`clone changes ${field}`, value => {
      const original = value.ref[field];
      let reads = 0;
      return {...value, ref: Object.defineProperty({...value.ref}, field, {
        enumerable: true,
        // The schema check and Run comparison see the issued field. Cloning
        // receives a different, still well-formed field from the Local getter.
        get: () => ++reads <= 2 ? original
          : field === 'namespaceId' ? 'foreign-namespace' : cid('f'),
      })};
    }]),
]) {
  test(`in-process: cancellation ${scenario} retains original Run uncertainty`, async t => {
    const f = await fixture(t, 'in-process', undefined, {
      physicalStart: true, transformCancelReply});
    const ref = {...f.execution.ref};
    const result = await f.execution.cancel().then(value => ({value}), error => ({error}));
    assert.equal(result.error?.code, 'InvalidHostCancellation', '[check-mutation:cancel-clone-invalid]');
    const expected = {observation: 'outcome_unknown',
      summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
      next: {operation: 'status', ref}};
    assert.deepEqual(sdk.explainCancellation(result.error), expected, '[check-mutation:cancel-clone-uncertainty]');
    assert.equal(sdk.explainCancellation({...result.error}), undefined);
    assert.deepEqual(f.execution.ref, ref);
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel']);
    const committed = [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}];
    assert.deepEqual(f.stored(), committed);
    const state = await f.execution.status();
    assert.equal(state.status, 'running');
    assert.equal(state.control.physical_stop, 'unknown');
    assert.equal(state.control.cancellation_requested, true);
    assert.deepEqual(sdk.explainCancellation(result.error), expected);
    assert.deepEqual(f.stored(), committed);
    assert.deepEqual(f.counts(), {cancelCalls: 1, submits: 0});
    assert.deepEqual(f.operations, ['connect', 'attach', 'cancel', 'status']);
  });
}

for (const transport of ['in-process', 'https']) {
  test(`${transport}: reused cancellation replies preserve each original Run observation`, async t => {
    // Reuse a Local port's response object, or its HTTPS serializer input,
    // while both cancellations still pass through the actual journal owner.
    const cancelResponseCache = {};
    const a = await fixture(t, transport, undefined, {
      physicalStart: true, runId: 'cache-run-a', cancelResponseCache});
    const b = await fixture(t, transport, undefined, {
      physicalStart: true, runId: 'cache-run-b', cancelResponseCache});
    assert.notDeepEqual(a.execution.ref, b.execution.ref);
    const expected = f => ({observation: 'accepted',
      revision: f.before[0].revision + 1,
      summary: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.',
      next: {operation: 'status', ref: {...f.execution.ref}}});
    const first = await a.execution.cancel();
    const second = await b.execution.cancel();
    assert.deepEqual(sdk.explainCancellation(first), expected(a), '[check-mutation:cancel-custody]');
    assert.deepEqual(sdk.explainCancellation(second), expected(b), '[check-mutation:cancel-custody]');
    assert.notEqual(first, second);
    assert.deepEqual(first, {kind: 'accepted', ref: a.execution.ref,
      revision: a.before[0].revision + 1});
    assert.deepEqual(second, {kind: 'accepted', ref: b.execution.ref,
      revision: b.before[0].revision + 1});
    const repeated = await a.execution.cancel();
    assert.deepEqual(sdk.explainCancellation(repeated), {...expected(a),
      observation: 'already_requested',
      summary: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.'});
    assert.deepEqual(sdk.explainCancellation(first), expected(a), '[check-mutation:cancel-custody]');
    assert.deepEqual(sdk.explainCancellation(second), expected(b), '[check-mutation:cancel-custody]');
    assert.equal(sdk.explainCancellation({...first}), undefined);
    for (const f of [a, b]) {
      assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
        revision: f.before[0].revision + 1}]);
      const state = await f.execution.status();
      assert.equal(state.status, 'running');
      assert.equal(state.control.physical_stop, 'unknown');
      assert.equal(state.control.cancellation_requested, true);
    }
    assert.deepEqual(a.counts(), {cancelCalls: 2, submits: 0});
    assert.deepEqual(b.counts(), {cancelCalls: 1, submits: 0});
  });

  test(`${transport}: Run cancellation explanations retain recorded control facts`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true});
    const accepted = await f.execution.cancel();
    assert.equal(typeof sdk.explainCancellation, 'function', '[check-mutation:cancel-explanation-api]');
    const next = {operation: 'status', ref: {...f.execution.ref}};
    const expected = {observation: 'accepted', revision: f.before[0].revision + 1,
      summary: 'The Host recorded a Run cancellation request. Refresh Run state for physical stop, Effects and release.', next};
    assert.deepEqual(sdk.explainCancellation(accepted), expected, '[check-mutation:cancel-explanation]');
    const beforeLocale = f.counts();
    for (const format of ['text', 'html', 'json']) {
      const output = sdk.formatCancellation(accepted, {format});
      assert.ok(output);
      if (format === 'json') assert.deepEqual(JSON.parse(output).explanation, expected,
        '[check-mutation:operation-cancel-public-format]');
    }
    assert.deepEqual(sdk.explainCancellation(accepted, {locale: 'ja'}), {...expected,
      summary: 'HostはRunの取消し要求を記録しました。物理停止・Effect・解放はRunの現在状態で確認してください。'},
    '[check-mutation:operation-cancel-public-locale]');
    assert.deepEqual(f.counts(), beforeLocale, '[check-mutation:operation-cancel-public-passive]');

    assert.equal(f.stored()[0].physical_close_confirmed, 0);
    const state = await f.execution.status();
    assert.equal(state.status, 'running');
    assert.equal(state.control.cancellation_requested, true);
    assert.equal(state.control.physical_stop, 'unknown');
    const already = await f.execution.cancel();
    assert.deepEqual(sdk.explainCancellation(already), {...expected,
      observation: 'already_requested',
      summary: 'The Host reports an existing Run cancellation request. Refresh Run state for physical stop, Effects and release.'},
    '[check-mutation:cancel-explanation]');
    assert.deepEqual(sdk.explainCancellation(JSON.parse(JSON.stringify(accepted))), undefined);
    assert.deepEqual(sdk.explainCancellation({kind: 'accepted', ref: f.execution.ref, revision: 999}), undefined);
    assert.equal(Object.isFrozen(sdk.explainCancellation(accepted).next.ref), true);
    if (!Object.isFrozen(accepted)) accepted.kind = 'already_terminal';
    assert.deepEqual(sdk.explainCancellation(accepted), expected, '[check-mutation:cancel-explanation]');
    assert.deepEqual(f.counts(), {cancelCalls: 2, submits: 0});
    f.authorize(false);
    await assert.rejects(f.execution.status(), {code: 'ClientConnectionDenied'});
    await assert.rejects(f.execution.cancel(), error => {
      assert.equal(sdk.explainCancellation(error), undefined);
      return error.code === 'ClientConnectionDenied';
    });
    assert.deepEqual(f.counts(), {cancelCalls: 2, submits: 0});
    assert.deepEqual(sdk.explainCancellation(accepted), expected);
    const terminal = await fixture(t, transport, undefined, {physicalStart: true, terminal: true});
    const reply = await terminal.execution.cancel();
    assert.deepEqual(sdk.explainCancellation(reply), {
      observation: 'already_terminal', revision: terminal.before[0].revision,
      summary: 'The Host reports the Run is already terminal for cancellation. Refresh Run state for Effect and release details.',
      next: {operation: 'status', ref: {...terminal.execution.ref}},
    }, '[check-mutation:cancel-explanation]');
    assert.equal(sdk.explainCancellation(reply, {locale: 'ja'}).summary,
      'Hostは取消しについてRunが既に終端状態にあると報告しました。Effect・解放の詳細はRunの現在状態で確認してください。');
    assert.equal(terminal.stored()[0].cancellation_requested, 0);
  });

  test(`${transport}: Run cancellation uncertainty retains read-only observation advice`, async t => {
    assert.equal(typeof sdk.explainCancellation, 'function', '[check-mutation:cancel-explanation-api]');
    for (const scenario of [
      {phase: 'before-dispatch', committed: false},
      {phase: 'after-commit', committed: true},
      {reply: 'foreign_ref', committed: true},
      {reply: 'malformed', committed: true},
      ...(transport === 'in-process' ? [{reply: 'response_object', committed: true}] : []),
    ]) {
      const f = await fixture(t, transport, scenario.phase, {reply: scenario.reply ?? null, physicalStart: true});
      let error;
      await assert.rejects(f.execution.cancel(), cause => {error = cause; return true;});
      if (scenario.reply === 'response_object') {
        assert.equal(error.code, 'InvalidLocalHostPortResponse');
      }
      const before = f.stored();
      assert.equal(before[0].cancellation_requested, scenario.committed ? 1 : 0);
      assert.equal(before[0].physical_close_confirmed, 0);
      assert.deepEqual(f.counts(), {cancelCalls: scenario.committed ? 1 : 0, submits: 0});
      const expected = {observation: 'outcome_unknown',
        summary: 'The Run cancellation outcome is unknown. The request may have been recorded.',
        next: {operation: 'status', ref: {...f.execution.ref}}};
      assert.deepEqual(sdk.explainCancellation(error), expected, '[check-mutation:cancel-unknown-explanation]');
      assert.deepEqual(sdk.explainCancellation(error, {locale: 'ja'}), {...expected,
        summary: 'Run取消しの結果を確認できません。要求は記録されている可能性があります。'},
      '[check-mutation:operation-cancel-unknown-public-locale]');

      error.code = 'Accepted'; error.message = 'stopped';
      assert.deepEqual(sdk.explainCancellation(error), expected, '[check-mutation:cancel-unknown-explanation]');
      assert.equal(sdk.explainCancellation(Object.assign(new Error(error.message), error)), undefined);
      await f.execution.status();
      assert.deepEqual(f.stored(), before);
      assert.deepEqual(f.counts(), {cancelCalls: scenario.committed ? 1 : 0, submits: 0});
      assert.deepEqual(sdk.explainCancellation(error), expected);
    }
    if (transport === 'https') {
      const credentials = await fixture(t, transport);
      const failed = new Error('private credential failure');
      credentials.rejectCredentials(failed);
      await assert.rejects(credentials.execution.cancel(), error => {
        assert.equal(error, failed);
        assert.equal(sdk.explainCancellation(error), undefined);
        return true;
      });
      assert.deepEqual(credentials.counts(), {cancelCalls: 0, submits: 0});
    }
    const closed = await fixture(t, transport);
    closed.client.close();
    await assert.rejects(closed.execution.cancel(), error => {
      assert.equal(sdk.explainCancellation(error), undefined);
      return error.code === 'ClientClosed';
    });
    assert.deepEqual(closed.counts(), {cancelCalls: 0, submits: 0});
  });
}


for (const transport of ['in-process', 'https']) {
  test(`${transport}: uninterpretable Run observations retain only the original authorized lookup`, async t => {
    let alter = value => value;
    const setup = await fixture(t, transport, undefined, {transformRunReply: value => alter(value)});
    const {execution} = setup;
    const original = await execution.status();
    assert.equal(original.status, 'running');
    const before = setup.stored();
    for (const [mutation, kind, problem] of [
      [value => ({...value, status: 'private-future-state', next_action: {kind: 'submit'}}), 'uninterpretable', 'unknown_state'],
      [value => ({...value, result_available: 'true'}), 'protocol_failure', 'malformed_response'],
      [value => ({...value, version: 'actql-private-future-state/0.1'}), 'protocol_failure', 'contract_mismatch'],
    ]) {
      alter = mutation;
      const previous = setup.operations.length;
      let error;
      try { await execution.status(); } catch (failure) { error = failure; }
      assert.equal(error?.code, 'InvalidHostRunState', '[check-mutation:run-protocol-public-rejection]');
      const view = sdk.explainRunObservationFailure(error);
      assert.deepEqual({kind: view?.kind, problem: view?.problem, operation: view?.operation},
        {kind, problem, operation: 'status'}, '[check-mutation:run-protocol-public-kind]');
      assert.deepEqual(view.next, {operation: 'status', ref: execution.ref}, '[check-mutation:run-protocol-public-ref]');
      assert.equal(sdk.explainRunObservationFailure({...error}), undefined);
      assert.equal(sdk.explainRunObservationFailure(error, {locale: 'ja'}).kind, kind);
      assert.equal(sdk.explainEffectUncertainty(error), undefined);
      assert.doesNotMatch(JSON.stringify({error, view}), /private-future-state|actql-private/);
      assert.deepEqual(setup.operations.slice(previous), ['status'], '[check-mutation:run-protocol-public-passive]');
      assert.deepEqual(setup.stored(), before);
    }
    alter = value => value;
    assert.deepEqual(await execution.status(), original);
    setup.authorize(false);
    let denied;
    try { await execution.status(); } catch (error) { denied = error; }
    assert.ok(denied);
    assert.equal(sdk.explainRunObservationFailure(denied), undefined);
    assert.deepEqual(setup.counts(), {cancelCalls: 0, submits: 0});
    assert.deepEqual(setup.stored(), before);
  });
}

for (const [entrance, transport] of [['local', 'in-process'], ['https', 'https']]) {
  test(`${entrance}: copied Run observations retain original owner facts`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true});
    const before = await f.execution.status();
    assert.equal(before.status, 'running');
    assert.equal(before.control.physical_stop, 'unknown');
    const clone = globalThis.structuredClone;
    t.after(() => { globalThis.structuredClone = clone; });
    let changed = 0;
    globalThis.structuredClone = value => {
      const copy = clone(value);
      if (value?.version === 'actql-run-state/0.1') {
        changed++;
        copy.control.physical_stop = 'confirmed';
        copy.control.revision++;
        copy.run_id = 'foreign-run-copy';
      }
      return copy;
    };
    let rejected;
    try { await f.execution.status(); } catch (error) { rejected = error; }
    assert.equal(rejected?.code, 'InvalidHostRunState', '[check-mutation:run-copy-public]');
    assert.ok(changed > 0, 'Fault must affect a Run observation copy');
    assert.deepEqual(sdk.explainRunObservationFailure(rejected), {
      kind: 'protocol_failure', problem: 'malformed_response', operation: 'status',
      summary: 'The Run reply violates the registered state contract.',
      hint: 'Refresh the original Run under current authorization. This observation establishes no execution, Effect, publication or release outcome and grants no write retry.',
      next: {operation: 'status', ref: f.execution.ref},
    });
    assert.equal(sdk.explainEffectUncertainty(rejected), undefined);
    assert.equal(Object.hasOwn(rejected, 'cause'), false);
    assert.doesNotMatch(JSON.stringify(rejected), /foreign-run-copy/);
    assert.equal(before.control.physical_stop, 'unknown');
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
    assert.equal(f.operations.filter(operation => operation === 'status').length, 2);
    globalThis.structuredClone = clone;
    const refreshed = await f.execution.status();
    assert.deepEqual(refreshed, before);
    assert.equal(f.operations.filter(operation => operation === 'status').length, 3);
    f.authorize(false);
    let denied;
    try { await f.execution.status(); } catch (error) { denied = error; }
    assert.equal(denied.code, 'ClientConnectionDenied');
    assert.equal(sdk.explainRunObservationFailure(denied), undefined);
    assert.deepEqual(f.stored(), f.before);
    assert.deepEqual(f.counts(), {cancelCalls: 0, submits: 0});
  });
  test(`${entrance}: request cancellation acceptance retains an unconfirmed physical stop`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true, targetOperation: 'cancel-request'});
    const answer = await f.client.cancelRequest(requestId);
    assert.equal(answer.kind, 'accepted');
    const explanation = sdk.explainRequestCancellation(answer);
    assert.deepEqual({observation: explanation.observation, requestId: explanation.requestId,
      revision: explanation.revision, next: explanation.next}, {
      observation: 'accepted', requestId, revision: f.before[0].revision + 1,
      next: {operation: 'status', ref: {...f.execution.ref}},
    }, '[check-mutation:request-cancel-public]');
    for (const field of ['stopped', 'physicalStop', 'cleanupComplete', 'resourcesReleased', 'runStatus', 'effectOutcome', 'cancelRef', 'permission']) {
      assert.equal(Object.hasOwn(explanation, field), false, '[check-mutation:request-cancel-physical-claim]');
    }
    assert.deepEqual(f.stored(), [{...f.before[0], cancellation_requested: 1,
      revision: f.before[0].revision + 1}]);
    const current = await f.execution.status();
    assert.equal(current.control.cancellation_requested, true);
    assert.equal(current.control.physical_stop, 'unknown');
    const before = {...f.counts()};
    for (const locale of ['en', 'ja']) for (const format of ['text', 'html', 'json']) {
      assert.ok(sdk.formatRequestCancellation(answer, {locale, format}));
    }
    assert.deepEqual(f.counts(), before);
    assert.equal(sdk.explainRequestCancellation(structuredClone(answer)), undefined);
    assert.equal(sdk.getSubmissionInput(answer), undefined);
    f.authorize(false);
    await assert.rejects(f.client.lookupRequest(requestId), {code: 'ClientConnectionDenied'});
    assert.deepEqual(f.counts(), before);
  });
  for (const phase of ['before-dispatch', 'after-commit']) {
    test(`${entrance}: request cancellation loss ${phase} keeps the original lookup without inventing acceptance`, async t => {
      const f = await fixture(t, transport, phase, {physicalStart: true, targetOperation: 'cancel-request'});
      let failure;try {await f.client.cancelRequest(requestId);} catch (error) {failure = error;}
      assert.equal(failure.code, 'CancellationUnknown');
      assert.equal(failure.requestId, requestId);
      const explanation = sdk.explainRequestCancellation(failure);
      assert.deepEqual({observation: explanation.observation, problem: explanation.problem,
        requestId: explanation.requestId, operation: explanation.next.operation,
        nextRequestId: explanation.next.requestId, scopeRef: explanation.next.lookupContext.scopeRef}, {
        observation: 'outcome_unknown', problem: 'exchange_failed', requestId,
        operation: 'lookupRequest', nextRequestId: requestId, scopeRef: 'local-principal',
      }, '[check-mutation:request-cancel-loss]');
      const committed = phase === 'after-commit';
      const expected = [{...f.before[0], cancellation_requested: committed ? 1 : 0,
        revision: f.before[0].revision + (committed ? 1 : 0)}];
      assert.deepEqual(f.stored(), expected);
      assert.deepEqual(f.counts(), {cancelCalls: committed ? 1 : 0, submits: 0});
      for (const locale of ['en', 'ja']) assert.ok(sdk.formatRequestCancellation(failure, {locale}));
      const found = await f.client.lookupRequest(requestId);
      assert.equal(found.kind, 'found');
      assert.deepEqual(found.ref, f.execution.ref);
      const current = await f.execution.status();
      assert.equal(current.control.cancellation_requested, committed);
      assert.equal(current.control.physical_stop, 'unknown');
      assert.deepEqual(f.stored(), expected);
      assert.equal(f.operations.filter(op => op === 'cancel-request').length, 1);
      assert.equal(f.operations.includes('submit'), false);
      assert.equal(f.operations.includes('reconcile'), false);
    });
  }
  test(`${entrance}: request cancellation already-terminal observation does not invent its Run outcome`, async t => {
    const f = await fixture(t, transport, undefined, {physicalStart: true, terminal: true, targetOperation: 'cancel-request'});
    const answer = await f.client.cancelRequest(requestId);
    assert.equal(answer.kind, 'already_terminal');
    const explanation = sdk.explainRequestCancellation(answer);
    assert.equal(explanation.observation, 'already_terminal');
    assert.equal(explanation.summary, 'The Host reports that this request is already terminal. This response does not establish its execution outcome, physical stop or resource release.');
    assert.deepEqual(explanation.next.ref, f.execution.ref);
    assert.equal(Object.hasOwn(explanation, 'runStatus'), false);
    assert.equal((await f.execution.status()).status, 'failed');
    assert.deepEqual(f.stored(), f.before);
  });
}

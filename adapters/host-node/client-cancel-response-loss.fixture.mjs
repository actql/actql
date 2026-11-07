// Public SDK/ingress component with the real request journal and
// common Run/control issuers and cancellation-operation custody. This does not
// establish ordinary Host or funded execution acceptance. Physical-start/close
// facts are recorded through the existing control owner only.
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
import {issueInstalledUnpublishedRunState} from
  '../host-common/run-state-observation.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRequestLookup} from './client-request-lookup.mjs';
import {installNodeClientRunAttach} from './client-run-attach.mjs';
import {fundedClientPreparation} from './funded-client-preparation.fixture.mjs';

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

export const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
export const requestId = 'saved-request';
const publicationControl = runtimeCore(moon).publicationControl;
const profile = {version: 'actql-client-host/0.1', mode: 'local',
  owner: 'local', durability: 'durable', scopeRef: 'local-principal',
  capabilities: [], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 10,
    maxBatchRetainedValueBytes: 2048}};

export async function fixture(t, transport, loss, {physicalStart = false, terminal = false,
  reply = null, runId = 'saved-run', targetOperation = 'cancel', cancelResponseCache, transformCancelReply, transformRunReply, transformLookupReply} = {}) {
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
    cancel({ref, cancelId, expectedRevision, attemptRef}) {
      cancelCalls++;
      const {recorded: _recorded, ...outcome} = journal.recordCancellationAttempt(ref, {
        attemptRef, cancelId, expectedRevision, currentAuthorization: cancelAllowed,
        publicationCommitted: false,
      }, moon, publicationControl);
      return outcome;
    },
    lookupCancellation({ref, cancelId, expectedRevision}) {
      return journal.lookupCancellationOperation({...ref, cancelId, expectedRevision},
        {currentAuthorization: cancelAllowed}, moon, publicationControl);
    },
    // This fixture connects the actual request journal and existing Run
    // cancellation owner to both installed ingress adapters. It does not
    // replace the production held-preparation cancellation or dispatch owner.
    cancelRequest({requestId: requested}) {
      const existing = journal.lookupDefinition({...scope, requestId: requested},
        moon, publicationControl);
      assert.ok(existing);
      cancelCalls++;
      return {requestId: requested, ...journal.requestCancellation(existing.ref, {
        currentAuthorization: cancelAllowed, publicationCommitted: false,
      }, moon, publicationControl)};
    },
    observeRun({ref}) {
      const retained = journal.lookupRunDefinition(ref, moon,
        publicationControl);
      assert.ok(retained);
      const state = issueInstalledUnpublishedRunState(moon, {
        runId: publicationControl.runDefinitionRunId(retained.runDefinition),
        observedAt: '2026-10-02T00:00:00.000Z',
        resultNames: retained.resultNames,
        dispatchReserved: retained.dispatchReserved,
        preDispatchFailureConfirmed: retained.preDispatchFailureConfirmed,
        cancelledBeforeStart: retained.cancellationRequested &&
          retained.physicalStartReserved === false,
        observedTerminalOutcome: retained.observedTerminalOutcome ?? 'none',
        executionUnknown: false,
      });
      return Object.freeze(JSON.parse(journal.publishRunState(retained, state,
        moon, publicationControl)));
    },
    maxRowBytes: 1024,
  };
  // Existing capture faults still target the durable cancellation DTO, which
  // is now nested in the invocation-bound public result.
  const alterReply = value => transformCancelReply !== undefined
    ? {...value, cancellation: transformCancelReply(value.cancellation)} : cancelResponseCache !== undefined
    ? Object.assign(cancelResponseCache, value) : reply === 'foreign_ref'
    ? {...value, cancellation: {...value.cancellation,
      ref: {...value.cancellation.ref, runDefinitionCid: cid('f')}}}
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
        if (operation === targetOperation) return alterReply(reply);
        if (operation === 'status' && transformRunReply) return transformRunReply(reply);
        if (operation === 'lookup-request' && transformLookupReply) return transformLookupReply(reply);
        return reply;
      },
    });
  } else {
    const environmentWire = await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8');
    const environmentBody = JSON.parse(environmentWire);
    const environment = moon.clientProgramCheckEnvironment(environmentWire.trimEnd(),
      environmentBody.evidence_bundle_cid, false, false, true, false, false, false, false);
    assert.ok(environment);
    const funded = await fundedClientPreparation(t, {moon, environment, http: true});
    const handler = createClientHttpHandler({...options, prepareRequest: funded.prepareRequest});
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
      const transformObservation = operation === 'status' ? transformRunReply
        : operation === 'lookup-request' ? transformLookupReply : undefined;
      if (transformObservation) {
        const end = response.end;
        response.end = function(data, ...args) {
          if (response.statusCode !== 200) return end.call(this, data, ...args);
          return end.call(this, JSON.stringify(transformObservation(JSON.parse(data.toString()))), ...args);
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
  let cancelSequence = 0, lastCancellationOptions;
  return {client, execution, before, stored, operations,
    cancelOptions() {
      lastCancellationOptions = {cancelId: `fixture-cancel-${++cancelSequence}`,
        expectedRevision: stored()[0].revision, attemptId: `fixture-attempt-${cancelSequence}`};
      return lastCancellationOptions;
    },
    cancellationRef: () => ({...execution.ref, cancelId: lastCancellationOptions.cancelId,
      expectedRevision: lastCancellationOptions.expectedRevision}),
    counts: () => ({cancelCalls, submits}),
    authorize: value => { authorized = value; },
    authorizeCancel: value => { cancelAllowed = value; },
    rejectCredentials: value => { credentialFailure = value; }};
}


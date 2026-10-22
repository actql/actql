import assert from 'node:assert/strict';
import test from 'node:test';
import {createServer} from 'node:http';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRunStateAuthority, installRunStateService} from
  '../host-common/run-state-access.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStateObservation, observeClientRunState} from
  './client-run-state.mjs';
import {createClientHttpHandler} from './client-http.mjs';
import {createNodeInProcessClientHost} from './in-process-client.mjs';
import {connect} from '../../packages/sdk/index.mjs';
import {connectInProcess} from '../../packages/sdk/host-port.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';

// Actual Common observation issuer and physical request Journal; the Store
// publication/availability ports below are explicit doubles, not execution or
// Result custody evidence. No terminal status supplies an observation revision.
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const at = '2026-10-20T00:00:00.000Z';
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'durable', scopeRef: 'reader', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 2048}};

async function fixture(t) {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'run-state-fallback-', label: 'original public fallback Journal'});
  const journals = [];
  const open = () => { const journal = openClientRequestJournal(scratch.path);
    journals.push(journal); return journal; };
  const journal = open();
  t.after(() => { for (const original of journals) original.close(); });
  const definition = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'original-scope',
    run_id: 'fallback-original', compiled_plan_cid: cid('1'),
    invocation_template_cid: cid('2'), authorization_context_cid: cid('3'),
    input_artifact_set_cid: cid('4'), created_at: at,
    valid_until: '2098-01-01T00:00:00.000Z'}), limits);
  const identity = moon.clientRequestAdmitRecord(cid('a'), 'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'), 'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert.ok(identity);
  const {ref} = journal.acceptDefinition(identity, {namespaceId: 'namespace-a',
    runDefinition: definition, lookupExpiresAt: '2099-01-01T00:00:00.000Z'}, moon, control);
  const request = {indexKey: ref, principalId: 'reader', purpose: 'inspect'};
  let allowed = true, beforeManifest, inspections = 0, servedDefinition = definition;
  const store = {
    async confirmCommittedIndex(key) {
      assert.deepEqual(key, ref);
      return {public_index_entry_cid: cid('5'), publication_attempt_cid: cid('6'),
        result_manifest_cid: cid('7'), run_definition_cid: ref.runDefinitionCid};
    },
    async readPublicationContract(_cid, kind) {
      if (kind === 'result_manifest') { inspections++; await beforeManifest?.(); }
      return kind === 'run_definition' ? servedDefinition : {};
    },
    async latestRecordContract() { return {}; },
    async observeTrustedClock() { assert.fail('empty inventory has no retention clock'); },
    async withCommittedResult() { assert.fail('empty inventory has no Result'); },
    async readCommittedResultRetentionExtension() { assert.fail('empty inventory has no retention'); },
  };
  const stateService = installRunStateService({store,
    control: {...control, manifestResultNames: () => [],
      projectCommittedPublicationState: () => 'succeeded'},
    authority: installRunStateAuthority({authorizeRunState: () => allowed,
      resultPolicyAvailable: () => true}), now: () => at, limits});
  const bind = original => installNodeClientRunStateObservation({journal: original,
    requestControl: moon, publicationControl: control});
  const runStateObservation = bind(journal);
  return {scratch, journal, open, ref, request, stateService, bind, runStateObservation,
    setAllowed(value) { allowed = value; }, beforeManifest(callback) { beforeManifest = callback; },
    setDefinition(value) { servedDefinition = value; },
    inspections: () => inspections,
    observe: (port = runStateObservation, req = request) => observeClientRunState(port, stateService, req)};
}

for (const transport of ['HTTP', 'in-process']) {
  test(`${transport} fallback uses the original durable observation across reread and reopen`, async t => {
    const f = await fixture(t);
    const configuration = {authenticate: () => 'reader', authorizeConnection: () => true,
      negotiate: () => profile, stateService: f.stateService,
      runStateObservation: f.runStateObservation, maxRowBytes: 1024,
      attach: () => ({ref: f.ref, durability: 'durable', revision: 0})};
    let server;
    let client;
    try {
      if (transport === 'HTTP') {
        server = createServer(createClientHttpHandler(configuration));
        await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
        client = await connect({mode: 'local', owner: 'local',
          endpoint: `http://127.0.0.1:${server.address().port}/`, token: 'reader'});
      } else {
        client = await connectInProcess({mode: 'local', owner: 'local'},
          createNodeInProcessClientHost(configuration));
      }
      const run = await client.attach(f.ref);
      const first = await run.status();
      assert.equal(validRunState(first), true);
      assert.equal(first.status, 'succeeded');
      assert.deepEqual(await run.status(), first);
      const original = f.journal.lookupRunDefinition(f.ref, moon, control);
      assert.equal(first.revision, JSON.parse(f.journal.publishRunState(original, first, moon, control)).revision);
      await client.close();
      f.journal.close();
      const reopened = f.open();
      assert.deepEqual(await f.observe(f.bind(reopened)), first);
      reopened.requestCancellation(f.ref, {currentAuthorization: true,
        publicationCommitted: true}, moon, control);
      const after = await f.observe(f.bind(reopened));
      assert.ok(after.revision >= first.revision);
      assert.equal(after.status, 'succeeded', 'a cancellation cannot replace confirmed publication');
    } finally {
      await client?.close();
      if (server) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
    f.scratch.passed();
  });
}

test('fallback refuses missing copied and fabricated ports and foreign or missing Run originals', async t => {
  const f = await fixture(t);
  for (const port of [null, {}, {...f.runStateObservation}, () => ({revision: 1})]) {
    await assert.rejects(f.observe(port), {code: 'RunStateObservationUnavailable'});
  }
  assert.throws(() => f.bind({...f.journal}), {code: 'ForeignClientRequestJournalCustody'});
  assert.equal(f.inspections(), 0);
  await assert.rejects(f.observe(f.runStateObservation, {...f.request,
    indexKey: {...f.ref, runDefinitionCid: cid('e')}}), {code: 'RunStateAccessDenied'});
  assert.equal(f.inspections(), 0);
  f.setAllowed(false);
  await assert.rejects(f.observe({}), {code: 'RunStateAccessDenied'});
  f.scratch.passed();
});

test('fallback reobserves a genuinely stale original frame but preserves current Account denial', async t => {
  const f = await fixture(t);
  let first = true;
  f.beforeManifest(() => {
    if (first) {
      first = false;
      f.journal.requestCancellation(f.ref, {currentAuthorization: true,
        publicationCommitted: false}, moon, control);
    }
  });
  const state = await f.observe();
  assert.equal(validRunState(state), true);
  assert.equal(f.inspections(), 2);
  assert.equal(state.control.cancellation_requested, true);
  f.beforeManifest(() => f.setAllowed(false));
  await assert.rejects(f.observe(), {code: 'RunStateAccessDenied'});
  f.scratch.passed();
});

test('fallback propagates uncertain observation COMMIT without retrying or issuing replacement state', async t => {
  const f = await fixture(t);
  const exec = DatabaseSync.prototype.exec;
  let commits = 0;
  const injected = t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (sql === 'COMMIT') {
      commits++;
      exec.call(this, sql);
      throw new Error('ORIGINAL_STATE_COMMIT_REPLY_LOST');
    }
    return exec.call(this, sql);
  });
  try {
    await assert.rejects(f.observe(), error => {
      assert.equal(error.code, 'ClientRunStateObservationUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.cause.message, 'ORIGINAL_STATE_COMMIT_REPLY_LOST');
      return true;
    });
    assert.equal(commits, 1);
    assert.equal(f.inspections(), 1);
  } finally { injected.mock.restore(); }
  const saved = await f.observe();
  assert.equal(validRunState(saved), true);
  assert.deepEqual(await f.observe(), saved);
  f.scratch.passed();
});

test('fallback rejects a foreign observed Run and propagates original Journal closure', async t => {
  const f = await fixture(t);
  const foreign = control.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'original-scope',
    run_id: 'foreign-run', compiled_plan_cid: cid('1'),
    invocation_template_cid: cid('2'), authorization_context_cid: cid('3'),
    input_artifact_set_cid: cid('4'), created_at: at,
    valid_until: '2098-01-01T00:00:00.000Z'}), limits);
  f.setDefinition(foreign);
  await assert.rejects(f.observe(), {code: 'MoonBitHostFailure'});
  assert.equal(f.inspections(), 1);
  f.beforeManifest(() => f.journal.close());
  await assert.rejects(f.observe(), {code: 'ClientRequestJournalClosed'});
  assert.equal(f.inspections(), 2);
  f.scratch.passed();
});

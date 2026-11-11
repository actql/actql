import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync} from 'node:crypto';
import {userInfo} from 'node:os';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installRunStateAuthority, installRunStateService} from
  '../host-common/run-state-access.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStateObservation, observeClientRunState} from
  './client-run-state.mjs';
import {validRunState} from '../../packages/client-wire/index.mjs';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {fixtureCertificates} from '../site-node/https-exchange-fixture.mjs';
import {openInstalledClientHostFixture} from './fixtures/installed-client-host.fixture.mjs';

// Actual Common observation issuer and physical request Journal; the Store
// publication/availability ports below are explicit doubles, not execution or
// Result custody evidence. No terminal status supplies an observation revision.
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const at = '2026-10-20T00:00:00.000Z';


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

// Keep the direct Journal/Store fallback contract separate from the actual
// installed transport. The production Host owns its own Journal and Store;
// the semantic double above cannot supply its operational preparation.
test('fallback uses the original durable observation across reread and reopen', async t => {
  const f = await fixture(t);
  const first = await f.observe();
  assert.equal(validRunState(first), true);
  assert.equal(first.status, 'succeeded');
  assert.deepEqual(await f.observe(), first);
  const original = f.journal.lookupRunDefinition(f.ref, moon, control);
  assert.equal(first.revision, JSON.parse(f.journal.publishRunState(original, first, moon, control)).revision);
  f.journal.close();
  const reopened = f.open();
  assert.deepEqual(await f.observe(f.bind(reopened)), first);
  reopened.requestCancellation(f.ref, {currentAuthorization: true,
    publicationCommitted: true}, moon, control);
  const after = await f.observe(f.bind(reopened));
  assert.ok(after.revision >= first.revision);
  assert.equal(after.status, 'succeeded', 'a cancellation cannot replace confirmed publication');
  f.scratch.passed();
});

async function currentInstalledState(run) {
  const before = Date.now();
  const state = await run.status();
  const after = Date.now();
  assert.equal(validRunState(state), true);
  // The real Store samples its current clock on each read. These two fields
  // are observations, not another durable state revision or a frozen clock.
  const observed = Date.parse(state.result_availability.answer.observed_at);
  assert.equal(new Date(observed).toISOString(), state.result_availability.answer.observed_at);
  assert.ok(observed >= before && observed <= after);
  assert.equal(state.updated_at, state.result_availability.answer.observed_at);
  return state;
}

function sameInstalledState(actual, original) {
  // Compare the complete public state. Only the separately checked clock
  // samples may differ; no identity, control, availability or revision is lost.
  assert.deepEqual(actual, {...original, updated_at: actual.updated_at,
    result_availability: {answer: {...original.result_availability.answer,
      observed_at: actual.result_availability.answer.observed_at}}});
}

for (const transport of ['HTTP', 'in-process']) {
  test(`${transport} installed Host retains the same Run observation across reread and reopen`, async t => {
    const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
      prefix: 'run-state-installed-', label: `${transport} installed Run observation`});
    const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
    let physicalStarts = 0;
    const authorization = {
      accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'run-state-installed', entries: [{entry_id: 'execution', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['read', 'write']}, exclusions: []}]}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
        publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
      hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
      faultInjection(name) {if (name === 'physical_start_reserved') physicalStarts++;},
    };
    const certificates = transport === 'HTTP' ? await fixtureCertificates(scratch.path) : undefined;
    const configuration = {entrance: transport, installation: {
      directory: join(scratch.path, 'host'), authorization},
    authenticate: () => principalId, certificates};
    const firstHost = await openInstalledClientHostFixture(t, configuration);
    const program = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.json', import.meta.url), 'utf8'));
    const run = await firstHost.client.start(program);
    const ref = run.ref;
    assert.equal((await run.wait()).status, 'succeeded');
    const first = await currentInstalledState(run);
    assert.equal(validRunState(first), true);
    assert.equal(first.status, 'succeeded');
    sameInstalledState(await currentInstalledState(run), first);
    assert.equal(physicalStarts, 1);
    await firstHost.close();
    const reopened = await openInstalledClientHostFixture(t, configuration);
    const attached = await reopened.client.attach(ref);
    sameInstalledState(await currentInstalledState(attached), first);
    assert.deepEqual(await attached.result('answer').all(), [{id: 1}, {id: 2}]);
    assert.equal(physicalStarts, 1, 'reread and reopen must not dispatch another Run');
    await reopened.close();
    scratch.passed();
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

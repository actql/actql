// Current public recovery from independently authored historical-format
// originals. Earlier public-Host production and cross-version compatibility
// are separate, unverified claims; this test never submits a bare request ID.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir, userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {writeSyntheticHistoricalHeldValues, syntheticHeldSnapshot, heldValuesExpected}
  from '../../scripts/fixtures/synthetic-historical-held-values.mjs';

const runtimeRootUrl = new URL('../../', import.meta.url);
const document = await readFile(new URL('packages/sdk/fixtures/values.json', runtimeRootUrl), 'utf8');
const until = async inspect => {
  const end = Date.now() + 15000;
  for (;;) {
    const found = await inspect();
    if (found) return found;
    assert.ok(Date.now() < end, 'Synthetic original did not settle within the existing bound');
    await new Promise(resolve => setTimeout(resolve, 25));
  }
};
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});

async function fixture(t, {seed = true} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-synthetic-held-values-'));
  const principalId = userInfo().username;
  const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
  let computes = 0, starts = 0, client;
  const authorization = {accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
    account_id: 'synthetic-original', entries: [{entry_id: 'read-original', outcome: 'allow',
      principal: {any_of: [principalId]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']},
      operation: {any_of: ['read']}, exclusions: []},
    {entry_id: 'run-acceptance', outcome: 'delegate',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer', principalId, publicKey: pem(reviewer.publicKey)}],
  reviewReaders: [principalId], hostKey: {keyId: 'host-key', privateKey: pem(host.privateKey)},
  resumeAfterAnswer: false, observe(name) {
    if (name === 'computed') computes++;
    if (name === 'physical_start_reserved') starts++;
  }};
  const close = async () => {await client?.close(); client = undefined;};
  const open = async () => client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    durability: 'durable', installation: {directory, authorization}});
  t.after(async () => {await close(); await rm(directory, {recursive: true, force: true});});
  await open(); await close();
  const original = seed ? await writeSyntheticHistoricalHeldValues({directory, document,
    requestId: 'original-synthetic-values', authorization, runtimeRootUrl}) : undefined;
  const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
    sign: bytes => sign(null, bytes, reviewer.privateKey)};
  return {directory, original, authorization, signer, open, close,
    get client() {return client;}, get computes() {return computes;}, get starts() {return starts;}};
}

test('synthetic historical Values retain zero pre-Run work, one approved Run and cleanup across public restart', async t => {
  const f = await fixture(t);
  const original = f.original;
  await f.open();
  const waiting = await f.client.lookupRequest(original.requestId);
  assert.equal(waiting.kind, 'held');
  assert.equal(waiting.state, 'waiting_checkpoint');
  assert.equal(waiting.prepareAttemptId, original.prepareAttemptId);
  assert.equal(waiting.checkpoint.checkpointCid, original.checkpointCid);
  assert.equal(Object.hasOwn(waiting, 'ref'), false);
  const recovery = f.client.recoverRequest(waiting);
  const target = JSON.parse(JSON.stringify(recovery.target));
  const before = await syntheticHeldSnapshot(f.directory, original);
  assert.deepEqual({runs: before.runs, accepted: before.accepted, intents: before.intents,
    computes: f.computes, starts: f.starts}, {runs: [], accepted: [], intents: 0, computes: 0, starts: 0});
  assert.deepEqual(before.preparations, [{status: 'waiting_checkpoint', run_id: '', checkpoint_cid: original.checkpointCid}]);
  assert.deepEqual(Object.values(before.holdings), Array(5).fill('held'));
  assert.deepEqual(Object.values(before.physicalHoldings), Array(5).fill(true));
  assert.equal(before.pendingPhysicalDeletions, 0);
  const [checkpoint] = (await f.client.checkpoints()).items;
  assert.equal(checkpoint.checkpointCid, original.checkpointCid);
  const review = await f.client.reviewCheckpoint(checkpoint);
  assert.equal(new TextDecoder().decode(review.bytes), original.reviewWire);
  await f.close(); await f.open();
  assert.deepEqual(await f.client.recoverRequest(target).lookup(), waiting);
  assert.deepEqual(await syntheticHeldSnapshot(f.directory, original), before);
  const approved = await f.client.resolveCheckpoints([{checkpoint, decision: 'approved'}], {signer: f.signer});
  assert.deepEqual(approved.results.map(value => value.status), ['committed']);
  assert.deepEqual((await f.client.resolveCheckpoints(approved.signed)).results.map(value => value.status), ['duplicate']);
  assert.equal((await f.client.lookupRequest(original.requestId)).state, 'resuming');
  const answered = await syntheticHeldSnapshot(f.directory, original);
  assert.deepEqual({runs: answered.runs, accepted: answered.accepted, computes: f.computes, starts: f.starts},
    {runs: [], accepted: [], computes: 0, starts: 0});
  await f.close(); await f.open();
  const ready = await until(async () => {
    const value = await f.client.lookupRequest(original.requestId);
    return value.kind === 'found' && value;
  });
  const run = await f.client.attach(ready.ref);
  assert.equal((await run.wait({signal: AbortSignal.timeout(15000)})).status, 'succeeded');
  assert.deepEqual(await run.result('answer').all(), heldValuesExpected);
  const finished = await until(async () => {
    const snapshot = await syntheticHeldSnapshot(f.directory, original);
    return snapshot.runs[0]?.status === 'succeeded' &&
      Object.entries(snapshot.holdings).every(([name, status]) => status ===
        (name === 'invocation_request' ? 'held' : 'retired')) &&
      Object.entries(snapshot.physicalHoldings).every(([name, present]) => present ===
        (name === 'invocation_request')) && snapshot.pendingPhysicalDeletions === 0 && snapshot;
  });
  assert.equal(f.computes, 1);
  assert.equal(f.starts, 1);
  assert.equal(finished.runs.length, 1);
  assert.equal(finished.accepted.length, 1);
  assert.equal(finished.intents, 0, 'Historical identity must not acquire an epoch-bound intent');
  assert.deepEqual(finished.accepted[0], {caller_request_id: original.requestId,
    logical_request_scope_cid: original.logicalRequestScopeCid,
    intent_fingerprint_cid: original.intentFingerprintCid,
    program_definition_cid: original.programDefinitionCid,
    parameter_values_cid: original.parameterValuesCid,
    caller_input_intent_cid: original.callerInputIntentCid,
    run_definition_cid: ready.ref.runDefinitionCid, physical_start_reserved: 1});
  assert.equal(ready.ref.authorityScopeCid, original.authorityScopeCid);
  await f.close(); await f.open();
  const restored = await f.client.recoverRequest(target).lookup();
  assert.deepEqual(restored.ref, ready.ref);
  assert.deepEqual(await (await f.client.attach(restored.ref)).result('answer').all(), heldValuesExpected);
  assert.deepEqual(await syntheticHeldSnapshot(f.directory, original), finished);
  assert.equal(f.computes, 1);
  assert.equal(f.starts, 1);
});

test('synthetic historical Checkpoint with a changed original hash is refused by public recovery', async t => {
  const f = await fixture(t);
  const database = new DatabaseSync(join(f.directory, 'checkpoints/journal/checkpoint-journal.sqlite3'));
  try {
    const row = database.prepare('SELECT checkpoint_wire FROM checkpoints').get();
    const changed = JSON.parse(row.checkpoint_wire);
    changed.human_summary = 'Changed without changing the original identity';
    database.prepare('UPDATE checkpoints SET checkpoint_wire = ?').run(JSON.stringify(changed));
  } finally {database.close();}
  await f.open();
  // Both public ingresses map private journal corruption to the exact 500
  // ClientHostFailure contract (client-http.mjs publicClientErrorCode).
  await assert.rejects(f.client.lookupRequest(f.original.requestId), {code: 'ClientHostFailure', status: 500});
  const snapshot = await syntheticHeldSnapshot(f.directory, f.original);
  assert.deepEqual(snapshot.runs, []);
  assert.deepEqual(snapshot.accepted, []);
  assert.equal(f.computes, 0);
  assert.equal(f.starts, 0);
});

test('new epoch-bound Values delegation remains an exact unsupported preparation failure', async t => {
  const f = await fixture(t, {seed: false});
  await f.open();
  const submissionRef = f.client.newSubmission({nonce: 'new-epoch-values'});
  let outcome;
  await assert.rejects(f.client.startSource(document, {format: 'json', submissionRef}), error => {
    assert.equal(error.code, 'SubmissionPreparationFailed');
    outcome = getSubmissionOutcome(error);
    assert.equal(outcome.kind, 'preparation_failed');
    assert.equal(outcome.problem.code, 'ACTQL_E_DELEGATION_UNAVAILABLE');
    assert.deepEqual(outcome.submissionRef, submissionRef);
    return true;
  });
  const database = new DatabaseSync(join(f.directory, 'checkpoints/journal/checkpoint-journal.sqlite3'), {readOnly: true});
  const requests = new DatabaseSync(join(f.directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  try {
    for (const table of ['preparations', 'checkpoints', 'runs']) {
      assert.equal(database.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0);
    }
    assert.equal(requests.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
    assert.deepEqual(requests.prepare('SELECT phase FROM client_submitted_intents').all().map(row => row.phase), ['preparation_failed']);
  } finally {database.close(); requests.close();}
  assert.deepEqual((await f.client.checkpoints()).items, []);
  await f.close(); await f.open();
  assert.deepEqual(await f.client.lookupSubmission(submissionRef), outcome);
  assert.equal(f.computes, 0);
  assert.equal(f.starts, 0);
});

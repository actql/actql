import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const publication = runtimeCore(moon).publicationControl;
const limits = {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64};
const scope = {namespaceId: 'namespace-a', authorityScopeCid: cid('a')};
const root = new URL('../../_build/client-cancellation-operation-tests/', import.meta.url);
const fields = {
  programDefinitionCid: 'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
  parameterValuesCid: 'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
  intentFingerprintCid: 'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d',
};

function admitRun(journal, requestId = 'saved-request', runId = 'saved-run') {
  // Independent logical-request law, not a product-generated expectation.
  const requestScope = `sha256:${createHash('sha256').update(JSON.stringify({
    authority_scope_cid: scope.authorityScopeCid, caller_request_id: requestId,
    version: 'actql-logical-request/0.1',
  })).digest('hex')}`;
  const identity = moon.clientRequestAdmitRecord(scope.authorityScopeCid,
    requestId, fields.programDefinitionCid, fields.parameterValuesCid,
    cid('b'), requestScope, fields.intentFingerprintCid);
  assert.ok(identity);
  const definition = publication.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1', scope_id: 'namespace-a-scope', run_id: runId,
    compiled_plan_cid: cid('1'), invocation_template_cid: cid('2'),
    authorization_context_cid: cid('3'), input_artifact_set_cid: cid('4'),
    created_at: '2026-09-24T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
  }), limits);
  const accepted = journal.acceptDefinition(identity, {
    namespaceId: scope.namespaceId, runDefinition: definition,
    revision: 17, lookupExpiresAt: '2099-01-01T00:00:00.000Z', resultNames: ['answer'],
  }, moon, publication);
  journal.reserveDispatch(identity, {namespaceId: scope.namespaceId,
    currentAuthorization: true}, moon, publication);
  journal.reservePhysicalStart(identity, {namespaceId: scope.namespaceId,
    ref: accepted.ref, currentAuthorization: true}, moon, publication);
  assert.equal(journal.lookupRunDefinition(accepted.ref, moon, publication).revision, 19);
  return accepted.ref;
}

async function fixture(t, options) {
  await mkdir(root, {recursive: true});
  const path = await mkdtemp(join(root.pathname, 'case-'));
  let journal = openClientRequestJournal(path, options);
  t.after(() => { journal.close(); return rm(path, {recursive: true, force: true}); });
  return {path, get journal() { return journal; }, reopen() {
    journal.close(); journal = openClientRequestJournal(path, options); return journal;
  }};
}

const cancel = (journal, ref, options = {}) => journal.recordCancellationOperation(ref, {
  cancelId: 'original-cancel', expectedRevision: 19,
  currentAuthorization: true, publicationCommitted: false, ...options,
}, moon, publication).cancellation;
const lookup = (journal, ref, currentAuthorization = true) =>
  journal.lookupCancellationOperation(ref, {currentAuthorization}, moon, publication);

test('original cancellation outcome survives later Run termination and journal restart', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const original = cancel(f.journal, ref);
  assert.deepEqual(original, {ref, cancelRef: {...ref, cancelId: 'original-cancel',
    expectedRevision: 19}, kind: 'accepted', revision: 20});
  f.journal.markPhysicalClose(ref, 'cancelled');
  f.reopen();
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).revision, 21);
  assert.deepEqual(cancel(f.journal, ref, {publicationCommitted: true}), original);
  assert.deepEqual(lookup(f.journal, original.cancelRef), {kind: 'found', cancellation: original});
  assert.throws(() => lookup(f.journal, original.cancelRef, false),
    {code: 'ClientCancellationDenied'});
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).revision, 21);
});

test('same cancellation key cannot change target or revision, including after restart', async t => {
  const f = await fixture(t);
  const first = admitRun(f.journal);
  const second = admitRun(f.journal, 'second-request', 'second-run');
  const original = cancel(f.journal, first);
  f.reopen();
  assert.throws(() => cancel(f.journal, second), {code: 'ClientCancellationIntentConflict'});
  assert.throws(() => cancel(f.journal, first, {expectedRevision: 20}),
    {code: 'ClientCancellationIntentConflict'});
  assert.deepEqual(lookup(f.journal, original.cancelRef), {kind: 'found', cancellation: original});
  assert.equal(f.journal.lookupRunDefinition(second, moon, publication).cancellationRequested, false);
});

test('failed final cancellation transaction retains pending identity without accepted fact', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.exec(`CREATE TRIGGER reject_cancel BEFORE UPDATE OF cancellation_requested
    ON client_requests BEGIN SELECT RAISE(ABORT, 'CancellationFlagWriteFailed'); END`);
  assert.throws(() => cancel(f.journal, ref), {code: 'ClientCancellationUnknown'});
  const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
  assert.deepEqual(lookup(f.journal, cancelRef), {kind: 'unknown', cancelRef});
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
  f.reopen();
  assert.deepEqual(lookup(f.journal, cancelRef), {kind: 'unknown', cancelRef});
  db.exec('DROP TRIGGER reject_cancel'); db.close();
  assert.equal(cancel(f.journal, ref).kind, 'accepted');
});

for (const afterCommit of [false, true]) {
  test(`lost final COMMIT reply ${afterCommit ? 'after' : 'before'} durable commit uses original lookup`, async t => {
    const f = await fixture(t);
    const ref = admitRun(f.journal);
    const exec = DatabaseSync.prototype.exec;
    let commits = 0;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && ++commits === 2) {
        if (afterCommit) exec.call(this, sql);
        throw new Error('CANCELLATION_COMMIT_REPLY_LOST');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => cancel(f.journal, ref), {code: 'ClientCancellationUnknown'});
    t.mock.restoreAll();
    f.reopen();
    const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
    const result = lookup(f.journal, cancelRef);
    assert.equal(result.kind, afterCommit ? 'found' : 'unknown');
    if (afterCommit) assert.deepEqual(result.cancellation, {ref, cancelRef, kind: 'accepted', revision: 20});
    assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, afterCommit);
  });
}

test('bounded journal retains immutable operations and replays them at capacity', async t => {
  const f = await fixture(t, {maxRecords: 2});
  const ref = admitRun(f.journal);
  const original = cancel(f.journal, ref);
  assert.deepEqual(cancel(f.journal, ref), original);
  assert.throws(() => cancel(f.journal, ref, {cancelId: 'second-cancel', expectedRevision: 20}),
    {code: 'ClientRequestJournalCapacity'});
  assert.deepEqual(lookup(f.journal, original.cancelRef), {kind: 'found', cancellation: original});
});

test('initial stale revision and denied authorization create no cancellation custody', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  assert.throws(() => cancel(f.journal, ref, {expectedRevision: 18}),
    {code: 'ClientCancellationRevisionConflict'});
  assert.throws(() => cancel(f.journal, ref, {currentAuthorization: false}),
    {code: 'ClientCancellationDenied'});
  assert.throws(() => cancel(f.journal, ref, {expectedRevision: 2147483648}),
    {code: 'InvalidClientCancellationOperation'});
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations').get().n, 0);
  db.close();
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
});

test('opaque composed and decomposed operation IDs retain separate exact outcomes', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const composed = cancel(f.journal, ref, {cancelId: 'é'});
  const decomposed = cancel(f.journal, ref, {cancelId: 'e\u0301', expectedRevision: 20});
  assert.equal(composed.cancelRef.cancelId, 'é');
  assert.equal(decomposed.cancelRef.cancelId, 'e\u0301');
  assert.equal(decomposed.kind, 'already_requested');
  f.reopen();
  for (const original of [composed, decomposed]) {
    assert.deepEqual(lookup(f.journal, original.cancelRef), {kind: 'found', cancellation: original});
  }
});

test('operation fingerprint uses the closed value-preserving preimage', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const definition = f.journal.lookupRunDefinition(ref, moon, publication).runDefinition;
  for (const id of ['é', 'e\u0301']) {
    const owner = moon.clientCancellationAdmitRecord(ref.namespaceId, ref.authorityScopeCid,
      id, definition, 19);
    const preimage = JSON.stringify({authority_scope_cid: ref.authorityScopeCid,
      cancel_id: id, expected_revision: 19, namespace_id: ref.namespaceId,
      operation: 'cancel', run_definition_cid: ref.runDefinitionCid,
      version: 'actql-client-host/0.1'});
    assert.equal(moon.clientCancellationIntentCid(owner),
      `sha256:${createHash('sha256').update(preimage).digest('hex')}`);
  }
});

test('missing operation cannot be recreated as a new intent after custody loss', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const original = cancel(f.journal, ref);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.exec('DELETE FROM client_cancellation_operations'); db.close();
  assert.throws(() => lookup(f.journal, original.cancelRef),
    {code: 'ClientCancellationLookupUnknown'});
  assert.throws(() => cancel(f.journal, ref, {expectedRevision: 20}),
    {code: 'ClientCancellationUnknown'});
  f.journal.close();
  const before = await readFile(join(f.path, 'client-requests.sqlite3'));
  const entries = await readdir(f.path);
  assert.throws(() => openClientRequestJournal(f.path),
    {code: 'UnknownClientRequestJournalFormat'});
  assert.deepEqual(await readFile(join(f.path, 'client-requests.sqlite3')), before);
  assert.deepEqual(await readdir(f.path), entries);
});

test('changed saved outcome is unknown and cannot become a new accepted result', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const original = cancel(f.journal, ref);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.prepare('UPDATE client_cancellation_operations SET outcome_wire = ?').run(
    JSON.stringify({...original, kind: 'already_terminal'}));
  db.close();
  f.reopen();
  assert.throws(() => lookup(f.journal, original.cancelRef),
    {code: 'ClientCancellationLookupUnknown'});
  assert.throws(() => cancel(f.journal, ref), {code: 'ClientCancellationUnknown'});
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).revision, 20);
});

test('additive cancellation custody preserves the prior journal marker and Run original', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const original = f.journal.lookupRunDefinition(ref, moon, publication);
  f.journal.close();
  // Construct the actually supported prior layout, before this additive
  // feature exists. No operation has been recorded or removed in this fixture.
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.exec('DROP TABLE client_cancellation_operations; DROP TABLE client_cancellation_custody');
  db.close();
  await rm(join(f.path, 'cancellation-operations-format.json'));
  const marker = await readFile(join(f.path, 'journal-format.json'));
  f.reopen();
  assert.deepEqual(await readFile(join(f.path, 'journal-format.json')), marker);
  assert.deepEqual(f.journal.lookupRunDefinition(ref, moon, publication), original);
  assert.equal(cancel(f.journal, ref).kind, 'accepted');
  f.reopen();
  assert.deepEqual(await readFile(join(f.path, 'journal-format.json')), marker);
});

test('partial cancellation format is refused without recreating missing custody tables', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  cancel(f.journal, ref);
  f.journal.close();
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.exec('DROP TABLE client_cancellation_operations'); db.close();
  const originalBytes = await readFile(join(f.path, 'client-requests.sqlite3'));
  const entries = await readdir(f.path);
  assert.throws(() => openClientRequestJournal(f.path),
    {code: 'UnknownClientRequestJournalFormat'});
  assert.deepEqual(await readFile(join(f.path, 'client-requests.sqlite3')), originalBytes);
  assert.deepEqual(await readdir(f.path), entries);
});

test('the physical recording receipt distinguishes first commit from replay', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const options = {cancelId: 'original-cancel', expectedRevision: 19,
    currentAuthorization: true, publicationCommitted: false};
  const first = f.journal.recordCancellationOperation(ref, options, moon, publication);
  assert.equal(first.recorded, true);
  const repeated = f.journal.recordCancellationOperation(ref, options, moon, publication);
  assert.equal(repeated.recorded, false);
  assert.deepEqual(repeated.cancellation, first.cancellation);
});

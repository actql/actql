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
import {originalModelRunWire} from './installed-model-originals.mjs';

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

function admitRun(journal, requestId = 'saved-request', runId = 'saved-run',
  {evidenceForRun, initialRevision = 17} = {}) {
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
    runAdmissionEvidence: evidenceForRun?.(definition),
    revision: initialRevision, lookupExpiresAt: '2099-01-01T00:00:00.000Z', resultNames: ['answer'],
  }, moon, publication);
  journal.reserveDispatch(identity, {namespaceId: scope.namespaceId,
    currentAuthorization: true}, moon, publication);
  journal.reservePhysicalStart(identity, {namespaceId: scope.namespaceId,
    ref: accepted.ref, currentAuthorization: true}, moon, publication);
  assert.equal(journal.lookupRunDefinition(accepted.ref, moon, publication).revision, initialRevision + 2);
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

const attempt = (journal, ref, attemptId, options = {}) =>
  journal.recordCancellationAttempt(ref, {attemptRef: {operation: 'cancel', attemptId},
    cancelId: 'original-cancel', expectedRevision: 19,
    currentAuthorization: true, publicationCommitted: false, ...options}, moon, publication);

test('initial refused attempt consumes no identity and cannot negate another accepted invocation', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const expected = {kind: 'refused', attemptRef: {operation: 'cancel', attemptId: 'denied-invocation'},
    guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'};
  assert.deepEqual(attempt(f.journal, ref, 'denied-invocation', {currentAuthorization: false}), expected);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
  t.after(() => db.close());
  const custody = () => ({operations: db.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations').get().n,
    issued: db.prepare('SELECT issued_count FROM client_cancellation_custody').get().issued_count});
  assert.deepEqual(custody(), {operations: 0, issued: 0});
  const accepted = attempt(f.journal, ref, 'accepted-invocation');
  assert.equal(accepted.kind, 'accepted');
  assert.equal(accepted.recorded, true);
  assert.deepEqual(accepted.attemptRef, {operation: 'cancel', attemptId: 'accepted-invocation'});
  assert.deepEqual(attempt(f.journal, ref, 'denied-invocation', {currentAuthorization: false}), expected);
  assert.deepEqual(custody(), {operations: 1, issued: 1});
  assert.deepEqual(lookup(f.journal, accepted.cancellation.cancelRef),
    {kind: 'found', cancellation: accepted.cancellation});
});

test('a typed stale-revision conflict is issued only after noncommitting initial admission', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  assert.deepEqual(attempt(f.journal, ref, 'stale-invocation', {expectedRevision: 18}), {
    kind: 'conflict', reason: 'control_revision',
    attemptRef: {operation: 'cancel', attemptId: 'stale-invocation'},
    cancelRef: {...ref, cancelId: 'original-cancel', expectedRevision: 18},
  });
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
});

test('AlreadySatisfied preserves the original satisfaction fact without asserting stop or release', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  attempt(f.journal, ref, 'first');
  const second = attempt(f.journal, ref, 'second', {cancelId: 'second-cancel', expectedRevision: 20});
  assert.equal(second.kind, 'already_satisfied');
  assert.equal(second.cancellation.kind, 'already_requested');
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).physicalCloseConfirmed, false);
});

test('typed capacity refusal preserves existing custody and exact replay at capacity', async t => {
  const f = await fixture(t, {maxRecords: 2});
  const ref = admitRun(f.journal);
  const original = attempt(f.journal, ref, 'first');
  assert.deepEqual(attempt(f.journal, ref, 'capacity-invocation',
    {cancelId: 'new-operation', expectedRevision: 20}), {
    kind: 'refused', reason: 'admission_capacity', guarantee: 'attempt_uncommitted_unconsumed',
    attemptRef: {operation: 'cancel', attemptId: 'capacity-invocation'},
    cancelRef: {...ref, cancelId: 'new-operation', expectedRevision: 20},
  });
  assert.deepEqual(attempt(f.journal, ref, 'replay'), {...original,
    attemptRef: {operation: 'cancel', attemptId: 'replay'}, recorded: false});
  assert.deepEqual(lookup(f.journal, original.cancellation.cancelRef),
    {kind: 'found', cancellation: original.cancellation});
});

test('a Model fence error cannot become an initial-admission refusal or conflict', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal, 'model-request', 'model-run', {evidenceForRun(definition) {
    // Opaque journal custody here; the real Model Owner validates these inputs.
    return {prepared: 'prepared-owner-wire', authorization: 'authorization-owner-wire',
      modelOriginalRunWire: JSON.stringify({boundInvocationTemplateWire: 'template-owner-wire',
        compiledPlanWire: 'compiled-plan-owner-wire', preparedInvocationWire: 'prepared-owner-wire',
        runAuthorizationWire: 'authorization-owner-wire', runDefinitionWire: definition.wire})};
  }});
  let fences = 0;
  assert.throws(() => attempt(f.journal, ref, 'fence-invocation', {modelCancellationOwner: {
    fenceRunCancellation() {
      fences++;
      throw Object.assign(new Error('ClientCancellationRevisionConflict'),
        {code: 'ClientCancellationRevisionConflict'});
    },
    modelCancellationFenced: () => false,
  }}), {code: 'ClientCancellationUnknown'});
  assert.equal(fences, 1);
  f.reopen();
  assert.deepEqual(lookup(f.journal, {...ref, cancelId: 'original-cancel', expectedRevision: 19}),
    {kind: 'unknown', cancelRef: {...ref, cancelId: 'original-cancel', expectedRevision: 19}});
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
});

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

for (const admission of [true, false]) {
  for (const afterCommit of [false, true]) {
    test(`typed attempt keeps ${admission ? 'initial' : 'final'} COMMIT loss ${afterCommit ? 'after' : 'before'} commit unknown`, async t => {
      const f = await fixture(t);
      const ref = admitRun(f.journal);
      const exec = DatabaseSync.prototype.exec;
      let commits = 0;
      t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
        if (sql === 'COMMIT' && ++commits === (admission ? 1 : 2)) {
          if (afterCommit) exec.call(this, sql);
          throw Object.assign(new Error('ClientCancellationRevisionConflict'),
            {code: 'ClientCancellationRevisionConflict'});
        }
        return exec.call(this, sql);
      });
      // Even a plausible semantic error code cannot certify a failed COMMIT.
      assert.throws(() => attempt(f.journal, ref, 'lost-invocation'),
        {code: 'ClientCancellationUnknown'});
      t.mock.restoreAll();
      f.reopen();
      const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
      assert.equal(lookup(f.journal, cancelRef).kind,
        !admission && afterCommit ? 'found' : 'unknown');
      assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested,
        !admission && afterCommit);
    });
  }
}

test('typed rejection requires confirmed rollback, not a stale revision error alone', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (sql === 'ROLLBACK') throw new Error('ROLLBACK_REPLY_LOST');
    return exec.call(this, sql);
  });
  assert.throws(() => attempt(f.journal, ref, 'rollback-lost', {expectedRevision: 18}),
    {code: 'ClientCancellationUnknown'});
  t.mock.restoreAll();
  f.reopen();
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
});

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

test('hash-valid accepted outcome without a revision advance is unknown on readmission', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal);
  const original = cancel(f.journal, ref);
  // Independently author the closed canonical order and invalid accepted
  // revision. A correct digest does not establish the operation's semantics.
  const orderedRef = {authorityScopeCid: ref.authorityScopeCid,
    namespaceId: ref.namespaceId, runDefinitionCid: ref.runDefinitionCid};
  const wire = JSON.stringify({cancelRef: {authorityScopeCid: ref.authorityScopeCid,
    cancelId: 'original-cancel', expectedRevision: 19,
    namespaceId: ref.namespaceId, runDefinitionCid: ref.runDefinitionCid},
  kind: 'accepted', ref: orderedRef, revision: 19});
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.prepare('UPDATE client_cancellation_operations SET outcome_wire = ?, outcome_cid = ?')
    .run(wire, `sha256:${createHash('sha256').update(wire).digest('hex')}`);
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
  for(const table of ['client_request_row_usage','client_cancellation_row_usage']) {
    for(const suffix of ['insert','delete']) db.exec(`DROP TRIGGER ${table}_${suffix}`);
    db.exec(`DROP TABLE ${table}`);
  }
  db.exec('PRAGMA user_version=1');
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


test('revision exhaustion refuses before retaining cancellation custody or touching a Model fence', async t => {
  const f = await fixture(t);
  const ref = admitRun(f.journal, 'exhausted-request', 'exhausted-run',
    {initialRevision: 2147483645});
  assert.throws(() => cancel(f.journal, ref, {expectedRevision: 2147483647}),
    {code: 'ClientCancellationRevisionConflict'});
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations').get().n, 0);
    assert.equal(db.prepare('SELECT issued_count FROM client_cancellation_custody').get().issued_count, 0);
  } finally { db.close(); }
  assert.equal(f.journal.lookupRunDefinition(ref, moon, publication).cancellationRequested, false);
});

for (const [name, text] of [['composed', 'é'], ['decomposed', 'e\u0301'],
  ['CR', 'a\rb'], ['LF', 'a\nb'], ['CRLF', 'a\r\nb']]) {
  test(`Model original ${name} values survive request-journal retention and restart exactly`, async t => {
    const f = await fixture(t);
    let expected;
    const ref = admitRun(f.journal, `original-${name}`, `run-${name}`, {evidenceForRun(definition) {
      // This test covers opaque original-byte storage, not Model admission.
      // The real installed Model Owner separately validates every leaf.
      const templateWire = JSON.stringify({text, nested: {values: [text]}});
      const preparedWire = 'prepared-owner-wire', authorizationWire = 'authorization-owner-wire';
      const originals = {boundInvocationTemplateWire: templateWire,
        compiledPlanWire: 'compiled-plan-owner-wire', preparedInvocationWire: preparedWire,
        runAuthorizationWire: authorizationWire, runDefinitionWire: definition.wire};
      // Independent closed-key order; never derive the expected stored bytes
      // from the original packaging function or journal's returned evidence.
      expected = JSON.stringify(originals);
      const wire = originalModelRunWire({template: {wire: templateWire},
        preparedEvidence: {wire: preparedWire}, authorization: {wire: authorizationWire},
        compiledPlan: {wire: originals.compiledPlanWire}}, definition);
      assert.equal(wire, expected);
      return {prepared: preparedWire, authorization: authorizationWire, modelOriginalRunWire: wire};
    }});
    assert.equal(f.journal.lookupRunDefinition(ref, moon, publication)
      .runAdmissionEvidence.modelOriginalRunWire, expected);
    f.reopen();
    const retained = f.journal.lookupRunDefinition(ref, moon, publication)
      .runAdmissionEvidence.modelOriginalRunWire;
    assert.equal(retained, expected);
    assert.deepEqual(JSON.parse(JSON.parse(retained).boundInvocationTemplateWire),
      {text, nested: {values: [text]}});
  });
}

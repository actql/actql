import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {issueInstalledUnpublishedRunState, issueInstalledRunControlObservation} from '../host-common/run-state-observation.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const limits = {maxWireBytes:65536, maxNodes:4096, maxDepth:64};
const at = '2026-10-16T00:00:00.000Z';
function definition(runId = 'observed-run') {
  return control.seal('run_definition', JSON.stringify({version:'actql-run-definition/0.1',
    scope_id:'original-scope', run_id:runId, compiled_plan_cid:cid('1'),
    invocation_template_cid:cid('2'), authorization_context_cid:cid('3'),
    input_artifact_set_cid:cid('4'), created_at:at, valid_until:'2098-01-01T00:00:00.000Z'}), limits);
}
function accept(journal) {
  const identity = moon.clientRequestAdmitRecord(cid('a'), 'saved-request',
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
    cid('b'), 'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
  assert.ok(identity);
  return journal.acceptDefinition(identity, {namespaceId:'namespace-a', runDefinition:definition(),
    lookupExpiresAt:'2099-01-01T00:00:00.000Z'}, moon, control).ref;
}
function state(frame, observedAt = at) {
  return {...issueInstalledUnpublishedRunState(moon, {runId:'observed-run', observedAt,
    resultNames:['answer'], dispatchReserved:false, preDispatchFailureConfirmed:false,
    cancelledBeforeStart:false, observedTerminalOutcome:'none', executionUnknown:false}),
  control:issueInstalledRunControlObservation(moon, {revision:frame.revision,
    cancellationRequested:frame.cancellationRequested,
    physicallyUnstarted:frame.physicalStartReserved === false,
    preDispatchFailureConfirmed:frame.preDispatchFailureConfirmed,
    physicalCloseConfirmed:frame.physicalCloseConfirmed})};
}
async function fixture(t) {
  const path = await mkdtemp(join(tmpdir(), 'actql-a-state-revision-'));
  t.after(() => rm(path, {recursive:true, force:true}));
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  return {path, journal, ref:accept(journal)};
}
const frame = (journal, ref) => journal.lookupRunDefinition(ref, moon, control);
const publish = (journal, ref, at) => {
  const original = frame(journal, ref);
  return JSON.parse(journal.publishRunState(original, state(original, at), moon, control));
};

test('state revision persists independently of control and unchanged rereads across reopen', async t => {
  const {path, journal, ref} = await fixture(t);
  const first = publish(journal, ref);
  assert.equal(first.revision, 0);
  assert.equal(first.control.revision, 0);
  assert.equal(publish(journal, ref, '2026-10-16T00:00:01.000Z').revision, 0);
  journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  const cancelled = publish(journal, ref);
  assert.equal(cancelled.control.revision, 1);
  assert.equal(cancelled.revision, 1);
  const current = frame(journal, ref);
  const forgedControl = {...state(current), control:{revision:0,
    cancellation_requested:false, physical_stop:'confirmed'}};
  assert.deepEqual(JSON.parse(journal.publishRunState(current, forgedControl, moon, control)), cancelled,
    'Control facts come only from the admitted same original journal row');
  journal.close();
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  assert.deepEqual(publish(reopened, ref), cancelled);
  assert.equal(publish(reopened, ref, '2026-10-16T00:00:02.000Z').revision, 1);
});

test('unchanged state observation reuses its admitted row without a write transaction', async t => {
  const {journal, ref} = await fixture(t);
  publish(journal, ref);
  let admissions = 0;
  const originalControl = Object.freeze({...control, admit(...args) {
    admissions++;
    return control.admit(...args);
  }});
  const original = journal.lookupRunDefinition(ref, moon, originalControl);
  const before = admissions;
  assert.equal(before, 1);
  const transactions = [];
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (/^(BEGIN|COMMIT|ROLLBACK)/u.test(sql)) transactions.push(sql);
    return exec.call(this, sql);
  });
  const observed = JSON.parse(journal.publishRunState(original, state(original), moon, originalControl));
  assert.equal(observed.revision, 0);
  assert.equal(admissions, before, 'the exact unchanged row keeps its typed definition');
  assert.deepEqual(transactions, [], 'an unchanged read has no durable mutation');
});

test('state projection reentry cannot reuse a row changed during its callback', async t => {
  const {journal, ref} = await fixture(t);
  publish(journal, ref);
  const original = frame(journal, ref), previous = state(original);
  let changed = false;
  const reentrant = {...previous, get updated_at() {
    if (!changed) {
      changed = true;
      journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
    }
    return previous.updated_at;
  }};
  assert.throws(() => journal.publishRunState(original, reentrant, moon, control),
    {code:'RunStateObservationChanged'});
  assert.equal(changed, true);
  assert.equal(frame(journal, ref).cancellationRequested, true);
});

test('state revision rejects copied foreign stale and changed complete original row frames', async t => {
  const {path, journal, ref} = await fixture(t);
  const original = frame(journal, ref), initial = state(original);
  assert.throws(() => journal.publishRunState({...original}, initial, moon, control),
    {code:'ForeignRunStateObservation'});
  assert.throws(() => journal.publishRunState(original, initial, moon, {...control}),
    {code:'ForeignRunStateObservation'});
  const other = openClientRequestJournal(path);
  t.after(() => other.close());
  assert.throws(() => other.publishRunState(original, initial, moon, control),
    {code:'ForeignRunStateObservation'});
  assert.throws(() => journal.publishRunState(original, {...initial, run_id:'other-run'}, moon, control),
    {code:'MoonBitHostFailure'});
  publish(other, ref);
  assert.throws(() => journal.publishRunState(original, initial, moon, control),
    {code:'RunStateObservationChanged'});
  const beforeCancel = frame(journal, ref);
  other.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  assert.throws(() => journal.publishRunState(beforeCancel, state(beforeCancel), moon, control),
    {code:'RunStateObservationChanged'});
  const current = frame(journal, ref);
  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  // A same-counter mutation must not bypass the complete original-row fence.
  writer.prepare('UPDATE client_requests SET lookup_expires_at = ?').run('2099-02-01T00:00:00.000Z');
  assert.throws(() => journal.publishRunState(current, state(current), moon, control),
    {code:'RunStateObservationChanged'});
});

test('state revision retains Unknown on COMMIT loss before or after durability', async t => {
  for (const committed of [false, true]) {
    const {path, journal, ref} = await fixture(t);
    publish(journal, ref);
    journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
    const original = frame(journal, ref);
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    const mock = t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && !injected) {
        injected = true;
        if (committed) exec.call(this, sql);
        throw new Error('STATE_COMMIT_REPLY_LOST');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => journal.publishRunState(original, state(original), moon, control), error => {
      assert.equal(error.code, 'ClientRunStateObservationUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.cause.message, 'STATE_COMMIT_REPLY_LOST');
      return true;
    });
    mock.mock.restore();
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    // A fresh original-row observation converges without repeating execution
    // or treating the lost COMMIT reply as a durable acknowledgement.
    assert.equal(publish(reopened, ref).revision, 1);
  }
});

test('state revision refuses exhaustion and missing noninitial history without reset', async t => {
  const {path, journal, ref} = await fixture(t);
  publish(journal, ref);
  const writer = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  t.after(() => writer.close());
  writer.prepare('UPDATE client_requests SET state_revision = ?').run(Number.MAX_SAFE_INTEGER);
  assert.equal(publish(journal, ref).revision, Number.MAX_SAFE_INTEGER);
  journal.requestCancellation(ref, {currentAuthorization:true, publicationCommitted:false}, moon, control);
  assert.throws(() => publish(journal, ref), {code:'MoonBitHostFailure'});
  writer.exec('UPDATE client_requests SET state_observation_key = NULL');
  assert.throws(() => publish(journal, ref), {code:'MoonBitHostFailure'});
  assert.equal(writer.prepare('SELECT state_revision FROM client_requests').get().state_revision,
    Number.MAX_SAFE_INTEGER);
});

test('state revision old private row layout is refused before original database mutation', async t => {
  const {path, journal} = await fixture(t);
  journal.close();
  const file = join(path, 'client-requests.sqlite3');
  const old = new DatabaseSync(file);
  old.exec('ALTER TABLE client_requests DROP COLUMN state_revision');
  old.exec('ALTER TABLE client_requests DROP COLUMN state_observation_key');
  old.close();
  const before = await readFile(file);
  assert.throws(() => openClientRequestJournal(path), {code:'UnknownClientRequestJournalFormat'});
  assert.deepEqual(await readFile(file), before);
});

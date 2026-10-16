import assert from 'node:assert/strict';
import {mkdtemp, rm, unlink} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const scope = {namespaceId: 'workspace', actorId: 'original-actor', authorityScopeCid,
  currentAuthorization: true};
const intent = (extra = {}) => moon.clientSubmittedIntent(JSON.stringify({
  kind: 'aql', input: {text: 'SELECT 1 AS value', format: 'aql-text'}, parameters: null,
  ...extra,
}), 1048576, 65536, 64);
const connection = {mode: 'local', owner: 'local', durability: 'durable', consentRefs: [], runners: []};

async function fixture(t, options = {}) {
  const path = await mkdtemp(join(tmpdir(), 'actql-a-submission-name-'));
  let now = 1_800_000_000_000;
  const journals = new Set();
  const open = () => {
    const journal = openClientRequestJournal(path, {...options,
      submissionEpochTtlMs: 1000, submissionEpochNow: () => now});
    journals.add(journal);
    return journal;
  };
  const journal = open();
  const ref = owner => ({epoch: owner.issueSubmissionEpoch(scope, moon), nonce: 'original-name-candidate'});
  t.after(async () => {
    for (const owner of journals) owner.close();
    await rm(path, {recursive: true, force: true});
  });
  const database = action => {
    const db = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    try {return action(db);} finally {db.close();}
  };
  return {path, journal, open, ref, database, now: value => {now = value;},
    resolve: (name = 'public-request', original = intent(), fields = {}) =>
      journal.resolveOrBindSubmittedName(name, original, {...scope, submissionRef: ref(journal), ...fields}, moon)};
}

test('scoped name binds original intent atomically and resolves across independent epochs and journals', async t => {
  const f = await fixture(t);
  const original = intent({readOnly: true});
  const first = f.resolve('public-request', original);
  assert.equal(first.inserted, true);
  assert.equal(first.phase, 'preparing');
  const other = f.open();
  const fresh = f.ref(other);
  assert.notDeepEqual(fresh.epoch, first.submissionRef.epoch);
  const found = other.resolveOrBindSubmittedName('public-request', original,
    {...scope, submissionRef: fresh}, moon);
  assert.equal(found.inserted, false);
  assert.equal(found.requestId, first.requestId);
  assert.deepEqual(found.submissionRef, first.submissionRef);
  assert.equal(found.intentWire, first.intentWire);
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(
    moon.clientSubmittedIntent(found.intentWire, 1048576, 65536, 64)), true);
  f.database(db => {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
  });
});

test('name conflict includes original content and continuation choices without replacing its reference', async t => {
  const f = await fixture(t);
  const first = f.resolve();
  for (const changed of [intent({parameters: {n: 1}}), intent({readOnly: true}),
    intent({stopBefore: 'commit'})]) {
    assert.ok(changed);
    assert.throws(() => f.resolve('public-request', changed), {code: 'ClientSubmittedIntentConflict'});
  }
  assert.throws(() => f.resolve('public-request', intent(),
    {authorityScopeCid: `sha256:${'b'.repeat(64)}`}), {code: 'ClientSubmittedIntentConflict'});
  assert.equal(f.resolve().requestId, first.requestId);
});

test('name is scoped to original workspace and actor and confers no current authorization', async t => {
  const f = await fixture(t);
  const first = f.resolve();
  assert.throws(() => f.resolve('public-request', intent(), {currentAuthorization: false}),
    {code: 'ClientSubmissionEpochUnauthorized'});
  assert.notEqual(f.resolve('public-request', intent(), {actorId: 'another-actor'}).requestId,
    first.requestId);
  assert.notEqual(f.resolve('public-request', intent(), {namespaceId: 'another-workspace'}).requestId,
    first.requestId);
});

test('name and original preparing intent roll back together on failed physical index write', async t => {
  const f = await fixture(t);
  f.database(db => db.exec(`CREATE TRIGGER refuse_named_binding BEFORE INSERT ON client_submission_names
    BEGIN SELECT RAISE(ABORT, 'fixture index write failure'); END;`));
  assert.throws(() => f.resolve());
  f.database(db => {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 0);
    assert.deepEqual({...db.prepare('SELECT * FROM client_submission_name_custody').get()},
      {singleton: 1, issued_count: 0, retained_count: 0});
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 0);
    db.exec('DROP TRIGGER refuse_named_binding');
  });
  assert.equal(f.resolve().inserted, true);
});

test('name survives formal intent retirement as an unresolved fence without new capacity', async t => {
  const f = await fixture(t, {maxRecords: 1});
  const original = intent();
  const first = f.resolve('public-request', original);
  f.journal.completeSubmittedIntent(first.submissionRef,
    {kind: 'preparation_failed', submissionRef: first.submissionRef, intentCid: first.intentCid,
      problem: {code: 'FixtureFailure', classification: 'operation_failed'}},
    {...scope, connection, expectedRevision: first.revision}, moon);
  f.now(1_800_000_001_000);
  assert.deepEqual(f.journal.retireSubmittedIntent(first.submissionRef,
    {...scope, expectedRevision: 1}, moon), {retired: true});
  assert.throws(() => f.resolve(), {code: 'ClientSubmissionNameUnresolvable'});
  const reopened = f.open();
  assert.throws(() => reopened.resolveOrBindSubmittedName('public-request', original,
    {...scope, submissionRef: f.ref(reopened)}, moon), {code: 'ClientSubmissionNameUnresolvable'});
  assert.throws(() => f.resolve('another-name'), {code: 'ClientSubmissionNameCapacity'});
  f.database(db => {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 0);
  });
});

test('missing named binding fences unused names instead of minting work', async t => {
  const f = await fixture(t);
  f.resolve();
  f.database(db => db.exec('DELETE FROM client_submission_names'));
  assert.throws(() => f.resolve('unused-name'), {code: 'ClientSubmissionNameCustodyLost'});
  assert.throws(() => f.open().resolveOrBindSubmittedName('public-request', intent(), scope, moon),
    {code: 'ClientSubmissionNameCustodyLost'});
});

test('changed named binding or original intent cannot be substituted by equal-looking data', async t => {
  for (const column of ['authority_scope_cid', 'submission_id', 'intent_cid', 'binding_authenticator']) {
    const f = await fixture(t);
    f.resolve();
    f.database(db => db.prepare(`UPDATE client_submission_names SET ${column} = ?`)
      .run(column === 'binding_authenticator' ? '0'.repeat(64) : `sha256:${'b'.repeat(64)}`));
    assert.throws(() => f.resolve(), {code: 'ClientSubmissionNameCustodyLost'});
  }
});

test('old explicit epoch nonce is not retroactively a public named reference', async t => {
  const f = await fixture(t);
  const reference = f.ref(f.journal);
  f.journal.recordSubmittedIntent(reference, intent(), scope, moon);
  assert.throws(() => f.resolve('public-request', intent(), {submissionRef: reference}),
    {code: 'ClientSubmissionNameReferenceUsed'});
  f.database(db => assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n, 0));
  assert.equal(f.resolve().inserted, true);
});

test('name authentication is tied to issuing journal and missing feature custody is not reinitialized', async t => {
  const f = await fixture(t), other = await fixture(t);
  const foreign = other.resolve();
  const row = other.database(db => db.prepare('SELECT * FROM client_submission_names').get());
  f.database(db => {
    db.prepare('INSERT INTO client_submission_names VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(...['namespace_id', 'actor_id', 'name', 'authority_scope_cid', 'submission_id',
        'intent_cid', 'binding_authenticator'].map(key => row[key]));
    db.exec('UPDATE client_submission_name_custody SET issued_count = 1');
  });
  assert.throws(() => f.resolve(), {code: 'ClientSubmissionNameCustodyLost'});
  assert.equal(foreign.inserted, true);
  await unlink(join(other.path, 'submission-name-format.json'));
  assert.throws(() => other.open(), {code: 'UnknownClientRequestJournalFormat'});
});

test('names reject malformed and oversized original strings before binding', async t => {
  const f = await fixture(t);
  for (const name of ['', null, false, 'x'.repeat(257), '\u0000', '\ud800']) {
    assert.throws(() => f.resolve(name), {code: 'InvalidClientSubmissionName'});
  }
  f.database(db => assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_names').get().n, 0));
});

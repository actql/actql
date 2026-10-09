import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const start = 1_800_000_000_000;
const fields = {authorityScopeCid, currentAuthorization: true};
const intentBody = (value = 'original') => ({
  kind: 'aql', input: {text: 'SELECT @value AS value', format: 'aql-text'},
  parameters: {value},
});
const input = value => moon.clientSubmittedIntent(JSON.stringify(intentBody(value)), 1048576, 65536, 64);
const stable = value => Array.isArray(value) ? `[${value.map(stable).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`
    : JSON.stringify(value);
// Independent submitted-intent law; no product CID supplies the oracle.
const intentCid = value => `sha256:${createHash('sha256').update(stable({
  version: 'actql-submitted-intent/0.1', intent: intentBody(value),
})).digest('hex')}`;
const attempt = attemptId => ({operation: 'submit', attemptId});

async function fixture(t, options = {}) {
  const path = await mkdtemp(join(tmpdir(), 'actql-d-submission-attempt-'));
  let now = start, journal;
  const open = () => journal = openClientRequestJournal(path, {...options,
    submissionEpochTtlMs: 1000, submissionEpochNow: () => now});
  open();
  t.after(async () => {journal.close(); await rm(path, {recursive: true, force: true});});
  const ref = {epoch: journal.issueSubmissionEpoch(fields, moon), nonce: 'original-submission'};
  return {path, ref, get journal() {return journal;}, now: value => {now = value;},
    restart() {journal.close(); open();},
    check(id, intent = input(), options = {}) {
      return journal.checkSubmissionAttempt(ref, intent,
        {...fields, attemptRef: attempt(id), ...options}, moon);
    },
    record(id, intent = input(), options = {}, submissionRef = ref) {
      return journal.recordSubmissionAttempt(submissionRef, intent,
        {...fields, attemptRef: attempt(id), ...options}, moon);
    },
    custody() {
      const db = new DatabaseSync(join(path, 'client-requests.sqlite3'), {readOnly: true});
      try {return {rows: db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n,
        issued: db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count};}
      finally {db.close();}
    }};
}

test('initial Submission Refused binds only this invocation and consumes no original identity', async t => {
  const f = await fixture(t);
  const expected = {kind: 'refused', attemptRef: attempt('denied'),
    guarantee: 'attempt_uncommitted_unconsumed', reason: 'authorization'};
  assert.deepEqual(f.check('denied', input(), {currentAuthorization: false}), expected);
  assert.deepEqual(f.custody(), {rows: 0, issued: 0});
  const original = f.record('accepted');
  assert.equal(original.kind, 'recorded');
  assert.equal(original.submission.inserted, true);
  assert.deepEqual(f.check('denied', input(), {currentAuthorization: false}), expected);
  assert.deepEqual(f.custody(), {rows: 1, issued: 1});
  f.restart();
  assert.equal(f.journal.lookupSubmittedIntent(f.ref, fields, moon).phase, 'preparing');
});

for (const phase of ['check', 'record']) {
  test(`Submission ${phase} rejects changed original values with an invocation-bound Conflict`, async t => {
    const f = await fixture(t);
    const original = f.record('original', input('e\u0301\r\n'));
    for (const changed of ['é\r\n', 'e\u0301\n', 'e\u0301\r']) {
      const actual = f[phase]('changed', input(changed));
      assert.deepEqual(actual, {kind: 'conflict', reason: 'intent',
        attemptRef: attempt('changed'), submissionRef: f.ref,
        intentCid: intentCid(changed)});
    }
    assert.deepEqual(f.custody(), {rows: 1, issued: 1});
    f.restart();
    const {inserted, ...retained} = original.submission;
    assert.equal(inserted, true);
    assert.deepEqual(f.journal.lookupSubmittedIntent(f.ref, fields, moon), retained);
  });
}

test('capacity Refused is not a durable NotAccepted and exact original replay stays available', async t => {
  const f = await fixture(t, {maxRecords: 1});
  const original = f.record('original');
  const newRef = {...f.ref, nonce: 'different-submission'};
  assert.deepEqual(f.record('at-capacity', input(), {}, newRef), {
    kind: 'refused', reason: 'admission_capacity', guarantee: 'attempt_uncommitted_unconsumed',
    attemptRef: attempt('at-capacity'), submissionRef: newRef,
    intentCid: intentCid(),
  });
  assert.deepEqual(f.record('replay'), {...original, attemptRef: attempt('replay'),
    submission: {...original.submission, inserted: false}});
  assert.equal(f.journal.lookupSubmittedIntent(newRef, fields, moon), undefined);
  assert.deepEqual(f.custody(), {rows: 1, issued: 1});
});

test('expired fresh Submission is refused without negating already retained acceptance', async t => {
  const f = await fixture(t);
  f.record('original');
  f.now(start + 1000);
  const newRef = {...f.ref, nonce: 'after-expiry'};
  assert.deepEqual(f.record('expired', input(), {}, newRef), {
    kind: 'refused', reason: 'epoch_expired', guarantee: 'attempt_uncommitted_unconsumed',
    attemptRef: attempt('expired'), submissionRef: newRef,
    intentCid: intentCid(),
  });
  assert.equal(f.record('original-replay').submission.inserted, false);
  assert.deepEqual(f.custody(), {rows: 1, issued: 1});
});

for (const phase of ['clock', 'intent']) for (const afterCommit of [false, true]) {
  test(`Submission ${phase} COMMIT reply lost ${afterCommit ? 'after' : 'before'} commit cannot certify Refused`, async t => {
    const f = await fixture(t);
    const exec = DatabaseSync.prototype.exec;
    let commits = 0;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && ++commits === (phase === 'clock' ? 1 : 2)) {
        if (afterCommit) exec.call(this, sql);
        throw Object.assign(new Error('ClientSubmittedIntentCapacity'), {code: 'ClientSubmittedIntentCapacity'});
      }
      return exec.call(this, sql);
    });
    assert.throws(() => f.record('lost-reply'), {code: 'ClientRequestJournalCommitOutcomeUnknown'});
    t.mock.restoreAll();
    f.restart();
    const admitted = phase === 'intent' && afterCommit;
    assert.deepEqual(f.custody(), {rows: admitted ? 1 : 0, issued: admitted ? 1 : 0});
    const original = f.journal.lookupSubmittedIntent(f.ref, fields, moon);
    assert.equal(original?.phase, admitted ? 'preparing' : undefined);
    assert.deepEqual(f.journal.lookupSubmittedIntent(f.ref, fields, moon), original,
      'repeated lookup observes the original, without a new admission');
  });
}

test('Submission Conflict requires confirmed rollback rather than its exception code', async t => {
  const f = await fixture(t);
  f.record('original');
  const exec = DatabaseSync.prototype.exec;
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    if (sql === 'ROLLBACK') throw new Error('ROLLBACK_REPLY_LOST');
    return exec.call(this, sql);
  });
  assert.throws(() => f.check('rollback-lost', input('changed')), {code: 'ClientRequestJournalRollbackFailed'});
  t.mock.restoreAll();
  f.restart();
  assert.deepEqual(f.custody(), {rows: 1, issued: 1});
});

test('lost Submission custody is unknown rather than an initial Refused certificate', async t => {
  const f = await fixture(t);
  f.record('original');
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  db.exec('DELETE FROM client_submitted_intents'); db.close();
  assert.throws(() => f.check('custody-lost'), {code: 'ClientSubmittedIntentCustodyLost'});
  assert.throws(() => f.record('custody-lost'), {code: 'ClientSubmittedIntentCustodyLost'});
});

import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const moon = await import(process.env.ACTQL_TEST_COMMON_RUNTIME ?? new URL(
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js',
  import.meta.url).href);

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const start = 1_800_000_000_000;
const fields = {authorityScopeCid, currentAuthorization: true};
const publication = runtimeCore(moon).publicationControl;
const connection = {mode: 'local', owner: 'local', durability: 'durable', consentRefs: [], runners: []};
const intent = (text = "SELECT 'e\u0301\r\n' AS value") => moon.clientSubmittedIntent(JSON.stringify({
  kind: 'aql', input: {text, format: 'aql-text'}, parameters: null,
}), 1048576, 65536, 64);
const outcome = (ref, input, kind = 'preparation_failed') => ({kind, submissionRef: ref,
  intentCid: moon.clientSubmittedIntentCid(input),
  problem: {code: 'FixturePreparationFailure', classification: 'operation_failed'}});
const request = requestId => moon.clientRequestAdmitRecord(authorityScopeCid, requestId,
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
  `sha256:${'b'.repeat(64)}`,
  `sha256:${createHash('sha256').update(JSON.stringify({authority_scope_cid: authorityScopeCid,
    caller_request_id: requestId, version: 'actql-logical-request/0.1'})).digest('hex')}`,
  'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
const definition = () => publication.seal('run_definition', JSON.stringify({
  version: 'actql-run-definition/0.1', scope_id: 'intent-scope', run_id: 'intent-run',
  compiled_plan_cid: `sha256:${'1'.repeat(64)}`, invocation_template_cid: `sha256:${'2'.repeat(64)}`,
  authorization_context_cid: `sha256:${'3'.repeat(64)}`, input_artifact_set_cid: `sha256:${'4'.repeat(64)}`,
  created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
}), {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});

async function fixture(t) {
  const path = await mkdtemp(join(tmpdir(), 'actql-d-submitted-intent-'));
  let now = start;
  let journal;
  const open = () => journal = openClientRequestJournal(path, {
    submissionEpochTtlMs: 1000, submissionEpochNow: () => now,
  });
  open();
  t.after(async () => {journal.close(); await rm(path, {recursive: true, force: true});});
  const ref = Object.freeze({epoch: journal.issueSubmissionEpoch(fields, moon), nonce: 'original-intent'});
  return {path, ref, get journal() {return journal;}, now: value => {now = value;},
    restart() {journal.close(); open();},
    lookup() {return journal.lookupSubmittedIntent(ref, fields, moon);},
    complete(input, kind, revision = 0) {
      return journal.completeSubmittedIntent(ref, outcome(ref, input, kind),
        {...fields, connection, expectedRevision: revision}, moon);
    }};
}

test('submitted intent receipt survives restart before any Run exists and preserves original values', async t => {
  const f = await fixture(t);
  const input = intent();
  const first = f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  assert.equal(first.inserted, true);
  assert.equal(first.phase, 'preparing');
  assert.equal(first.revision, 0);
  assert.equal(first.outcome, undefined);
  assert.deepEqual(JSON.parse(first.intentWire).input,
    {format: 'aql-text', text: "SELECT 'e\u0301\r\n' AS value"});
  f.restart();
  const restored = f.lookup();
  const {inserted, ...retained} = first;
  assert.equal(inserted, true);
  assert.deepEqual(restored, retained);
  assert.equal('runDefinitionCid' in restored, false);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);}
  finally {db.close();}
  assert.equal(f.journal.recordSubmittedIntent(f.ref, input, fields, moon).inserted, false);
  for (const changed of [intent("SELECT 'é\r\n' AS value"), intent("SELECT 'e\u0301\n' AS value")]) {
    assert.throws(() => f.journal.recordSubmittedIntent(f.ref, changed, fields, moon),
      {code: 'ClientSubmittedIntentConflict'});
  }
});

test('durable NotAccepted consumes the original identity and cannot become accepted', async t => {
  const f = await fixture(t);
  const input = intent('SELECT missing AS value');
  const refusal = outcome(f.ref, input, 'not_accepted');
  const first = f.journal.recordSubmittedIntent(f.ref, input,
    {...fields, phase: 'not_accepted', outcome: refusal}, moon);
  f.restart();
  assert.deepEqual(f.lookup().outcome, refusal);
  assert.equal(f.journal.recordSubmittedIntent(f.ref, input, fields, moon).phase, 'not_accepted');
  assert.throws(() => f.complete(input, 'preparation_failed'), {code: 'InvalidClientSubmittedIntentOutcome'});
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, intent('SELECT 1 AS value'), fields, moon),
    {code: 'ClientSubmittedIntentConflict'});
  assert.equal(first.revision, f.lookup().revision);
});

test('original read-only intent survives reopening and conflicts with another choice', async t => {
  const f = await fixture(t);
  const original = intent('SELECT 1 AS value');
  const wire = {...JSON.parse(moon.clientSubmittedIntentWire(original)), readOnly: true};
  const readOnly = moon.clientSubmittedIntent(JSON.stringify(wire), 1048576, 65536, 64);
  assert.ok(readOnly);
  const first = f.journal.recordSubmittedIntent(f.ref, readOnly, fields, moon);
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, original, fields, moon),
    {code: 'ClientSubmittedIntentConflict'});
  f.restart();
  const saved = f.lookup();
  assert.equal(saved.intentWire, first.intentWire);
  assert.equal(saved.intentCid, first.intentCid);
  const restored = moon.clientSubmittedIntent(saved.intentWire, 1048576, 65536, 64);
  assert.equal(moon.clientSubmittedIntentRequestsReadOnly(restored), true);
  assert.equal(moon.clientSubmittedIntentRequestsCommitStop(restored), false);
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, original, fields, moon),
    {code: 'ClientSubmittedIntentConflict'});
});

test('accepted preparation failure never turns into a pre-acceptance rejection', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  assert.throws(() => f.complete(input, 'not_accepted'), {code: 'InvalidClientSubmittedIntentOutcome'});
  assert.equal(f.lookup().phase, 'preparing');
  const failed = f.complete(input, 'preparation_failed');
  assert.equal(failed.revision, 1);
  f.restart();
  assert.deepEqual(f.lookup(), failed);
  assert.throws(() => f.complete(input, 'not_accepted', 1), {code: 'InvalidClientSubmittedIntentOutcome'});
});

test('stale completion preserves the result committed by another observer', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  const winner = f.complete(input, 'preparation_failed');
  const loser = {...outcome(f.ref, input), problem: {code: 'LateObserver', classification: 'operation_failed'}};
  assert.deepEqual(f.journal.completeSubmittedIntent(f.ref, loser,
    {...fields, connection, expectedRevision: 0}, moon), winner);
  f.restart();
  assert.deepEqual(f.lookup(), winner);
});

test('expired accepted intent may finish preparation but a fresh identity cannot be admitted', async t => {
  const f = await fixture(t);
  const input = intent();
  const accepted = f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.now(start + 1000); f.restart();
  assert.equal(f.journal.recordSubmittedIntent(f.ref, input, fields, moon).inserted, false);
  const newRef = {...f.ref, nonce: 'new-after-expiry'};
  assert.throws(() => f.journal.recordSubmittedIntent(newRef, input, fields, moon),
    {code: 'ClientSubmissionEpochExpired'});
  let issued = 0;
  const original = request(accepted.requestId);
  assert.ok(original);
  const binding = {...f.ref, currentAuthorization: true, intentCid: accepted.intentCid};
  const ready = await f.journal.admitOrLookupDefinition(original, {
    namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z', submission: binding,
    issueDefinition: () => {issued++; return definition();},
  }, moon, publication);
  assert.equal(ready.inserted, true);
  f.restart();
  assert.deepEqual((await f.journal.admitOrLookupDefinition(original, {
    namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z', submission: binding,
    issueDefinition: () => {issued++; return definition();},
  }, moon, publication)).ref, ready.ref);
  assert.equal(issued, 1);
});

test('missing intent custody refuses replacement admission without claiming NotAccepted', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec('DELETE FROM client_submitted_intents');} finally {db.close();}
  assert.equal(f.lookup(), undefined);
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, input, fields, moon),
    {code: 'ClientSubmittedIntentCustodyLost'});
  assert.throws(() => f.complete(input, 'preparation_failed'), {code: 'ClientSubmittedIntentCustodyLost'});
});

test('failed intent insert rolls back its custody counter', async t => {
  const f = await fixture(t);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec(`CREATE TRIGGER reject_intent BEFORE INSERT ON client_submitted_intents
    BEGIN SELECT RAISE(ABORT, 'fixture insert rejected'); END;`);} finally {db.close();}
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, intent(), fields, moon));
  const check = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    assert.equal(check.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 0);
    assert.equal(check.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 0);
  } finally {check.close();}
});

test('expired terminal intent retirement preserves issuance custody across restart', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.complete(input, 'preparation_failed');
  f.now(start + 1000);
  assert.deepEqual(f.journal.retireSubmittedIntent(f.ref,
    {...fields, expectedRevision: 1}, moon), {retired: true});
  f.restart();
  assert.equal(f.lookup(), undefined, 'missing expired history is not a rejection or a rollback');
  assert.deepEqual(f.journal.retireSubmittedIntent(f.ref,
    {...fields, expectedRevision: 1}, moon), {retired: false});
  f.now(start);
  assert.throws(() => f.journal.recordSubmittedIntent(f.ref, input, fields, moon),
    {code: 'ClientSubmissionEpochExpired'});
  const fresh = {epoch: f.journal.issueSubmissionEpoch(fields, moon), nonce: 'deliberate-new-intent'};
  assert.equal(f.journal.recordSubmittedIntent(fresh, input, fields, moon).inserted, true);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
  try {
    assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 2);
    assert.equal(db.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
  } finally {db.close();}
});

for (const missing of ['authorization', 'expiry', 'terminal phase', 'revision', 'authentic epoch']) {
  test(`intent retirement cannot omit ${missing}`, async t => {
    const f = await fixture(t);
    const input = intent();
    f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
    if (missing !== 'terminal phase') f.complete(input, 'preparation_failed');
    if (missing !== 'expiry') f.now(start + 1000);
    const ref = missing === 'authentic epoch'
      ? {...f.ref, epoch: {...f.ref.epoch, authenticator: '0'.repeat(64)}} : f.ref;
    const expected = {
      authorization: 'ClientSubmissionEpochUnauthorized',
      expiry: 'ClientSubmittedIntentNotRetirable',
      'terminal phase': 'ClientSubmittedIntentNotRetirable',
      revision: 'ClientSubmittedIntentRetirementConflict',
      'authentic epoch': 'ClientSubmissionEpochUnverifiable',
    }[missing];
    assert.throws(() => f.journal.retireSubmittedIntent(ref,
      {...fields, currentAuthorization: missing !== 'authorization',
        expectedRevision: missing === 'revision' ? 0 : missing === 'terminal phase' ? 0 : 1}, moon),
      {code: expected});
    f.restart();
    assert.ok(f.lookup(), 'failed retirement cannot erase original custody');
  });
}

test('unrecorded row loss remains fenced after a legitimate retirement', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.complete(input, 'preparation_failed');
  f.now(start + 1000);
  f.journal.retireSubmittedIntent(f.ref, {...fields, expectedRevision: 1}, moon);
  const fresh = {epoch: f.journal.issueSubmissionEpoch(fields, moon), nonce: 'lost-new-intent'};
  f.journal.recordSubmittedIntent(fresh, input, fields, moon);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec('DELETE FROM client_submitted_intents');} finally {db.close();}
  f.restart();
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, fields, moon),
    {code: 'ClientSubmittedIntentCustodyLost'});
  assert.throws(() => f.journal.retireSubmittedIntent(fresh,
    {...fields, expectedRevision: 0}, moon), {code: 'ClientSubmittedIntentCustodyLost'});
});

test('failed retirement transaction retains the original and does not advance retirement', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.complete(input, 'preparation_failed');
  f.now(start + 1000);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    db.exec(`CREATE TRIGGER reject_retirement BEFORE UPDATE ON client_submitted_intent_retirement
      BEGIN SELECT RAISE(ABORT, 'fixture retirement rejected'); END;`);
    assert.throws(() => f.journal.retireSubmittedIntent(f.ref,
      {...fields, expectedRevision: 1}, moon));
    assert.equal(db.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count, 0);
  } finally {db.close();}
  f.restart();
  assert.equal(f.lookup().phase, 'preparation_failed');
});

test('a Run-connected Ready receipt cannot be retired by the pre-Run retention operation', async t => {
  const f = await fixture(t);
  const input = intent();
  const retained = f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  const accepted = await f.journal.admitOrLookupDefinition(request(retained.requestId), {
    namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: {...f.ref, currentAuthorization: true, intentCid: retained.intentCid},
    issueDefinition: definition,
  }, moon, publication);
  const ready = {kind: 'ready', submissionRef: f.ref, intentCid: retained.intentCid,
    admission: {ref: accepted.ref, durability: accepted.durability, revision: accepted.revision}};
  f.journal.completeSubmittedIntent(f.ref, ready,
    {...fields, connection, expectedRevision: 0}, moon);
  f.now(start + 1000);
  assert.throws(() => f.journal.retireSubmittedIntent(f.ref,
    {...fields, expectedRevision: 1}, moon), {code: 'ClientSubmittedIntentNotRetirable'});
  f.restart();
  assert.deepEqual(f.lookup().outcome, ready);
  assert.deepEqual(f.journal.lookup({namespaceId: 'namespace-a', authorityScopeCid,
    requestId: retained.requestId}, moon).ref, accepted.ref);
});

for (const lost of [false, true]) {
  test(`retirement feature adoption preserves prior ${lost ? 'lost' : 'intact'} intent custody`, async t => {
    const f = await fixture(t);
    const input = intent();
    const original = f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
    try {
      db.exec('DROP TABLE client_submitted_intent_retirement');
      if (lost) db.exec('DELETE FROM client_submitted_intents');
    } finally {db.close();}
    await rm(join(f.path, 'submitted-intent-retirement-format.json'));
    f.restart();
    if (lost) {
      assert.equal(f.lookup(), undefined);
      assert.throws(() => f.journal.recordSubmittedIntent(f.ref, input, fields, moon),
        {code: 'ClientSubmittedIntentCustodyLost'});
    } else {
      const {inserted, ...expected} = original;
      assert.equal(inserted, true);
      assert.deepEqual(f.lookup(), expected);
    }
    const check = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(check.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 1);
      assert.equal(check.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count, 0);
    } finally {check.close();}
  });
}

for (const loss of ['marker', 'table', 'counter']) {
  test(`retirement ${loss} loss refuses journal reopening without repair`, async t => {
    const f = await fixture(t);
    if (loss === 'marker') await rm(join(f.path, 'submitted-intent-retirement-format.json'));
    else {
      const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
      try {db.exec(loss === 'table' ? 'DROP TABLE client_submitted_intent_retirement'
        : 'DELETE FROM client_submitted_intent_retirement');} finally {db.close();}
    }
    assert.throws(() => f.restart(), {code: 'UnknownClientRequestJournalFormat'});
  });
}

for (const afterCommit of [false, true]) {
  test(`retirement COMMIT reply loss ${afterCommit ? 'after' : 'before'} commit preserves atomic custody`, async t => {
    const f = await fixture(t);
    const input = intent();
    f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
    f.complete(input, 'preparation_failed');
    f.now(start + 1000);
    const exec = DatabaseSync.prototype.exec;
    let lost = false;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && !lost &&
          this.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count === 1) {
        lost = true;
        if (afterCommit) exec.call(this, sql);
        throw new Error('FixtureRetirementCommitReplyLost');
      }
      return exec.call(this, sql);
    });
    try {
      assert.throws(() => f.journal.retireSubmittedIntent(f.ref,
        {...fields, expectedRevision: 1}, moon), {code: 'ClientRequestJournalCommitOutcomeUnknown'});
      assert.equal(lost, true);
    } finally {t.mock.restoreAll();}
    f.restart();
    assert.equal(f.lookup() === undefined, afterCommit);
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 1);
      assert.equal(db.prepare('SELECT retired_count FROM client_submitted_intent_retirement').get().retired_count, afterCommit ? 1 : 0);
      assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, afterCommit ? 0 : 1);
    } finally {db.close();}
    // The trusted retention policy may explicitly retry; this never submits
    // a Program or settles any prior execution outcome.
    assert.deepEqual(f.journal.retireSubmittedIntent(f.ref,
      {...fields, expectedRevision: 1}, moon), {retired: !afterCommit});
  });
}

test('explicit unresolved-history decision binds original and fresh intent atomically across restart', async t => {
  const f = await fixture(t);
  const input = intent();
  f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.complete(input, 'preparation_failed');
  f.now(start + 1000);
  f.journal.retireSubmittedIntent(f.ref, {...fields, expectedRevision: 1}, moon);
  const fresh = {epoch: f.journal.issueSubmissionEpoch(fields, moon), nonce: 'explicit-new-work'};
  const unresolvedHistory = {submissionRef: f.ref,
    acknowledgement: 'possible_prior_execution_and_effects'};
  const decisionFields = {...fields, actorId: 'authenticated-actor', unresolvedHistory};
  const admitted = f.journal.recordSubmittedIntent(fresh, input, decisionFields, moon);
  const expected = {submissionRef: f.ref, acknowledgement: 'possible_prior_execution_and_effects',
    freshSubmissionRef: fresh, intentCid: 'sha256:' + createHash('sha256').update(JSON.stringify({
      intent: {input: {format: 'aql-text', text: "SELECT 'e\u0301\r\n' AS value"}, kind: 'aql', parameters: null},
      version: 'actql-submitted-intent/0.1',
    })).digest('hex'), actorId: 'authenticated-actor'};
  assert.deepEqual(admitted.unresolvedHistory, expected);
  f.restart();
  assert.equal(f.lookup(), undefined, 'the original outcome stays unknown');
  assert.deepEqual(f.journal.lookupSubmittedIntent(fresh, fields, moon).unresolvedHistory, expected);
  assert.deepEqual(f.journal.recordSubmittedIntent(fresh, input, decisionFields, moon).unresolvedHistory, expected);
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, fields, moon),
    {code: 'ClientSubmissionRestartConflict'});
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input,
    {...decisionFields, actorId: 'another-actor'}, moon), {code: 'ClientSubmissionRestartConflict'});
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, intent('SELECT 2 AS value'), decisionFields, moon),
    {code: 'ClientSubmittedIntentConflict'});
});

async function restartFixture(t) {
  const f = await fixture(t);
  const input = intent();
  const original = f.journal.recordSubmittedIntent(f.ref, input, fields, moon);
  f.complete(input, 'preparation_failed');
  f.now(start + 1000);
  f.journal.retireSubmittedIntent(f.ref, {...fields, expectedRevision: 1}, moon);
  const fresh = {epoch: f.journal.issueSubmissionEpoch(fields, moon), nonce: 'explicit-new-work'};
  const decision = {...fields, actorId: 'authenticated-actor', unresolvedHistory: {
    submissionRef: f.ref, acknowledgement: 'possible_prior_execution_and_effects'}};
  return {f, input, original, fresh, decision};
}

for (const missing of ['acknowledgement', 'actor', 'authorization', 'authentic original']) {
  test(`explicit new work cannot omit ${missing}`, async t => {
    const {f, input, fresh, decision} = await restartFixture(t);
    const candidate = structuredClone(decision);
    if (missing === 'acknowledgement') candidate.unresolvedHistory.acknowledgement = 'retry';
    if (missing === 'actor') delete candidate.actorId;
    if (missing === 'authorization') candidate.currentAuthorization = false;
    if (missing === 'authentic original') candidate.unresolvedHistory.submissionRef.epoch.authenticator = '0'.repeat(64);
    assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, candidate, moon), {
      code: missing === 'authorization' ? 'ClientSubmissionEpochUnauthorized'
        : missing === 'authentic original' ? 'ClientSubmissionEpochUnverifiable' : 'InvalidClientSubmissionRestart',
    });
    f.restart();
    assert.equal(f.journal.lookupSubmittedIntent(fresh, fields, moon), undefined);
  });
}

test('an admissible original may not be replaced under a risk acknowledgement', async t => {
  const f = await fixture(t);
  const input = intent();
  const fresh = {epoch: f.ref.epoch, nonce: 'new-while-original-admissible'};
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, {
    ...fields, actorId: 'authenticated-actor', unresolvedHistory: {
      submissionRef: f.ref, acknowledgement: 'possible_prior_execution_and_effects'},
  }, moon), {code: 'ClientSubmissionRestartOriginalResolvable'});
  assert.equal(f.journal.lookupSubmittedIntent(fresh, fields, moon), undefined);
});

test('existing original Run responsibility prevents new-work permission', async t => {
  const {f, input, fresh, decision, original} = await restartFixture(t);
  f.journal.acceptDefinition(request(original.requestId), {namespaceId: 'namespace-a',
    runDefinition: definition(), lookupExpiresAt: '2099-01-01T00:00:00.000Z'}, moon, publication);
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, decision, moon),
    {code: 'ClientSubmissionRestartRequiresReconciliation'});
  assert.equal(f.journal.lookupSubmittedIntent(fresh, fields, moon), undefined);
});

test('each deliberately distinct fresh identity retains its own explicit decision', async t => {
  const {f, input, fresh, decision} = await restartFixture(t);
  f.journal.recordSubmittedIntent(fresh, input, decision, moon);
  const secondRef = {...fresh, nonce: 'second-new-work'};
  const second = f.journal.recordSubmittedIntent(secondRef, input, decision, moon);
  assert.deepEqual(second.unresolvedHistory.freshSubmissionRef, secondRef);
  f.restart();
  assert.deepEqual(f.journal.lookupSubmittedIntent(secondRef, fields, moon).unresolvedHistory,
    second.unresolvedHistory);
  assert.deepEqual(f.journal.lookupSubmittedIntent(fresh, fields, moon).unresolvedHistory.freshSubmissionRef, fresh);
});

test('a lost decision link cannot be reinterpreted as an ordinary fresh submission', async t => {
  const {f, input, fresh, decision} = await restartFixture(t);
  f.journal.recordSubmittedIntent(fresh, input, decision, moon);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec('DELETE FROM client_submission_restarts');} finally {db.close();}
  f.restart();
  assert.throws(() => f.journal.lookupSubmittedIntent(fresh, fields, moon),
    {code: 'ClientSubmissionRestartCustodyLost'});
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, fields, moon),
    {code: 'ClientSubmissionRestartCustodyLost'});
});

for (const afterCommit of [false, true]) {
  test(`restart decision COMMIT reply loss ${afterCommit ? 'after' : 'before'} commit keeps intent and link atomic`, async t => {
    const {f, input, fresh, decision} = await restartFixture(t);
    const exec = DatabaseSync.prototype.exec;
    let lost = false;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && !lost &&
          this.prepare('SELECT issued_count FROM client_submission_restart_custody').get().issued_count === 1) {
        lost = true;
        if (afterCommit) exec.call(this, sql);
        throw new Error('FixtureRestartCommitReplyLost');
      }
      return exec.call(this, sql);
    });
    try {
      assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, decision, moon),
        {code: 'ClientRequestJournalCommitOutcomeUnknown'});
      assert.equal(lost, true);
    } finally {t.mock.restoreAll();}
    f.restart();
    const retained = f.journal.lookupSubmittedIntent(fresh, fields, moon);
    assert.equal(retained !== undefined, afterCommit);
    if (afterCommit) assert.deepEqual(retained.unresolvedHistory.submissionRef, f.ref);
    const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submitted_intents').get().n, afterCommit ? 1 : 0);
      assert.equal(db.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, afterCommit ? 2 : 1);
      assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_restarts').get().n, afterCommit ? 1 : 0);
      assert.equal(db.prepare('SELECT issued_count FROM client_submission_restart_custody').get().issued_count, afterCommit ? 1 : 0);
    } finally {db.close();}
    assert.equal(f.lookup(), undefined, 'neither COMMIT result settles the original history');
  });
}

test('a failed decision insertion rolls back intent acceptance and both issuance counters', async t => {
  const {f, input, fresh, decision} = await restartFixture(t);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec(`CREATE TRIGGER fixture_restart_failure BEFORE INSERT ON client_submission_restarts
    BEGIN SELECT RAISE(ABORT, 'FixtureRestartInsertionFailed'); END`);} finally {db.close();}
  assert.throws(() => f.journal.recordSubmittedIntent(fresh, input, decision, moon),
    /FixtureRestartInsertionFailed/u);
  f.restart();
  assert.equal(f.journal.lookupSubmittedIntent(fresh, fields, moon), undefined);
  const check = new DatabaseSync(join(f.path, 'client-requests.sqlite3'), {readOnly: true});
  try {
    assert.equal(check.prepare('SELECT issued_count FROM client_submitted_intent_custody').get().issued_count, 1);
    assert.equal(check.prepare('SELECT issued_count FROM client_submission_restart_custody').get().issued_count, 0);
  } finally {check.close();}
});

for (const loss of ['marker', 'table', 'counter']) {
  test(`restart ${loss} loss refuses journal reopening without repairing history`, async t => {
    const {f, input, fresh, decision} = await restartFixture(t);
    f.journal.recordSubmittedIntent(fresh, input, decision, moon);
    if (loss === 'marker') await rm(join(f.path, 'submission-restart-format.json'));
    else {
      const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
      try {db.exec(loss === 'table' ? 'DROP TABLE client_submission_restarts'
        : 'DELETE FROM client_submission_restart_custody');} finally {db.close();}
    }
    assert.throws(() => f.restart(), {code: 'UnknownClientRequestJournalFormat'});
  });
}

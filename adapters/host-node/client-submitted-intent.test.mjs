import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

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

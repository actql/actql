import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

const authorityScopeCid = `sha256:${'a'.repeat(64)}`;
const otherAuthority = `sha256:${'b'.repeat(64)}`;
const issuedAt = 1_800_000_000_000;
const publication = runtimeCore(moon).publicationControl;
const digest = body => `sha256:${createHash('sha256').update(JSON.stringify(body)).digest('hex')}`;
const request = requestId => moon.clientRequestAdmitRecord(authorityScopeCid, requestId,
  'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
  'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
  `sha256:${'b'.repeat(64)}`,
  digest({authority_scope_cid: authorityScopeCid, caller_request_id: requestId,
    version: 'actql-logical-request/0.1'}),
  'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d');
const definition = () => publication.seal('run_definition', JSON.stringify({
  version: 'actql-run-definition/0.1', scope_id: 'epoch-scope', run_id: 'epoch-run',
  compiled_plan_cid: `sha256:${'1'.repeat(64)}`,
  invocation_template_cid: `sha256:${'2'.repeat(64)}`,
  authorization_context_cid: `sha256:${'3'.repeat(64)}`,
  input_artifact_set_cid: `sha256:${'4'.repeat(64)}`,
  created_at: '2026-10-07T00:00:00.000Z', valid_until: '2098-01-01T00:00:00.000Z',
}), {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64});

async function fixture(t) {
  const path = await mkdtemp(join(tmpdir(), 'actql-d-submission-epoch-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  let now = issuedAt;
  let journal;
  const open = () => journal = openClientRequestJournal(path, {
    submissionEpochTtlMs: 1000, submissionEpochNow: () => now,
  });
  open();
  t.after(() => journal.close());
  return {path, get journal() {return journal;},
    now: value => {now = value;}, restart() {journal.close(); open();}};
}

function verify(journal, epoch, fields = {}) {
  return journal.verifySubmissionEpoch(epoch, {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit', ...fields,
  }, moon);
}

test('submission epoch expiry survives restart and a backwards clock', async t => {
  const f = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  assert.equal(epoch.notBefore, issuedAt);
  assert.equal(epoch.expiresAt, issuedAt + 1000);
  assert.equal(verify(f.journal, epoch).validity, 'admissible');
  f.now(issuedAt + 999);
  assert.equal(verify(f.journal, epoch).validity, 'admissible');
  f.now(issuedAt + 1000);
  assert.equal(verify(f.journal, epoch).validity, 'expired');
  f.restart();
  f.now(issuedAt);
  assert.equal(verify(f.journal, epoch).validity, 'expired');
  // Lookup preserves the original identity even after admission expires.
  const found = verify(f.journal, epoch, {purpose: 'lookup'});
  assert.equal(found.validity, 'expired');
  assert.deepEqual(found.epoch, epoch);
});

test('submission epoch authentication binds authority, interval and issuing Host', async t => {
  const f = await fixture(t);
  const other = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  for (const changed of [
    {...epoch, authorityScopeCid: otherAuthority},
    {...epoch, epochNonce: 'c'.repeat(64)},
    {...epoch, notBefore: epoch.notBefore - 1},
    {...epoch, expiresAt: epoch.expiresAt + 1},
    {...epoch, authenticator: '0'.repeat(64)},
    {...epoch, notBefore: String(epoch.notBefore)},
    {...epoch, expiresAt: null},
    {...epoch, extra: 'unbound'},
    {...epoch, version: 'unknown'},
  ]) assert.throws(() => verify(f.journal, changed),
    {code: 'ClientSubmissionEpochUnverifiable'});
  assert.throws(() => verify(other.journal, epoch),
    {code: 'ClientSubmissionEpochUnverifiable'});
  assert.throws(() => verify(f.journal, epoch, {authorityScopeCid: otherAuthority}),
    {code: 'ClientSubmissionEpochScopeMismatch'});
  assert.throws(() => verify(f.journal, epoch, {currentAuthorization: false}),
    {code: 'ClientSubmissionEpochUnauthorized'});
  assert.throws(() => f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: false}, moon), {code: 'ClientSubmissionEpochUnauthorized'});
});

test('submission epoch validation retains constant storage and exact nonce identity', async t => {
  const f = await fixture(t);
  const first = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const second = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const original = f.journal.submissionIdentity(first, 'original-request', {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon);
  assert.equal(original.validity, 'admissible');
  f.restart();
  assert.deepEqual(f.journal.submissionIdentity(first, 'original-request', {
    authorityScopeCid, currentAuthorization: true, purpose: 'lookup'}, moon), original);
  assert.notEqual(f.journal.submissionIdentity(second, 'original-request', {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon).requestId,
  original.requestId);
  assert.notEqual(f.journal.submissionIdentity(first, 'another-request', {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon).requestId,
  original.requestId);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_submission_epoch_authority').get().n, 1);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
  } finally {db.close();}
  assert.throws(() => f.journal.submissionIdentity(first, 'e\u0301', {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon),
  {code: 'InvalidClientSubmissionNonce'});
});

test('submission epoch validation material is not reconstructed after loss', async t => {
  const f = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {db.exec('DELETE FROM client_submission_epoch_authority');}
  finally {db.close();}
  assert.throws(() => verify(f.journal, epoch),
    {code: 'ClientSubmissionEpochCustodyLost'});
  f.journal.close();
  assert.throws(() => openClientRequestJournal(f.path),
    {code: 'UnknownClientRequestJournalFormat'});
});

for (const loss of ['marker', 'key', 'schema']) {
  test(`partial submission epoch ${loss} is refused without rebuilding validation material`, async t => {
    const f = await fixture(t);
    f.journal.issueSubmissionEpoch({authorityScopeCid, currentAuthorization: true}, moon);
    f.journal.close();
    const database = join(f.path, 'client-requests.sqlite3');
    if (loss === 'marker') await rm(join(f.path, 'submission-epoch-format.json'));
    else {
      const db = new DatabaseSync(database);
      try {
        if (loss === 'key') db.exec("UPDATE client_submission_epoch_authority SET authentication_key = 'lost'");
        else db.exec('ALTER TABLE client_submission_epoch_authority RENAME COLUMN observed_at TO foreign_time');
      } finally {db.close();}
    }
    const before = await readFile(database);
    assert.throws(() => openClientRequestJournal(f.path), {code: 'UnknownClientRequestJournalFormat'});
    assert.deepEqual(await readFile(database), before);
  });
}

test('expired submission admission never invokes the Run issuer', async t => {
  const f = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const binding = {epoch, nonce: 'expired-request', currentAuthorization: true};
  const original = request(f.journal.submissionIdentity(epoch, binding.nonce, {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon).requestId);
  assert.ok(original);
  f.now(issuedAt + 1000);
  let issued = 0;
  await assert.rejects(f.journal.admitOrLookupDefinition(original, {
    namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: binding, issueDefinition: () => {issued++; return definition();},
  }, moon, publication), {code: 'ClientSubmissionEpochExpired'});
  assert.equal(issued, 0);
});

test('submission expiry is rechecked atomically after awaited issuance', async t => {
  const f = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const binding = {epoch, nonce: 'awaited-request', currentAuthorization: true};
  const original = request(f.journal.submissionIdentity(epoch, binding.nonce, {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon).requestId);
  assert.ok(original);
  await assert.rejects(f.journal.admitOrLookupDefinition(original, {
    namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: binding, issueDefinition: async () => {
      await Promise.resolve(); f.now(issuedAt + 1000); return definition();
    },
  }, moon, publication), {code: 'ClientSubmissionEpochExpired'});
  const db = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  try {
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
    assert.equal(db.prepare('SELECT issued_count FROM client_submission_custody').get().issued_count, 0);
    assert.equal(db.prepare('SELECT observed_at FROM client_submission_epoch_authority').get().observed_at,
      issuedAt + 1000);
  } finally {db.close();}
  f.restart(); f.now(issuedAt);
  assert.equal(verify(f.journal, epoch).validity, 'expired');
});

test('retained acceptance is identified after epoch expiry without issuing another Run', async t => {
  const f = await fixture(t);
  const epoch = f.journal.issueSubmissionEpoch({authorityScopeCid,
    currentAuthorization: true}, moon);
  const binding = {epoch, nonce: 'retained-request', currentAuthorization: true};
  const original = request(f.journal.submissionIdentity(epoch, binding.nonce, {
    authorityScopeCid, currentAuthorization: true, purpose: 'admit'}, moon).requestId);
  assert.ok(original);
  let issued = 0;
  const options = {namespaceId: 'namespace-a', lookupExpiresAt: '2099-01-01T00:00:00.000Z',
    submission: binding, issueDefinition: () => {issued++; return definition();}};
  const first = await f.journal.admitOrLookupDefinition(original, options, moon, publication);
  assert.equal(first.inserted, true);
  f.now(issuedAt + 1000); f.restart();
  const second = await f.journal.admitOrLookupDefinition(original, options, moon, publication);
  assert.equal(second.inserted, false);
  assert.deepEqual(second.ref, first.ref);
  assert.equal(issued, 1);
  await assert.rejects(f.journal.admitOrLookupDefinition(original, {
    ...options, submission: {...binding, nonce: 'different-request'},
  }, moon, publication), {code: 'ClientSubmissionIdentityMismatch'});
});

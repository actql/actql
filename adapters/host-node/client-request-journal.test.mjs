import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';

const root = new URL('../../_build/client-request-journal-tests/', import.meta.url);
const cid = digit => `sha256:${digit.repeat(64)}`;
const fixture = Object.freeze({
  authorityScopeCid: cid('a'),
  requestId: 'saved-request',
  programDefinitionCid:
    'sha256:f3514c8f22c6d72818a167ca3341b3c945397042351c51a5982d7abc881a298c',
  parameterValuesCid:
    'sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52',
  callerInputIntentCid: cid('b'),
  logicalRequestScopeCid:
    'sha256:2e497e1244d7db59831b0ab81ae7dc89333babea783a102a747a55f3e7890dd3',
  intentFingerprintCid:
    'sha256:d526e372e357f6bbd1d804e385fc8d88fad9e538ec5a70058f1205af9a0a7d9d',
});
const expires = '2099-01-01T00:00:00.000Z';

function identity(fields = fixture) {
  return moon.clientRequestAdmitRecord(
    fields.authorityScopeCid, fields.requestId,
    fields.programDefinitionCid, fields.parameterValuesCid,
    fields.callerInputIntentCid, fields.logicalRequestScopeCid,
    fields.intentFingerprintCid,
  );
}

function hashCanonical(object) {
  return `sha256:${createHash('sha256').update(JSON.stringify(object))
    .digest('hex')}`;
}

async function directory(t) {
  await mkdir(root, {recursive: true});
  const path = await mkdtemp(join(root.pathname, 'case-'));
  t.after(() => rm(path, {recursive: true, force: true}));
  return path;
}

test('durable Client request survives ACK loss and restart without a new Run',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const requested = identity();
    assert.ok(requested);
    const accepted = first.accept(requested, {
      tenantId: 'tenant-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon);
    assert.equal(accepted.inserted, true);
    assert.deepEqual(accepted.ref, {
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      runDefinitionCid: cid('d'),
    });
    first.close(); // The acceptance reply is deliberately not used.

    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const found = reopened.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon);
    assert.deepEqual(found, {
      requestId: fixture.requestId,
      ref: accepted.ref,
      durability: 'durable', revision: 0,
      lookupExpiresAt: expires,
    });
    const repeated = reopened.accept(identity(), {
      tenantId: 'tenant-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon);
    assert.equal(repeated.inserted, false);
    assert.deepEqual(repeated.ref, accepted.ref);
    assert.equal(reopened.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('c'), requestId: fixture.requestId}, moon),
    undefined);
    assert.equal(reopened.lookup({tenantId: 'tenant-b',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    undefined);
  });

test('the atomic key rejects changed intent and keeps the original Run',
  async t => {
    const path = await directory(t);
    const left = openClientRequestJournal(path);
    const right = openClientRequestJournal(path);
    t.after(() => left.close());
    t.after(() => right.close());
    left.accept(identity(), {
      tenantId: 'tenant-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon);
    const changed = {...fixture, parameterValuesCid: cid('c')};
    changed.intentFingerprintCid = hashCanonical({
      caller_input_intent_cid: changed.callerInputIntentCid,
      parameter_values_cid: changed.parameterValuesCid,
      program_definition_cid: changed.programDefinitionCid,
      version: 'actql-logical-request-intent/0.1',
    });
    assert.ok(identity(changed));
    assert.throws(() => right.accept(identity(changed), {
      tenantId: 'tenant-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestIntentConflict'});
    assert.equal(right.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon)
      .ref.runDefinitionCid, cid('d'));
    assert.equal(right.accept(identity(), {
      tenantId: 'tenant-a', runDefinitionCid: cid('f'),
      lookupExpiresAt: expires,
    }, moon).inserted, false);
    assert.throws(() => right.accept(identity(), {
      tenantId: 'tenant-b', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestOwnerMismatch'});
  });

test('retained identity corruption is not reported as absence', async t => {
  const path = await directory(t);
  const store = openClientRequestJournal(path);
  store.accept(identity(), {
    tenantId: 'tenant-a', runDefinitionCid: cid('d'),
    lookupExpiresAt: expires,
  }, moon);
  store.close();
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  database.prepare('UPDATE client_requests SET intent_fingerprint_cid = ?')
    .run(cid('f'));
  database.close();
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  assert.throws(() => reopened.lookup({tenantId: 'tenant-a',
    authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    {code: 'ClientRequestJournalCorrupt'});
});

test('different requests cannot alias one Run and capacity rejects before commit',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path, {maxRecords: 2});
    t.after(() => first.close());
    first.accept(identity(), {
      tenantId: 'tenant-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon);
    const next = {...fixture, requestId: 'another-request'};
    next.logicalRequestScopeCid = hashCanonical({
      authority_scope_cid: next.authorityScopeCid,
      caller_request_id: next.requestId,
      version: 'actql-logical-request/0.1',
    });
    assert.ok(identity(next));
    assert.throws(() => first.accept(identity(next), {
      tenantId: 'tenant-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestRunAlreadyAssigned'});
    assert.equal(first.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: next.requestId}, moon),
    undefined);
    first.accept(identity(next), {
      tenantId: 'tenant-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon);
    const third = {...fixture, requestId: 'third-request'};
    third.logicalRequestScopeCid = hashCanonical({
      authority_scope_cid: third.authorityScopeCid,
      caller_request_id: third.requestId,
      version: 'actql-logical-request/0.1',
    });
    assert.throws(() => first.accept(identity(third), {
      tenantId: 'tenant-a', runDefinitionCid: cid('f'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestJournalCapacity'});
  });

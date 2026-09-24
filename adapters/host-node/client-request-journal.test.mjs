import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

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
const publicationControl = runtimeCore(moon).publicationControl;
const contractLimits = Object.freeze({
  maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64,
});

function runDefinition(runId = 'saved-run') {
  return publicationControl.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1',
    scope_id: 'tenant-a-scope',
    run_id: runId,
    compiled_plan_cid: cid('1'),
    invocation_template_cid: cid('2'),
    authorization_context_cid: cid('3'),
    input_artifact_set_cid: cid('4'),
    created_at: '2026-09-24T00:00:00.000Z',
    valid_until: '2098-01-01T00:00:00.000Z',
  }), contractLimits);
}

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

test('Run Definition and request acceptance survive one atomic restart',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition();
    const accepted = first.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    first.close(); // Simulate losing the response after durable acceptance.

    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    const retained = restarted.lookupDefinition(key, moon,
      publicationControl);
    assert.equal(retained.ref.runDefinitionCid, definition.identity);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const repeated = restarted.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: runDefinition('new-run'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.equal(repeated.inserted, false);
    assert.equal(repeated.runDefinition.wire, definition.wire);
    assert.equal(restarted.lookupDefinition({...key, tenantId: 'tenant-b'},
      moon, publicationControl), undefined);
  });

test('Run Definition re-admission rejects corruption and incomplete records',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    const definition = runDefinition();
    assert.throws(() => journal.acceptDefinition(identity(), {
      tenantId: 'tenant-a',
      runDefinition: {...definition, identity: cid('f')},
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'InvalidClientRunDefinition'});
    assert.equal(journal.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    undefined);
    journal.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    journal.close();
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.prepare('UPDATE client_requests SET run_definition_wire = ?')
      .run('{}');
    database.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.equal(reopened.lookup(key, moon).ref.runDefinitionCid,
      definition.identity);
    assert.throws(() => reopened.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => reopened.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
  });

test('legacy request rows are not invented as complete Run Definitions',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    journal.accept(identity(), {tenantId: 'tenant-a',
      runDefinitionCid: cid('d'), lookupExpiresAt: expires}, moon);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.throws(() => reopened.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestDefinitionMissing'});
    assert.throws(() => reopened.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: runDefinition(),
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'ClientRequestDefinitionMissing'});
  });

test('existing journal schema migrates without inventing Run authority',
  async t => {
    const path = await directory(t);
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.exec(`CREATE TABLE client_requests (
      authority_scope_cid TEXT NOT NULL,
      caller_request_id TEXT NOT NULL,
      logical_request_scope_cid TEXT NOT NULL UNIQUE,
      intent_fingerprint_cid TEXT NOT NULL,
      program_definition_cid TEXT NOT NULL,
      parameter_values_cid TEXT NOT NULL,
      caller_input_intent_cid TEXT NOT NULL,
      tenant_id TEXT NOT NULL,
      run_definition_cid TEXT NOT NULL UNIQUE,
      revision INTEGER NOT NULL CHECK (revision >= 0),
      lookup_expires_at TEXT NOT NULL,
      PRIMARY KEY (authority_scope_cid, caller_request_id)
    ) STRICT`);
    database.prepare(`INSERT INTO client_requests VALUES
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
      fixture.authorityScopeCid, fixture.requestId,
      fixture.logicalRequestScopeCid, fixture.intentFingerprintCid,
      fixture.programDefinitionCid, fixture.parameterValuesCid,
      fixture.callerInputIntentCid, 'tenant-a', cid('d'), 0, expires);
    database.close();
    const migrated = openClientRequestJournal(path);
    t.after(() => migrated.close());
    const key = {tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.equal(migrated.lookup(key, moon).ref.runDefinitionCid, cid('d'));
    assert.throws(() => migrated.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestDefinitionMissing'});
    const next = {...fixture, requestId: 'after-migration'};
    next.logicalRequestScopeCid = hashCanonical({
      authority_scope_cid: next.authorityScopeCid,
      caller_request_id: next.requestId,
      version: 'actql-logical-request/0.1',
    });
    assert.ok(identity(next));
    assert.equal(migrated.acceptDefinition(identity(next), {
      tenantId: 'tenant-a', runDefinition: runDefinition('new-run'),
      lookupExpiresAt: expires,
    }, moon, publicationControl).inserted, true);
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

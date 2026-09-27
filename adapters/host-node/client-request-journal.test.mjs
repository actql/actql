import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';

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

function claimPhysicalStart(journal, ref, requested = identity(),
  currentAuthorization = true) {
  return journal.reservePhysicalStart(requested, {tenantId: 'tenant-a',
    ref, currentAuthorization}, moon, publicationControl);
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

test('rollback failure retains the primary acceptance error', async t => {
  const path = await directory(t);
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  database.exec(`CREATE TRIGGER reject_client_accept
    BEFORE INSERT ON client_requests BEGIN
      SELECT RAISE(ROLLBACK, 'PrimaryAcceptanceFailure');
    END`);
  database.close();
  assert.throws(() => journal.accept(identity(), {
    tenantId: 'tenant-a', runDefinitionCid: cid('d'),
    lookupExpiresAt: expires,
  }, moon), error => {
    assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
    assert.equal(error.operation, 'accept');
    assert.equal(error.outcome, 'unknown');
    assert.match(error.cause.message, /PrimaryAcceptanceFailure/u);
    assert.match(error.rollbackCause.message, /rollback/u);
    return true;
  });
  assert.equal(journal.lookup({tenantId: 'tenant-a',
    authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
  undefined);
});

test('rollback failure retains the primary Run-start error', async t => {
  const path = await directory(t);
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const requested = identity();
  const accepted = journal.acceptDefinition(requested, {
    tenantId: 'tenant-a', runDefinition: runDefinition(),
    lookupExpiresAt: expires, resultNames: ['answer'],
  }, moon, publicationControl);
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  database.exec(`CREATE TRIGGER reject_client_start
    BEFORE UPDATE OF dispatch_reserved ON client_requests BEGIN
      SELECT RAISE(ROLLBACK, 'PrimaryStartFailure');
    END`);
  database.close();
  assert.throws(() => journal.reserveDispatch(requested, {
    tenantId: 'tenant-a', currentAuthorization: true,
  }, moon, publicationControl), error => {
    assert.equal(error.code, 'ClientRunStartUnknown');
    assert.equal(error.operation, 'start');
    assert.equal(error.outcome, 'unknown');
    assert.match(error.cause.message, /PrimaryStartFailure/u);
    assert.match(error.rollbackCause.message, /rollback/u);
    return true;
  });
  assert.equal(journal.lookupRunDefinition(accepted.ref, moon,
    publicationControl).dispatchReserved, false);
});

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
    assert.equal(first.resolveDefinition(identity(), {tenantId: 'tenant-a'},
      moon, publicationControl), undefined);
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
    const attached = restarted.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.deepEqual(attached.ref, accepted.ref);
    assert.equal(attached.durability, 'durable');
    assert.equal(attached.runDefinition.wire, definition.wire);
    for (const foreign of [
      {...accepted.ref, tenantId: 'tenant-b'},
      {...accepted.ref, authorityScopeCid: cid('c')},
      {...accepted.ref, runDefinitionCid: cid('d')},
    ]) {
      assert.equal(restarted.lookupRunDefinition(foreign, moon,
        publicationControl), undefined);
    }
    const resolved = restarted.resolveDefinition(identity(),
      {tenantId: 'tenant-a'}, moon, publicationControl);
    assert.equal(resolved.ref.runDefinitionCid, definition.identity);
    assert.equal(resolved.runDefinition.wire, definition.wire);
    assert.equal(restarted.resolveDefinition(identity(),
      {tenantId: 'tenant-b'}, moon, publicationControl), undefined);
    const changed = {...fixture, parameterValuesCid: cid('c')};
    changed.intentFingerprintCid = hashCanonical({
      caller_input_intent_cid: changed.callerInputIntentCid,
      parameter_values_cid: changed.parameterValuesCid,
      program_definition_cid: changed.programDefinitionCid,
      version: 'actql-logical-request-intent/0.1',
    });
    assert.throws(() => restarted.resolveDefinition(identity(changed),
      {tenantId: 'tenant-a'}, moon, publicationControl),
    {code: 'ClientRequestIntentConflict'});
    const repeated = restarted.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: runDefinition('new-run'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.equal(repeated.inserted, false);
    assert.equal(repeated.runDefinition.wire, definition.wire);
    assert.equal(restarted.lookupDefinition({...key, tenantId: 'tenant-b'},
      moon, publicationControl), undefined);
  });

test('one durable Run dispatch reservation survives an unknown start',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition('reserved-run');
    first.acceptDefinition(identity(), {tenantId: 'tenant-a',
      runDefinition: definition, lookupExpiresAt: expires},
    moon, publicationControl);
    first.close(); // The Run is accepted, but no dispatch was reserved.

    const restarted = openClientRequestJournal(path);
    const deniedStart = installNodeClientRunStart({journal: restarted,
      requestControl: moon, publicationControl,
      authorizeRunStart: () => false});
    await assert.rejects(deniedStart({identity: identity(),
      tenantId: 'tenant-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRunStartDenied'});
    assert.throws(() => restarted.reserveDispatch(identity(), {
      tenantId: 'tenant-b', currentAuthorization: true,
    }, moon, publicationControl), {code: 'ClientRunStartDenied'});
    const start = installNodeClientRunStart({journal: restarted,
      requestControl: moon, publicationControl,
      authorizeRunStart: ({ref}) => ref.runDefinitionCid ===
        definition.identity});
    const reserved = await start({identity: identity(),
      tenantId: 'tenant-a', principalId: 'principal-a', connection: {}});
    assert.equal(reserved.kind, 'reserved');
    assert.equal(reserved.revision, 1);
    assert.equal(reserved.ref.runDefinitionCid, definition.identity);
    assert.equal(restarted.reserveDispatch(identity(), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl).kind, 'reconcile');
    restarted.close(); // Physical work may or may not have started.

    const recovered = openClientRequestJournal(path);
    t.after(() => recovered.close());
    const repeated = recovered.reserveDispatch(identity(), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl);
    assert.equal(repeated.kind, 'reconcile');
    assert.equal(repeated.revision, 1);
    assert.equal(recovered.lookupRunDefinition(reserved.ref, moon,
      publicationControl).preDispatchFailureConfirmed, false);
    const changed = {...fixture, parameterValuesCid: cid('c')};
    changed.intentFingerprintCid = hashCanonical({
      caller_input_intent_cid: changed.callerInputIntentCid,
      parameter_values_cid: changed.parameterValuesCid,
      program_definition_cid: changed.programDefinitionCid,
      version: 'actql-logical-request-intent/0.1',
    });
    const recoveredDeniedStart = installNodeClientRunStart({journal: recovered,
      requestControl: moon, publicationControl,
      authorizeRunStart: () => false});
    const recoveredStart = installNodeClientRunStart({journal: recovered,
      requestControl: moon, publicationControl,
      authorizeRunStart: () => true});
    await assert.rejects(recoveredDeniedStart({identity: identity(changed),
      tenantId: 'tenant-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRunStartDenied'});
    await assert.rejects(recoveredStart({identity: identity(changed),
      tenantId: 'tenant-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => recovered.reserveDispatch(identity(changed), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl), {code: 'ClientRequestIntentConflict'});
    assert.equal(recovered.lookup({tenantId: 'tenant-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon)
      .revision, 1);
  });

test('only an exact reserved Run retains a confirmed pre-dispatch failure',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition('failed-before-site');
    const accepted = first.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.throws(() => first.markPreDispatchFailure(accepted.ref),
      {code: 'ClientRunFailureObservationDenied'});
    first.reserveDispatch(identity(), {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    for (const ref of [
      {...accepted.ref, tenantId: 'other-tenant'},
      {...accepted.ref, authorityScopeCid: cid('c')},
      {...accepted.ref, runDefinitionCid: cid('d')},
    ]) {
      assert.throws(() => first.markPreDispatchFailure(ref),
        {code: 'ClientRunFailureObservationDenied'});
    }
    first.markPreDispatchFailure(accepted.ref);
    first.markPreDispatchFailure(accepted.ref);
    first.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const retained = reopened.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.equal(retained.preDispatchFailureConfirmed, true);
    assert.equal(retained.physicalStartReserved, false);
    assert.equal(retained.revision, 2);
    assert.equal(claimPhysicalStart(reopened, accepted.ref), false);
    assert.equal(reopened.reserveDispatch(identity(), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl).kind, 'reconcile');
  });

test('a restarted Run can claim physical start once after a safe reservation',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const accepted = first.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: runDefinition('restart-before-site'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    first.reserveDispatch(identity(), {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    first.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.lookupRunDefinition(accepted.ref, moon,
      publicationControl).physicalStartReserved, false);
    assert.throws(() => claimPhysicalStart(reopened, {
      ...accepted.ref, tenantId: 'other-tenant',
    }), {code: 'ClientRunPhysicalStartDenied'});
    assert.throws(() => claimPhysicalStart(reopened, accepted.ref,
      identity(), false), {code: 'ClientRunPhysicalStartDenied'});
    assert.equal(claimPhysicalStart(reopened, accepted.ref), true);
    assert.equal(claimPhysicalStart(reopened, accepted.ref), false);
    assert.equal(reopened.lookupRunDefinition(accepted.ref, moon,
      publicationControl).physicalStartReserved, true);
    assert.throws(() => reopened.markPreDispatchFailure(accepted.ref),
      {code: 'ClientRunFailureObservationDenied'});
    assert.equal(reopened.lookupRunDefinition(accepted.ref, moon,
      publicationControl).revision, 2);
  });

test('checked Result inventory stays with the durable Run', async t => {
  const path = await directory(t);
  const journal = openClientRequestJournal(path);
  const definition = runDefinition('inventory-run');
  const first = journal.acceptDefinition(identity(), {
    tenantId: 'tenant-a', runDefinition: definition,
    resultNames: ['answer'], lookupExpiresAt: expires,
  }, moon, publicationControl);
  assert.deepEqual(first.resultNames, ['answer']);
  assert.throws(() => journal.acceptDefinition(identity(), {
    tenantId: 'tenant-a', runDefinition: definition,
    resultNames: ['different'], lookupExpiresAt: expires,
  }, moon, publicationControl), {code: 'ClientRequestResultInventoryMismatch'});
  journal.close();
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  const retained = reopened.lookupRunDefinition(first.ref, moon,
    publicationControl);
  assert.deepEqual(retained.resultNames, ['answer']);
  assert.equal(retained.dispatchReserved, false);
});

test('admit-or-lookup skips issuance after ACK loss and rejects changed intent',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    t.after(() => first.close());
    let issued = 0;
    const accepted = await first.admitOrLookupDefinition(identity(), {
      tenantId: 'tenant-a', lookupExpiresAt: expires,
      issueDefinition: () => { issued++; return runDefinition(); },
    }, moon, publicationControl);
    assert.equal(accepted.inserted, true);
    assert.equal(issued, 1);
    first.close(); // The caller never observes the acceptance reply.

    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const repeated = await restarted.admitOrLookupDefinition(identity(), {
      tenantId: 'tenant-a', lookupExpiresAt: expires,
      issueDefinition: () => { issued++; return runDefinition('foreign'); },
    }, moon, publicationControl);
    assert.equal(repeated.inserted, false);
    assert.equal(repeated.ref.runDefinitionCid,
      accepted.ref.runDefinitionCid);
    assert.equal(repeated.runDefinition.wire, accepted.runDefinition.wire);
    assert.equal(issued, 1);

    const changed = {...fixture, parameterValuesCid: cid('c')};
    changed.intentFingerprintCid = hashCanonical({
      caller_input_intent_cid: changed.callerInputIntentCid,
      parameter_values_cid: changed.parameterValuesCid,
      program_definition_cid: changed.programDefinitionCid,
      version: 'actql-logical-request-intent/0.1',
    });
    await assert.rejects(restarted.admitOrLookupDefinition(
      identity(changed), {
        tenantId: 'tenant-a', lookupExpiresAt: expires,
        issueDefinition: () => { issued++; return runDefinition('changed'); },
      }, moon, publicationControl), {code: 'ClientRequestIntentConflict'});
    assert.equal(issued, 1);
  });

test('racing issuers return one atomic Run acceptance', async t => {
  const path = await directory(t);
  const left = openClientRequestJournal(path);
  const right = openClientRequestJournal(path);
  t.after(() => left.close());
  t.after(() => right.close());
  const gate = Promise.withResolvers();
  let issuers = 0;
  const submit = (journal, runId) => journal.admitOrLookupDefinition(
    identity(), {tenantId: 'tenant-a', lookupExpiresAt: expires,
      issueDefinition: async () => {
        issuers++;
        await gate.promise;
        return runDefinition(runId);
      }}, moon, publicationControl);
  const pending = [submit(left, 'race-left'), submit(right, 'race-right')];
  assert.equal(issuers, 2);
  gate.resolve();
  const accepted = await Promise.all(pending);
  assert.equal(accepted.filter(entry => entry.inserted).length, 1);
  assert.deepEqual(accepted[0].ref, accepted[1].ref);
  assert.equal(accepted[0].runDefinition.wire,
    accepted[1].runDefinition.wire);
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
    assert.throws(() => reopened.lookupRunDefinition({
      tenantId: 'tenant-a', authorityScopeCid: cid('a'),
      runDefinitionCid: definition.identity,
    }, moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => reopened.resolveDefinition(identity(),
      {tenantId: 'tenant-a'}, moon, publicationControl),
    {code: 'ClientRequestJournalCorrupt'});
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
    const nextDefinition = runDefinition('new-run');
    assert.equal(migrated.acceptDefinition(identity(next), {
      tenantId: 'tenant-a', runDefinition: nextDefinition,
      lookupExpiresAt: expires,
    }, moon, publicationControl).inserted, true);
    assert.equal(migrated.reserveDispatch(identity(next), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl).kind, 'reserved');
  });

test('legacy accepted Runs migrate as dispatch-uncertain, not unstarted',
  async t => {
    const path = await directory(t);
    const definition = runDefinition('legacy-run');
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
      run_definition_wire TEXT,
      revision INTEGER NOT NULL CHECK (revision >= 0),
      lookup_expires_at TEXT NOT NULL,
      PRIMARY KEY (authority_scope_cid, caller_request_id)
    ) STRICT`);
    database.prepare(`INSERT INTO client_requests VALUES
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
      fixture.authorityScopeCid, fixture.requestId,
      fixture.logicalRequestScopeCid, fixture.intentFingerprintCid,
      fixture.programDefinitionCid, fixture.parameterValuesCid,
      fixture.callerInputIntentCid, 'tenant-a', definition.identity,
      definition.wire, 0, expires);
    database.close();
    const migrated = openClientRequestJournal(path);
    t.after(() => migrated.close());
    const start = migrated.reserveDispatch(identity(), {
      tenantId: 'tenant-a', currentAuthorization: true,
    }, moon, publicationControl);
    assert.equal(start.kind, 'reconcile');
    assert.equal(start.revision, 0);
    assert.equal(start.ref.runDefinitionCid, definition.identity);
    assert.equal(migrated.lookupRunDefinition(start.ref, moon,
      publicationControl).physicalStartReserved, undefined);
    assert.equal(claimPhysicalStart(migrated, start.ref), false);
  });

test('prior reserved Runs never migrate into a safe physical restart',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const accepted = first.acceptDefinition(identity(), {
      tenantId: 'tenant-a', runDefinition: runDefinition('prior-reserved'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    first.reserveDispatch(identity(), {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    first.close();
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.exec('ALTER TABLE client_requests DROP COLUMN '
      + 'physical_start_reserved');
    database.close();
    const migrated = openClientRequestJournal(path);
    t.after(() => migrated.close());
    const retained = migrated.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.equal(retained.dispatchReserved, true);
    assert.equal(retained.physicalStartReserved, undefined);
    assert.equal(claimPhysicalStart(migrated, accepted.ref), false);
    assert.throws(() => migrated.markPreDispatchFailure(accepted.ref),
      {code: 'ClientRunFailureObservationDenied'});
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


test('durable cancellation excludes physical start after restart', async t => {
  const path = await directory(t);
  let journal = openClientRequestJournal(path);
  const requested = identity();
  const accepted = journal.acceptDefinition(requested, {tenantId: 'tenant-a',
    runDefinition: runDefinition(), lookupExpiresAt: expires,
    resultNames: ['answer']}, moon, publicationControl);
  journal.reserveDispatch(requested, {tenantId: 'tenant-a',
    currentAuthorization: true}, moon, publicationControl);
  assert.throws(() => journal.requestCancellation(accepted.ref, {
    currentAuthorization: false, publicationCommitted: false,
  }, moon, publicationControl), /ClientRunCancellationDenied/);
  const cancelled = journal.requestCancellation(accepted.ref, {
    currentAuthorization: true, publicationCommitted: false,
  }, moon, publicationControl);
  assert.equal(cancelled.kind, 'accepted');
  journal.close();
  journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  assert.equal(claimPhysicalStart(journal, accepted.ref), false);
  const repeated = journal.requestCancellation(accepted.ref, {
    currentAuthorization: true, publicationCommitted: false,
  }, moon, publicationControl);
  assert.equal(repeated.kind, 'already_requested');
  assert.equal(repeated.revision, cancelled.revision);
  const retained = journal.lookupRunDefinition(accepted.ref, moon,
    publicationControl);
  assert.equal(retained.cancellationRequested, true);
  assert.equal(retained.physicalStartReserved, false);
  assert.deepEqual(JSON.parse(moon.clientRunControlObservation(
    retained.revision, true, true, false, false)), {
    cancellation_requested: true, physical_stop: 'confirmed',
    revision: cancelled.revision,
  });
  assert.throws(() => journal.requestCancellation({...accepted.ref,
    tenantId: 'other'}, {currentAuthorization: true,
    publicationCommitted: false}, moon, publicationControl),
  /ClientRunCancellationDenied/);
});

test('started cancellation never invents stop and terminal completion wins',
  async t => {
    const journal = openClientRequestJournal(await directory(t));
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {tenantId: 'tenant-a',
      runDefinition: runDefinition(), lookupExpiresAt: expires,
      resultNames: ['answer']}, moon, publicationControl);
    journal.reserveDispatch(requested, {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    assert.equal(claimPhysicalStart(journal, accepted.ref), true);
    const cancelled = journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted: false,
    }, moon, publicationControl);
    assert.equal(JSON.parse(moon.clientRunControlObservation(
      cancelled.revision, true, false, false, false)).physical_stop, 'unknown');
    assert.equal(claimPhysicalStart(journal, accepted.ref), false);
    journal.markPhysicalClose(accepted.ref);
    const retained = journal.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.equal(retained.physicalCloseConfirmed, true);
    assert.equal(journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted: true,
    }, moon, publicationControl).kind, 'already_terminal');
  });

test('started Run records only a confirmed terminal outcome across restart',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {
      tenantId: 'tenant-a', runDefinition: runDefinition(),
      lookupExpiresAt: expires, resultNames: ['answer'],
    }, moon, publicationControl);
    journal.reserveDispatch(requested, {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    assert.equal(claimPhysicalStart(journal, accepted.ref), true);
    journal.close();
    journal = openClientRequestJournal(path);
    const state = () => {
      const retained = journal.lookupRunDefinition(accepted.ref, moon,
        publicationControl);
      return JSON.parse(checked(
        moon.clientProgramIssueControlledUnpublishedRunState(
          publicationControl.runDefinitionRunId(retained.runDefinition),
          '2026-09-27T00:00:00.000Z', retained.resultNames,
          retained.dispatchReserved, retained.preDispatchFailureConfirmed,
          false, retained.observedTerminalOutcome ?? 'none',
          retained.physicalStartReserved === true &&
            retained.observedTerminalOutcome === null)));
    };
    assert.equal(state().status, 'needs_reconciliation');
    assert.deepEqual(state().next_action,
      {kind: 'reconcile_run', reason: 'execution_unknown'});
    journal.markPhysicalClose(accepted.ref, 'failed');
    assert.equal(state().status, 'failed');
    journal.markPhysicalClose(accepted.ref, 'failed');
    assert.throws(() => journal.markPhysicalClose(accepted.ref,
      'cancelled'), {code: 'ClientRunStopObservationDenied'});
    journal.close();
    journal = openClientRequestJournal(path);
    assert.equal(state().status, 'failed');
    assert.equal(claimPhysicalStart(journal, accepted.ref), false);
  });

test('a started Run keeps one reconciliation state across a restart',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {tenantId: 'tenant-a',
      runDefinition: runDefinition(), lookupExpiresAt: expires,
      resultNames: ['answer']}, moon, publicationControl);
    const state = effects => JSON.stringify({version: 'actql-run-state/0.1',
      run_id: 'saved-run', status: 'needs_reconciliation',
      updated_at: '2026-09-24T00:00:03.000Z',
      next_action: {kind: 'reconcile', effects},
      result_available: false, result_availability: {answer: {
        state: 'unavailable', observed_at: '2026-09-24T00:00:03.000Z',
        reason: 'not_published'}}});
    // Nothing is recorded for a Run that never claimed its physical start.
    assert.throws(() => journal.recordReconciliationState(accepted.ref,
      state(['save'])), {code: 'ClientRunReconciliationDenied'});
    journal.reserveDispatch(requested, {tenantId: 'tenant-a',
      currentAuthorization: true}, moon, publicationControl);
    assert.equal(claimPhysicalStart(journal, accepted.ref), true);
    assert.equal(journal.lookupReconciliationState(accepted.ref), undefined);
    assert.throws(() => journal.recordReconciliationState(accepted.ref,
      JSON.stringify({status: 'succeeded'})),
    {code: 'InvalidClientRunReconciliation'});
    journal.recordReconciliationState(accepted.ref, state(['save']));
    journal.recordReconciliationState(accepted.ref, state(['save']));
    assert.throws(() => journal.recordReconciliationState(accepted.ref,
      state(['save', 'save_again'])),
    {code: 'ClientRunReconciliationConflict'});
    journal.close();
    journal = openClientRequestJournal(path);
    assert.equal(journal.lookupReconciliationState(accepted.ref),
      state(['save']));
    assert.equal(journal.lookupReconciliationState({...accepted.ref,
      runDefinitionCid: cid('9')}), undefined);
  });

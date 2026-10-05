import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {canonicalJson} from './local-account-config.mjs';
import './client-two-source-checkpoints.test.mjs';
import {installNodeClientRunStart} from './client-run-start.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {issueInstalledRunControlObservation} from
  '../host-common/run-state-observation.mjs';

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

test('Run-control issuer failure retains its typed reason across the Host JS bridge',
  () => {
    assert.throws(() => issueInstalledRunControlObservation(moon, {
      revision: -1, cancellationRequested: false,
      physicallyUnstarted: false, preDispatchFailureConfirmed: false,
      physicalCloseConfirmed: false,
    }), error => {
      assert.equal(error.message, 'InvalidRunControl');
      assert.equal(error.cause.code, 'MoonBitHostFailure');
      assert.equal(error.primaryFailure, error.cause.cause);
      assert.equal(typeof error.primaryFailure?.$tag, 'number');
      return true;
    });
  });
const publicationControl = runtimeCore(moon).publicationControl;
const contractLimits = Object.freeze({
  maxWireBytes: 65536, maxNodes: 4096, maxDepth: 64,
});

function runDefinition(runId = 'saved-run') {
  return publicationControl.seal('run_definition', JSON.stringify({
    version: 'actql-run-definition/0.1',
    scope_id: 'namespace-a-scope',
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
  return journal.reservePhysicalStart(requested, {namespaceId: 'namespace-a',
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

test('automatic rollback retains the primary acceptance error', async t => {
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
    namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
    lookupExpiresAt: expires,
  }, moon), error => {
    assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
    assert.equal(error.operation, 'accept');
    assert.equal(error.outcome, 'failed');
    assert.match(error.cause.message, /PrimaryAcceptanceFailure/u);
    assert.equal(error.rollbackCause, undefined);
    assert.equal(error.connectionUsable, true);
    return true;
  });
  assert.equal(journal.lookup({namespaceId: 'namespace-a',
    authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
  undefined);
});

test('automatic rollback retains the primary Run-start error', async t => {
  const path = await directory(t);
  const journal = openClientRequestJournal(path);
  t.after(() => journal.close());
  const requested = identity();
  const accepted = journal.acceptDefinition(requested, {
    namespaceId: 'namespace-a', runDefinition: runDefinition(),
    lookupExpiresAt: expires, resultNames: ['answer'],
  }, moon, publicationControl);
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  database.exec(`CREATE TRIGGER reject_client_start
    BEFORE UPDATE OF dispatch_reserved ON client_requests BEGIN
      SELECT RAISE(ROLLBACK, 'PrimaryStartFailure');
    END`);
  database.close();
  assert.throws(() => journal.reserveDispatch(requested, {
    namespaceId: 'namespace-a', currentAuthorization: true,
  }, moon, publicationControl), error => {
    assert.equal(error.code, 'ClientRunStartUnknown');
    assert.equal(error.operation, 'start');
    assert.equal(error.outcome, 'failed');
    assert.match(error.cause.message, /PrimaryStartFailure/u);
    assert.equal(error.rollbackCause, undefined);
    assert.equal(error.connectionUsable, true);
    return true;
  });
  assert.equal(journal.lookupRunDefinition(accepted.ref, moon,
    publicationControl).dispatchReserved, false);
});

test('COMMIT and rollback loss retain both causes and fence the journal',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    const exec = DatabaseSync.prototype.exec;
    let commitFailure = true;
    let rollbackFailure = true;
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && commitFailure) {
        commitFailure = false;
        throw new Error('COMMIT_RESULT_LOST');
      }
      if (sql === 'ROLLBACK' && rollbackFailure) {
        rollbackFailure = false;
        throw new Error('ROLLBACK_FAILED');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => journal.accept(identity(), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon), error => {
      assert.equal(error.code, 'ClientRequestAcceptanceUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.operation, 'accept');
      assert.match(error.cause.message, /COMMIT_RESULT_LOST/u);
      assert.match(error.rollbackCause.message, /ROLLBACK_FAILED/u);
      assert.equal(error.connectionUsable, false);
      return true;
    });
    assert.throws(() => journal.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    {code: 'ClientRequestJournalConnectionUnusable'});
    t.mock.restoreAll();
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    undefined);
  });

test('durable Client request survives ACK loss and restart without a new Run',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const requested = identity();
    assert.ok(requested);
    const accepted = first.accept(requested, {
      namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon);
    assert.equal(accepted.inserted, true);
    assert.deepEqual(accepted.ref, {
      namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      runDefinitionCid: cid('d'),
    });
    first.close(); // The acceptance reply is deliberately not used.

    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const found = reopened.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon);
    assert.deepEqual(found, {
      requestId: fixture.requestId,
      ref: accepted.ref,
      durability: 'durable', revision: 0,
      lookupExpiresAt: expires,
    });
    const repeated = reopened.accept(identity(), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon);
    assert.equal(repeated.inserted, false);
    assert.deepEqual(repeated.ref, accepted.ref);
    assert.equal(reopened.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('c'), requestId: fixture.requestId}, moon),
    undefined);
    assert.equal(reopened.lookup({namespaceId: 'namespace-b',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    undefined);
  });

test('Run Definition and request acceptance survive one atomic restart',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition();
    assert.equal(first.resolveDefinition(identity(), {namespaceId: 'namespace-a'},
      moon, publicationControl), undefined);
    const accepted = first.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.equal(accepted.inserted, true);
    assert.equal(accepted.ref.runDefinitionCid, definition.identity);
    first.close(); // Simulate losing the response after durable acceptance.

    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    const retained = restarted.lookupDefinition(key, moon,
      publicationControl);
    assert.equal(retained.ref.runDefinitionCid, definition.identity);
    assert.equal(retained.runDefinition.wire, definition.wire);
    const attached = restarted.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.deepEqual(attached.ref, accepted.ref);
    assert.equal(attached.durability, 'durable');
    assert.equal(attached.requestId, fixture.requestId);
    assert.equal(attached.runDefinition.wire, definition.wire);
    for (const foreign of [
      {...accepted.ref, namespaceId: 'namespace-b'},
      {...accepted.ref, authorityScopeCid: cid('c')},
      {...accepted.ref, runDefinitionCid: cid('d')},
    ]) {
      assert.equal(restarted.lookupRunDefinition(foreign, moon,
        publicationControl), undefined);
    }
    const resolved = restarted.resolveDefinition(identity(),
      {namespaceId: 'namespace-a'}, moon, publicationControl);
    assert.equal(resolved.ref.runDefinitionCid, definition.identity);
    assert.equal(resolved.runDefinition.wire, definition.wire);
    assert.equal(restarted.resolveDefinition(identity(),
      {namespaceId: 'namespace-b'}, moon, publicationControl), undefined);
    const changed = {...fixture, parameterValuesCid: cid('c')};
    changed.intentFingerprintCid = hashCanonical({
      caller_input_intent_cid: changed.callerInputIntentCid,
      parameter_values_cid: changed.parameterValuesCid,
      program_definition_cid: changed.programDefinitionCid,
      version: 'actql-logical-request-intent/0.1',
    });
    assert.throws(() => restarted.resolveDefinition(identity(changed),
      {namespaceId: 'namespace-a'}, moon, publicationControl),
    {code: 'ClientRequestIntentConflict'});
    const repeated = restarted.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition('new-run'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.equal(repeated.inserted, false);
    assert.equal(repeated.runDefinition.wire, definition.wire);
    assert.equal(restarted.lookupDefinition({...key, namespaceId: 'namespace-b'},
      moon, publicationControl), undefined);
  });

test('one durable Run dispatch reservation survives an unknown start',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition('reserved-run');
    first.acceptDefinition(identity(), {namespaceId: 'namespace-a',
      runDefinition: definition, lookupExpiresAt: expires},
    moon, publicationControl);
    first.close(); // The Run is accepted, but no dispatch was reserved.

    const restarted = openClientRequestJournal(path);
    const deniedStart = installNodeClientRunStart({journal: restarted,
      requestControl: moon, publicationControl,
      authorizeRunStart: () => false});
    await assert.rejects(deniedStart({identity: identity(),
      namespaceId: 'namespace-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRunStartDenied'});
    assert.throws(() => restarted.reserveDispatch(identity(), {
      namespaceId: 'namespace-b', currentAuthorization: true,
    }, moon, publicationControl), {code: 'ClientRunStartDenied'});
    const start = installNodeClientRunStart({journal: restarted,
      requestControl: moon, publicationControl,
      authorizeRunStart: ({ref}) => ref.runDefinitionCid ===
        definition.identity});
    const reserved = await start({identity: identity(),
      namespaceId: 'namespace-a', principalId: 'principal-a', connection: {}});
    assert.equal(reserved.kind, 'reserved');
    assert.equal(reserved.revision, 1);
    assert.equal(reserved.ref.runDefinitionCid, definition.identity);
    assert.equal(restarted.reserveDispatch(identity(), {
      namespaceId: 'namespace-a', currentAuthorization: true,
    }, moon, publicationControl).kind, 'reconcile');
    restarted.close(); // Physical work may or may not have started.

    const recovered = openClientRequestJournal(path);
    t.after(() => recovered.close());
    const repeated = recovered.reserveDispatch(identity(), {
      namespaceId: 'namespace-a', currentAuthorization: true,
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
      namespaceId: 'namespace-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRunStartDenied'});
    await assert.rejects(recoveredStart({identity: identity(changed),
      namespaceId: 'namespace-a', principalId: 'principal-a', connection: {}}),
    {code: 'ClientRequestIntentConflict'});
    assert.throws(() => recovered.reserveDispatch(identity(changed), {
      namespaceId: 'namespace-a', currentAuthorization: true,
    }, moon, publicationControl), {code: 'ClientRequestIntentConflict'});
    assert.equal(recovered.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon)
      .revision, 1);
  });

test('only an exact reserved Run retains a confirmed pre-dispatch failure',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const definition = runDefinition('failed-before-site');
    const accepted = first.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    assert.throws(() => first.markPreDispatchFailure(accepted.ref),
      {code: 'ClientRunFailureObservationDenied'});
    first.reserveDispatch(identity(), {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl);
    for (const ref of [
      {...accepted.ref, namespaceId: 'other-namespace'},
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
      namespaceId: 'namespace-a', currentAuthorization: true,
    }, moon, publicationControl).kind, 'reconcile');
  });

test('a restarted Run can claim physical start once after a safe reservation',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    const accepted = first.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition('restart-before-site'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    first.reserveDispatch(identity(), {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl);
    first.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    assert.equal(reopened.lookupRunDefinition(accepted.ref, moon,
      publicationControl).physicalStartReserved, false);
    assert.throws(() => claimPhysicalStart(reopened, {
      ...accepted.ref, namespaceId: 'other-namespace',
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
    namespaceId: 'namespace-a', runDefinition: definition,
    resultNames: ['answer'], lookupExpiresAt: expires,
  }, moon, publicationControl);
  assert.deepEqual(first.resultNames, ['answer']);
  assert.throws(() => journal.acceptDefinition(identity(), {
    namespaceId: 'namespace-a', runDefinition: definition,
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
      namespaceId: 'namespace-a', lookupExpiresAt: expires,
      issueDefinition: () => { issued++; return runDefinition(); },
    }, moon, publicationControl);
    assert.equal(accepted.inserted, true);
    assert.equal(issued, 1);
    first.close(); // The caller never observes the acceptance reply.

    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    const repeated = await restarted.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires,
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
        namespaceId: 'namespace-a', lookupExpiresAt: expires,
        issueDefinition: () => { issued++; return runDefinition('changed'); },
      }, moon, publicationControl), {code: 'ClientRequestIntentConflict'});
    assert.equal(issued, 1);
  });

test('accepted Result policy original survives restart without reissuing a Run',
  async t => {
    const path = await directory(t);
    const wire = canonicalJson({classification: 'unknown',
      source_data_policy_cids: [], source_response_policy_cids: [],
      unknown_provenance: true, version: 'actql-effective-data-policy/0.1'});
    const original = publicationControl.admitSourceFreeResultPolicy({
      kind: 'data_policy',
      cid: `sha256:${createHash('sha256').update(wire).digest('hex')}`,
      wire,
    }, contractLimits);
    const first = openClientRequestJournal(path);
    const accepted = await first.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires,
      issueDefinition: () => ({...runDefinition(),
        runAdmissionEvidence: {prepared: 'prepared-owner-wire',
          authorization: 'authorization-owner-wire',
          resultPolicyOriginal: original}}),
    }, moon, publicationControl);
    assert.deepEqual(accepted.runAdmissionEvidence.resultPolicyOriginal,
      original);
    first.close();
    const restarted = openClientRequestJournal(path);
    t.after(() => restarted.close());
    let reissued = false;
    const repeated = await restarted.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires,
      issueDefinition: () => { reissued = true; return runDefinition('foreign'); },
    }, moon, publicationControl);
    assert.equal(reissued, false);
    assert.deepEqual(repeated.runAdmissionEvidence.resultPolicyOriginal,
      original);
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
    identity(), {namespaceId: 'namespace-a', lookupExpiresAt: expires,
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
      namespaceId: 'namespace-a',
      runDefinition: {...definition, identity: cid('f')},
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'InvalidClientRunDefinition'});
    assert.equal(journal.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    undefined);
    journal.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    journal.close();
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.prepare('UPDATE client_requests SET run_definition_wire = ?')
      .run('{}');
    database.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.equal(reopened.lookup(key, moon).ref.runDefinitionCid,
      definition.identity);
    assert.throws(() => reopened.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => reopened.lookupRunDefinition({
      namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      runDefinitionCid: definition.identity,
    }, moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => reopened.resolveDefinition(identity(),
      {namespaceId: 'namespace-a'}, moon, publicationControl),
    {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => reopened.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: definition,
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
  });

test('legacy request rows are not invented as complete Run Definitions',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    journal.accept(identity(), {namespaceId: 'namespace-a',
      runDefinitionCid: cid('d'), lookupExpiresAt: expires}, moon);
    journal.close();
    const reopened = openClientRequestJournal(path);
    t.after(() => reopened.close());
    const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.throws(() => reopened.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestDefinitionMissing'});
    assert.throws(() => reopened.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition(),
      lookupExpiresAt: expires,
    }, moon, publicationControl), {code: 'ClientRequestDefinitionMissing'});
  });

test('an unmarked prior journal is rejected without changing its bytes',
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
      fixture.callerInputIntentCid, 'namespace-a', cid('d'), 0, expires);
    database.close();
    const databasePath = join(path, 'client-requests.sqlite3');
    const original = await readFile(databasePath);
    const names = await readdir(path);
    assert.throws(() => openClientRequestJournal(path),
      {code: 'LegacyClientRequestJournalFormat'});
    assert.deepEqual(await readFile(databasePath), original);
    assert.deepEqual(await readdir(path), names);
  });

test('an unmarked accepted Run is never opened for physical restart',
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
      namespace_id TEXT NOT NULL,
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
      fixture.callerInputIntentCid, 'namespace-a', definition.identity,
      definition.wire, 0, expires);
    database.close();
    const databasePath = join(path, 'client-requests.sqlite3');
    const original = await readFile(databasePath);
    assert.throws(() => openClientRequestJournal(path),
      {code: 'LegacyClientRequestJournalFormat'});
    assert.deepEqual(await readFile(databasePath), original);
  });

test('a changed schema under the current marker is rejected before use',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path);
    first.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition('prior-reserved'),
      lookupExpiresAt: expires,
    }, moon, publicationControl);
    first.reserveDispatch(identity(), {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl);
    first.close();
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.exec('ALTER TABLE client_requests DROP COLUMN '
      + 'physical_start_reserved');
    database.close();
    const databasePath = join(path, 'client-requests.sqlite3');
    const original = await readFile(databasePath);
    assert.throws(() => openClientRequestJournal(path),
      {code: 'UnknownClientRequestJournalFormat'});
    assert.deepEqual(await readFile(databasePath), original);
  });

test('a mismatched WAL journal is refused without creating shared memory',
  async t => {
    const path = await directory(t);
    openClientRequestJournal(path).close();
    const databasePath = join(path, 'client-requests.sqlite3');
    const writer = new DatabaseSync(databasePath);
    t.after(() => writer.close());
    writer.exec('PRAGMA wal_autocheckpoint = 0');
    writer.exec('ALTER TABLE client_requests RENAME COLUMN namespace_id '
      + 'TO tenant_id');
    await rm(`${databasePath}-shm`, {force: true});
    const snapshot = async () => new Map(await Promise.all(
      (await readdir(path)).sort().map(async name =>
        [name, await readFile(join(path, name))])));
    const before = await snapshot();
    assert.ok(before.has('client-requests.sqlite3-wal'));
    assert.ok(!before.has('client-requests.sqlite3-shm'));
    const journalUrl = new URL('./client-request-journal.mjs', import.meta.url);
    const probe = spawnSync(process.execPath, ['--input-type=module', '-e',
      `import {openClientRequestJournal} from ${JSON.stringify(journalUrl.href)};
       try { openClientRequestJournal(process.argv[1]); process.exit(2); }
       catch (error) {
         if (error.code !== 'UnknownClientRequestJournalFormat') throw error;
       }`, path], {encoding: 'utf8'});
    assert.equal(probe.status, 0, probe.stderr);
    const after = await snapshot();
    assert.deepEqual([...after.keys()], [...before.keys()]);
    for (const [name, bytes] of before) {
      assert.deepEqual(after.get(name), bytes, name);
    }
  });

test('a current journal remains readable with uncheckpointed WAL', async t => {
  const path = await directory(t);
  openClientRequestJournal(path).close();
  const databasePath = join(path, 'client-requests.sqlite3');
  const writer = new DatabaseSync(databasePath);
  t.after(() => writer.close());
  writer.exec('PRAGMA wal_autocheckpoint = 0');
  // The main database is stale; only the uncheckpointed WAL has the
  // current schema. Ignoring WAL must not make this valid root fail.
  writer.exec('ALTER TABLE client_requests RENAME COLUMN namespace_id '
    + 'TO tenant_id');
  writer.exec('PRAGMA wal_checkpoint(TRUNCATE)');
  writer.exec('ALTER TABLE client_requests RENAME COLUMN tenant_id '
    + 'TO namespace_id');
  await rm(`${databasePath}-shm`, {force: true});
  assert.ok((await readdir(path)).includes('client-requests.sqlite3-wal'));
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  assert.equal(reopened.lookup({namespaceId: 'namespace-a',
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
      namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
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
      namespaceId: 'namespace-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestIntentConflict'});
    assert.equal(right.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon)
      .ref.runDefinitionCid, cid('d'));
    assert.equal(right.accept(identity(), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('f'),
      lookupExpiresAt: expires,
    }, moon).inserted, false);
    assert.throws(() => right.accept(identity(), {
      namespaceId: 'namespace-b', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestOwnerMismatch'});
  });

test('equal caller IDs in separate authority scopes remain independent',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const other = {...fixture, authorityScopeCid: cid('e')};
    other.logicalRequestScopeCid = hashCanonical({
      authority_scope_cid: other.authorityScopeCid,
      caller_request_id: other.requestId,
      version: 'actql-logical-request/0.1',
    });
    assert.ok(identity(other));
    journal.accept(identity(), {namespaceId: 'namespace-a',
      runDefinitionCid: cid('d'), lookupExpiresAt: expires}, moon);
    journal.accept(identity(other), {namespaceId: 'namespace-b',
      runDefinitionCid: cid('e'), lookupExpiresAt: expires}, moon);
    assert.equal(journal.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: fixture.authorityScopeCid,
      requestId: fixture.requestId}, moon).ref.runDefinitionCid, cid('d'));
    assert.equal(journal.lookup({namespaceId: 'namespace-b',
      authorityScopeCid: other.authorityScopeCid,
      requestId: other.requestId}, moon).ref.runDefinitionCid, cid('e'));
    assert.equal(journal.lookup({namespaceId: 'namespace-b',
      authorityScopeCid: fixture.authorityScopeCid,
      requestId: fixture.requestId}, moon), undefined);
  });

test('retained identity corruption is not reported as absence', async t => {
  const path = await directory(t);
  const store = openClientRequestJournal(path);
  store.accept(identity(), {
    namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
    lookupExpiresAt: expires,
  }, moon);
  store.close();
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  database.prepare('UPDATE client_requests SET intent_fingerprint_cid = ?')
    .run(cid('f'));
  database.close();
  const reopened = openClientRequestJournal(path);
  t.after(() => reopened.close());
  assert.throws(() => reopened.lookup({namespaceId: 'namespace-a',
    authorityScopeCid: cid('a'), requestId: fixture.requestId}, moon),
    {code: 'ClientRequestJournalCorrupt'});
});

test('different requests cannot alias one Run and capacity rejects before commit',
  async t => {
    const path = await directory(t);
    const first = openClientRequestJournal(path, {maxRecords: 2});
    t.after(() => first.close());
    first.accept(identity(), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
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
      namespaceId: 'namespace-a', runDefinitionCid: cid('d'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestRunAlreadyAssigned'});
    assert.equal(first.lookup({namespaceId: 'namespace-a',
      authorityScopeCid: cid('a'), requestId: next.requestId}, moon),
    undefined);
    first.accept(identity(next), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('e'),
      lookupExpiresAt: expires,
    }, moon);
    const third = {...fixture, requestId: 'third-request'};
    third.logicalRequestScopeCid = hashCanonical({
      authority_scope_cid: third.authorityScopeCid,
      caller_request_id: third.requestId,
      version: 'actql-logical-request/0.1',
    });
    assert.throws(() => first.accept(identity(third), {
      namespaceId: 'namespace-a', runDefinitionCid: cid('f'),
      lookupExpiresAt: expires,
    }, moon), {code: 'ClientRequestJournalCapacity'});
  });


test('durable cancellation excludes physical start after restart', async t => {
  const path = await directory(t);
  let journal = openClientRequestJournal(path);
  const requested = identity();
  const accepted = journal.acceptDefinition(requested, {namespaceId: 'namespace-a',
    runDefinition: runDefinition(), lookupExpiresAt: expires,
    resultNames: ['answer']}, moon, publicationControl);
  journal.reserveDispatch(requested, {namespaceId: 'namespace-a',
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
  assert.deepEqual(JSON.parse(checked(moon.clientRunControlObservation(
    retained.revision, true, true, false, false))), {
    cancellation_requested: true, physical_stop: 'confirmed',
    revision: cancelled.revision,
  });
  assert.throws(() => journal.requestCancellation({...accepted.ref,
    namespaceId: 'other'}, {currentAuthorization: true,
    publicationCommitted: false}, moon, publicationControl),
  /ClientRunCancellationDenied/);
});

test('started cancellation never invents stop and terminal completion wins',
  async t => {
    const journal = openClientRequestJournal(await directory(t));
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {namespaceId: 'namespace-a',
      runDefinition: runDefinition(), lookupExpiresAt: expires,
      resultNames: ['answer']}, moon, publicationControl);
    journal.reserveDispatch(requested, {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl);
    assert.equal(claimPhysicalStart(journal, accepted.ref), true);
    const cancelled = journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted: false,
    }, moon, publicationControl);
    assert.equal(JSON.parse(checked(moon.clientRunControlObservation(
      cancelled.revision, true, false, false, false))).physical_stop, 'unknown');
    assert.equal(claimPhysicalStart(journal, accepted.ref), false);
    journal.markPhysicalClose(accepted.ref);
    const retained = journal.lookupRunDefinition(accepted.ref, moon,
      publicationControl);
    assert.equal(retained.physicalCloseConfirmed, true);
    assert.equal(journal.requestCancellation(accepted.ref, {
      currentAuthorization: true, publicationCommitted: true,
    }, moon, publicationControl).kind, 'already_terminal');
  });

for (const outcome of ['failed', 'cancelled']) {
test(`started Run retains confirmed ${outcome} across restart and cancellation`,
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {
      namespaceId: 'namespace-a', runDefinition: runDefinition(),
      lookupExpiresAt: expires, resultNames: ['answer'],
    }, moon, publicationControl);
    journal.reserveDispatch(requested, {namespaceId: 'namespace-a',
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
    journal.markPhysicalClose(accepted.ref, outcome);
    assert.equal(state().status, outcome);
    const checkCancellation = () => {
      const before = journal.lookupRunDefinition(accepted.ref, moon,
        publicationControl);
      assert.equal(journal.requestCancellation(accepted.ref, {
        currentAuthorization: true, publicationCommitted: false,
      }, moon, publicationControl).kind, 'already_terminal');
      assert.throws(() => journal.requestCancellation(accepted.ref, {
        currentAuthorization: false, publicationCommitted: false,
      }, moon, publicationControl), {code: 'ClientRunCancellationDenied'});
      const after = journal.lookupRunDefinition(accepted.ref, moon,
        publicationControl);
      assert.equal(after.revision, before.revision);
      assert.equal(after.cancellationRequested, before.cancellationRequested);
    };
    checkCancellation();
    journal.markPhysicalClose(accepted.ref, outcome);
    assert.throws(() => journal.markPhysicalClose(accepted.ref,
      outcome === 'failed' ? 'cancelled' : 'failed'),
    {code: 'ClientRunStopObservationDenied'});
    journal.close();
    journal = openClientRequestJournal(path);
    assert.equal(state().status, outcome);
    checkCancellation();
    assert.equal(claimPhysicalStart(journal, accepted.ref), false);
  });
}

test('every definition lookup rejects a corrupt retained Result inventory',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {
      namespaceId: 'namespace-a', runDefinition: runDefinition(),
      lookupExpiresAt: expires, resultNames: ['answer'],
    }, moon, publicationControl);
    const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
    database.prepare('UPDATE client_requests SET result_names_json = ?')
      .run('["answer","answer"]');
    database.close();
    const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
      requestId: fixture.requestId};
    assert.throws(() => journal.lookupDefinition(key, moon,
      publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => journal.lookupRunDefinition(accepted.ref, moon,
      publicationControl), {code: 'ClientRequestJournalCorrupt'});
    assert.throws(() => journal.resolveDefinition(requested,
      {namespaceId: 'namespace-a'}, moon, publicationControl),
    {code: 'ClientRequestJournalCorrupt'});
  });

test('a started Run keeps one reconciliation state across a restart',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const requested = identity();
    const accepted = journal.acceptDefinition(requested, {namespaceId: 'namespace-a',
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
    journal.reserveDispatch(requested, {namespaceId: 'namespace-a',
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

// These are Host-private storage fixtures, not authorization evidence. The
// common admission owner remains responsible for the opaque owner wires.
function sourceInventoryObject() {
  return {
    version: 'actql-client-source-inventory/0.1', environmentCid: cid('e'),
    acquisitions: ['left', 'right'].map((side, index) => ({
      stage: index, input: 0, task: index,
      checkedSource: {
        requirementCid: cid(String(index + 1)),
        sourceRef: `connector://fixture/${side}/r#v`,
        sourceContractCid: cid('3'), carrierSchemaContractCid: cid('4'),
        sourceDataPolicyCid: cid('5'), dataClassification: 'internal',
        sourceViewContractCid: cid('6'), inputContractCid: cid('7'),
        outputContractCid: cid('8'),
      },
      readTuple: {connection: 'database', resource: '/warehouse.db',
        operation: 'read'},
      physicalBinding: {version: 'actql-installed-duckdb-target/0.1',
        database: 'warehouse', schema: 'main', table: side,
        utf8_hex: {database: '77617265686f757365', schema: '6d61696e',
          table: index === 0 ? '6c656674' : '7269676874'}},
    })),
  };
}

function githubInventoryObject() {
  const value = sourceInventoryObject();
  for (const [index, item] of value.acquisitions.entries()) {
    item.readTuple = {connection: 'github:api.example.test/octocat/hello',
      resource: 'issues', operation: 'read'};
    item.physicalBinding = {version: 'actql-installed-github-target/0.1',
      api_origin: 'https://api.example.test', repository_id: 1296269 + index,
      repository_node_id: `R_${index}`, owner: 'octocat', repo: 'hello',
      catalog_cid: cid('a'), resource: 'issues',
      fields: ['number', 'title']};
  }
  return value;
}

function inventoryEvidence(sourceInventory) {
  return {prepared: 'prepared-owner-wire', authorization: 'authorization-owner-wire',
    ...(sourceInventory === undefined ? {} : {sourceInventory})};
}

function acceptInventory(journal, sourceInventory, runId = 'inventory-run') {
  return journal.acceptDefinition(identity(), {
    namespaceId: 'namespace-a', runDefinition: runDefinition(runId),
    lookupExpiresAt: expires, resultNames: ['answer'],
    runAdmissionEvidence: inventoryEvidence(sourceInventory),
  }, moon, publicationControl);
}

function readInventoryRow(path) {
  const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
  try { return database.prepare('SELECT * FROM client_requests').get(); }
  finally { database.close(); }
}

test('source inventory is retained atomically and byte-exactly across restart',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const authored = sourceInventoryObject();
    // Native UTF-8 bytes survive even when the logical identifier uses NFC.
    authored.acquisitions[1].physicalBinding.table = 'right_é';
    authored.acquisitions[1].physicalBinding.utf8_hex.table = '72696768745f65cc81';
    const sourceInventory = canonicalJson(authored);
    const evidence = inventoryEvidence(sourceInventory);
    const accepted = journal.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition('two-source-run'),
      lookupExpiresAt: expires, resultNames: ['answer'], runAdmissionEvidence: evidence,
    }, moon, publicationControl);
    assert.equal(accepted.inserted, true);
    assert.deepEqual(accepted.runAdmissionEvidence, evidence);
    assert.equal(typeof accepted.runAdmissionEvidence.sourceInventory, 'string');
    assert.equal(Object.isFrozen(accepted.runAdmissionEvidence), true);

    const row = readInventoryRow(path);
    assert.equal(row.run_admission_evidence_json, JSON.stringify(evidence));
    assert.equal(row.run_definition_cid, accepted.ref.runDefinitionCid);
    assert.equal(row.caller_input_intent_cid, fixture.callerInputIntentCid);
    assert.equal(row.program_definition_cid, fixture.programDefinitionCid);
    assert.equal(row.parameter_values_cid, fixture.parameterValuesCid);
    assert.equal(row.logical_request_scope_cid, fixture.logicalRequestScopeCid);
    assert.equal(row.intent_fingerprint_cid, fixture.intentFingerprintCid);

    // Caller-owned mutable objects cannot retrofit the accepted string.
    authored.environmentCid = cid('9');
    authored.acquisitions[1].checkedSource.requirementCid = cid('a');
    evidence.sourceInventory = canonicalJson(authored);
    assert.equal(accepted.runAdmissionEvidence.sourceInventory, sourceInventory);
    assert.throws(() => { accepted.runAdmissionEvidence.sourceInventory = 'changed'; },
      TypeError);
    journal.close();
    journal = openClientRequestJournal(path);
    const retained = journal.lookupRunDefinition(accepted.ref, moon, publicationControl);
    assert.equal(retained.runAdmissionEvidence.sourceInventory, sourceInventory);
    assert.equal(retained.runDefinition.wire, accepted.runDefinition.wire);
    assert.equal(retained.dispatchReserved, false);
    assert.equal(retained.physicalStartReserved, false);
    let issuers = 0;
    const repeated = await journal.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory,
      issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
    }, moon, publicationControl);
    assert.equal(issuers, 0);
    assert.equal(repeated.inserted, false);
    assert.deepEqual(repeated.ref, accepted.ref);
    assert.equal(repeated.runAdmissionEvidence.sourceInventory, sourceInventory);
    assert.equal(readInventoryRow(path).run_admission_evidence_json,
      row.run_admission_evidence_json);
  });

test('installed row targets retain exact physical identity across restart',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const wire = canonicalJson(githubInventoryObject());
    const accepted = acceptInventory(journal, wire, 'github-inventory-run');
    journal.close();
    journal = openClientRequestJournal(path);
    assert.equal(journal.lookupRunDefinition(accepted.ref, moon,
      publicationControl).runAdmissionEvidence.sourceInventory, wire);
    const before = readInventoryRow(path);
    const changed = githubInventoryObject();
    changed.acquisitions[1].physicalBinding.repository_node_id = 'R_foreign';
    assert.throws(() => acceptInventory(journal, canonicalJson(changed)),
      {code: 'ClientRequestSourceInventoryMismatch'});
    assert.deepEqual(readInventoryRow(path), before);
  });

for (const [label, mutate] of [
  ['noncanonical API origin', value => {
    value.acquisitions[1].physicalBinding.api_origin =
      'https://api.example.test/path';
  }],
  ['foreign resource', value => {
    value.acquisitions[1].physicalBinding.resource = 'pull_requests';
  }],
  ['foreign access target', value => {
    value.acquisitions[1].readTuple.connection =
      'github:api.example.test/octocat/other';
  }],
]) {
  test(`installed row inventory rejects ${label} before issuance`, async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const value = githubInventoryObject();
    mutate(value);
    assert.throws(() => acceptInventory(journal, canonicalJson(value)),
      {code: 'InvalidClientSourceInventory'});
    assert.equal(readInventoryRow(path), undefined);
  });
}

test('source inventory does not change legacy singular admission evidence bytes',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const bytes = '{"prepared":"prepared-owner-wire","authorization":"authorization-owner-wire"}';
    const accepted = acceptInventory(journal, undefined, 'singular-run');
    assert.equal(readInventoryRow(path).run_admission_evidence_json, bytes);
    journal.close();
    journal = openClientRequestJournal(path);
    const retained = journal.lookupRunDefinition(accepted.ref, moon, publicationControl);
    assert.deepEqual(retained.runAdmissionEvidence, JSON.parse(bytes));
    assert.equal(Object.hasOwn(retained.runAdmissionEvidence, 'sourceInventory'), false);
    assert.equal(readInventoryRow(path).run_admission_evidence_json, bytes);
  });

const inventoryMutations = [
  ['second physical binding', value => {
    value.acquisitions[1].physicalBinding.table = 'other';
    value.acquisitions[1].physicalBinding.utf8_hex.table = '6f74686572';
  }],
  ['second checked requirement', value => {
    value.acquisitions[1].checkedSource.requirementCid = cid('9');
  }],
  ['environment generation', value => { value.environmentCid = cid('9'); }],
];

for (const [label, mutate] of inventoryMutations) {
  test(`source inventory rejects changed ${label} before duplicate issuance`,
    async t => {
      const path = await directory(t);
      let journal = openClientRequestJournal(path);
      t.after(() => journal.close());
      const original = canonicalJson(sourceInventoryObject());
      const accepted = acceptInventory(journal, original);
      const before = readInventoryRow(path);
      journal.close();
      journal = openClientRequestJournal(path);
      const changed = sourceInventoryObject();
      mutate(changed);
      const proposed = canonicalJson(changed);
      let issuers = 0;
      await assert.rejects(journal.admitOrLookupDefinition(identity(), {
        namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: proposed,
        issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
      }, moon, publicationControl), {code: 'ClientRequestSourceInventoryMismatch'});
      assert.equal(issuers, 0);
      assert.throws(() => acceptInventory(journal, proposed, 'different-run'),
        {code: 'ClientRequestSourceInventoryMismatch'});
      assert.deepEqual(readInventoryRow(path), before);
      const retained = journal.lookupRunDefinition(accepted.ref, moon, publicationControl);
      assert.equal(retained.runAdmissionEvidence.sourceInventory, original);
      assert.equal(retained.dispatchReserved, false);
      assert.equal(retained.physicalStartReserved, false);
    });
}

test('source inventory mismatch in racing issuers preserves only the winning Run',
  async t => {
    const path = await directory(t);
    const left = openClientRequestJournal(path);
    const right = openClientRequestJournal(path);
    t.after(() => left.close());
    t.after(() => right.close());
    const original = canonicalJson(sourceInventoryObject());
    const changed = sourceInventoryObject();
    inventoryMutations[0][1](changed);
    const proposed = canonicalJson(changed);
    const gate = Promise.withResolvers();
    let issuers = 0;
    const losing = right.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: proposed,
      issueDefinition: async () => {
        issuers++;
        await gate.promise;
        return {runDefinition: runDefinition('race-loser'),
          runAdmissionEvidence: inventoryEvidence(proposed)};
      },
    }, moon, publicationControl);
    const rejected = assert.rejects(losing, {code: 'ClientRequestSourceInventoryMismatch'});
    const accepted = await left.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: original,
      issueDefinition: () => {
        issuers++;
        return {runDefinition: runDefinition('race-winner'),
          runAdmissionEvidence: inventoryEvidence(original)};
      },
    }, moon, publicationControl);
    assert.equal(issuers, 2);
    assert.equal(accepted.inserted, true);
    const before = readInventoryRow(path);
    gate.resolve();
    await rejected;
    assert.deepEqual(readInventoryRow(path), before);
    const retained = right.resolveDefinition(identity(), {namespaceId: 'namespace-a'},
      moon, publicationControl);
    assert.deepEqual(retained.ref, accepted.ref);
    assert.equal(retained.runAdmissionEvidence.sourceInventory, original);
    assert.equal(retained.dispatchReserved, false);
    assert.equal(retained.physicalStartReserved, false);
  });

test('source inventory must equal the issued evidence before initial acceptance',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const original = canonicalJson(sourceInventoryObject());
    const changed = sourceInventoryObject();
    inventoryMutations[2][1](changed);
    for (const issuedInventory of [undefined, canonicalJson(changed)]) {
      let issuers = 0;
      await assert.rejects(journal.admitOrLookupDefinition(identity(), {
        namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: original,
        issueDefinition: () => {
          issuers++;
          return {runDefinition: runDefinition(),
            runAdmissionEvidence: inventoryEvidence(issuedInventory)};
        },
      }, moon, publicationControl), {code: 'ClientRequestSourceInventoryMismatch'});
      assert.equal(issuers, 1);
      assert.equal(readInventoryRow(path), undefined);
    }
  });

for (const legacyEvidence of [undefined, inventoryEvidence(undefined)]) {
  test(`source inventory cannot retrofit an unstarted row with ${legacyEvidence === undefined
    ? 'absent' : 'singular'} evidence`, async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    journal.acceptDefinition(identity(), {
      namespaceId: 'namespace-a', runDefinition: runDefinition(), lookupExpiresAt: expires,
      runAdmissionEvidence: legacyEvidence,
    }, moon, publicationControl);
    const before = readInventoryRow(path);
    const sourceInventory = canonicalJson(sourceInventoryObject());
    let issuers = 0;
    await assert.rejects(journal.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory,
      issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
    }, moon, publicationControl), {code: 'ClientRequestSourceInventoryMismatch'});
    assert.equal(issuers, 0);
    assert.throws(() => acceptInventory(journal, sourceInventory),
      {code: 'ClientRequestSourceInventoryMismatch'});
    assert.deepEqual(readInventoryRow(path), before);
  });
}

test('source inventory cannot be omitted from an accepted unstarted two-source row',
  async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    acceptInventory(journal, canonicalJson(sourceInventoryObject()));
    const before = readInventoryRow(path);
    let issuers = 0;
    await assert.rejects(journal.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires,
      issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
    }, moon, publicationControl), {code: 'ClientRequestSourceInventoryMismatch'});
    assert.equal(issuers, 0);
    assert.throws(() => acceptInventory(journal, undefined),
      {code: 'ClientRequestSourceInventoryMismatch'});
    assert.deepEqual(readInventoryRow(path), before);
  });

const malformedInventories = [
  ['non-string object', value => value],
  ['invalid JSON', () => '{'],
  ['noncanonical whitespace', value => ` ${canonicalJson(value)}`],
  ['unknown version', value => { value.version = 'unknown'; return canonicalJson(value); }],
  ['extra root field', value => { value.extra = true; return canonicalJson(value); }],
  ['missing environment', value => { delete value.environmentCid; return canonicalJson(value); }],
  ['missing second source', value => { value.acquisitions.pop(); return canonicalJson(value); }],
  ['wrong stage ordinal', value => { value.acquisitions.reverse(); return canonicalJson(value); }],
  ['wrong input ordinal', value => { value.acquisitions[1].input = 1; return canonicalJson(value); }],
  ['wrong task ordinal', value => { value.acquisitions[1].task = 0; return canonicalJson(value); }],
  ['duplicate requirement', value => {
    value.acquisitions[1].checkedSource.requirementCid = cid('1'); return canonicalJson(value);
  }],
  ['invalid checked CID', value => {
    value.acquisitions[1].checkedSource.outputContractCid = 'sha256:bad'; return canonicalJson(value);
  }],
  ['extra checked field', value => {
    value.acquisitions[1].checkedSource.extra = true; return canonicalJson(value);
  }],
  ['non-read operation', value => {
    value.acquisitions[1].readTuple.operation = 'write'; return canonicalJson(value);
  }],
  ['extra binding field', value => {
    value.acquisitions[1].physicalBinding.extra = true; return canonicalJson(value);
  }],
  ['mismatched native UTF-8 name', value => {
    value.acquisitions[1].physicalBinding.utf8_hex.table = '6c656674'; return canonicalJson(value);
  }],
  ['odd native UTF-8 hex', value => {
    value.acquisitions[1].physicalBinding.utf8_hex.table = 'f'; return canonicalJson(value);
  }],
  ['invalid native UTF-8 bytes', value => {
    value.acquisitions[1].physicalBinding.table = '\ufffd';
    value.acquisitions[1].physicalBinding.utf8_hex.table = 'ff'; return canonicalJson(value);
  }],
];

for (const [label, malformed] of malformedInventories) {
  test(`source inventory refuses ${label} before issuance or acceptance`, async t => {
    const path = await directory(t);
    const journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const sourceInventory = malformed(sourceInventoryObject());
    assert.throws(() => acceptInventory(journal, sourceInventory),
      {code: 'InvalidClientSourceInventory'});
    let issuers = 0;
    await assert.rejects(journal.admitOrLookupDefinition(identity(), {
      namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory,
      issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
    }, moon, publicationControl), {code: 'InvalidClientSourceInventory'});
    assert.equal(issuers, 0);
    assert.equal(readInventoryRow(path), undefined);
  });
}

test('source inventory corruption fails every definition recovery path after restart',
  async t => {
    for (const [label, malformed] of malformedInventories) {
      await t.test(label, async t => {
        const path = await directory(t);
        let journal = openClientRequestJournal(path);
        t.after(() => journal.close());
        const original = canonicalJson(sourceInventoryObject());
        const accepted = acceptInventory(journal, original);
        journal.close();
        const database = new DatabaseSync(join(path, 'client-requests.sqlite3'));
        database.prepare('UPDATE client_requests SET run_admission_evidence_json = ?')
          .run(JSON.stringify(inventoryEvidence(malformed(sourceInventoryObject()))));
        database.close();
        journal = openClientRequestJournal(path);
        const key = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'),
          requestId: fixture.requestId};
        assert.throws(() => journal.lookupDefinition(key, moon, publicationControl),
          {code: 'ClientRequestJournalCorrupt'});
        assert.throws(() => journal.lookupRunDefinition(accepted.ref, moon, publicationControl),
          {code: 'ClientRequestJournalCorrupt'});
        assert.throws(() => journal.resolveDefinition(identity(), {namespaceId: 'namespace-a'},
          moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
        assert.throws(() => acceptInventory(journal, original),
          {code: 'ClientRequestJournalCorrupt'});
        let issuers = 0;
        await assert.rejects(journal.admitOrLookupDefinition(identity(), {
          namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: original,
          issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
        }, moon, publicationControl), {code: 'ClientRequestJournalCorrupt'});
        assert.equal(issuers, 0);
      });
    }
  });

test('source inventory for an already-started Run retains its original identity on resend',
  async t => {
    const path = await directory(t);
    let journal = openClientRequestJournal(path);
    t.after(() => journal.close());
    const sourceInventory = canonicalJson(sourceInventoryObject());
    const accepted = acceptInventory(journal, sourceInventory, 'already-started-run');
    journal.reserveDispatch(identity(), {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl);
    assert.equal(claimPhysicalStart(journal, accepted.ref), true);
    const before = readInventoryRow(path);
    journal.close();
    journal = openClientRequestJournal(path);
    const changed = sourceInventoryObject();
    for (const [, mutate] of inventoryMutations) mutate(changed);
    let issuers = 0;
    for (const proposed of [canonicalJson(changed), undefined]) {
      const retained = await journal.admitOrLookupDefinition(identity(), {
        namespaceId: 'namespace-a', lookupExpiresAt: expires, sourceInventory: proposed,
        issueDefinition: () => { issuers++; throw new Error('UnexpectedIssuer'); },
      }, moon, publicationControl);
      assert.equal(retained.inserted, false);
      assert.deepEqual(retained.ref, accepted.ref);
      assert.equal(retained.runDefinition.wire, accepted.runDefinition.wire);
      assert.equal(retained.runAdmissionEvidence.sourceInventory, sourceInventory);
      assert.equal(retained.physicalStartReserved, true);
      const duplicate = acceptInventory(journal, proposed, 'must-not-replace-started');
      assert.deepEqual(duplicate.ref, accepted.ref);
      assert.equal(duplicate.runAdmissionEvidence.sourceInventory, sourceInventory);
    }
    assert.equal(issuers, 0);
    assert.equal(journal.reserveDispatch(identity(), {namespaceId: 'namespace-a',
      currentAuthorization: true}, moon, publicationControl).kind, 'reconcile');
    assert.equal(claimPhysicalStart(journal, accepted.ref), false);
    assert.deepEqual(readInventoryRow(path), before);
  });

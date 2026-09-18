import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const runtime = runtimeCore(moon);

const request = (dispatchId, taskAttempt = 1, connectorRevision = 'local/1') =>
  Object.freeze({
    coordinatorAuthority: 'coordinator-a',
    runDefinitionCid: cid('0'),
    taskKey: 'task-a',
    taskAttempt,
    dispatchId,
    siteKey: 'site-a',
    siteGeneration: 1,
    runtimeBundleCid: cid('a'),
    connectorRegistration: 'local',
    connectorRevision,
    strategyRevision: 'strategy/1',
    inputBindingCid: cid('1'),
    obligationsCid: cid('2'),
    budgetCid: cid('3'),
    grantCid: cid('4'),
  });

function site() {
  return runtime.siteControl.create(Object.freeze({
    key: 'site-a',
    generation: 1,
    runtimeRevision: cid('a'),
    maxConcurrentOperations: 4,
    maxConcurrentTransfers: 4,
    maxRetainedBytes: 1_048_576n,
    maxExecutionBytes: 1_048_576n,
  }));
}

async function fixture(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-journal-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const store = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
    ...options,
  });
  t.after(() => store.close());
  return {root, store};
}

test('accepted dispatch is durable before MoonBit permits execution', async t => {
  const {store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const journal = control.createJournal(site());
  const prepared = control.prepare(request('dispatch-a'));
  const admission = control.prepareAdmission(journal, prepared);
  const record = store.accept(admission, prepared, control);
  assert.deepEqual(control.status(record), [0, 0, 0, 0, 0]);
  assert.deepEqual(store.inspect(prepared, control), {
    dispatch_request_cid: control.identity(prepared),
    request_json: control.requestJson(prepared),
  });
  store.advance(control.prepareProvisioning(record), record, control);
  store.advance(control.prepareExecution(record), record, control);
  assert.deepEqual(control.status(record), [2, 0, 0, 0, 0]);
  assert.equal(control.revision(record), 2);
});

test('reopen reconciles exact resend and rejects durable collisions', async t => {
  const {root, store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const firstJournal = control.createJournal(site());
  const first = control.prepare(request('dispatch-a'));
  store.accept(control.prepareAdmission(firstJournal, first), first, control);
  store.close();

  const reopened = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
  });
  t.after(() => reopened.close());
  const recoveredJournal = control.createJournal(site());
  const resend = control.prepare(request('dispatch-a'));
  const record = reopened.accept(
    control.prepareAdmission(recoveredJournal, resend),
    resend,
    control,
  );
  assert.deepEqual(control.status(record), [0, 0, 0, 0, 0]);

  const collisionJournal = control.createJournal(site());
  const collision = control.prepare(request('dispatch-a', 1, 'local/2'));
  assert.throws(() => reopened.accept(
    control.prepareAdmission(collisionJournal, collision),
    collision,
    control,
  ), {code: 'RemoteDispatchCollision'});

  const duplicateJournal = control.createJournal(site());
  const duplicate = control.prepare(request('dispatch-b'));
  assert.throws(() => reopened.accept(
    control.prepareAdmission(duplicateJournal, duplicate),
    duplicate,
    control,
  ), {code: 'RemoteAttemptAlreadyDispatched'});
});

test('failed durable admission does not consume the MoonBit attempt', async t => {
  const {store} = await fixture(t, {maxDispatches: 1});
  const control = runtime.remoteSiteControl;
  const firstJournal = control.createJournal(site());
  const first = control.prepare(request('dispatch-a'));
  store.accept(control.prepareAdmission(firstJournal, first), first, control);

  const journal = control.createJournal(site());
  const second = control.prepare(request('dispatch-c', 2));
  const admission = control.prepareAdmission(journal, second);
  assert.throws(
    () => store.accept(admission, second, control),
    {code: 'RemoteJournalCapacityExceeded'},
  );
  assert.doesNotThrow(() => control.prepareAdmission(journal, second));
});

test('durable transitions restore before later execution progress', async t => {
  const {root, store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const prepared = control.prepare(request('dispatch-a'));
  const journal = control.createJournal(site());
  const record = store.accept(
    control.prepareAdmission(journal, prepared),
    prepared,
    control,
  );
  const first = control.prepareProvisioning(record);
  const competing = control.prepareProvisioning(record);
  store.advance(first, record, control);
  assert.throws(
    () => store.advance(competing, record, control),
    {code: 'RemoteDispatchStateCollision'},
  );
  store.advance(control.prepareExecution(record), record, control);
  assert.deepEqual(store.inspectState(prepared, control), [
    2, 2, 0, 0, false, false, '', '', '',
  ]);
  store.close();

  const reopened = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
  });
  t.after(() => reopened.close());
  const recoveredJournal = control.createJournal(site());
  const recoveredRequest = control.prepare(request('dispatch-a'));
  const recovered = reopened.accept(
    control.prepareAdmission(recoveredJournal, recoveredRequest),
    recoveredRequest,
    control,
  );
  assert.deepEqual(control.status(recovered), [2, 0, 0, 0, 0]);
  assert.equal(control.revision(recovered), 2);
  reopened.advance(control.prepareSettled(recovered), recovered, control);
  assert.deepEqual(control.status(recovered), [3, 0, 0, 0, 0]);
  assert.equal(control.revision(recovered), 3);
});

test('evidence and cleanup planes persist independently', async t => {
  const {root, store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const prepared = control.prepare(request('dispatch-a'));
  const journal = control.createJournal(site());
  const record = store.accept(
    control.prepareAdmission(journal, prepared),
    prepared,
    control,
  );
  store.advance(control.prepareProvisioning(record), record, control);
  store.advance(control.prepareExecution(record), record, control);
  store.advance(control.prepareSettled(record), record, control);
  store.advance(control.prepareRetained(
    record,
    'material-generation-a',
    cid('c'),
  ), record, control);
  store.advance(control.prepareEvidence(record, cid('d')), record, control);
  store.advance(control.prepareRelease(record), record, control);
  assert.deepEqual(control.status(record), [3, 2, 1, 1, 0]);
  store.close();

  const reopened = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
  });
  t.after(() => reopened.close());
  const recoveredJournal = control.createJournal(site());
  const recoveredRequest = control.prepare(request('dispatch-a'));
  const recovered = reopened.accept(
    control.prepareAdmission(recoveredJournal, recoveredRequest),
    recoveredRequest,
    control,
  );
  assert.deepEqual(control.status(recovered), [3, 2, 1, 1, 0]);
  reopened.advance(control.prepareReleased(recovered), recovered, control);
  assert.deepEqual(control.status(recovered), [3, 2, 2, 0, 0]);
});

test('force loss durably quarantines before revoking Site authority', async t => {
  const {store} = await fixture(t);
  const control = runtime.remoteSiteControl;
  const siteControl = runtime.siteControl;
  const controlledSite = site();
  const journal = control.createJournal(controlledSite);
  const prepared = control.prepare(request('dispatch-a'));
  const record = store.accept(
    control.prepareAdmission(journal, prepared),
    prepared,
    control,
  );
  assert.throws(
    () => control.prepareForceLoss(journal, record, false),
    {code: 'MoonBitHostFailure'},
  );
  const force = control.prepareForceLoss(journal, record, true);
  store.forceLoss(force, record, control);
  assert.deepEqual(control.status(record), [6, 0, 4, 0, 1]);
  assert.equal(siteControl.revoked(controlledSite), true);
  store.advance(control.prepareLossRecovery(record), record, control);
  assert.deepEqual(control.status(record), [6, 0, 5, 0, 0]);
});

test('journal migration preserves accepted request identity', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-remote-journal-v1-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'dispatch-journal.sqlite3');
  const legacy = new DatabaseSync(path);
  const control = runtime.remoteSiteControl;
  const prepared = control.prepare(request('dispatch-a'));
  legacy.exec(`
    CREATE TABLE journal_metadata (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    ) STRICT;
    INSERT INTO journal_metadata VALUES (
      'schema_version', 'actql-remote-site-journal/0.1'
    );
    CREATE TABLE dispatches (
      coordinator_authority TEXT NOT NULL,
      site_key TEXT NOT NULL,
      site_generation INTEGER NOT NULL,
      dispatch_id TEXT NOT NULL,
      dispatch_request_cid TEXT NOT NULL,
      run_definition_cid TEXT NOT NULL,
      task_key TEXT NOT NULL,
      task_attempt INTEGER NOT NULL,
      request_json TEXT NOT NULL,
      PRIMARY KEY (
        coordinator_authority, site_key, site_generation, dispatch_id
      ),
      UNIQUE (
        coordinator_authority, run_definition_cid, task_key, task_attempt
      )
    ) STRICT;
  `);
  const key = control.journalKey(prepared);
  legacy.prepare(`
    INSERT INTO dispatches (
      coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, run_definition_cid, task_key, task_attempt,
      request_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    key[0], key[1], Number(key[2]), key[3], control.identity(prepared),
    key[4], key[5], Number(key[6]), control.requestJson(prepared),
  );
  legacy.close();
  const migrated = openSqliteDispatchJournal(root, {
    siteKey: 'site-a',
    siteGeneration: 1,
  });
  t.after(() => migrated.close());
  const journal = control.createJournal(site());
  const record = migrated.accept(
    control.prepareAdmission(journal, prepared),
    prepared,
    control,
  );
  assert.deepEqual(control.status(record), [0, 0, 0, 0, 0]);
  assert.equal(control.revision(record), 0);
});

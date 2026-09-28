import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  './sqlite-coordinator-journal.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const control = runtimeCore(moon).remoteSiteControl;
const request = (dispatchId, taskAttempt = 1) => control.prepare({
  coordinatorAuthority: 'coordinator-a',
  runDefinitionCid: cid('0'),
  taskKey: 'task-a',
  taskAttempt,
  dispatchId,
  siteKey: 'site-a',
  siteGeneration: 1,
  runtimeBundleCid: cid('a'),
  connectorRegistration: 'local',
  connectorRevision: 'local/1',
  strategyRevision: 'strategy/1',
  inputBindingCid: cid('1'),
  obligationsCid: cid('2'),
  budgetCid: cid('3'),
  evidenceIssuerCapabilityCid: cid('b'),
  grantCid: cid('4'),
});

test('Coordinator journal retries a failed physical close', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-close-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const journal = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  const originalClose = DatabaseSync.prototype.close;
  let attempts = 0;
  DatabaseSync.prototype.close = function() {
    attempts++;
    if (attempts === 1) throw new Error('injected close failure');
    return originalClose.call(this);
  };
  try {
    assert.throws(() => journal.close(), /injected close failure/u);
    assert.equal(journal.close(), true);
    assert.equal(attempts, 2);
  } finally {
    DatabaseSync.prototype.close = originalClose;
  }
  const reopened = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  assert.equal(reopened.close(), true);
});

test('Coordinator intent persists before send and restores after restart',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-journal-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const firstStore = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    const firstJournal = control.createCoordinatorJournal('coordinator-a');
    const dispatch = request('dispatch-a');
    const admission = control.prepareCoordinatorIntent(firstJournal, dispatch);
    const record = firstStore.accept(admission, dispatch, control);
    assert.equal(control.coordinatorIntentMatches(record, dispatch), true);
    assert.equal(firstStore.contains(dispatch, control), true);
    firstStore.close();

    const reopened = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => reopened.close());
    const restoredJournal = control.createCoordinatorJournal('coordinator-a');
    const recovered = reopened.recoverJournal(restoredJournal, control);
    assert.equal(recovered.length, 1);
    assert.equal(
      control.coordinatorIntentMatches(recovered[0].record, dispatch),
      true,
    );
    const retry = control.prepareCoordinatorIntent(restoredJournal, dispatch);
    assert.equal(control.coordinatorIntentIsNew(retry), false);
    reopened.accept(retry, dispatch, control);
  });

test('Coordinator journal transaction rejects a second dispatch occurrence',
  async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-race-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const left = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    const right = openSqliteCoordinatorDispatchJournal(root, {
      coordinatorAuthority: 'coordinator-a',
    });
    t.after(() => left.close());
    t.after(() => right.close());
    const leftJournal = control.createCoordinatorJournal('coordinator-a');
    const rightJournal = control.createCoordinatorJournal('coordinator-a');
    const first = request('dispatch-a');
    const second = request('dispatch-b');
    left.accept(
      control.prepareCoordinatorIntent(leftJournal, first),
      first,
      control,
    );
    assert.throws(
      () => right.accept(
        control.prepareCoordinatorIntent(rightJournal, second),
        second,
        control,
      ),
      {code: 'RemoteAttemptAlreadyDispatched'},
    );
  });

test('Coordinator journal migration preserves durable intent state', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-migration-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const dispatch = request('dispatch-migrated');
  const key = control.journalKey(dispatch);
  const legacy = new DatabaseSync(
    join(root, 'coordinator-dispatch-journal.sqlite3'),
  );
  legacy.exec(`
    CREATE TABLE journal_metadata (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    ) STRICT;
    CREATE TABLE dispatch_intents (
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
        coordinator_authority,
        site_key,
        site_generation,
        dispatch_id
      ),
      UNIQUE (
        coordinator_authority,
        run_definition_cid,
        task_key,
        task_attempt
      ),
      UNIQUE (dispatch_request_cid)
    ) STRICT;
  `);
  const metadata = legacy.prepare(
    'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
  );
  metadata.run('schema_version', 'actql-remote-coordinator-journal/0.1');
  metadata.run('coordinator_authority', 'coordinator-a');
  legacy.prepare(`
    INSERT INTO dispatch_intents (
      coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, run_definition_cid, task_key, task_attempt,
      request_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    key[0], key[1], Number(key[2]), key[3], control.identity(dispatch),
    key[4], key[5], Number(key[6]), control.requestJson(dispatch),
  );
  legacy.close();

  const store = openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  });
  t.after(() => store.close());
  const recovered = store.recoverJournal(
    control.createCoordinatorJournal('coordinator-a'),
    control,
  );
  assert.equal(recovered.length, 1);
  assert.deepEqual(store.inspectState(dispatch, control), [
    0, 0, -1, -1, -1, -1, false, false, '', '', '',
  ]);
});

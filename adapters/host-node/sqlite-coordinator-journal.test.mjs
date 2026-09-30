import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm, unlink} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
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
    assert.throws(() => journal.hasOutputOperations(),
      {code: 'CoordinatorJournalClosed'});
    assert.equal(journal.close(), true);
    assert.equal(journal.close(), false);
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

test('Coordinator journal refuses legacy records without inventing observation history', async t => {
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

  const names = await readdir(root);
  const bytes = await readFile(join(root, names[0]));
  assert.throws(() => openSqliteCoordinatorDispatchJournal(root, {
    coordinatorAuthority: 'coordinator-a',
  }), {code: 'CoordinatorJournalObservationHistoryRequired'});
  assert.deepEqual(await readdir(root), names);
  assert.deepEqual(await readFile(join(root, names[0])), bytes);
  // The old request and its custody remain available to the legacy owner.
  const retained = new DatabaseSync(join(root, names[0]), {readOnly: true});
  try {
    const row = retained.prepare('SELECT request_json FROM dispatch_intents').get();
    assert.equal(row.request_json, control.requestJson(dispatch));
  } finally { retained.close(); }
});

test('Coordinator SQLite stores admission history with state and replays after restart', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-replay-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const store = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
  const journal = control.createCoordinatorJournal('coordinator-a');
  const dispatch = request('replay');
  const record = store.accept(control.prepareCoordinatorIntent(journal, dispatch), dispatch, control);
  const observe = revision => ({revision, state: [2, 0, 0, 0, 0]});
  for (const revision of [1, 3]) {
    store.advance(control.prepareCoordinatorObservation(record, observe(revision)), record, control);
  }
  const state = store.inspectState(dispatch, control);
  const history = control.coordinatorRecordHistoryJson(record);
  assert.deepEqual(JSON.parse(history), [
    ['1', '2', '0', '0', '0', '0', '', '', ''],
    ['3', '2', '0', '0', '0', '0', '', '', ''],
  ]);
  store.close();
  const reopened = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
  t.after(() => reopened.close());
  const [{record: restored}] = reopened.recoverJournal(control.createCoordinatorJournal('coordinator-a'), control);
  assert.equal(control.coordinatorRecordHistoryJson(restored), history);
  for (const revision of [3, 1]) {
    const transition = control.prepareCoordinatorObservation(restored, observe(revision));
    assert.equal(control.coordinatorTransitionIsReplay(transition), true);
    reopened.advance(transition, restored, control);
    assert.deepEqual(reopened.inspectState(dispatch, control), state);
    assert.equal(control.coordinatorRecordRevision(restored), 2);
    assert.equal(control.coordinatorRecordHistoryJson(restored), history);
  }
  assert.throws(() => control.prepareCoordinatorObservation(restored, observe(2)));
  assert.throws(() => control.prepareCoordinatorObservation(restored,
    {revision: 1, state: [4, 0, 0, 0, 0]}));
});

test('a separate Coordinator process restores exact receipts without pending memory', async t => {
  const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-process-replay-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const store = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
  const dispatch = request('process-replay');
  const record = store.accept(control.prepareCoordinatorIntent(
    control.createCoordinatorJournal('coordinator-a'), dispatch), dispatch, control);
  for (const revision of [1, 3]) {
    store.advance(control.prepareCoordinatorObservation(record,
      {revision, state: [2, 0, 0, 0, 0]}), record, control);
  }
  const before = store.inspectState(dispatch, control);
  store.close();
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
    import assert from 'node:assert/strict';
    import * as moon from ${JSON.stringify(new URL(
      '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url).href)};
    import {runtimeCore} from ${JSON.stringify(new URL('../host-common/runtime-core.mjs', import.meta.url).href)};
    import {openSqliteCoordinatorDispatchJournal} from ${JSON.stringify(new URL('./sqlite-coordinator-journal.mjs', import.meta.url).href)};
    const control = runtimeCore(moon).remoteSiteControl;
    const store = openSqliteCoordinatorDispatchJournal(process.argv[1], {
      coordinatorAuthority: 'coordinator-a',
    });
    const recovered = store.recoverJournal(control.createCoordinatorJournal('coordinator-a'), control);
    assert.equal(recovered.length, 1);
    const [{request: dispatch, record}] = recovered;
    const expected = JSON.parse(process.argv[2]);
    assert.deepEqual(store.inspectState(dispatch, control), expected);
    const history = control.coordinatorRecordHistoryJson(record);
    assert.deepEqual(JSON.parse(history), [
      ['1', '2', '0', '0', '0', '0', '', '', ''],
      ['3', '2', '0', '0', '0', '0', '', '', ''],
    ]);
    for (const revision of [1, 3]) {
      const transition = control.prepareCoordinatorObservation(record,
        {revision, state: [2, 0, 0, 0, 0]});
      assert.equal(control.coordinatorTransitionIsReplay(transition), true);
      store.advance(transition, record, control);
      assert.deepEqual(store.inspectState(dispatch, control), expected);
      assert.equal(control.coordinatorRecordRevision(record), 2);
      assert.equal(control.coordinatorRecordHistoryJson(record), history);
    }
    assert.throws(() => control.prepareCoordinatorObservation(record,
      {revision: 2, state: [2, 0, 0, 0, 0]}));
    assert.throws(() => control.prepareCoordinatorObservation(record,
      {revision: 1, state: [4, 0, 0, 0, 0]}));
    assert.deepEqual(store.inspectState(dispatch, control), expected);
    store.close();
    console.log('separate-process-replay-verified');
  `, root, JSON.stringify(before)], {encoding: 'utf8', timeout: 15_000});
  assert.equal(result.status, 0, `${result.stderr}\n${result.stdout}`);
  assert.match(result.stdout, /separate-process-replay-verified/u);
});

for (const mismatch of ['legacy-version', 'current-version-wrong-schema',
  'missing-metadata', 'missing-output-table', 'missing-output-constraints']) {
  test(`Coordinator refuses ${mismatch} with uncheckpointed WAL and no SHM without source mutation`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-wal-refusal-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const path = join(root, 'coordinator-dispatch-journal.sqlite3');
    const store = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
    const dispatch = request('wal-custody');
    const record = store.accept(control.prepareCoordinatorIntent(control.createCoordinatorJournal('coordinator-a'), dispatch), dispatch, control);
    store.advance(control.prepareCoordinatorObservation(record, {revision: 2, state: [3, 1, 3, 1, 0]}), record, control);
    store.close();
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', `
      import {DatabaseSync} from 'node:sqlite';
      const database = new DatabaseSync(process.argv[1]);
      database.exec('PRAGMA wal_autocheckpoint = 0');
      if (process.argv[2] === 'legacy-version') {
        database.prepare('UPDATE journal_metadata SET value = ? WHERE key = ?')
          .run('actql-remote-coordinator-journal/0.1', 'schema_version');
      } else if (process.argv[2] === 'current-version-wrong-schema') {
        database.exec('ALTER TABLE dispatch_intents RENAME COLUMN observation_history_json TO unsupported_history');
      } else if (process.argv[2] === 'missing-metadata') {
        database.exec('DROP TABLE journal_metadata');
      } else if (process.argv[2] === 'missing-output-table') {
        database.exec('DROP TABLE output_operations');
      } else {
        // Keep every column name but remove types/constraints. Comparing only
        // PRAGMA table_info names would silently accept this different format.
        database.exec('ALTER TABLE output_operations RENAME TO prior_output_operations');
        database.exec('CREATE TABLE output_operations AS SELECT * FROM prior_output_operations');
        database.exec('DROP TABLE prior_output_operations');
      }
      // Leave these committed bytes in WAL, not in a cleanly closed database.
      process.exit(0);
    `, path, mismatch], {encoding: 'utf8'});
    assert.equal(result.status, 0, result.stderr);
    await unlink(`${path}-shm`);
    const snapshot = async () => Object.fromEntries(await Promise.all(
      (await readdir(root)).sort().map(async name => [name, await readFile(join(root, name))])));
    const before = await snapshot();
    assert.ok(before['coordinator-dispatch-journal.sqlite3-wal'].length > 0);
    assert.throws(() => openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'}), {
      code: mismatch === 'legacy-version' ? 'CoordinatorJournalObservationHistoryRequired' : 'UnknownCoordinatorJournalFormat',
    });
    assert.deepEqual(await snapshot(), before);
  });
}

for (const committed of [false, true]) {
  test(`Coordinator admission ${committed ? 'COMMIT response loss' : 'save failure'} never ACKs and restores only durable history`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-coordinator-save-failure-'));
    t.after(() => rm(root, {recursive: true, force: true}));
    const store = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
    const dispatch = request('save-failure');
    const record = store.accept(control.prepareCoordinatorIntent(
      control.createCoordinatorJournal('coordinator-a'), dispatch), dispatch, control);
    const observed = {revision: 3, state: [2, 0, 0, 0, 0]};
    const transition = control.prepareCoordinatorObservation(record, observed);
    const exec = DatabaseSync.prototype.exec;
    let injected = false;
    DatabaseSync.prototype.exec = function(sql) {
      if (!injected && sql === 'COMMIT') {
        injected = true;
        if (committed) exec.call(this, sql);
        throw new Error('COMMIT_RESPONSE_LOST');
      }
      return exec.call(this, sql);
    };
    try {
      assert.throws(() => store.advance(transition, record, control),
        {code: 'CoordinatorJournalCommitOutcomeUnknown'});
      assert.equal(control.coordinatorRecordRevision(record), 0);
      assert.equal(control.coordinatorRecordHistoryJson(record), '[]');
    } finally { DatabaseSync.prototype.exec = exec; }
    store.close();
    const reopened = openSqliteCoordinatorDispatchJournal(root, {coordinatorAuthority: 'coordinator-a'});
    t.after(() => reopened.close());
    const [{record: restored}] = reopened.recoverJournal(control.createCoordinatorJournal('coordinator-a'), control);
    assert.equal(control.coordinatorRecordRevision(restored), committed ? 1 : 0);
    assert.equal(control.coordinatorRecordHistoryJson(restored), committed
      ? '[["3","2","0","0","0","0","","",""]]' : '[]');
    const retry = control.prepareCoordinatorObservation(restored, observed);
    assert.equal(control.coordinatorTransitionIsReplay(retry), committed);
    reopened.advance(retry, restored, control);
    assert.equal(control.coordinatorRecordRevision(restored), 1);
    assert.equal(control.coordinatorTransitionIsReplay(
      control.prepareCoordinatorObservation(restored, observed)), true);
  });
}

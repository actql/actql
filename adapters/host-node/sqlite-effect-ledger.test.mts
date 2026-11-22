import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';

import type {SQLInputValue, StatementSync} from 'node:sqlite';
import type {TestContext} from 'node:test';

type Ledger = ReturnType<typeof openSqliteEffectLedger>;
type Options = NonNullable<Parameters<typeof openSqliteEffectLedger>[1]>;
type SqlRow = NonNullable<ReturnType<StatementSync['get']>>;
type BatchResponse = NonNullable<Parameters<Ledger['outcomeForLocator']>[1]>;
type AppendConflict = ReturnType<Ledger['append']> & Readonly<{conflict: true}>;
type TransactionFailure = Error & Readonly<{
  code: string; outcome: string; connectionUsable: boolean; cause: Error; rollbackCause: Error;
}>;
type CleanupFailure = Error & Readonly<{
  code: string; primaryFailure: {code: string}; cleanupPending: boolean;
  cleanupErrors: readonly {error: Error}[];
  cleanupHandle: {
    status(): {owners: readonly string[]};
    retry(): {pending: boolean};
  };
}>;

const cid = (digit: string) => `sha256:${digit.repeat(64)}`;
const scope = cid('a');
const locator = cid('b');
const firstJson = '{"fence":1,"state":"prepared"}';
const secondJson = '{"fence":2,"state":"dispatching"}';

async function fixture(t: TestContext) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-ledger-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

function append(ledger: Ledger, expectedRevision: number, entryCid: string, entryJson: string) {
  return ledger.append({
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: locator,
    expectedRevision,
    entryCid,
    entryJson,
  });
}

test('append-only Effect facts survive restart and exact retry', async t => {
  const root = await fixture(t);
  const first = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => first.close());
  assert.equal(append(first, 0, cid('1'), firstJson).created, true);
  assert.equal(append(first, 0, cid('1'), firstJson).created, false);
  assert.equal(append(first, 1, cid('2'), secondJson).created, true);
  first.close();
  const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => reopened.close());
  assert.equal(reopened.current(locator)!.revision, 2);
  assert.equal(reopened.current(locator)!.entryJson, secondJson);
  assert.deepEqual(reopened.currentSnapshot([locator, cid('c')]),
    [reopened.current(locator), undefined]);
  assert.throws(() => reopened.currentSnapshot([locator, locator]),
    {code: 'InvalidEffectLedgerSnapshot'});
  assert.deepEqual(reopened.history(locator, 2).map(value => value.entryJson),
    [firstJson, secondJson]);
  assert.equal(append(reopened, 1, cid('2'), secondJson).created, false);
  assert.throws(() => append(reopened, 1, cid('2'), '{}'), {
    code: 'EffectLedgerEntryCollision',
  });
});

test('Effect COMMIT uncertainty keeps the connection separate from the result',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    const exec = DatabaseSync.prototype.exec;
    let loseCommit = true;
    t.mock.method(DatabaseSync.prototype, 'exec', function(this: DatabaseSync, sql: string) {
      if (sql === 'COMMIT' && loseCommit) {
        loseCommit = false;
        throw new Error('COMMIT_RESULT_LOST');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => append(ledger, 0, cid('1'), firstJson), error => {
      assert.equal((error as TransactionFailure).code, 'EffectLedgerCommitOutcomeUnknown');
      assert.equal((error as TransactionFailure).outcome, 'unknown');
      assert.equal((error as TransactionFailure).connectionUsable, true);
      assert.match((error as TransactionFailure).cause.message, /COMMIT_RESULT_LOST/u);
      return true;
    });
    assert.equal(ledger.current(locator), undefined);
    t.mock.restoreAll();
    ledger.close();
    const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => reopened.close());
    assert.equal(reopened.current(locator), undefined);
  });

test('Effect COMMIT plus rollback loss fences further reads and writes',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    const exec = DatabaseSync.prototype.exec;
    let loseCommit = true;
    let loseRollback = true;
    t.mock.method(DatabaseSync.prototype, 'exec', function(this: DatabaseSync, sql: string) {
      if (sql === 'COMMIT' && loseCommit) {
        loseCommit = false;
        throw new Error('COMMIT_RESULT_LOST');
      }
      if (sql === 'ROLLBACK' && loseRollback) {
        loseRollback = false;
        throw new Error('ROLLBACK_FAILED');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => append(ledger, 0, cid('1'), firstJson), error => {
      assert.equal((error as TransactionFailure).code, 'EffectLedgerCommitOutcomeUnknown');
      assert.equal((error as TransactionFailure).outcome, 'unknown');
      assert.equal((error as TransactionFailure).connectionUsable, false);
      assert.match((error as TransactionFailure).cause.message, /COMMIT_RESULT_LOST/u);
      assert.match((error as TransactionFailure).rollbackCause.message, /ROLLBACK_FAILED/u);
      return true;
    });
    assert.throws(() => ledger.current(locator),
      {code: 'EffectLedgerConnectionUnusable'});
    assert.throws(() => append(ledger, 0, cid('1'), firstJson),
      {code: 'EffectLedgerConnectionUnusable'});
    t.mock.restoreAll();
    ledger.close();
    const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => reopened.close());
    assert.equal(reopened.current(locator), undefined);
  });

test('Effect close failure rejects operations and retries only close',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    const close = DatabaseSync.prototype.close;
    let failOnce = true;
    let closes = 0;
    t.mock.method(DatabaseSync.prototype, 'close', function(this: DatabaseSync) {
      closes++;
      if (failOnce) {
        failOnce = false;
        throw new Error('CLOSE_FAILED');
      }
      return close.call(this);
    });
    assert.throws(() => ledger.close(), /CLOSE_FAILED/u);
    assert.throws(() => ledger.current(locator), {code: 'EffectLedgerClosed'});
    assert.equal(ledger.close(), true);
    assert.equal(ledger.close(), false);
    assert.equal(closes, 2);
    t.mock.restoreAll();
    const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => reopened.close());
  });

for (const [name, fails] of [
  ['late statement preparation', (sql: string) =>
    sql.includes('FROM effect_ledger_heads WHERE')],
  ['usage statement preparation', (sql: string) =>
    sql.includes('(SELECT COUNT(*) FROM effect_ledger_entries)')],
] as const) {
  test(`Effect initialization owns ${name} failure`, async t => {
    const root = await fixture(t);
    const prepare = DatabaseSync.prototype.prepare;
    const close = DatabaseSync.prototype.close;
    let closes = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
      if (fails(sql)) throw new Error('PREPARE_FAILED');
      return prepare.call(this, sql);
    });
    t.mock.method(DatabaseSync.prototype, 'close', function(this: DatabaseSync) {
      closes++;
      return close.call(this);
    });
    assert.throws(() => openSqliteEffectLedger(root,
      {authorityScopeCid: scope}), /PREPARE_FAILED/u);
    assert.equal(closes, 1);
    t.mock.restoreAll();
    const reopened = openSqliteEffectLedger(root,
      {authorityScopeCid: scope});
    t.after(() => reopened.close());
  });
}

test('Effect usage read failure retains the database cleanup owner',
  async t => {
    const root = await fixture(t);
    const prepare = DatabaseSync.prototype.prepare;
    const close = DatabaseSync.prototype.close;
    let closes = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
      if (sql.includes('(SELECT COUNT(*) FROM effect_ledger_entries)')) {
        return {get() { throw new Error('USAGE_READ_FAILED'); }};
      }
      return prepare.call(this, sql);
    });
    t.mock.method(DatabaseSync.prototype, 'close', function(this: DatabaseSync) {
      closes++;
      return close.call(this);
    });
    assert.throws(() => openSqliteEffectLedger(root,
      {authorityScopeCid: scope}), /USAGE_READ_FAILED/u);
    assert.equal(closes, 1);
    t.mock.restoreAll();
    const reopened = openSqliteEffectLedger(root,
      {authorityScopeCid: scope});
    t.after(() => reopened.close());
  });

test('Effect capacity failure keeps its cause through failed close retry',
  async t => {
    const root = await fixture(t);
    const seeded = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    append(seeded, 0, cid('1'), firstJson);
    append(seeded, 1, cid('2'), secondJson);
    seeded.close();
    const close = DatabaseSync.prototype.close;
    let closes = 0;
    t.mock.method(DatabaseSync.prototype, 'close', function(this: DatabaseSync) {
      closes++;
      if (closes === 1) throw new Error('CLOSE_FAILED');
      return close.call(this);
    });
    let failure!: CleanupFailure;
    assert.throws(() => openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 1}), error => {
      failure = error as CleanupFailure;
      assert.equal((error as CleanupFailure).code, 'SqliteJournalInitializationCleanupPending');
      assert.equal((error as CleanupFailure).primaryFailure.code,
        'EffectLedgerCapacityExceeded');
      assert.match((error as CleanupFailure).cleanupErrors[0].error.message, /CLOSE_FAILED/u);
      assert.equal((error as CleanupFailure).cleanupPending, true);
      return true;
    });
    assert.deepEqual(failure.cleanupHandle.status().owners,
      ['effect_ledger']);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(failure.cleanupPending, false);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(closes, 2);
    t.mock.restoreAll();
    const reopened = openSqliteEffectLedger(root,
      {authorityScopeCid: scope});
    t.after(() => reopened.close());
    assert.equal(reopened.current(locator)!.revision, 2);
  });

test('two processes cannot advance one Effect head from one revision',
  async t => {
    const root = await fixture(t);
    const first = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    const second = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => first.close());
    t.after(() => second.close());
    append(first, 0, cid('1'), firstJson);
    assert.equal(append(first, 1, cid('2'), secondJson).created, true);
    const lost = append(second, 1, cid('3'), '{"state":"failed"}') as AppendConflict;
    assert.equal(lost.created, false);
    assert.equal(lost.conflict, true);
    assert.equal(lost.entry!.entryCid, cid('2'));
    assert.equal(second.history(locator, 2).length, 2);
    assert.throws(() => second.append({
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: cid('f'),
      expectedRevision: 0,
      entryCid: cid('2'),
      entryJson: '{"other":"item"}',
    }), {code: 'EffectLedgerEntryCollision'});
    assert.throws(() => openSqliteEffectLedger(root, {
      authorityScopeCid: cid('9'),
    }), {code: 'EffectLedgerAuthorityMismatch'});
  });

test('batch append rolls back every row after a later insert failure',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => ledger.close());
    const secondLocator = cid('c');
    const operations = [locator, secondLocator].map(logicalItemLocatorCid => ({
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid,
      expectedRevision: 0,
      expectedEntryCid: null,
      entries: [{entryCid: cid('1'), entryJson: firstJson}],
    }));
    assert.throws(() => ledger.appendBatch(operations));
    assert.equal(ledger.current(locator), undefined);
    assert.equal(ledger.current(secondLocator), undefined);
    ledger.close();
    const restarted = openSqliteEffectLedger(root,
      {authorityScopeCid: scope});
    t.after(() => restarted.close());
    assert.equal(restarted.current(locator), undefined);
    assert.equal(restarted.current(secondLocator), undefined);
  });

test('batch response is one durable observation for every claimed row',
  async t => {
    const root = await fixture(t);
    const responseBytes = Buffer.from('[{"success":true},{"success":false}]');
    const entryBytes = 2 * (Buffer.byteLength(firstJson) +
      Buffer.byteLength(secondJson));
    const limits = {authorityScopeCid: scope, maxEntries: 7,
      maxStoredBytes: entryBytes + responseBytes.byteLength};
    const ledger = openSqliteEffectLedger(root, limits);
    t.after(() => ledger.close());
    const secondLocator = cid('c');
    const operations = [
      {logicalItemLocatorCid: locator, ids: [cid('1'), cid('2')]},
      {logicalItemLocatorCid: secondLocator, ids: [cid('3'), cid('4')]},
    ].map(row => ({
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: row.logicalItemLocatorCid,
      expectedRevision: 0,
      expectedEntryCid: null,
      entries: row.ids.map((entryCid, index) => ({entryCid,
        entryJson: index === 0 ? firstJson : secondJson})),
    }));
    assert.equal(ledger.appendBatch(operations).created, true);
    const members = [
      {logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')},
      {logicalItemLocatorCid: secondLocator, dispatchEntryCid: cid('4')},
    ];
    const observation = {logicalRequestScopeCid: scope,
      credentialUseCid: cid('d'), statusCode: 200, responseBytes, members};
    assert.equal(ledger.recordBatchResponse(observation).created, true);
    assert.equal(ledger.recordBatchResponse(observation).created, false);
    assert.throws(() => ledger.recordResponse({
      logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2'), credentialUseCid: cid('d'),
      statusCode: 200, responseBytes,
    }), {code: 'EffectPhysicalResponseCollision'});
    const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    assert.equal(database.prepare(`
      SELECT SUM(LENGTH(response_bytes)) AS bytes
      FROM effect_ledger_batch_responses
    `).get()!.bytes, responseBytes.byteLength);
    assert.equal(database.prepare(`
      SELECT COUNT(*) AS count FROM effect_ledger_responses
    `).get()!.count, 0);
    database.close();
    ledger.close();
    const restarted = openSqliteEffectLedger(root, limits);
    t.after(() => restarted.close());
    assert.deepEqual(restarted.response(cid('2'))!.responseBytes,
      responseBytes);
    assert.deepEqual(restarted.response(cid('4'))!.responseBytes,
      responseBytes);
    assert.equal((restarted.response(cid('2')) as BatchResponse).batchOwnerCid, cid('2'));
    assert.equal((restarted.response(cid('4')) as BatchResponse).batchPosition, 1);
    assert.deepEqual(restarted.response(cid('2'))!.batchMembers, members);
    const tamper = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    tamper.prepare(`
      UPDATE effect_ledger_batch_members SET logical_item_locator_cid = ?
      WHERE dispatch_entry_cid = ?
    `).run(cid('e'), cid('4'));
    tamper.close();
    assert.throws(() => restarted.response(cid('2')),
      {code: 'EffectLedgerIntegrityFailed'});
  });

test('batch response capacity failure leaves no partial row observations',
  async t => {
    const root = await fixture(t);
    const responseBytes = Buffer.from('[{"success":true}]');
    const entryBytes = 2 * (Buffer.byteLength(firstJson) +
      Buffer.byteLength(secondJson));
    const ledger = openSqliteEffectLedger(root, {
      authorityScopeCid: scope, maxEntries: 7,
      maxStoredBytes: entryBytes + responseBytes.byteLength - 1,
    });
    t.after(() => ledger.close());
    const secondLocator = cid('c');
    ledger.appendBatch([locator, secondLocator].map((item, index) => ({
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: item,
      expectedRevision: 0,
      expectedEntryCid: null,
      entries: [
        {entryCid: cid(index === 0 ? '1' : '3'), entryJson: firstJson},
        {entryCid: cid(index === 0 ? '2' : '4'), entryJson: secondJson},
      ],
    })));
    assert.throws(() => ledger.recordBatchResponse({
      logicalRequestScopeCid: scope, credentialUseCid: cid('d'),
      statusCode: 200, responseBytes,
      members: [
        {logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')},
        {logicalItemLocatorCid: secondLocator, dispatchEntryCid: cid('4')},
      ],
    }), {code: 'EffectLedgerCapacityExceeded'});
    assert.equal(ledger.response(cid('2')), undefined);
    assert.equal(ledger.response(cid('4')), undefined);
  });

test('physical corruption fails closed and bounded history cannot truncate',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    append(ledger, 1, cid('2'), secondJson);
    assert.throws(() => ledger.history(locator, 1), {
      code: 'EffectLedgerHistoryLimitExceeded',
    });
    const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    database.prepare(`
      UPDATE effect_ledger_entries SET entry_json = ?
      WHERE logical_item_locator_cid = ? AND revision = 2
    `).run('{"state":"applied"}', locator);
    database.close();
    assert.throws(() => ledger.current(locator), {
      code: 'EffectLedgerIntegrityFailed',
    });
  });

test('entry capacity is reserved before append without changing the head',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {
      authorityScopeCid: scope,
      maxEntries: 1,
      maxEntryBytes: 64,
    });
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    assert.throws(() => append(ledger, 1, cid('2'), secondJson), {
      code: 'EffectLedgerCapacityExceeded',
    });
    assert.equal(ledger.current(locator)!.entryCid, cid('1'));
    assert.throws(() => append(ledger, 1, cid('2'), 'x'.repeat(65)), {
      code: 'InvalidEffectLedgerAppend',
    });
  });

test('aggregate retained bytes are bounded across independent entries',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {
      authorityScopeCid: scope,
      maxStoredBytes: Buffer.byteLength(firstJson) +
        Buffer.byteLength(secondJson) - 1,
    });
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    assert.throws(() => append(ledger, 1, cid('2'), secondJson), {
      code: 'EffectLedgerCapacityExceeded',
    });
    assert.equal(ledger.current(locator)!.entryCid, cid('1'));
    ledger.close();
    assert.throws(() => openSqliteEffectLedger(root, {
      authorityScopeCid: scope,
      maxStoredBytes: Buffer.byteLength(firstJson) - 1,
    }), {code: 'EffectLedgerCapacityExceeded'});
  });

test('bounded physical responses survive restart without becoming outcomes',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {
      authorityScopeCid: scope,
      maxResponseBytes: 32,
      maxEntries: 3,
    });
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    append(ledger, 1, cid('2'), secondJson);
    const response = {
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2'),
      credentialUseCid: cid('c'),
      statusCode: 201,
      responseBytes: Buffer.from('{"ok":true}'),
    };
    assert.equal(ledger.recordResponse(response).created, true);
    assert.equal(ledger.recordResponse(response).created, false);
    assert.deepEqual(ledger.response(cid('2'))!.responseBytes,
      response.responseBytes);
    assert.throws(() => ledger.recordResponse({
      ...response, responseBytes: Buffer.from('{"ok":false}'),
    }), {code: 'EffectPhysicalResponseCollision'});
    assert.throws(() => ledger.recordResponse({
      ...response, dispatchEntryCid: cid('9'),
    }), {code: 'EffectDispatchNotOwned'});
    assert.throws(() => ledger.recordResponse({
      ...response, responseBytes: Buffer.alloc(33),
    }), {code: 'InvalidEffectPhysicalResponse'});
    assert.throws(() => append(ledger, 2, cid('3'),
      '{"state":"applied"}'), {code: 'EffectLedgerCapacityExceeded'});
    ledger.close();
    const reopened = openSqliteEffectLedger(root, {
      authorityScopeCid: scope, maxResponseBytes: 32, maxEntries: 3,
    });
    t.after(() => reopened.close());
    assert.equal(reopened.response(cid('2'))!.statusCode, 201);
    assert.deepEqual(reopened.response(cid('2'))!.responseBytes,
      response.responseBytes);
  });

for (const batch of [false, true]) {
  test(`a ${batch ? 'batch' : 'single'} response reader bounds selected BLOBs before materialization without rejecting unrelated history`,
    async t => {
      const root = await fixture(t);
      const first = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxResponseBytes: 128});
      t.after(() => first.close());
      append(first, 0, cid('1'), firstJson);
      append(first, 1, cid('2'), secondJson);
      const large = Buffer.alloc(65, 37), small = Buffer.alloc(32, 41);
      const common = {logicalRequestScopeCid: scope, credentialUseCid: cid('d'), statusCode: 200};
      if (batch) {
        first.recordBatchResponse({...common, responseBytes: large,
          members: [{logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')}]});
      } else {
        first.recordResponse({...common, responseBytes: large,
          logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')});
      }
      first.append({logicalRequestScopeCid: scope, logicalItemLocatorCid: cid('c'),
        expectedRevision: 0, entryCid: cid('3'), entryJson: firstJson});
      first.recordResponse({...common, responseBytes: small,
        logicalItemLocatorCid: cid('c'), dispatchEntryCid: cid('3')});
      first.close();

      // Observe the real SQLite result, rather than a source-text condition.
      // An oversized BLOB must already be absent when Statement.get returns.
      const prepare = DatabaseSync.prototype.prepare, returned: unknown[] = [];
      t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, ...args: Parameters<DatabaseSync['prepare']>) {
        const statement = Reflect.apply(prepare, this, args), get = statement.get;
        t.mock.method(statement, 'get', function(this: StatementSync, ...values: SQLInputValue[]) {
          const row = Reflect.apply(get, this, values);
          if (row && Object.hasOwn(row, 'response_bytes')) returned.push(row.response_bytes);
          return row;
        });
        return statement;
      });
      const reader = openSqliteEffectLedger(root, {authorityScopeCid: scope,
        maxResponseBytes: 128, maxReadResponseBytes: 32});
      t.after(() => reader.close());
      assert.equal(reader.current(locator)!.revision, 2);
      assert.throws(() => reader.response(cid('2')), {code: 'EffectLedgerIntegrityFailed'});
      assert.strictEqual(returned.at(-1), null);
      assert.deepEqual(reader.response(cid('3'))!.responseBytes, small);
      assert.equal(reader.response(cid('9')), undefined);
      reader.append({logicalRequestScopeCid: scope, logicalItemLocatorCid: cid('e'),
        expectedRevision: 0, entryCid: cid('5'), entryJson: firstJson});
      const record = (responseBytes: Uint8Array) => batch
        ? reader.recordBatchResponse({...common, responseBytes,
          members: [{logicalItemLocatorCid: cid('e'), dispatchEntryCid: cid('5')}]})
        : reader.recordResponse({...common, responseBytes,
          logicalItemLocatorCid: cid('e'), dispatchEntryCid: cid('5')});
      // A write acknowledgement is another returned response. Reject it before
      // insertion when it cannot fit this receiver, on both physical paths.
      assert.throws(() => record(large), {code: batch
        ? 'InvalidEffectPhysicalBatchResponse' : 'InvalidEffectPhysicalResponse'});
      assert.equal(reader.response(cid('5')), undefined);
      assert.equal(record(small).created, true);
      assert.equal(record(small).created, false);
      assert.deepEqual(reader.response(cid('5'))!.responseBytes, small);
      reader.close();
      t.mock.restoreAll();
      const wide = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxResponseBytes: 128});
      t.after(() => wide.close());
      assert.deepEqual(wide.response(cid('2'))!.responseBytes, large);
      assert.deepEqual(wide.response(cid('3'))!.responseBytes, small);
    });
}

test('invalid response receiver budgets are rejected before opening a connection', async t => {
  const root = await fixture(t);
  for (const maxReadResponseBytes of [0, -1, 1.5, NaN, 129]) {
    assert.throws(() => openSqliteEffectLedger(root, {authorityScopeCid: scope,
      maxResponseBytes: 128, maxReadResponseBytes}), {code: 'InvalidEffectLedgerConfiguration'});
  }
});

test('one logical row cannot acquire a second physical response', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  append(ledger, 1, cid('2'), secondJson);
  const response = {
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('2'),
    credentialUseCid: cid('c'),
    statusCode: 201,
    responseBytes: Buffer.from('first'),
  };
  assert.equal(ledger.recordResponse(response).created, true);
  append(ledger, 2, cid('3'), '{"state":"dispatching-again"}');
  assert.throws(() => ledger.recordResponse({
    ...response, dispatchEntryCid: cid('3'),
    responseBytes: Buffer.from('second'),
  }), {code: 'EffectPhysicalResponseCollision'});
  const secondLocator = cid('d');
  ledger.append({logicalRequestScopeCid: scope,
    logicalItemLocatorCid: secondLocator, expectedRevision: 0,
    entryCid: cid('4'), entryJson: secondJson});
  assert.throws(() => ledger.recordBatchResponse({
    logicalRequestScopeCid: scope, credentialUseCid: cid('c'),
    statusCode: 200, responseBytes: Buffer.from('batch'),
    members: [
      {logicalItemLocatorCid: locator, dispatchEntryCid: cid('3')},
      {logicalItemLocatorCid: secondLocator, dispatchEntryCid: cid('4')},
    ],
  }), {code: 'EffectDispatchNotOwned'});
  assert.equal(ledger.response(cid('3')), undefined);
  assert.equal(ledger.response(cid('4')), undefined);
  assert.deepEqual(ledger.response(cid('2'))!.responseBytes,
    Buffer.from('first'));
});

test('a sealed batch row cannot be reused by a later single response',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    append(ledger, 1, cid('2'), secondJson);
    assert.equal(ledger.recordBatchResponse({
      logicalRequestScopeCid: scope, credentialUseCid: cid('c'),
      statusCode: 200, responseBytes: Buffer.from('[{"success":true}]'),
      members: [{logicalItemLocatorCid: locator,
        dispatchEntryCid: cid('2')}],
    }).created, true);
    append(ledger, 2, cid('3'), '{"state":"dispatching-again"}');
    assert.throws(() => ledger.recordResponse({
      logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('3'), credentialUseCid: cid('c'),
      statusCode: 201, responseBytes: Buffer.from('second'),
    }), {code: 'EffectPhysicalResponseCollision'});
    assert.equal(ledger.response(cid('3')), undefined);
    assert.equal((ledger.response(cid('2')) as BatchResponse).batchCount, 1);
  });

test('response metadata tampering fails physical integrity checks', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  append(ledger, 1, cid('2'), secondJson);
  ledger.recordResponse({
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('2'),
    credentialUseCid: cid('c'),
    statusCode: 201,
    responseBytes: Buffer.from('ok'),
  });
  const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  database.prepare(`
    UPDATE effect_ledger_responses SET status_code = 200
    WHERE dispatch_entry_cid = ?
  `).run(cid('2'));
  database.close();
  assert.throws(() => ledger.response(cid('2')), {
    code: 'EffectLedgerIntegrityFailed',
  });
});

test('typed outcome custody binds one stored response across restart',
  async t => {
    const root = await fixture(t);
    const ledger = openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 4});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    append(ledger, 1, cid('2'), secondJson);
    const draft = {
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2'),
      responsePhysicalSha256: '0'.repeat(64),
      outcomeCid: cid('3'),
      outcomeJson: '{"state":"applied"}',
    };
    assert.throws(() => ledger.recordOutcome(draft),
      {code: 'EffectPhysicalResponseNotOwned'});
    ledger.recordResponse({
      logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2'),
      credentialUseCid: cid('4'),
      statusCode: 201,
      responseBytes: Buffer.from('{"id":"001"}'),
    });
    const exact = {...draft, responsePhysicalSha256:
      ledger.response(cid('2'))!.responsePhysicalSha256};
    assert.throws(() => ledger.recordOutcome(draft),
      {code: 'EffectPhysicalResponseNotOwned'});
    const constrained = openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 3});
    assert.throws(() => constrained.recordOutcome(exact),
      {code: 'EffectLedgerCapacityExceeded'});
    assert.equal(constrained.outcome(cid('2')), undefined);
    constrained.close();
    assert.equal(ledger.recordOutcome(exact).created, true);
    assert.equal(ledger.recordOutcome(exact).created, false);
    assert.throws(() => ledger.recordOutcome({...exact,
      outcomeJson: '{"state":"failed"}'}),
    {code: 'EffectPhysicalOutcomeCollision'});
    ledger.close();
    const restarted = openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 4});
    t.after(() => restarted.close());
    assert.equal(restarted.outcome(cid('2'))!.outcomeJson,
      exact.outcomeJson);
    assert.equal(restarted.outcome(cid('2'))!.responsePhysicalSha256,
      exact.responsePhysicalSha256);
    assert.equal(restarted.recordOutcome(exact).created, false);
    assert.throws(() => openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 3}),
    {code: 'EffectLedgerCapacityExceeded'});
    const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    database.prepare(`
      UPDATE effect_ledger_outcomes SET outcome_json = ?
      WHERE dispatch_entry_cid = ?
    `).run('{"state":"failed"}', cid('2'));
    database.close();
    assert.throws(() => restarted.outcome(cid('2')),
      {code: 'EffectLedgerIntegrityFailed'});
  });

test('batch outcome custody keeps each row owner distinct', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root,
    {authorityScopeCid: scope, maxEntries: 9});
  t.after(() => ledger.close());
  const secondLocator = cid('c');
  const operations = [
    {logicalItemLocatorCid: locator, ids: [cid('1'), cid('2')]},
    {logicalItemLocatorCid: secondLocator, ids: [cid('3'), cid('4')]},
  ].map(row => ({
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: row.logicalItemLocatorCid,
    expectedRevision: 0,
    expectedEntryCid: null,
    entries: row.ids.map((entryCid, index) => ({entryCid,
      entryJson: index === 0 ? firstJson : secondJson})),
  }));
  ledger.appendBatch(operations);
  ledger.recordBatchResponse({
    logicalRequestScopeCid: scope,
    credentialUseCid: cid('d'),
    statusCode: 200,
    responseBytes: Buffer.from('[{"success":true},{"success":false}]'),
    members: [
      {logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')},
      {logicalItemLocatorCid: secondLocator, dispatchEntryCid: cid('4')},
    ],
  });
  const first = {
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('2'),
    responsePhysicalSha256:
      ledger.response(cid('2'))!.responsePhysicalSha256,
    outcomeCid: cid('5'),
    outcomeJson: '{"row":0}',
  };
  const second = {...first, logicalItemLocatorCid: secondLocator,
    dispatchEntryCid: cid('4'), outcomeCid: cid('6'),
    outcomeJson: '{"row":1}'};
  const batchEvidence = ledger.response(cid('2')) as BatchResponse;
  assert.equal(first.responsePhysicalSha256,
    ledger.response(cid('4'))!.responsePhysicalSha256);
  assert.throws(() => ledger.recordOutcome({...first,
    batchEvidence: {...batchEvidence}}),
  {code: 'EffectPhysicalResponseNotOwned'});
  assert.equal(ledger.recordOutcome({...first, batchEvidence}).created, true);
  assert.throws(() => ledger.recordOutcome({...second,
    logicalItemLocatorCid: locator}),
  {code: 'EffectPhysicalResponseNotOwned'});
  assert.equal(ledger.recordOutcome({...second, batchEvidence}).created, true);
  assert.equal(ledger.outcome(cid('2'))!.outcomeCid, cid('5'));
  assert.equal(ledger.outcome(cid('4'))!.outcomeCid, cid('6'));
  assert.throws(() => ledger.recordOutcome({...second, outcomeCid: cid('5')}),
    {code: 'EffectPhysicalOutcomeCollision'});
  ledger.close();
  const reopened = openSqliteEffectLedger(root,
    {authorityScopeCid: scope, maxEntries: 9});
  t.after(() => reopened.close());
  assert.equal(reopened.outcome(cid('2'))!.outcomeJson, '{"row":0}');
  assert.equal(reopened.outcome(cid('4'))!.outcomeJson, '{"row":1}');
});

test('external batch mutation invalidates a verified response fact', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  append(ledger, 1, cid('2'), secondJson);
  ledger.recordBatchResponse({
    logicalRequestScopeCid: scope, credentialUseCid: cid('c'),
    statusCode: 200, responseBytes: Buffer.from('original'),
    members: [{logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2')}],
  });
  const batchEvidence = ledger.response(cid('2')) as BatchResponse;
  const database = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  database.prepare(`
    UPDATE effect_ledger_batch_responses SET response_bytes = ?
    WHERE batch_owner_cid = ?
  `).run(Buffer.from('changed'), cid('2'));
  database.close();
  assert.throws(() => ledger.recordOutcome({
    logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('2'),
    responsePhysicalSha256: batchEvidence.responsePhysicalSha256,
    outcomeCid: cid('3'), outcomeJson: '{"row":0}', batchEvidence,
  }), {code: 'EffectLedgerIntegrityFailed'});
  const inspect = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  assert.equal(inspect.prepare('SELECT COUNT(*) AS count FROM effect_ledger_outcomes')
    .get()!.count, 0);
  inspect.close();
});

test('response bytes reserve capacity before durable insertion', async t => {
  const root = await fixture(t);
  const entryBytes = Buffer.byteLength(firstJson) +
    Buffer.byteLength(secondJson);
  const ledger = openSqliteEffectLedger(root, {
    authorityScopeCid: scope,
    maxStoredBytes: entryBytes + 2,
  });
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  append(ledger, 1, cid('2'), secondJson);
  assert.throws(() => ledger.recordResponse({
    logicalRequestScopeCid: scope,
    logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('2'),
    credentialUseCid: cid('c'),
    statusCode: 201,
    responseBytes: Buffer.from('three'),
  }), {code: 'EffectLedgerCapacityExceeded'});
  assert.equal(ledger.response(cid('2')), undefined);
  assert.equal(ledger.current(locator)!.entryCid, cid('2'));
});


test('Effect quota mutations do not reaggregate the whole durable history', async t => {
  const root = await fixture(t);
  const prepare = DatabaseSync.prototype.prepare;
  let fullHistoryReads = 0;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
    const statement = prepare.call(this, sql);
    if (!sql.includes('SUM(LENGTH(')) return statement;
    const get = statement.get;
    return new Proxy(statement, {get(target, key) {
      if (key === 'get') return (...args: SQLInputValue[]) => {
        fullHistoryReads++;
        return Reflect.apply(get, target, args);
      };
      const value = Reflect.get(target, key, target);
      return typeof value === 'function' ? value.bind(target) : value;
    }});
  });
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope});
  t.after(() => ledger.close());
  // Initialization/restoration has its own original full admission boundary.
  fullHistoryReads = 0;
  for (let index = 0; index < 40; index++) {
    append(ledger, index,
      `sha256:${(index + 100).toString(16).padStart(64, '0')}`,
      JSON.stringify({revision: index + 1}));
  }
  assert.equal(ledger.current(locator)!.revision, 40);
  assert.equal(fullHistoryReads, 0,
    'no same-connection mutation may rescan every retained entry/response');
});

test('Effect transactional usage rolls back the external-change stamp with a failed insert', async t => {
  const root = await fixture(t);
  const first = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntries: 2});
  t.after(() => first.close());
  const other = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntries: 2});
  t.after(() => other.close());
  other.append({logicalRequestScopeCid: scope, logicalItemLocatorCid: cid('c'),
    expectedRevision: 0, entryCid: cid('3'), entryJson: firstJson});
  const prepare = DatabaseSync.prototype.prepare;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
    if (sql.includes('INSERT INTO effect_ledger_entries')) {
      throw new Error('INSERT_AFTER_EXTERNAL_REFRESH_FAILED');
    }
    return prepare.call(this, sql);
  });
  assert.throws(() => append(first, 0, cid('1'), firstJson),
    /INSERT_AFTER_EXTERNAL_REFRESH_FAILED/u);
  t.mock.restoreAll();
  // No further external COMMIT: the earlier failed transaction must not make
  // this same version look admitted while retaining its old empty totals.
  assert.throws(() => first.appendBatch(['d', 'e'].map((digit, index) => ({
    logicalRequestScopeCid: scope, logicalItemLocatorCid: cid(digit),
    expectedRevision: 0, expectedEntryCid: null,
    entries: [{entryCid: cid(index === 0 ? '4' : '5'), entryJson: firstJson}],
  }))), {code: 'EffectLedgerCapacityExceeded'});
  assert.equal(first.current(locator), undefined);
  assert.equal(first.current(cid('d')), undefined);
  assert.equal(first.current(cid('e')), undefined);
  assert.equal(first.current(cid('c'))!.revision, 1);
});

test('Effect transactional usage reobserves externally changed UTF8 bytes before a new quota decision', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope,
    maxStoredBytes: Buffer.byteLength(firstJson) + 2});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  t.after(() => external.close());
  external.prepare('UPDATE effect_ledger_entries SET entry_json = ?').run('界'.repeat(100));
  assert.throws(() => ledger.append({logicalRequestScopeCid: scope,
    logicalItemLocatorCid: cid('c'), expectedRevision: 0,
    entryCid: cid('2'), entryJson: '{}'}), {code: 'EffectLedgerCapacityExceeded'});
  assert.equal(ledger.current(cid('c')), undefined);
  // Capacity projection does not bless externally corrupted physical facts.
  assert.throws(() => ledger.current(locator), {code: 'EffectLedgerIntegrityFailed'});
});

test('Effect transactional usage survives actual COMMIT reply loss and fresh reopen without a second mutation', async t => {
  const root = await fixture(t);
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntries: 1});
  t.after(() => ledger.close());
  const exec = DatabaseSync.prototype.exec;
  let commits = 0;
  t.mock.method(DatabaseSync.prototype, 'exec', function(this: DatabaseSync, sql: string) {
    const result = exec.call(this, sql);
    if (sql === 'COMMIT') {
      commits++;
      throw new Error('ACTUAL_COMMIT_REPLY_LOST');
    }
    return result;
  });
  assert.throws(() => append(ledger, 0, cid('1'), firstJson), error => {
    assert.equal((error as TransactionFailure).code, 'EffectLedgerCommitOutcomeUnknown');
    assert.equal((error as TransactionFailure).outcome, 'unknown');
    assert.equal((error as TransactionFailure).connectionUsable, true);
    return true;
  });
  assert.equal(commits, 1);
  t.mock.restoreAll();
  assert.equal(ledger.current(locator)!.entryCid, cid('1'));
  ledger.close();
  const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntries: 1});
  t.after(() => reopened.close());
  assert.equal(reopened.current(locator)!.entryCid, cid('1'));
  assert.throws(() => append(reopened, 1, cid('2'), secondJson),
    {code: 'EffectLedgerCapacityExceeded'});
  const inspector = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  t.after(() => inspector.close());
  assert.equal(inspector.prepare("SELECT COUNT(*) AS n FROM sqlite_schema WHERE name = 'effect_ledger_usage'").get()!.n, 0);
});


for (const kind of ['entry', 'single response', 'batch response', 'outcome']) {
  test(`Effect bounded SQL projection refuses oversized ${kind} before returning its column`, async t => {
    const root = await fixture(t);
    const prepare = DatabaseSync.prototype.prepare;
    let oversizedColumns = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
      const statement = prepare.call(this, sql);
      if (!sql.trimStart().startsWith('SELECT')) return statement;
      return new Proxy(statement, {get(target, key) {
        const method = Reflect.get(target, key, target);
        if (key !== 'get' && key !== 'all') {
          return typeof method === 'function' ? method.bind(target) : method;
        }
        return (...args: SQLInputValue[]) => {
          const value = Reflect.apply(method, target, args) as SqlRow | SqlRow[] | undefined;
          for (const row of (key === 'all' ? value : [value]) as (SqlRow | undefined)[]) {
            if (row === undefined) continue;
            for (const field of ['entry_json', 'outcome_json']) {
              if (typeof row[field] === 'string' && Buffer.byteLength(row[field] as string) > 64) oversizedColumns++;
            }
            if (row.response_bytes instanceof Uint8Array && row.response_bytes.byteLength > 4) oversizedColumns++;
          }
          return value;
        };
      }});
    });
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope,
      maxEntryBytes: 64, maxResponseBytes: 4});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    append(ledger, 1, cid('2'), secondJson);
    if (kind === 'single response' || kind === 'outcome') {
      ledger.recordResponse({logicalRequestScopeCid: scope,
        logicalItemLocatorCid: locator, dispatchEntryCid: cid('2'),
        credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok')});
    } else if (kind === 'batch response') {
      ledger.recordBatchResponse({logicalRequestScopeCid: scope,
        credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok'),
        members: [{logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')}]});
    }
    if (kind === 'outcome') {
      const response = ledger.response(cid('2'))!;
      ledger.recordOutcome({logicalRequestScopeCid: scope,
        logicalItemLocatorCid: locator, dispatchEntryCid: cid('2'),
        responsePhysicalSha256: response.responsePhysicalSha256,
        outcomeCid: cid('4'), outcomeJson: '{}'});
    }
    const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    try {
      if (kind === 'entry') external.prepare('UPDATE effect_ledger_entries SET entry_json = ?').run('界'.repeat(100));
      if (kind === 'single response') external.prepare('UPDATE effect_ledger_responses SET response_bytes = ?').run(Buffer.alloc(100));
      if (kind === 'batch response') external.prepare('UPDATE effect_ledger_batch_responses SET response_bytes = ?').run(Buffer.alloc(100));
      if (kind === 'outcome') external.prepare('UPDATE effect_ledger_outcomes SET outcome_json = ?').run('界'.repeat(100));
    } finally {external.close();}
    oversizedColumns = 0;
    const read = kind === 'entry' ? () => ledger.current(locator)
      : kind === 'outcome' ? () => ledger.outcome(cid('2')) : () => ledger.response(cid('2'));
    assert.throws(read, {code: 'EffectLedgerIntegrityFailed'});
    if (kind === 'entry') {
      assert.throws(() => ledger.history(locator, 2), {code: 'EffectLedgerIntegrityFailed'});
    }
    assert.equal(oversizedColumns, 0, 'oversized SQLite columns must not cross into Node before refusal');
  });
}

function observeResponseMetadataBounds(t: TestContext,
  observeRows?: (kind: 'get' | 'all', rows: SqlRow | readonly SqlRow[] | undefined) => void) {
  const prepare = DatabaseSync.prototype.prepare;
  const textUnits = {logical_item_locator_cid: 71, dispatch_entry_cid: 71,
    logical_request_scope_cid: 71, credential_use_cid: 71, entry_cid: 71,
    batch_owner_cid: 71, physical_sha256: 64, response_physical_sha256: 64, outcome_cid: 71};
  let rows = 0;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
    const statement = Reflect.apply(prepare, this, [sql]);
    if (!sql.trimStart().startsWith('SELECT')) return statement;
    return new Proxy(statement, {get(target, key) {
      const method = Reflect.get(target, key, target);
      if (key !== 'get' && key !== 'all') return typeof method === 'function' ? method.bind(target) : method;
      return (...args: SQLInputValue[]) => {
        const value = Reflect.apply(method, target, args) as SqlRow | SqlRow[] | undefined;
        observeRows?.(key, value);
        for (const row of (key === 'all' ? value : [value]) as (SqlRow | undefined)[]) {
          if (row === undefined) continue;
          rows++;
          for (const [field, units] of Object.entries(textUnits)) {
            if (typeof row[field] === 'string') assert((row[field] as string).length <= units,
              `${field} must be bounded before Statement returns`);
          }
          for (const field of ['revision', 'status_code', 'position', 'member_count']) {
            if (row[field] !== undefined && row[field] !== null) assert(Number.isSafeInteger(row[field]));
          }
          if (row.response_bytes !== undefined && row.response_bytes !== null) {
            assert(row.response_bytes instanceof Uint8Array);
            assert(row.response_bytes.byteLength <= 4);
          }
        }
        return value;
      };
    }});
  });
  return () => rows;
}

const oversizedMetadata = '界'.repeat(32768);
const unsafeSqlInteger = 9007199254740992n;
for (const [kind, table, field, malformed] of [
  ['ownership', 'effect_ledger_heads', 'logical_request_scope_cid', oversizedMetadata],
  ['ownership', 'effect_ledger_heads', 'entry_cid', oversizedMetadata],
  ['ownership', 'effect_ledger_heads', 'revision', unsafeSqlInteger],
  ['ownership', 'effect_ledger_entries', 'logical_item_locator_cid', oversizedMetadata],
  ['single', 'effect_ledger_responses', 'logical_item_locator_cid', oversizedMetadata],
  ['single', 'effect_ledger_responses', 'logical_request_scope_cid', oversizedMetadata],
  ['single', 'effect_ledger_responses', 'credential_use_cid', oversizedMetadata],
  ['single', 'effect_ledger_responses', 'physical_sha256', oversizedMetadata],
  ['single', 'effect_ledger_responses', 'status_code', unsafeSqlInteger],
  ['single', 'effect_ledger_responses', 'response_bytes', Buffer.alloc(131072)],
  ['locator', 'effect_ledger_responses', 'dispatch_entry_cid', oversizedMetadata],
  ['batch', 'effect_ledger_batch_responses', 'logical_request_scope_cid', oversizedMetadata],
  ['batch', 'effect_ledger_batch_responses', 'credential_use_cid', oversizedMetadata],
  ['batch', 'effect_ledger_batch_responses', 'physical_sha256', oversizedMetadata],
  ['batch', 'effect_ledger_batch_responses', 'status_code', unsafeSqlInteger],
  ['batch', 'effect_ledger_batch_responses', 'member_count', unsafeSqlInteger],
  ['batch', 'effect_ledger_batch_members', 'batch_owner_cid', oversizedMetadata],
  ['batch', 'effect_ledger_batch_members', 'logical_item_locator_cid', oversizedMetadata],
  ['batch', 'effect_ledger_batch_members', 'position', unsafeSqlInteger],
  ['batch locator', 'effect_ledger_batch_members', 'dispatch_entry_cid', oversizedMetadata],
] as const) {
  test(`Effect response SQL bounds ${table}.${field} and retains integrity through ${kind}`, async t => {
    const root = await fixture(t);
    const observedRows = observeResponseMetadataBounds(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxReadResponseBytes: 4});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson); append(ledger, 1, cid('2'), secondJson);
    const response = {logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('2'), credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok')};
    const batch = kind.startsWith('batch');
    if (batch) ledger.recordBatchResponse({logicalRequestScopeCid: scope,
      credentialUseCid: cid('c'), statusCode: 200, responseBytes: response.responseBytes,
      members: [{logicalItemLocatorCid: locator, dispatchEntryCid: cid('2')}]});
    else if (kind !== 'ownership') ledger.recordResponse(response);
    const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    try {
      // Preserve the original field before corruption; no oversized readback is
      // used to restore it. Foreign-key/check bypass is confined to this writer.
      external.exec('PRAGMA foreign_keys = OFF; PRAGMA ignore_check_constraints = ON');
      const original = external.prepare(`SELECT ${field} AS original FROM ${table} LIMIT 1`).get()!.original;
      const update = external.prepare(`UPDATE ${table} SET ${field} = ?`);
      update.run(malformed);
      const read = kind === 'ownership' ? () => ledger.recordResponse(response)
        : kind.includes('locator') ? () => ledger.responseForLocator(locator) : () => ledger.response(cid('2'));
      assert.throws(read, {code: 'EffectLedgerIntegrityFailed'});
      if (kind === 'single' || kind === 'locator') {
        assert.throws(() => ledger.recordResponse(response), {code: 'EffectLedgerIntegrityFailed'});
      }
      assert(observedRows() > 0, 'assertions observe actual native Statement output');
      update.run(original);
      if (kind === 'ownership') assert.equal(ledger.recordResponse(response).created, true);
      const restored = ledger.responseForLocator(locator)!;
      assert.equal(restored.dispatchEntryCid, cid('2'));
      assert.equal(restored.logicalItemLocatorCid, locator);
      assert.equal(restored.logicalRequestScopeCid, scope);
      assert.equal(restored.credentialUseCid, cid('c'));
      assert.deepEqual(restored.responseBytes, Buffer.from('ok'));
    } finally {external.close();}
  });
}

test('Effect response fixed metadata preserves exact UTF8 and UTF16 original values', async t => {
  for (const encoding of ['UTF-8', 'UTF-16le', 'UTF-16be']) {
    const root = await fixture(t), setup = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    setup.exec(`PRAGMA encoding = '${encoding}'`); setup.exec('CREATE TABLE encoding_pin (n INTEGER)'); setup.close();
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxReadResponseBytes: 4});
    try {
      append(ledger, 0, cid('1'), firstJson);
      const response = {logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
        dispatchEntryCid: cid('1'), credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok')};
      assert.equal(ledger.recordResponse(response).created, true);
      assert.equal(ledger.recordResponse(response).created, false);
      assert.equal(ledger.current(locator)!.entryCid, cid('1'));
      assert.deepEqual(ledger.responseForLocator(locator)!.responseBytes, Buffer.from('ok'));
    } finally {ledger.close();}
  }
});

for (const field of ['dispatch_entry_cid', 'logical_item_locator_cid', 'logical_request_scope_cid',
  'response_physical_sha256', 'outcome_cid', 'physical_sha256']) {
  test(`Effect selected outcome bounds ${field} before native text and retains healthy custody`, async t => {
    const root = await fixture(t), rows = observeResponseMetadataBounds(t);
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxReadResponseBytes: 4});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), firstJson);
    const observed = ledger.recordResponse({logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('1'), credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok')}).response!;
    const outcome = {logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
      dispatchEntryCid: cid('1'), responsePhysicalSha256: observed.responsePhysicalSha256,
      outcomeCid: cid('d'), outcomeJson: '{}', singleOnly: true};
    ledger.recordOutcome(outcome);
    const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    try {
      external.exec('PRAGMA foreign_keys = OFF');
      const original = external.prepare(`SELECT ${field} AS original FROM effect_ledger_outcomes`).get()!.original;
      const update = external.prepare(`UPDATE effect_ledger_outcomes SET ${field} = ?`);
      update.run(oversizedMetadata);
      if (field !== 'logical_item_locator_cid') {
        assert.throws(() => ledger.outcomeForLocator(locator, undefined, true), {code: 'EffectLedgerIntegrityFailed'});
      }
      if (field !== 'dispatch_entry_cid') {
        assert.throws(() => ledger.outcome(cid('1'), true), {code: 'EffectLedgerIntegrityFailed'});
        assert.throws(() => ledger.recordOutcome(outcome), {code: 'EffectLedgerIntegrityFailed'});
      }
      assert(rows() > 0);
      update.run(original);
      assert.equal(ledger.outcomeForLocator(locator, undefined, true)!.outcomeCid, cid('d'));
      assert.equal(ledger.outcome(cid('1'), true)!.outcomeJson, '{}');
      assert.equal(ledger.recordOutcome(outcome).created, false);
    } finally {external.close();}
  });
}

test('Effect selected single response and outcome refuse batch presence before any member array materializes', async t => {
  const root = await fixture(t);
  let memberRows = 0;
  observeResponseMetadataBounds(t, (kind, rows) => {
    if (kind === 'all') memberRows += (rows as readonly SqlRow[]).filter(row => Object.hasOwn(row, 'position')).length;
  });
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxReadResponseBytes: 4});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson);
  ledger.append({logicalRequestScopeCid: scope, logicalItemLocatorCid: cid('e'),
    expectedRevision: 0, entryCid: cid('2'), entryJson: firstJson});
  const members = [{logicalItemLocatorCid: locator, dispatchEntryCid: cid('1')},
    {logicalItemLocatorCid: cid('e'), dispatchEntryCid: cid('2')}];
  ledger.recordBatchResponse({logicalRequestScopeCid: scope,
    credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok'), members});
  const batch = ledger.response(cid('1')) as BatchResponse;
  const facts = {logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('1'), responsePhysicalSha256: batch.responsePhysicalSha256,
    outcomeCid: cid('d'), outcomeJson: '{}'};
  ledger.recordOutcome({...facts, batchEvidence: batch});
  memberRows = 0;
  for (const read of [() => ledger.response(cid('1'), true), () => ledger.responseForLocator(locator, true),
    () => ledger.outcome(cid('1'), true), () => ledger.outcomeForLocator(locator, undefined, true),
    () => ledger.outcomeForLocator(locator, batch, true), () => ledger.recordOutcome({...facts, singleOnly: true}),
    () => ledger.recordOutcome({...facts, batchEvidence: batch, singleOnly: true})]) {
    assert.throws(read, {code: 'EffectResponseKindMismatch'});
    assert.equal(memberRows, 0);
  }
  assert.equal(ledger.response(cid('3'), true), undefined);
  assert.equal(ledger.responseForLocator(cid('3'), true), undefined);
  const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  try {
    external.prepare('UPDATE effect_ledger_batch_members SET position = ? WHERE position = 0').run(unsafeSqlInteger);
    assert.throws(() => ledger.response(cid('1'), true), {code: 'EffectLedgerIntegrityFailed'});
    assert.equal(memberRows, 0);
    external.prepare('UPDATE effect_ledger_batch_members SET position = 0 WHERE position = ?').run(unsafeSqlInteger);
  } finally {external.close();}
  assert.equal((ledger.response(cid('1')) as BatchResponse).batchMembers.length, 2);
  assert(memberRows >= 2, 'the same observer sees generic batch materialization');
  assert.equal(ledger.outcome(cid('1'))!.outcomeCid, cid('d'));
  // Copy an independently valid single physical row into this batch Store to
  // create an actual cross-table collision, without synthesizing its digest.
  const singleRoot = await fixture(t), single = openSqliteEffectLedger(singleRoot, {authorityScopeCid: scope});
  append(single, 0, cid('1'), firstJson);
  single.recordResponse({logicalRequestScopeCid: scope, logicalItemLocatorCid: locator,
    dispatchEntryCid: cid('1'), credentialUseCid: cid('c'), statusCode: 200, responseBytes: Buffer.from('ok')});
  single.close();
  const collision = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  try {
    collision.prepare('ATTACH DATABASE ? AS original_single').run(join(singleRoot, 'effect-ledger.sqlite3'));
    collision.exec('INSERT INTO effect_ledger_responses SELECT * FROM original_single.effect_ledger_responses');
    memberRows = 0;
    for (const flag of [true, false]) {
      assert.throws(() => ledger.response(cid('1'), flag), {code: 'EffectLedgerIntegrityFailed'});
      assert.equal(memberRows, 0, 'collision refusal precedes batch member allocation');
    }
  } finally {collision.close();}
  // Exercise the JavaScript boundary with deliberately malformed flags.
  for (const flag of [null, 0, 'true', {}] as unknown as readonly boolean[]) {
    assert.throws(() => ledger.response(cid('1'), flag), {code: 'InvalidEffectDispatchEntry'});
    assert.throws(() => ledger.responseForLocator(locator, flag), {code: 'InvalidEffectItemLocator'});
    assert.throws(() => ledger.outcome(cid('1'), flag), {code: 'InvalidEffectDispatchEntry'});
    assert.throws(() => ledger.outcomeForLocator(locator, undefined, flag), {code: 'InvalidEffectItemLocator'});
    assert.throws(() => ledger.recordOutcome({...facts, singleOnly: flag}), {code: 'InvalidEffectPhysicalOutcome'});
  }
});

test('Effect whole history funds actual count and wire backing before native materialization in the same transaction', async t => {
  for (const encoding of ['UTF-8', 'UTF-16le', 'UTF-16be']) {
    const root = await fixture(t), setup = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    setup.exec(`PRAGMA encoding = '${encoding}'`); setup.exec('CREATE TABLE encoding_pin (n INTEGER)'); setup.close();
    const prepare = DatabaseSync.prototype.prepare;
    let originalDatabase!: DatabaseSync, materialized = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
      originalDatabase ??= this;
      const statement = Reflect.apply(prepare, this, [sql]);
      const all = statement.all;
      t.mock.method(statement, 'all', function(this: StatementSync, ...args: SQLInputValue[]) {
        materialized++; return Reflect.apply(all, this, args);
      });
      return statement;
    });
    const first = JSON.stringify({value: 'é😀'}), second = JSON.stringify({value: '界'}), observations: [number, number][] = [];
    const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    external.exec('PRAGMA busy_timeout = 0');
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope,
      beforeHistoryRead(entries, wireUnits) {
        assert.equal(originalDatabase.isTransaction, true);
        assert.equal(materialized, 0, 'funding precedes the actual Statement.all');
        observations.push([entries, wireUnits]);
        assert.throws(() => external.prepare('UPDATE effect_ledger_entries SET entry_json = entry_json').run(),
          'another connection cannot mutate the observed geometry before materialization');
      }});
    try {
      append(ledger, 0, cid('1'), first); append(ledger, 1, cid('2'), second);
      assert.deepEqual(ledger.history(locator, 2).map(row => row.entryJson), [first, second]);
      const units = encoding === 'UTF-8' ? Buffer.byteLength(first) + Buffer.byteLength(second) : first.length + second.length;
      assert.deepEqual(observations, [[2, units]]);
      assert.equal(materialized, 1);
      assert.equal(originalDatabase.isTransaction, false);
      assert.doesNotThrow(() => external.prepare('UPDATE effect_ledger_entries SET entry_json = entry_json').run());
    } finally {ledger.close(); external.close(); t.mock.restoreAll();}
  }
});

test('Effect whole history preserves funding refusal and non-Unit failure before allocation and permits healthy recovery', async t => {
  for (const refusal of [new Error('original funding refused'), null, false, Promise.resolve()]) {
    const root = await fixture(t), prepare = DatabaseSync.prototype.prepare;
    let materialized = 0, attempts = 0, recover = false;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
      const statement = Reflect.apply(prepare, this, [sql]), all = statement.all;
      t.mock.method(statement, 'all', function(this: StatementSync, ...args: SQLInputValue[]) {materialized++; return Reflect.apply(all, this, args);});
      return statement;
    });
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, beforeHistoryRead() {
      attempts++;
      if (recover) return;
      if (refusal instanceof Error) throw refusal;
      // The production hook must refuse all non-Unit fixture returns.
      return refusal as unknown as ReturnType<NonNullable<Options['beforeHistoryRead']>>;
    }});
    try {
      append(ledger, 0, cid('1'), firstJson); append(ledger, 1, cid('2'), secondJson);
      assert.throws(() => ledger.history(locator, 2), refusal instanceof Error
        ? cause => cause === refusal : {code: 'InvalidEffectLedgerHistory'});
      assert.equal(materialized, 0); assert.equal(attempts, 1);
      assert.equal(ledger.current(locator)!.entryCid, cid('2'));
      recover = true;
      assert.deepEqual(ledger.history(locator, 2).map(row => row.entryJson), [firstJson, secondJson]);
      assert.equal(materialized, 1); assert.equal(attempts, 2);
    } finally {ledger.close(); t.mock.restoreAll();}
  }
});

test('Effect whole history rejects invalid geometry before funding and never truncates or confuses a missing head', async t => {
  const root = await fixture(t), prepare = DatabaseSync.prototype.prepare;
  let materialized = 0, funded = 0;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(this: DatabaseSync, sql: string) {
    const statement = Reflect.apply(prepare, this, [sql]), all = statement.all;
    t.mock.method(statement, 'all', function(this: StatementSync, ...args: SQLInputValue[]) {materialized++; return Reflect.apply(all, this, args);});
    return statement;
  });
  const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntryBytes: 64,
    beforeHistoryRead() {funded++;}});
  t.after(() => ledger.close());
  append(ledger, 0, cid('1'), firstJson); append(ledger, 1, cid('2'), secondJson);
  assert.deepEqual(ledger.history(cid('c'), 2), []);
  assert.throws(() => ledger.history(locator, 1), {code: 'EffectLedgerHistoryLimitExceeded'});
  assert.equal(funded, 0); assert.equal(materialized, 0);
  const external = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  try {
    external.prepare('UPDATE effect_ledger_entries SET entry_json = ? WHERE revision = 2').run('界'.repeat(100));
    assert.throws(() => ledger.history(locator, 2), {code: 'EffectLedgerIntegrityFailed'});
    assert.equal(funded, 0); assert.equal(materialized, 0);
    external.prepare('UPDATE effect_ledger_entries SET entry_json = ? WHERE revision = 2').run(secondJson);
    external.prepare('DELETE FROM effect_ledger_entries WHERE revision = 1').run();
    assert.throws(() => ledger.history(locator, 2), {code: 'EffectLedgerIntegrityFailed'});
    assert.equal(funded, 0); assert.equal(materialized, 0);
  } finally {external.close();}
});

for (const encoding of ['UTF-16le', 'UTF-16be']) {
  test(`Effect original SQLite text encoding ${encoding} retains exact valid text and native-byte quota`, async t => {
    const root = await fixture(t);
    const setup = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
    try {
      setup.exec(`PRAGMA encoding = '${encoding}'`);
      setup.exec('CREATE TABLE encoding_fixture (value TEXT) STRICT');
    } finally {setup.close();}
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope,
      maxEntryBytes: 64, maxStoredBytes: 191});
    t.after(() => ledger.close());
    const exact = '"' + 'x'.repeat(62) + '"';
    append(ledger, 0, cid('1'), exact);
    assert.equal(ledger.current(locator)!.entryJson, exact);
    // The original SUM sees128 native bytes, and the original next-write
    // preflight adds64 encoded input bytes:192 does not fit191.
    assert.throws(() => append(ledger, 1, cid('2'), exact),
      {code: 'EffectLedgerCapacityExceeded'});
    assert.equal(ledger.current(locator)!.revision, 1);
    assert.equal(ledger.history(locator, 1)[0].entryJson, exact);
  });
}

for (const responseBytes of [Buffer.alloc(0), Buffer.from('ééé')]) {
  test(`Effect bounded exact UTF8 text and ${responseBytes.length}-byte body retain the full original physical facts`, async t => {
    const root = await fixture(t);
    const exactText = JSON.stringify('界'.repeat(20));
    const ledger = openSqliteEffectLedger(root, {authorityScopeCid: scope,
      maxEntryBytes: Buffer.byteLength(exactText), maxResponseBytes: 6});
    t.after(() => ledger.close());
    append(ledger, 0, cid('1'), exactText);
    assert.equal(ledger.current(locator)!.entryJson, exactText);
    assert.equal(ledger.history(locator, 1)[0].entryJson, exactText);
    assert.throws(() => append(ledger, 1, cid('2'), exactText + ' '),
      {code: 'InvalidEffectLedgerAppend'});
    const response = ledger.recordResponse({logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator, dispatchEntryCid: cid('1'),
      credentialUseCid: cid('c'), statusCode: 200, responseBytes}).response!;
    assert.deepEqual(response.responseBytes, responseBytes);
    ledger.recordOutcome({logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator, dispatchEntryCid: cid('1'),
      responsePhysicalSha256: response.responsePhysicalSha256,
      outcomeCid: cid('3'), outcomeJson: exactText});
    assert.equal(ledger.outcome(cid('1'))!.outcomeJson, exactText);
    assert.deepEqual(ledger.response(cid('1'))!.responseBytes, responseBytes);
  });
}

async function metadataFixture(t: TestContext, encoding: string, field?: string) {
  const root=await fixture(t),database=new DatabaseSync(join(root,'effect-ledger.sqlite3'));
  database.exec(`PRAGMA encoding = '${encoding}'`);
  database.exec('CREATE TABLE effect_ledger_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL) STRICT');
  const insert=database.prepare('INSERT INTO effect_ledger_metadata (key,value) VALUES (?,?)');
  insert.run('schema_version',field==='schema_version'?'x'.repeat(262144):'actql-effect-ledger-store/0.1');
  insert.run('authority_scope_cid',field==='authority_scope_cid'?'x'.repeat(262144):scope);
  database.close();return root;
}

test('Effect open metadata accepts original UTF8 and UTF16 exact schema and authority', async t=>{
  for(const encoding of ['UTF-8','UTF-16le','UTF-16be']){
    const root=await metadataFixture(t,encoding);
    const ledger=openSqliteEffectLedger(root,{authorityScopeCid:scope});
    assert.equal(ledger.current(locator),undefined);ledger.close();
  }
});

for(const field of ['schema_version','authority_scope_cid'])test(`Effect open bounds oversized ${field} before returning native text and keeps authority refusal`,async t=>{
  const root=await metadataFixture(t,'UTF-16le',field),prepare=DatabaseSync.prototype.prepare;
  let observed=0;
  t.mock.method(DatabaseSync.prototype,'prepare',function(this: DatabaseSync, sql: string, ...args: unknown[]){
    const statement=Reflect.apply(prepare,this,[sql,...args]);
    if(sql.includes('FROM effect_ledger_metadata WHERE key')){
      const get=statement.get;
      t.mock.method(statement,'get',function(this: StatementSync, key: SQLInputValue, ...rest: SQLInputValue[]){
        const result=Reflect.apply(get,this,[key,...rest]) as SqlRow;
        if(key===field){observed++;assert.equal(result.value,null);assert.deepEqual(Object.keys(result),['value']);}
        return result;
      });
    }
    return statement;
  });
  assert.throws(()=>openSqliteEffectLedger(root,{authorityScopeCid:scope}),{code:'EffectLedgerAuthorityMismatch'});
  assert.equal(observed,1);
  // The failed constructor's actual native close has returned: an independent
  // same-fixture connection can inspect counts without any business replay.
  const read=new DatabaseSync(join(root,'effect-ledger.sqlite3'));
  assert.equal(read.prepare('SELECT COUNT(*) AS n FROM effect_ledger_metadata').get()!.n,2);
  read.close();
});

for(const [table,field] of [['effect_ledger_heads','logical_request_scope_cid'],['effect_ledger_heads','entry_cid'],['effect_ledger_entries','entry_cid'],['effect_ledger_entries','physical_sha256']])test(`standard Ledger snapshot bounds ${table}.${field} before native text and retains integrity failure`,async t=>{
  const root=await fixture(t);
  const initialized=openSqliteEffectLedger(root,{authorityScopeCid:scope});
  append(initialized,0,cid('1'),firstJson);initialized.close();
  const raw=new DatabaseSync(join(root,'effect-ledger.sqlite3'));
  raw.prepare(`UPDATE ${table} SET ${field} = ?`).run('x'.repeat(262144));raw.close();
  const prepare=DatabaseSync.prototype.prepare;let observed=0;
  t.mock.method(DatabaseSync.prototype,'prepare',function(this: DatabaseSync, sql: string, ...args: unknown[]){
    const statement=Reflect.apply(prepare,this,[sql,...args]);
    if(new RegExp(`FROM\\s+${table}\\s+WHERE`,'u').test(sql)&&sql.includes('CASE WHEN')){
      const get=statement.get;
      t.mock.method(statement,'get',function(this: StatementSync, ...values: SQLInputValue[]){const result=Reflect.apply(get,this,values) as SqlRow;observed++;assert.equal(result[field],null);return result;});
    }
    return statement;
  });
  const ledger=openSqliteEffectLedger(root,{authorityScopeCid:scope});
  assert.throws(()=>ledger.currentSnapshot([locator]),{code:'EffectLedgerIntegrityFailed'});
  assert.equal(observed,1);ledger.close();
});

test('standard Ledger snapshot retains exact selected UTF8 and UTF16 heads and missing-head distinction',async t=>{
  for(const encoding of ['UTF-8','UTF-16le','UTF-16be']){
    const root=await fixture(t),setup=new DatabaseSync(join(root,'effect-ledger.sqlite3'));
    setup.exec(`PRAGMA encoding = '${encoding}'`);setup.exec('CREATE TABLE encoding_pin (n INTEGER)');setup.close();
    const ledger=openSqliteEffectLedger(root,{authorityScopeCid:scope});
    append(ledger,0,cid('1'),firstJson);
    assert.deepEqual(ledger.currentSnapshot([locator,cid('c')]),[
      {logicalRequestScopeCid:scope,logicalItemLocatorCid:locator,revision:1,entryCid:cid('1'),entryJson:firstJson},undefined]);
    assert.throws(()=>ledger.currentSnapshot([locator,locator]),{code:'InvalidEffectLedgerSnapshot'});
    ledger.close();
  }
});

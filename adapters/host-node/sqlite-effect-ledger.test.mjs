import assert from 'node:assert/strict';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {openSqliteEffectLedger} from './sqlite-effect-ledger.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const scope = cid('a');
const locator = cid('b');
const firstJson = '{"fence":1,"state":"prepared"}';
const secondJson = '{"fence":2,"state":"dispatching"}';

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-ledger-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  return root;
}

function append(ledger, expectedRevision, entryCid, entryJson) {
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
  assert.equal(reopened.current(locator).revision, 2);
  assert.equal(reopened.current(locator).entryJson, secondJson);
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
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
      if (sql === 'COMMIT' && loseCommit) {
        loseCommit = false;
        throw new Error('COMMIT_RESULT_LOST');
      }
      return exec.call(this, sql);
    });
    assert.throws(() => append(ledger, 0, cid('1'), firstJson), error => {
      assert.equal(error.code, 'EffectLedgerCommitOutcomeUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.connectionUsable, true);
      assert.match(error.cause.message, /COMMIT_RESULT_LOST/u);
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
    t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
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
      assert.equal(error.code, 'EffectLedgerCommitOutcomeUnknown');
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.connectionUsable, false);
      assert.match(error.cause.message, /COMMIT_RESULT_LOST/u);
      assert.match(error.rollbackCause.message, /ROLLBACK_FAILED/u);
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
    t.mock.method(DatabaseSync.prototype, 'close', function() {
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
  ['late statement preparation', sql =>
    sql.includes('FROM effect_ledger_heads WHERE')],
  ['usage statement preparation', sql =>
    sql.includes('(SELECT COUNT(*) FROM effect_ledger_entries)')],
]) {
  test(`Effect initialization owns ${name} failure`, async t => {
    const root = await fixture(t);
    const prepare = DatabaseSync.prototype.prepare;
    const close = DatabaseSync.prototype.close;
    let closes = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
      if (fails(sql)) throw new Error('PREPARE_FAILED');
      return prepare.call(this, sql);
    });
    t.mock.method(DatabaseSync.prototype, 'close', function() {
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
    t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
      if (sql.includes('(SELECT COUNT(*) FROM effect_ledger_entries)')) {
        return {get() { throw new Error('USAGE_READ_FAILED'); }};
      }
      return prepare.call(this, sql);
    });
    t.mock.method(DatabaseSync.prototype, 'close', function() {
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
    t.mock.method(DatabaseSync.prototype, 'close', function() {
      closes++;
      if (closes === 1) throw new Error('CLOSE_FAILED');
      return close.call(this);
    });
    let failure;
    assert.throws(() => openSqliteEffectLedger(root,
      {authorityScopeCid: scope, maxEntries: 1}), error => {
      failure = error;
      assert.equal(error.code, 'SqliteJournalInitializationCleanupPending');
      assert.equal(error.primaryFailure.code,
        'EffectLedgerCapacityExceeded');
      assert.match(error.cleanupErrors[0].error.message, /CLOSE_FAILED/u);
      assert.equal(error.cleanupPending, true);
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
    assert.equal(reopened.current(locator).revision, 2);
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
    const lost = append(second, 1, cid('3'), '{"state":"failed"}');
    assert.equal(lost.created, false);
    assert.equal(lost.conflict, true);
    assert.equal(lost.entry.entryCid, cid('2'));
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
    `).get().bytes, responseBytes.byteLength);
    assert.equal(database.prepare(`
      SELECT COUNT(*) AS count FROM effect_ledger_responses
    `).get().count, 0);
    database.close();
    ledger.close();
    const restarted = openSqliteEffectLedger(root, limits);
    t.after(() => restarted.close());
    assert.deepEqual(restarted.response(cid('2')).responseBytes,
      responseBytes);
    assert.deepEqual(restarted.response(cid('4')).responseBytes,
      responseBytes);
    assert.equal(restarted.response(cid('2')).batchOwnerCid, cid('2'));
    assert.equal(restarted.response(cid('4')).batchPosition, 1);
    assert.deepEqual(restarted.response(cid('2')).batchMembers, members);
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
    assert.equal(ledger.current(locator).entryCid, cid('1'));
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
    assert.equal(ledger.current(locator).entryCid, cid('1'));
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
    assert.deepEqual(ledger.response(cid('2')).responseBytes,
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
    assert.equal(reopened.response(cid('2')).statusCode, 201);
    assert.deepEqual(reopened.response(cid('2')).responseBytes,
      response.responseBytes);
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
  assert.deepEqual(ledger.response(cid('2')).responseBytes,
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
    assert.equal(ledger.response(cid('2')).batchCount, 1);
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
      ledger.response(cid('2')).responsePhysicalSha256};
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
    assert.equal(restarted.outcome(cid('2')).outcomeJson,
      exact.outcomeJson);
    assert.equal(restarted.outcome(cid('2')).responsePhysicalSha256,
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
      ledger.response(cid('2')).responsePhysicalSha256,
    outcomeCid: cid('5'),
    outcomeJson: '{"row":0}',
  };
  const second = {...first, logicalItemLocatorCid: secondLocator,
    dispatchEntryCid: cid('4'), outcomeCid: cid('6'),
    outcomeJson: '{"row":1}'};
  const batchEvidence = ledger.response(cid('2'));
  assert.equal(first.responsePhysicalSha256,
    ledger.response(cid('4')).responsePhysicalSha256);
  assert.throws(() => ledger.recordOutcome({...first,
    batchEvidence: {...batchEvidence}}),
  {code: 'EffectPhysicalResponseNotOwned'});
  assert.equal(ledger.recordOutcome({...first, batchEvidence}).created, true);
  assert.throws(() => ledger.recordOutcome({...second,
    logicalItemLocatorCid: locator}),
  {code: 'EffectPhysicalResponseNotOwned'});
  assert.equal(ledger.recordOutcome({...second, batchEvidence}).created, true);
  assert.equal(ledger.outcome(cid('2')).outcomeCid, cid('5'));
  assert.equal(ledger.outcome(cid('4')).outcomeCid, cid('6'));
  assert.throws(() => ledger.recordOutcome({...second, outcomeCid: cid('5')}),
    {code: 'EffectPhysicalOutcomeCollision'});
  ledger.close();
  const reopened = openSqliteEffectLedger(root,
    {authorityScopeCid: scope, maxEntries: 9});
  t.after(() => reopened.close());
  assert.equal(reopened.outcome(cid('2')).outcomeJson, '{"row":0}');
  assert.equal(reopened.outcome(cid('4')).outcomeJson, '{"row":1}');
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
  const batchEvidence = ledger.response(cid('2'));
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
    .get().count, 0);
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
  assert.equal(ledger.current(locator).entryCid, cid('2'));
});


test('Effect quota mutations do not reaggregate the whole durable history', async t => {
  const root = await fixture(t);
  const prepare = DatabaseSync.prototype.prepare;
  let fullHistoryReads = 0;
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
    const statement = prepare.call(this, sql);
    if (!sql.includes('SUM(LENGTH(')) return statement;
    const get = statement.get;
    return new Proxy(statement, {get(target, key) {
      if (key === 'get') return (...args) => {
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
  assert.equal(ledger.current(locator).revision, 40);
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
  t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
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
  assert.equal(first.current(cid('c')).revision, 1);
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
  t.mock.method(DatabaseSync.prototype, 'exec', function(sql) {
    const result = exec.call(this, sql);
    if (sql === 'COMMIT') {
      commits++;
      throw new Error('ACTUAL_COMMIT_REPLY_LOST');
    }
    return result;
  });
  assert.throws(() => append(ledger, 0, cid('1'), firstJson), error => {
    assert.equal(error.code, 'EffectLedgerCommitOutcomeUnknown');
    assert.equal(error.outcome, 'unknown');
    assert.equal(error.connectionUsable, true);
    return true;
  });
  assert.equal(commits, 1);
  t.mock.restoreAll();
  assert.equal(ledger.current(locator).entryCid, cid('1'));
  ledger.close();
  const reopened = openSqliteEffectLedger(root, {authorityScopeCid: scope, maxEntries: 1});
  t.after(() => reopened.close());
  assert.equal(reopened.current(locator).entryCid, cid('1'));
  assert.throws(() => append(reopened, 1, cid('2'), secondJson),
    {code: 'EffectLedgerCapacityExceeded'});
  const inspector = new DatabaseSync(join(root, 'effect-ledger.sqlite3'));
  t.after(() => inspector.close());
  assert.equal(inspector.prepare("SELECT COUNT(*) AS n FROM sqlite_schema WHERE name = 'effect_ledger_usage'").get().n, 0);
});


for (const kind of ['entry', 'single response', 'batch response', 'outcome']) {
  test(`Effect bounded SQL projection refuses oversized ${kind} before returning its column`, async t => {
    const root = await fixture(t);
    const prepare = DatabaseSync.prototype.prepare;
    let oversizedColumns = 0;
    t.mock.method(DatabaseSync.prototype, 'prepare', function(sql) {
      const statement = prepare.call(this, sql);
      if (!sql.trimStart().startsWith('SELECT')) return statement;
      return new Proxy(statement, {get(target, key) {
        const method = Reflect.get(target, key, target);
        if (key !== 'get' && key !== 'all') {
          return typeof method === 'function' ? method.bind(target) : method;
        }
        return (...args) => {
          const value = Reflect.apply(method, target, args);
          for (const row of key === 'all' ? value : [value]) {
            if (row === undefined) continue;
            for (const field of ['entry_json', 'outcome_json']) {
              if (typeof row[field] === 'string' && Buffer.byteLength(row[field]) > 64) oversizedColumns++;
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
      const response = ledger.response(cid('2'));
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
    assert.equal(ledger.current(locator).entryJson, exact);
    // The original SUM sees128 native bytes, and the original next-write
    // preflight adds64 encoded input bytes:192 does not fit191.
    assert.throws(() => append(ledger, 1, cid('2'), exact),
      {code: 'EffectLedgerCapacityExceeded'});
    assert.equal(ledger.current(locator).revision, 1);
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
    assert.equal(ledger.current(locator).entryJson, exactText);
    assert.equal(ledger.history(locator, 1)[0].entryJson, exactText);
    assert.throws(() => append(ledger, 1, cid('2'), exactText + ' '),
      {code: 'InvalidEffectLedgerAppend'});
    const response = ledger.recordResponse({logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator, dispatchEntryCid: cid('1'),
      credentialUseCid: cid('c'), statusCode: 200, responseBytes}).response;
    assert.deepEqual(response.responseBytes, responseBytes);
    ledger.recordOutcome({logicalRequestScopeCid: scope,
      logicalItemLocatorCid: locator, dispatchEntryCid: cid('1'),
      responsePhysicalSha256: response.responsePhysicalSha256,
      outcomeCid: cid('3'), outcomeJson: exactText});
    assert.equal(ledger.outcome(cid('1')).outcomeJson, exactText);
    assert.deepEqual(ledger.response(cid('1')).responseBytes, responseBytes);
  });
}

async function metadataFixture(t, encoding, field) {
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
  t.mock.method(DatabaseSync.prototype,'prepare',function(sql,...args){
    const statement=Reflect.apply(prepare,this,[sql,...args]);
    if(sql.includes('FROM effect_ledger_metadata WHERE key')){
      const get=statement.get;
      t.mock.method(statement,'get',function(key,...rest){
        const result=Reflect.apply(get,this,[key,...rest]);
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
  assert.equal(read.prepare('SELECT COUNT(*) AS n FROM effect_ledger_metadata').get().n,2);
  read.close();
});

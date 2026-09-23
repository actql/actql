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
  assert.deepEqual(reopened.history(locator, 2).map(value => value.entryJson),
    [firstJson, secondJson]);
  assert.equal(append(reopened, 1, cid('2'), secondJson).created, false);
  assert.throws(() => append(reopened, 1, cid('2'), '{}'), {
    code: 'EffectLedgerEntryCollision',
  });
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

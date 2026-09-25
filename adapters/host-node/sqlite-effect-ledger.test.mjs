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

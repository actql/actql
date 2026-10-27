import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';

test('the separate original observation connection enforces the selected database extent', async () => {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-observation-extent-', label: 'same Journal secondary database extent',
  });
  const bytes = 1024 * 1024;
  const journal = openClientRequestJournal(join(scratch.path, 'requests'),
    {maxDatabaseBytes: bytes});
  // This test observes the actual second native wrapper, not a product getter
  // or facility issuer. Primary and observation own separate native closes.
  const originalOpen = DatabaseSync.prototype.open;
  let database;
  DatabaseSync.prototype.open = function (...args) {
    database = this;
    return Reflect.apply(originalOpen, this, args);
  };
  try {
    journal.observationStorage();
  } finally {
    DatabaseSync.prototype.open = originalOpen;
  }
  try {
    const page = database.prepare('PRAGMA page_size').get().page_size;
    const pages = database.prepare('PRAGMA max_page_count').get().max_page_count;
    assert.ok(pages * page <= bytes,
      `The same selected secondary limit is required: ${pages} pages of ${page} bytes`);
    assert.equal(database.prepare('PRAGMA temp_store').get().temp_store, 0,
      'An unselected connection retains its original temporary-storage choice');
    database.exec('CREATE TABLE observation_extent_fixture(value BLOB) STRICT');
    assert.throws(() => database.prepare('INSERT INTO observation_extent_fixture VALUES (zeroblob(?))')
      .run(bytes * 2), cause => cause.code === 'ERR_SQLITE_ERROR' && cause.errcode === 13);
    assert.equal(database.isTransaction, false);
    assert.ok(database.prepare('PRAGMA page_count').get().page_count * page <= bytes);
    assert.equal(database.prepare('SELECT count(*) AS n FROM observation_extent_fixture').get().n, 0);
  } finally {
    journal.close();
  }
  assert.equal(database.isOpen, false);
  const custody = observeOriginalClientRequestJournalCustody(journal);
  assert.equal(custody.databaseClosed, true);
  assert.equal(custody.observationDatabaseClosed, true);
  scratch.passed();
});

test('both execution-bounded Journal connections select original in-memory temporary storage', async () => {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-temporary-storage-', label: 'same Journal temporary Btree selection',
  });
  const originalOpen = DatabaseSync.prototype.open;
  const databases = [];
  DatabaseSync.prototype.open = function (...args) {
    databases.push(this);
    return Reflect.apply(originalOpen, this, args);
  };
  let journal;
  try {
    journal = openClientRequestJournal(join(scratch.path, 'requests'), {
      maxDatabaseBytes: 1024 * 1024,
      primarySqlLimits: {maxPreparedStatements: 1000,
        maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
      primaryExecutionLimits: {maxParameters: 64,
        maxParameterBytes: 65536, maxResultRows: 1000},
    });
    journal.observationStorage();
    assert.equal(databases.length, 2);
    for (const database of databases) {
      assert.equal(database.prepare('PRAGMA temp_store').get().temp_store, 2);
    }
  } finally {
    DatabaseSync.prototype.open = originalOpen;
    journal?.close();
  }
  assert.ok(databases.every(database => !database.isOpen));
  scratch.passed();
});

for (const refusal of ['unsupported compilation', 'ineffective selection']) {
test(`temporary-store ${refusal} refuses before Journal DDL and closes the original database`, async () => {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-temporary-refusal-', label: 'unsupported original temporary facility',
  });
  const originalOpen = DatabaseSync.prototype.open;
  const originalPrepare = DatabaseSync.prototype.prepare;
  const originalExec = DatabaseSync.prototype.exec;
  let database, ddl = 0;
  DatabaseSync.prototype.open = function (...args) {
    database = this;
    return Reflect.apply(originalOpen, this, args);
  };
  DatabaseSync.prototype.prepare = function (sql) {
    const unsupported = refusal === 'unsupported compilation' &&
      sql === "SELECT sqlite_compileoption_used('TEMP_STORE=1') AS supported";
    const ineffective = refusal === 'ineffective selection' && sql === 'PRAGMA temp_store';
    if (unsupported || ineffective) {
      return {get() {return unsupported ? {supported: 0} : {temp_store: 0};},
        run() {assert.fail('Unsupported compile probe must not run');},
        iterate() {assert.fail('Unsupported compile probe must not iterate');}};
    }
    return Reflect.apply(originalPrepare, this, [sql]);
  };
  DatabaseSync.prototype.exec = function (sql) {
    if (/CREATE TABLE/u.test(sql)) ddl++;
    return Reflect.apply(originalExec, this, [sql]);
  };
  try {
    assert.throws(() => openClientRequestJournal(join(scratch.path, 'requests'), {
      maxDatabaseBytes: 1024 * 1024,
      primarySqlLimits: {maxPreparedStatements: 1000,
        maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
      primaryExecutionLimits: {maxParameters: 64,
        maxParameterBytes: 65536, maxResultRows: 1000},
    }), {code: 'ClientRequestJournalTemporaryUnavailable'});
    assert.equal(ddl, 0);
    assert.equal(database.isOpen, false);
  } finally {
    DatabaseSync.prototype.open = originalOpen;
    DatabaseSync.prototype.prepare = originalPrepare;
    DatabaseSync.prototype.exec = originalExec;
  }
  scratch.passed();
});
}

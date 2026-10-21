import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';

const options = {maxDatabaseBytes: 1024 * 1024, maxWalFrames: 200000,
  primarySqlLimits: {maxCalls: 1000, maxPreparedStatements: 1000,
    maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
  primaryExecutionLimits: {maxStatementCalls: 1000, maxParameters: 64,
    maxParameterBytes: 65536, maxResultRows: 1000}};

for (const phase of ['primary', 'observation']) {
test(`selected ${phase} temporary storage precedes the schema-loading Pager pragma`, async () => {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-schema-temporary-order-', label: 'same original schema temporary order',
  });
  const path = join(scratch.path, 'requests');
  let journal;
  if (phase === 'observation') journal = openClientRequestJournal(path, options);
  const prepare = DatabaseSync.prototype.prepare, open = DatabaseSync.prototype.open;
  const originals = [];
  let geometry = 0;
  DatabaseSync.prototype.open = function (...args) {
    originals.push(this);
    return Reflect.apply(open, this, args);
  };
  DatabaseSync.prototype.prepare = function (sql) {
    if (/^PRAGMA max_page_count = /u.test(sql)) {
      geometry++;
      // Explicit native observation at the actual preparation boundary.
      // It is not a product query, new capacity, or an operational issuer.
      assert.equal(Reflect.apply(prepare, this, ['PRAGMA temp_store']).get().temp_store, 2,
        'max_page_count has PragFlg_NeedSchema; MEMORY must already be effective');
    }
    return Reflect.apply(prepare, this, [sql]);
  };
  try {
    if (phase === 'primary') journal = openClientRequestJournal(path, options);
    else journal.observationStorage();
    assert.equal(geometry, 1);
  } finally {
    DatabaseSync.prototype.open = open;
    DatabaseSync.prototype.prepare = prepare;
    journal?.close();
    assert(originals.every(database => database.isOpen === false));
  }
  const custody = observeOriginalClientRequestJournalCustody(journal);
  assert.equal(custody.databaseClosed, true);
  assert.equal(custody.observationDatabaseClosed, true);
  scratch.passed();
});
}

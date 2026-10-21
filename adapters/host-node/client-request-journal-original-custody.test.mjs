import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';

async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-custody-original-',
    label: 'original physical Journal close observation',
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

// Actual SQLite/FS with explicit fault injection. These cases establish only
// the same existing Journal owner's observation, not an operational Root,
// covered connection, business permission or normal Host success.
test('original Journal custody distinguishes its actual native close from copies', async () => {
  const {scratch, directory} = await fixture();
  const journal = openClientRequestJournal(directory);
  try {
    assert.deepEqual(observeOriginalClientRequestJournalCustody(journal), {
      journalClosed: false, databaseClosed: false, observationAttempted: false,
      observationDatabaseClosed: true,
    });
    for (const foreign of [{...journal}, Object.freeze({databaseClosed: true}), null]) {
      assert.throws(() => observeOriginalClientRequestJournalCustody(foreign),
        {code: 'ForeignClientRequestJournalCustody'});
    }
  } finally { journal.close(); }
  const observation = observeOriginalClientRequestJournalCustody(journal);
  assert.equal(Object.isFrozen(observation), true);
  assert.deepEqual(observation, {
    journalClosed: true, databaseClosed: true, observationAttempted: false,
    observationDatabaseClosed: true,
  });
  scratch.passed();
});

test('logical close and a throwing original native close do not acknowledge physical custody', async () => {
  const {scratch, directory} = await fixture();
  const close = DatabaseSync.prototype.close;
  let database, calls = 0, permit = false, journal;
  DatabaseSync.prototype.close = function () {
    database ??= this;
    assert.equal(this, database);
    calls++;
    if (!permit) throw new Error('OriginalNativeClosePending');
    return Reflect.apply(close, this, []);
  };
  try {
    journal = openClientRequestJournal(directory);
    assert.throws(() => journal.close(), /OriginalNativeClosePending/);
    assert.equal(database.isOpen, true);
    assert.deepEqual(observeOriginalClientRequestJournalCustody(journal), {
      journalClosed: true, databaseClosed: false, observationAttempted: false,
      observationDatabaseClosed: true,
    });
    // Restoration does not replace the captured successful original callback.
    DatabaseSync.prototype.close = () => undefined;
    assert.throws(() => journal.close(), /OriginalNativeClosePending/);
    assert.equal(calls, 2);
    permit = true;
    journal.close();
    assert.equal(database.isOpen, false);
    assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
    journal.close();
    assert.equal(calls, 3);
  } finally {
    DatabaseSync.prototype.close = close;
    if (database?.isOpen) Reflect.apply(close, database, []);
    journal?.close();
  }
  scratch.passed();
});

test('the separate optional observation connection is not certified by primary close', async () => {
  const {scratch, directory} = await fixture();
  const journal = openClientRequestJournal(directory);
  try {
    journal.observationStorage();
    assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, true);
  } finally { journal.close(); }
  assert.deepEqual(observeOriginalClientRequestJournalCustody(journal), {
    journalClosed: true, databaseClosed: true, observationAttempted: true,
    observationDatabaseClosed: true,
  });
  scratch.passed();
});

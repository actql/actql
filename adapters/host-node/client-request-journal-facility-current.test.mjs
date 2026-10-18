import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from '../host-common/sqlite-format-inspection.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent} from './client-request-journal.mjs';

const limits = Object.freeze({maxDatabaseBytes: 1048576,
  primarySqlLimits: {maxCalls: 1000, maxPreparedStatements: 256,
    maxSqlBytes: 8192, maxTotalSqlBytes: 262144},
  primaryExecutionLimits: {maxStatementCalls: 1000, maxParameters: 32,
    maxParameterBytes: 262144, maxResultRows: 128}});
async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-facility-current-', label: 'same native Journal facility currentness',
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

// Actual native SQLite and filesystem, with explicit currentness faults.
// Correspondence/currentness is not an operational Root or capacity issuer.
test('fixed Journal namespace accepts only the same native constructor pair', () => {
  assert.equal(assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync), undefined);
  for (const [database, statement] of [[{}, StatementSync], [DatabaseSync, {}],
    [Object.assign(function () {}, DatabaseSync), StatementSync]]) {
    assert.throws(() => assertOriginalClientRequestJournalFacilityCurrent(database, statement),
      {code: 'ClientRequestJournalFacilityUnavailable'});
  }
  assert.equal(assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync), undefined);
});

test('selected current refusal precedes the first Journal directory or database acquisition', async () => {
  const {scratch, directory} = await fixture();
  const original = new Error('OriginalJournalFacilityNotCurrent');
  assert.throws(() => openClientRequestJournal(directory, {...limits,
    primaryCurrent() { throw original; }}), error => error === original);
  assert.equal(existsSync(directory), false);
  scratch.passed();
});

test('later current refusal prevents Journal use without disabling its original native close', async () => {
  const {scratch, directory} = await fixture();
  let current = true;
  const original = new Error('OriginalJournalFacilityChanged');
  const journal = openClientRequestJournal(directory, {...limits, primaryCurrent() {
    if (!current) throw original;
    assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync);
  }});
  current = false;
  assert.throws(() => journal.observationStorage(), error => error === original);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).observationAttempted, false);
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('same selected current and SQL execution bounds cover the separate observation connection', async () => {
  const {scratch, directory} = await fixture();
  let observations = 0;
  const journal = openClientRequestJournal(directory, {...limits, primaryCurrent() {
    observations++;
    assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync);
  }});
  const before = observations;
  journal.observationStorage();
  assert.ok(observations > before + 8);
  journal.close();
  assert.deepEqual(observeOriginalClientRequestJournalCustody(journal), {
    journalClosed: true, databaseClosed: true, observationAttempted: true,
    observationDatabaseClosed: true,
  });
  scratch.passed();
});

for (const refusedAt of [3, 4]) {
  test(`cold inspection current refusal ${refusedAt === 3 ? 'before' : 'after'} native open retains and closes its original`, async () => {
    const {scratch} = await fixture();
    const path = join(scratch.path, 'source.sqlite3');
    const source = new DatabaseSync(path);
    source.exec('CREATE TABLE metadata(value TEXT) STRICT');
    source.close();
    let observations = 0, opens = 0, wrapper;
    const original = new Error('OriginalColdJournalCurrentChanged');
    const open = DatabaseSync.prototype.open;
    DatabaseSync.prototype.open = function () {
      wrapper = this; opens++;
      return Reflect.apply(open, this, []);
    };
    try {
      assert.throws(() => inspectSqliteSnapshot(path, () => assert.fail('refused before inspection'), {
        maxSourceBytes: 1048576,
        assertCurrent() { if (++observations === refusedAt) throw original; },
      }), error => error === original);
      assert.equal(opens, refusedAt === 3 ? 0 : 1);
      if (wrapper !== undefined) assert.equal(wrapper.isOpen, false);
    } finally { DatabaseSync.prototype.open = open; }
    scratch.passed();
  });
}

test('replacing a selected native operation invalidates its original even after restoration', () => {
  const original = DatabaseSync.prototype.prepare;
  try {
    DatabaseSync.prototype.prepare = function () { throw new Error('MustNotUseReplacement'); };
    assert.throws(() => assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync),
      {code: 'ClientRequestJournalFacilityUnavailable'});
  } finally { DatabaseSync.prototype.prepare = original; }
  assert.throws(() => assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync),
    {code: 'ClientRequestJournalFacilityUnavailable'});
});

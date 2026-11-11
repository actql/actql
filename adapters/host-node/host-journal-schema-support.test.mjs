import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readdirSync, readFileSync} from 'node:fs';
import {DatabaseSync, StatementSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {inspectSqliteSnapshot} from '../host-common/sqlite-format-inspection.mjs';
import support from './host-journal-schema-support.cjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody,
  assertOriginalClientRequestJournalFacilityCurrent} from './client-request-journal.mjs';

const options = Object.freeze({maxDatabaseBytes: 4194304, maxRecords: 128,
  maxInspectionEntries: 32, maxInspectionBytes: 4194304,
  primarySqlLimits: {maxPreparedStatements: 256,
    maxSqlBytes: 8192, maxTotalSqlBytes: 262144},
  primaryExecutionLimits: {maxParameters: 32,
    maxParameterBytes: 262144, maxResultRows: 128},
  primarySchemaLimits: {maxSchemaBytes: 65536, maxSchemaEntries: 128,
    maxSchemaPages: 256, maxWalFrames: 8192},
  sourceOperationLimits: {maxRecords: 128, maxWireBytes: 65536},
  primarySchemaSqlSupport: support.sql});
const snapshot = directory => readdirSync(directory).sort().map(name => ({name,
  sha256: createHash('sha256').update(readFileSync(join(directory, name))).digest('hex')}));
async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-own-schema-', label: 'same original Journal selected own-schema cold support',
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

// Actual fixed Journal, SQLite and filesystem with explicit diagnostic bounds.
// The support asset is DATA, not the missing operational prefix disposition.
test('selected Journal reopens its own durable usage metadata without changing original bytes', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory, options).close();
  const before = snapshot(directory);
  const reopened = openClientRequestJournal(directory, options);
  reopened.close();
  assert.deepEqual(snapshot(directory), before);
  assert.equal(observeOriginalClientRequestJournalCustody(reopened).databaseClosed, true);
  scratch.passed();
});

test('selected own-DDL bytes cover the actual primary, Source and observation schema then cold reopen', async () => {
  const {scratch, directory} = await fixture();
  const selected = {...options, primaryCurrent() {
    assertOriginalClientRequestJournalFacilityCurrent(DatabaseSync, StatementSync);
  }};
  const journal = openClientRequestJournal(directory, selected);
  journal.observationStorage();
  journal.close();
  assert.equal(observeOriginalClientRequestJournalCustody(journal).observationDatabaseClosed, true);
  // Observe the schema through the same isolated-copy owner, not a read-only
  // open on the original path (which may itself create WAL/SHM auxiliaries).
  const actual = inspectSqliteSnapshot(join(directory, 'client-requests.sqlite3'), original =>
    original.prepare('SELECT sql FROM sqlite_schema WHERE sql IS NOT NULL')
      .all().map(row => row.sql).sort(), {maxSourceBytes: options.maxDatabaseBytes});
  assert.equal(actual.length, 32);
  // This fixture intentionally opens without an owned Store. The supported
  // local execution-owner table is conditional on that original ownership and
  // must not be manufactured just to make an unowned schema equal the asset.
  const selectedSql = support.sql.filter(sql => !sql.startsWith('CREATE TABLE client_local_execution_owners ('));
  assert.deepEqual(actual, [...selectedSql].sort());
  const before = snapshot(directory);
  const restored = openClientRequestJournal(directory, selected);
  restored.observationStorage();
  restored.close();
  assert.deepEqual(snapshot(directory), before);
  assert.deepEqual(observeOriginalClientRequestJournalCustody(restored), {
    journalClosed: true, databaseClosed: true, observationAttempted: true,
    observationDatabaseClosed: true,
  });
  scratch.passed();
});

test('valid but unsupported extra schema refuses before cold native open and preserves original bytes', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory, options).close();
  const original = new DatabaseSync(join(directory, 'client-requests.sqlite3'));
  try { original.exec('CREATE VIEW valid_external_view AS SELECT namespace_id FROM client_requests'); }
  finally { original.close(); }
  const before = snapshot(directory);
  const open = DatabaseSync.prototype.open;
  let nativeOpens = 0;
  DatabaseSync.prototype.open = function () {nativeOpens++; return Reflect.apply(open, this, []);};
  try {
    assert.throws(() => openClientRequestJournal(directory, options),
      {code: 'SqliteSchemaPreparationUnavailable'});
    assert.equal(nativeOpens, 0);
  } finally { DatabaseSync.prototype.open = open; }
  assert.deepEqual(snapshot(directory), before);
  scratch.passed();
});

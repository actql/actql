import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';

const selected = {
  maxDatabaseBytes: 1024 * 1024,
  primarySqlLimits: {maxCalls: 1000, maxPreparedStatements: 1000,
    maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
  primaryExecutionLimits: {maxStatementCalls: 1000, maxParameters: 64,
    maxParameterBytes: 65536, maxResultRows: 1000},
};
async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-operation-bound-', label: 'original Journal operation lifetime',
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

test('failed pre-SQL operations consume the original lifetime before another argument read', async () => {
  const {scratch, directory} = await fixture();
  const journal = openClientRequestJournal(directory, {...selected, maxJournalOperations: 1});
  let reads = 0, refusal;
  const input = {get namespaceId() {reads++; return undefined;}};
  try {
    assert.throws(() => journal.lookupReconciliationState(input), {code: 'InvalidClientRunLookup'});
    assert.throws(() => journal.lookupReconciliationState(input), error => {
      refusal = error;
      return error.code === 'ClientRequestJournalOperationUnavailable';
    });
    const borrowed = {...journal};
    assert.throws(() => borrowed.lookupReconciliationState(input), error => error === refusal);
    assert.equal(reads, 1);
  } finally { journal.close(); }
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('a successful native Journal read consumes the same lifetime without replacement credit', async () => {
  const {scratch, directory} = await fixture();
  const ref = {namespaceId: 'missing', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
    runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  const journal = openClientRequestJournal(directory, {...selected, maxJournalOperations: 1});
  try {
    assert.equal(journal.lookupReconciliationState(ref), undefined);
    assert.throws(() => journal.lookupReconciliationState(ref),
      {code: 'ClientRequestJournalOperationUnavailable'});
  } finally {journal.close();}
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('operation exhaustion preserves the original asynchronous Journal method contract', async () => {
  const {scratch, directory} = await fixture();
  const journal = openClientRequestJournal(directory, {...selected, maxJournalOperations: 1});
  try {
    assert.throws(() => journal.lookupReconciliationState({}), {code: 'InvalidClientRunLookup'});
    let result;
    assert.doesNotThrow(() => {result = journal.admitOrLookupDefinition();});
    assert.ok(result instanceof Promise);
    await assert.rejects(result, {code: 'ClientRequestJournalOperationUnavailable'});
  } finally { journal.close(); }
  scratch.passed();
});

test('failed original currentness consumes its operation before argument access without blocking close', async () => {
  const {scratch, directory} = await fixture();
  const original = new Error('OriginalJournalGenerationChanged');
  let failed = false, checks = 0, reads = 0;
  const journal = openClientRequestJournal(directory, {...selected, maxJournalOperations: 1,
    primaryCurrent() {checks++; if (failed) throw original;}});
  const before = checks;
  const input = {get namespaceId() {reads++; return undefined;}};
  try {
    failed = true;
    assert.throws(() => journal.lookupReconciliationState(input), error => error === original);
    assert.equal(checks, before + 1);
    assert.equal(reads, 0);
    failed = false;
    assert.throws(() => journal.lookupReconciliationState(input),
      {code: 'ClientRequestJournalOperationUnavailable'});
    assert.equal(checks, before + 1);
    assert.equal(reads, 0);
    assert.throws(() => observeOriginalClientRequestJournalCustody({...journal}),
      {code: 'ForeignClientRequestJournalCustody'});
  } finally {journal.close();}
  assert.equal(checks, before + 1);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('exhausted operations retain both original connections through pending close and same-receiver retry', async () => {
  const {scratch, directory} = await fixture();
  const originalClose = DatabaseSync.prototype.close;
  let permit = false, closes = 0;
  DatabaseSync.prototype.close = function () {
    closes++;
    if (!permit) return false;
    return Reflect.apply(originalClose, this, []);
  };
  let journal;
  try {
    journal = openClientRequestJournal(directory, {...selected, maxJournalOperations: 1});
    journal.observationStorage();
  } finally { DatabaseSync.prototype.close = originalClose; }
  try {
    assert.throws(() => journal.lookupReconciliationState({}),
      {code: 'ClientRequestJournalOperationUnavailable'});
    assert.throws(() => journal.close());
    assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, false);
    permit = true;
    journal.close();
    const custody = observeOriginalClientRequestJournalCustody(journal);
    assert.equal(custody.databaseClosed, true);
    assert.equal(custody.observationDatabaseClosed, true);
    assert.ok(closes >= 3);
  } finally {permit = true; journal?.close();}
  scratch.passed();
});

test('operation bounds reject invalid or incomplete selected configurations before filesystem work', async () => {
  const {scratch, directory} = await fixture();
  for (const [index, value] of [0, -1, NaN, Infinity, '1'].entries()) {
    const path = directory + index;
    assert.throws(() => openClientRequestJournal(path, {...selected, maxJournalOperations: value}),
      {code: 'InvalidClientRequestJournalConfiguration'});
    assert.equal(existsSync(path), false);
  }
  assert.throws(() => openClientRequestJournal(directory, {maxJournalOperations: 1}),
    {code: 'InvalidClientRequestJournalConfiguration'});
  assert.equal(existsSync(directory), false);
  const journal = openClientRequestJournal(directory);
  try {
    for (let index = 0; index < 3; index++) {
      assert.throws(() => journal.lookupReconciliationState({}), {code: 'InvalidClientRunLookup'});
    }
  } finally {journal.close();}
  scratch.passed();
});

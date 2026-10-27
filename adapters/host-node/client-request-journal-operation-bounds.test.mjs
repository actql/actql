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
  primarySqlLimits: {maxPreparedStatements: 1000,
    maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024},
  primaryExecutionLimits: {maxParameters: 64,
    maxParameterBytes: 65536, maxResultRows: 1000},
};
async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-operation-bound-', label: 'original Journal operation currentness and cleanup',
  });
  return {scratch, directory: join(scratch.path, 'requests')};
}

test('failed pre-SQL operations keep current checks and do not create lifetime call debt', async () => {
  const {scratch, directory} = await fixture();
  let current = true, reads = 0;
  const refusal = new Error('OriginalJournalCurrentRefused');
  const journal = openClientRequestJournal(directory, {...selected,
    primaryCurrent() {if (!current) throw refusal;}});
  const input = {get namespaceId() {reads++; return undefined;}};
  try {
    for (let index = 0; index < 3; index++) {
      assert.throws(() => journal.lookupReconciliationState(input), {code: 'InvalidClientRunLookup'});
    }
    assert.equal(reads, 3);
    current = false;
    assert.throws(() => journal.lookupReconciliationState(input), error => error === refusal);
    const borrowed = {...journal};
    assert.throws(() => borrowed.lookupReconciliationState(input), error => error === refusal);
    assert.equal(reads, 3, 'both original facade calls refuse before another argument read');
  } finally { journal.close(); }
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('completed native Journal reads remain usable and a later current refusal still precedes SQL', async () => {
  const {scratch, directory} = await fixture();
  const ref = {namespaceId: 'missing', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
    runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
  let current = true;
  const refusal = new Error('OriginalJournalCurrentRefused');
  const journal = openClientRequestJournal(directory, {...selected,
    primaryCurrent() {if (!current) throw refusal;}});
  try {
    for (let index = 0; index < 32; index++) {
      assert.equal(journal.lookupReconciliationState(ref), undefined);
    }
    current = false;
    assert.throws(() => journal.lookupReconciliationState(ref),
      error => error === refusal);
  } finally {journal.close();}
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('current refusal preserves the original asynchronous Journal method contract', async () => {
  const {scratch, directory} = await fixture();
  let current = true;
  const refusal = new Error('OriginalJournalCurrentRefused');
  const journal = openClientRequestJournal(directory, {...selected,
    primaryCurrent() {if (!current) throw refusal;}});
  try {
    assert.throws(() => journal.lookupReconciliationState({}), {code: 'InvalidClientRunLookup'});
    current = false;
    let result;
    assert.doesNotThrow(() => {result = journal.admitOrLookupDefinition();});
    assert.ok(result instanceof Promise);
    await assert.rejects(result, error => error === refusal);
  } finally { journal.close(); }
  scratch.passed();
});

test('each original current refusal precedes argument access without blocking close', async () => {
  const {scratch, directory} = await fixture();
  const original = new Error('OriginalJournalGenerationChanged');
  let failed = false, checks = 0, reads = 0;
  const journal = openClientRequestJournal(directory, {...selected,
    primaryCurrent() {checks++; if (failed) throw original;}});
  const before = checks;
  const input = {get namespaceId() {reads++; return undefined;}};
  try {
    failed = true;
    assert.throws(() => journal.lookupReconciliationState(input), error => error === original);
    assert.equal(checks, before + 1);
    assert.equal(reads, 0);
    assert.throws(() => journal.lookupReconciliationState(input), error => error === original);
    assert.equal(checks, before + 2);
    assert.equal(reads, 0);
    assert.throws(() => observeOriginalClientRequestJournalCustody({...journal}),
      {code: 'ForeignClientRequestJournalCustody'});
  } finally {journal.close();}
  assert.equal(checks, before + 2);
  assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, true);
  scratch.passed();
});

test('current-refused operations retain both original connections through pending close and same-receiver retry', async () => {
  const {scratch, directory} = await fixture();
  const originalClose = DatabaseSync.prototype.close;
  let permit = false, closes = 0;
  DatabaseSync.prototype.close = function () {
    closes++;
    if (!permit) return false;
    return Reflect.apply(originalClose, this, []);
  };
  let journal, current = true;
  const refusal = new Error('OriginalJournalCurrentRefused');
  try {
    journal = openClientRequestJournal(directory, {...selected,
      primaryCurrent() {if (!current) throw refusal;}});
    journal.observationStorage();
  } finally { DatabaseSync.prototype.close = originalClose; }
  try {
    current = false;
    assert.throws(() => journal.lookupReconciliationState({}),
      error => error === refusal);
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

test('current and closed selected records reject invalid or incomplete inputs before filesystem work', async () => {
  const {scratch, directory} = await fixture();
  const invalid = [
    {...selected, primaryCurrent: 0},
    {...selected, primarySqlLimits: {...selected.primarySqlLimits, maxCalls: 1}},
    {...selected, primaryExecutionLimits: {...selected.primaryExecutionLimits, maxStatementCalls: 1}},
    {primaryExecutionLimits: selected.primaryExecutionLimits},
  ];
  for (const [index, value] of invalid.entries()) {
    const path = directory + index;
    assert.throws(() => openClientRequestJournal(path, value),
      {code: 'InvalidClientRequestJournalConfiguration'});
    assert.equal(existsSync(path), false);
  }
  assert.equal(existsSync(directory), false);
  const journal = openClientRequestJournal(directory);
  try {
    for (let index = 0; index < 3; index++) {
      assert.throws(() => journal.lookupReconciliationState({}), {code: 'InvalidClientRunLookup'});
    }
  } finally {journal.close();}
  scratch.passed();
});

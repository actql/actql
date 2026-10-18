import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const defaults = {maxCalls: 1000, maxPreparedStatements: 1000,
  maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024};
const ref = {namespaceId: 'missing', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
async function fixture() {
  const scratch = await createOwnedScratch({
    parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-sql-bound-', label: 'actual Journal primary SQL lifetime'});
  return {scratch, directory: join(scratch.path, 'requests')};
}

// Native observations are explicit test instrumentation, not product getters
// or an operational admission. Restore every prototype before returning.
function observe(action) {
  const open = DatabaseSync.prototype.open, exec = DatabaseSync.prototype.exec;
  const prepare = DatabaseSync.prototype.prepare;
  const byteLength = Buffer.byteLength;
  const state = {database: undefined, calls: 0, prepared: 0, bytes: 0};
  DatabaseSync.prototype.open = function() {
    state.database = this; return Reflect.apply(open, this, []);
  };
  DatabaseSync.prototype.exec = function(sql) {
    state.calls++; state.bytes += Reflect.apply(byteLength, Buffer, [sql, 'utf8']);
    return Reflect.apply(exec, this, [sql]);
  };
  DatabaseSync.prototype.prepare = function(sql) {
    state.calls++; state.prepared++;
    state.bytes += Reflect.apply(byteLength, Buffer, [sql, 'utf8']);
    if (state.failPrepare !== undefined) throw state.failPrepare;
    return Reflect.apply(prepare, this, [sql]);
  };
  try { action(state); }
  finally {
    DatabaseSync.prototype.open = open; DatabaseSync.prototype.exec = exec;
    DatabaseSync.prototype.prepare = prepare;
  }
  return state;
}

test('primary SQL call and byte ceilings refuse before the next native compilation and still close', async () => {
  const {scratch, directory} = await fixture();
  const cases = [{maxCalls: 1}, {maxSqlBytes: 1},
    {maxTotalSqlBytes: Buffer.byteLength('PRAGMA journal_mode = WAL')}];
  for (const [index, selected] of cases.entries()) {
    observe(state => {
      let journal;
      try {
        assert.throws(() => { journal = openClientRequestJournal(directory + index,
          {primarySqlLimits: {...defaults, ...selected}}); },
        {code: 'ClientRequestJournalSqlUnavailable'});
        assert.equal(state.calls, index === 1 ? 0 : 1);
        assert.equal(state.database.isOpen, false);
      } finally { journal?.close(); }
    });
  }
  scratch.passed();
});

for (const [label, replacement] of [['zero', () => 0], ['NaN', () => NaN]]) {
test(`later byteLength replacement (${label}) cannot bypass the primary aggregate SQL ceiling`, async () => {
  const {scratch, directory} = await fixture();
    observe(state => {
      const journal = openClientRequestJournal(directory,
        {primarySqlLimits: {...defaults, maxCalls: 10000,
          maxPreparedStatements: 10000, maxTotalSqlBytes: 65536}});
      const byteLength = Buffer.byteLength;
      let failure, nativeCalls;
      try {
        Buffer.byteLength = replacement;
        for (let index = 0; index < 1000; index++) {
          try { journal.lookupReconciliationState(ref); }
          catch (cause) { failure = cause; break; }
        }
        nativeCalls = state.calls;
        try { journal.lookupReconciliationState(ref); } catch { /* Same refusal. */ }
      } finally { Buffer.byteLength = byteLength; journal.close(); }
      assert.equal(failure?.code, 'ClientRequestJournalSqlUnavailable');
      assert.equal(state.calls, nativeCalls);
      assert.ok(state.bytes <= 65536);
      assert.equal(state.database.isOpen, false);
    });
  scratch.passed();
});
}

test('repeated actual Journal prepares consume one lifetime allowance without GC refunds', async () => {
  const {scratch, directory} = await fixture();
  observe(state => {
    const primarySqlLimits = {...defaults, maxPreparedStatements: 70};
    const journal = openClientRequestJournal(directory,
      {primarySqlLimits});
    primarySqlLimits.maxPreparedStatements = 10000;
    try {
      let accepted = 0;
      for (; accepted < 100; accepted++) {
        try { assert.equal(journal.lookupReconciliationState(ref), undefined); }
        catch (error) {
          assert.equal(error.code, 'ClientRequestJournalSqlUnavailable'); break;
        }
      }
      assert.ok(accepted > 0 && accepted < 100);
      assert.equal(state.prepared, 70);
      const before = state.calls;
      assert.throws(() => journal.lookupReconciliationState(ref),
        {code: 'ClientRequestJournalSqlUnavailable'});
      assert.equal(state.calls, before);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('native prepare failure consumes the same primary lifetime allowance and cannot refill it', async () => {
  const {scratch, directory} = await fixture();
  observe(state => {
    const journal = openClientRequestJournal(directory,
      {primarySqlLimits: {...defaults, maxPreparedStatements: 70}});
    try {
      const cause = new Error('explicit original native prepare failure');
      state.failPrepare = cause;
      while (state.prepared < 70) {
        assert.throws(() => journal.lookupReconciliationState(ref), error => error === cause);
      }
      const before = state.calls;
      assert.throws(() => journal.lookupReconciliationState(ref),
        {code: 'ClientRequestJournalSqlUnavailable'});
      assert.equal(state.calls, before);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('selected primary SQL limits are immutable own DATA and refuse invalid configurations before filesystem work', async () => {
  const {scratch, directory} = await fixture();
  let getterReads = 0;
  const getter = {...defaults};
  Object.defineProperty(getter, 'maxCalls', {get() { getterReads++; return 1000; }});
  for (const [index, primarySqlLimits] of [
    {...defaults, maxCalls: 0}, {...defaults, maxTotalSqlBytes: Infinity},
    {...defaults, maxSqlBytes: 1.5}, {...defaults, maxPreparedStatements: -1},
    {...defaults, extra: 1}, getter,
  ].entries()) {
    let journal;
    const path = directory + index;
    try { assert.throws(() => { journal = openClientRequestJournal(path, {primarySqlLimits}); },
      {code: 'InvalidClientRequestJournalConfiguration'}); }
    finally { journal?.close(); }
    assert.equal(existsSync(path), false);
  }
  assert.equal(getterReads, 0); scratch.passed();
});

import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal, observeOriginalClientRequestJournalCustody}
  from './client-request-journal.mjs';

const primarySqlLimits = {maxPreparedStatements: 10000,
  maxSqlBytes: 65536, maxTotalSqlBytes: 16 * 1024 * 1024};
const primaryExecutionLimits = {maxParameters: 32,
  maxParameterBytes: 262144, maxResultRows: 128};
const options = maxWalFrames => ({maxDatabaseBytes: 1024 * 1024,
  primarySqlLimits, primaryExecutionLimits, maxWalFrames});
const ref = {namespaceId: 'missing', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const fixture = () => createOwnedScratch({
  parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
  prefix: 'journal-wal-bound-', label: 'same Journal WAL lifetime support bound'});

// Explicit native observations, never a physical facility issuer or authority.
// Keep every acquired database and original receiver observable through close.
function instrument(action) {
  const open = DatabaseSync.prototype.open, prepare = DatabaseSync.prototype.prepare;
  const exec = DatabaseSync.prototype.exec, close = DatabaseSync.prototype.close;
  const state = {databases: [], calls: 0, fault: undefined, closePending: false};
  DatabaseSync.prototype.open = function(...args) {
    state.databases.push(this);
    return Reflect.apply(open, this, args);
  };
  DatabaseSync.prototype.prepare = function(sql) {
    state.calls++;
    const statement = Reflect.apply(prepare, this, [sql]);
    for (const name of ['get', 'run', 'iterate']) {
      const original = statement[name];
      statement[name] = function(...values) {
        state.calls++;
        if (state.fault !== undefined) {
          const cause = state.fault;
          state.fault = undefined;
          throw cause;
        }
        return Reflect.apply(original, this, values);
      };
    }
    return statement;
  };
  DatabaseSync.prototype.exec = function(sql) {
    state.calls++;
    return Reflect.apply(exec, this, [sql]);
  };
  DatabaseSync.prototype.close = function(...args) {
    if (state.closePending) return false;
    return Reflect.apply(close, this, args);
  };
  try { return action(state); }
  finally {
    DatabaseSync.prototype.open = open; DatabaseSync.prototype.prepare = prepare;
    DatabaseSync.prototype.exec = exec; DatabaseSync.prototype.close = close;
  }
}

test('unsupported WAL lifetime refuses before native open instead of treating a later file bound as backing', async () => {
  const scratch = await fixture();
  instrument(state => {
    let journal;
    try {
      assert.throws(() => {journal = openClientRequestJournal(join(scratch.path, 'requests'), options(1));},
        {code: 'ClientRequestJournalWalUnavailable'});
      assert.equal(state.databases.length, 0);
      assert.equal(state.calls, 0);
    } finally { journal?.close(); }
  });
  scratch.passed();
});

test('WAL support requires the original finite SQL, operand and database boundaries', async () => {
  const scratch = await fixture();
  instrument(state => {
    const complete = options(200000);
    for (const name of ['maxDatabaseBytes', 'primarySqlLimits', 'primaryExecutionLimits']) {
      const selected = {...complete};
      delete selected[name];
      assert.throws(() => openClientRequestJournal(join(scratch.path, name), selected),
        {code: 'InvalidClientRequestJournalConfiguration'});
    }
    assert.equal(state.databases.length, 0);
  });
  scratch.passed();
});

test('both writable connections share one non-refilling WAL lifetime without charging metadata reads', async () => {
  const scratch = await fixture();
  instrument(state => {
    const selected = options(200000);
    const journal = openClientRequestJournal(join(scratch.path, 'requests'), selected);
    // Changing the caller's plain options cannot replace the original finite
    // primitive captured by this constructor's same lifetime counter.
    selected.maxWalFrames = Number.MAX_SAFE_INTEGER;
    const observations = journal.observationStorage();
    try {
      assert.equal(state.databases.length, 2);
      let accepted = 0;
      for (; accepted < 1000; accepted++) {
        try { assert.equal(observations.consume({ref, scope: 'test', revision: 'one',
          bytes: 1, maxRecords: 1, maxBytes: 1}), undefined); }
        catch (cause) { assert.equal(cause.code, 'ClientRequestJournalWalUnavailable'); break; }
      }
      assert.ok(accepted > 0 && accepted < 1000);
      const before = state.calls;
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.ok(state.calls > before, 'A metadata read uses no writable-frame allowance');
      const afterRead = state.calls;
      assert.throws(() => observations.consume({ref, scope: 'test', revision: 'one',
        bytes: 1, maxRecords: 1, maxBytes: 1}), {code: 'ClientRequestJournalWalUnavailable'});
      assert.equal(state.calls, afterRead, 'The observation connection cannot borrow a new allowance');
    } finally { journal.close(); }
    assert.ok(state.databases.every(database => database.isOpen === false));
    const custody = observeOriginalClientRequestJournalCustody(journal);
    assert.equal(custody.databaseClosed, true);
    assert.equal(custody.observationDatabaseClosed, true);
  });
  scratch.passed();
});

test('failed metadata reads do not debit writable WAL and exhausted writers retain original pending close', async () => {
  const scratch = await fixture();
  const remaining = [];
  for (const [index, fault] of [undefined, new Error('OriginalNativeReadFailure')].entries()) {
    instrument(state => {
      const journal = openClientRequestJournal(join(scratch.path, String(index)), options(200000));
      const observations = journal.observationStorage();
      try {
        if (fault !== undefined) {
          state.fault = fault;
          assert.throws(() => journal.lookupReconciliationState(ref), cause => cause === fault);
        }
        let accepted = 0;
        for (; accepted < 1000; accepted++) {
          try { observations.consume({ref, scope: 'test', revision: 'one',
            bytes: 1, maxRecords: 1, maxBytes: 1}); }
          catch (cause) { assert.equal(cause.code, 'ClientRequestJournalWalUnavailable'); break; }
        }
        assert.ok(accepted > 0 && accepted < 1000);
        remaining.push(accepted);
        state.closePending = true;
        assert.throws(() => journal.close(), {message: 'ClientRequestJournalConnectionCleanupPending'});
        assert.equal(state.databases[0].isOpen, true);
        assert.equal(observeOriginalClientRequestJournalCustody(journal).databaseClosed, false);
      } finally {
        state.closePending = false;
        journal.close();
      }
      assert.ok(state.databases.every(database => database.isOpen === false));
    });
  }
  assert.equal(remaining[0], remaining[1],
    'A failed SELECT spends its SQL attempt, not a fictional WAL write; actual write charges never refill');
  scratch.passed();
});

test('later integer conversion replacement cannot erase the original WAL lifetime charge', async () => {
  const scratch = await fixture();
  instrument(state => {
    const journal = openClientRequestJournal(join(scratch.path, 'requests'), options(200000));
    const observations = journal.observationStorage();
    const original = globalThis.BigInt;
    try {
      globalThis.BigInt = () => 0n;
      let accepted = 0;
      for (; accepted < 1000; accepted++) {
        try { observations.consume({ref, scope: 'test', revision: 'one',
          bytes: 1, maxRecords: 1, maxBytes: 1}); }
        catch (cause) { assert.equal(cause.code, 'ClientRequestJournalWalUnavailable'); break; }
      }
      assert.ok(accepted > 0 && accepted < 1000);
      const before = state.calls;
      assert.throws(() => observations.consume({ref, scope: 'test', revision: 'one',
        bytes: 1, maxRecords: 1, maxBytes: 1}),
        {code: 'ClientRequestJournalWalUnavailable'});
      assert.equal(state.calls, before);
    } finally { globalThis.BigInt = original; journal.close(); }
    assert.ok(state.databases.every(database => database.isOpen === false));
  });
  scratch.passed();
});

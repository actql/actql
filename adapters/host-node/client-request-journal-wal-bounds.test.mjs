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
  prefix: 'journal-wal-bound-', label: 'same Journal live WAL support bound'});

// Explicit native observations, never a physical facility issuer or authority.
// Keep every acquired database and original receiver observable through close.
function instrument(action) {
  const open = DatabaseSync.prototype.open, prepare = DatabaseSync.prototype.prepare;
  const exec = DatabaseSync.prototype.exec, close = DatabaseSync.prototype.close;
  const state = {databases: [], calls: 0, fault: undefined, closePending: false, checkpoints: 0};
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
        const result = Reflect.apply(original, this, values);
        if (name === 'get' && sql === 'PRAGMA wal_checkpoint(TRUNCATE)') {
          assert.deepEqual({...result}, {busy: 0, log: 0, checkpointed: 0});
          state.checkpoints++;
        }
        return result;
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

test('unsupported WAL support refuses before native open instead of treating a later file bound as backing', async () => {
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

test('both original writable connections reuse finite WAL support only after actual native truncation', async () => {
  const scratch = await fixture();
  instrument(state => {
    const selected = options(200000);
    const journal = openClientRequestJournal(join(scratch.path, 'requests'), selected);
    // Changing the caller's plain options cannot replace the original finite
    // primitive captured by this constructor's same live support bound.
    selected.maxWalFrames = Number.MAX_SAFE_INTEGER;
    const observations = journal.observationStorage();
    try {
      assert.equal(state.databases.length, 2);
      for (let accepted = 0; accepted < 1000; accepted++) {
        assert.equal(observations.consume({ref, scope: 'test', revision: 'one',
          bytes: 1, maxRecords: 1, maxBytes: 1}), undefined);
        assert.equal(journal.lookupReconciliationState(ref), undefined);
      }
      assert.ok(state.checkpoints > 1, 'Repeated finite operations exceed the former lifetime allowance');
      const checkpoints = state.checkpoints;
      const before = state.calls;
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.ok(state.calls > before, 'A metadata read uses no writable-frame allowance');
      assert.equal(state.checkpoints, checkpoints, 'SELECT does not request WAL reclamation');
      assert.equal(observations.consume({ref, scope: 'test', revision: 'one',
        bytes: 1, maxRecords: 1, maxBytes: 1}), undefined);
    } finally { journal.close(); }
    assert.ok(state.databases.every(database => database.isOpen === false));
    const custody = observeOriginalClientRequestJournalCustody(journal);
    assert.equal(custody.databaseClosed, true);
    assert.equal(custody.observationDatabaseClosed, true);
  });
  scratch.passed();
});

test('failed metadata reads do not debit writable WAL and reused writers retain original pending close', async () => {
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
        for (let accepted = 0; accepted < 1000; accepted++) {
          observations.consume({ref, scope: 'test', revision: 'one',
            bytes: 1, maxRecords: 1, maxBytes: 1});
        }
        assert.ok(state.checkpoints > 0);
        remaining.push(state.checkpoints);
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
    'A failed SELECT spends its SQL attempt, not WAL capacity or a checkpoint');
  scratch.passed();
});

test('later integer conversion replacement cannot erase the original finite WAL charge', async () => {
  const scratch = await fixture();
  instrument(state => {
    const journal = openClientRequestJournal(join(scratch.path, 'requests'), options(200000));
    const observations = journal.observationStorage();
    const original = globalThis.BigInt;
    try {
      globalThis.BigInt = () => 0n;
      for (let accepted = 0; accepted < 1000; accepted++) {
        observations.consume({ref, scope: 'test', revision: 'one',
          bytes: 1, maxRecords: 1, maxBytes: 1});
      }
      assert.ok(state.checkpoints > 1, 'Real truncation must still be required to reclaim charges');
    } finally { globalThis.BigInt = original; journal.close(); }
    assert.ok(state.databases.every(database => database.isOpen === false));
  });
  scratch.passed();
});

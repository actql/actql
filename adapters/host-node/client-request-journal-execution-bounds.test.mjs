import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const primarySqlLimits = {maxCalls: 1000, maxPreparedStatements: 1000,
  maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024};
const execution = {maxStatementCalls: 1000, maxParameters: 32,
  maxParameterBytes: 262144, maxResultRows: 128};
const ref = {namespaceId: 'missing', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
async function fixture() {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-execution-bound-', label: 'actual primary SQLite statement/cursor custody'});
  return {scratch, directory: join(scratch.path, 'requests')};
}
function instrument(action, {cursorFailure = false, firstClosePending = false} = {}) {
  const open = DatabaseSync.prototype.open, prepare = DatabaseSync.prototype.prepare;
  const close = DatabaseSync.prototype.close;
  const state = {database: undefined, nativeCalls: 0, nativeAll: 0, maxCursorSteps: 0, closes: 0};
  DatabaseSync.prototype.open = function() {
    state.database = this;
    return Reflect.apply(open, this, []);
  };
  DatabaseSync.prototype.close = function() {
    if (this !== state.database) return Reflect.apply(close, this, []);
    state.closes++;
    if (firstClosePending && state.closes === 1) return false;
    return Reflect.apply(close, this, []);
  };
  DatabaseSync.prototype.prepare = function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]);
    if (this !== state.database) return statement;
    for (const name of ['get', 'run']) {
      const original = statement[name];
      statement[name] = function(...args) {
        state.nativeCalls++; return Reflect.apply(original, this, args);
      };
    }
    statement.all = function() {
      state.nativeAll++; throw new Error('Native complete vector must not be used');
    };
    const iterate = statement.iterate;
    statement.iterate = function(...args) {
      state.nativeCalls++;
      const iterator = Reflect.apply(iterate, this, args);
      const next = iterator.next, end = iterator.return;
      let steps = 0;
      iterator.next = function() {
        state.maxCursorSteps = Math.max(state.maxCursorSteps, ++steps);
        return Reflect.apply(next, this, []);
      };
      iterator.return = function() {
        if (cursorFailure) throw new Error('Explicit original iterator close failure');
        return Reflect.apply(end, this, []);
      };
      return iterator;
    };
    return statement;
  };
  try { action(state); }
  finally {
    DatabaseSync.prototype.open = open; DatabaseSync.prototype.prepare = prepare;
    DatabaseSync.prototype.close = close;
  }
}
function options(primaryExecutionLimits = execution) {
  return {maxDatabaseBytes: 1024 * 1024, primarySqlLimits, primaryExecutionLimits};
}

test('selected primary metadata uses original bounded cursors instead of native All vectors', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory).close();
  instrument(state => {
    const journal = openClientRequestJournal(directory, options());
    try { assert.equal(journal.lookupReconciliationState(ref), undefined); }
    finally { journal.close(); }
    assert.equal(state.nativeAll, 0); assert.ok(state.maxCursorSteps > 1);
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('row overflow retains only its bounded result and one native lookahead before original close', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory).close();
  instrument(state => {
    assert.throws(() => openClientRequestJournal(directory,
      options({...execution, maxResultRows: 1})), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(state.nativeAll, 0); assert.equal(state.maxCursorSteps, 2);
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('unsupported original bind extent refuses before native statement invocation without changing old public field validation', async () => {
  const {scratch, directory} = await fixture();
  instrument(state => {
    const limits = {...execution, maxParameterBytes: 256};
    const journal = openClientRequestJournal(directory, options(limits));
    limits.maxParameterBytes = 100000;
    try {
      const before = state.nativeCalls;
      assert.throws(() => journal.lookupReconciliationState({...ref, namespaceId: 'x'.repeat(256)}),
        {code: 'ClientRequestJournalSqlUnavailable'});
      assert.equal(state.nativeCalls, before);
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(state.nativeCalls, before + 1);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('statement lifetime exhaustion blocks the next native call but leaves original database close reachable', async () => {
  const {scratch, directory} = await fixture();
  instrument(state => {
    const journal = openClientRequestJournal(directory, options({...execution, maxStatementCalls: 100}));
    try {
      let accepted = 0;
      for (; accepted < 100; accepted++) {
        try { journal.lookupReconciliationState(ref); }
        catch (cause) { assert.equal(cause.code, 'ClientRequestJournalSqlUnavailable'); break; }
      }
      assert.ok(accepted > 0 && accepted < 100);
      assert.equal(state.nativeCalls, 100);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('failed original cursor close and pending database close retain the same native connection until its close ACK', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory).close();
  instrument(state => {
    let failure;
    try { openClientRequestJournal(directory, options()); } catch (cause) { failure = cause; }
    assert.equal(failure.code, 'SqliteJournalInitializationCleanupPending');
    assert.equal(failure.primaryFailure.code, 'ClientRequestJournalSqlCleanupPending');
    assert.equal(failure.cleanupHandle.status().pending, true);
    assert.equal(state.database.isOpen, true);
    assert.equal(state.closes, 1);
    assert.equal(failure.cleanupHandle.retry().pending, false);
    assert.equal(state.database.isOpen, false); assert.equal(state.closes, 2);
    assert.equal(failure.cleanupHandle.retry().pending, false); assert.equal(state.closes, 2);
  }, {cursorFailure: true, firstClosePending: true});
  scratch.passed();
});

test('selected current callback cannot reenter the same Journal before native preparation', async () => {
  const {scratch, directory} = await fixture();
  instrument(state => {
    let journal, armed = false, nestedFailure, nestedAttempts = 0;
    journal = openClientRequestJournal(directory, {...options(), primaryCurrent() {
      if (!armed) return;
      armed = false;
      nestedAttempts++;
      try { journal.lookupReconciliationState(ref); }
      catch (cause) { nestedFailure = cause; }
    }});
    try {
      const before = state.nativeCalls;
      armed = true;
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(nestedAttempts, 1);
      assert.equal(nestedFailure?.code, 'ClientRequestJournalSqlCleanupPending');
      assert.equal(state.nativeCalls, before + 1);
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(state.nativeCalls, before + 2);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

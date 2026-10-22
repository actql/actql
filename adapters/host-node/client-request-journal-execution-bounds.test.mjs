import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';

const primarySqlLimits = {maxCalls: 1000, maxPreparedStatements: 1000,
  maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024};
const execution = {maxStatementCalls: 1000, maxParameters: 32,
  maxParameterBytes: 262144, maxResultRows: 128};
const ref = {namespaceId: 'missing', authorityScopeCid: 'sha256:' + 'a'.repeat(64),
  runDefinitionCid: 'sha256:' + 'b'.repeat(64)};
// Execute the exact private boundary with actual SQLite originals. Its
// compilation/execution counters are not Host resource or permission issuers.
const source = readFileSync(new URL('./client-request-journal.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declarations = ['fail', 'applyOriginal'].map(name => ast.body.find(node =>
  node.type === 'VariableDeclaration' && node.declarations.some(item => item.id.name === name)));
const bounded = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'boundedPrimarySql');
assert.ok(bounded); assert.ok(declarations.every(Boolean));
const boundedOriginalSql = compileFunction([...declarations, bounded].map(node =>
  source.slice(node.start, node.end)).join('\n') + '\nreturn boundedPrimarySql;', [])();
async function fixture() {
  const scratch = await createOwnedScratch({parent: fileURLToPath(new URL('../../_build/', import.meta.url)),
    prefix: 'journal-execution-bound-', label: 'actual primary SQLite statement/cursor custody'});
  return {scratch, directory: join(scratch.path, 'requests')};
}
function instrument(action, {cursorFailure = false, firstClosePending = false} = {}) {
  const open = DatabaseSync.prototype.open, prepare = DatabaseSync.prototype.prepare;
  const close = DatabaseSync.prototype.close;
  const state = {database: undefined, nativeCalls: 0, nativeAll: 0, maxCursorSteps: 0, closes: 0,
    preparations: []};
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
    state.preparations.push({sql, statement});
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

test('selected Journal reuses one original statement for repeated exact SQL without spending another preparation allowance', async () => {
  const {scratch, directory} = await fixture();
  openClientRequestJournal(directory).close();
  instrument(state => {
    const sqlLimits = {...primarySqlLimits, maxPreparedStatements: 70};
    const journal = openClientRequestJournal(directory, {...options(), primarySqlLimits: sqlLimits});
    sqlLimits.maxPreparedStatements = 10000;
    try {
      const before = state.preparations.length;
      for (let index = 0; index < 100; index++) {
        assert.equal(journal.lookupReconciliationState({...ref, namespaceId: 'missing-' + index}), undefined);
      }
      assert.equal(state.preparations.length - before, 1);
      assert.ok(state.preparations.length <= 70);
      assert.equal(state.nativeAll, 0);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

test('exact statement reuse rebinds parameters and retains native methods without refilling compilation or execution limits', () => {
  const database = new DatabaseSync(':memory:');
  const prepare = database.prepare;
  let preparations = 0, originalStatement;
  database.prepare = function(sql) {
    assert.equal(this, database); preparations++;
    const statement = Reflect.apply(prepare, this, [sql]);
    originalStatement ??= statement;
    return statement;
  };
  const port = boundedOriginalSql(database, {...primarySqlLimits, maxCalls: 2, maxPreparedStatements: 2},
    {...execution, maxStatementCalls: 3});
  try {
    const first = port.database.prepare('SELECT ? AS n');
    assert.equal(first.get(1).n, 1);
    originalStatement.get = () => {throw new Error('ReplacementMustNotRun');};
    const same = port.database.prepare('SELECT ? AS n');
    assert.equal(same, first); assert.equal(same.get(2).n, 2);
    const distinct = port.database.prepare('SELECT ? AS m');
    assert.notEqual(distinct, first); assert.equal(distinct.get(3).m, 3);
    assert.equal(preparations, 2);
    assert.throws(() => port.database.prepare('SELECT ? AS other'), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(preparations, 2);
    assert.equal(port.database.prepare('SELECT ? AS n'), first);
    assert.throws(() => first.get(4), {code: 'ClientRequestJournalSqlUnavailable'});
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

test('failed selected native preparation is never cached and never refunds its original attempts', () => {
  const database = new DatabaseSync(':memory:');
  const prepare = database.prepare;
  let preparations = 0;
  database.prepare = function(sql) {preparations++; return Reflect.apply(prepare, this, [sql]);};
  const port = boundedOriginalSql(database, {...primarySqlLimits, maxCalls: 2, maxPreparedStatements: 2}, execution);
  try {
    for (let index = 0; index < 2; index++) assert.throws(() => port.database.prepare('INVALID SQL'), {code: 'ERR_SQLITE_ERROR'});
    assert.equal(preparations, 2);
    assert.throws(() => port.database.prepare('INVALID SQL'), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(preparations, 2);
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

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
    // Startup now admits the complete own usage-schema name vector. The
    // selected namespace remains within its 256-code-unit public field bound.
    const limits = {...execution, maxParameterBytes: 512};
    const journal = openClientRequestJournal(directory, options(limits));
    limits.maxParameterBytes = 100000;
    try {
      const before = state.nativeCalls;
      assert.throws(() => journal.lookupReconciliationState({...ref, namespaceId: '界'.repeat(256)}),
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

test('selected preparation current callback cannot reenter the same Journal before native preparation', async () => {
  const {scratch, directory} = await fixture();
  instrument(state => {
    let journal, armed = false, currentReads = 0, nestedFailure, nestedAttempts = 0;
    journal = openClientRequestJournal(directory, {...options(), primaryCurrent() {
      if (!armed) return;
      // ensureOpen has a current boundary before a SQL operation exists.
      // Target the following consume current, inside actual preparation.
      if (++currentReads === 1) return;
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
      assert.equal(currentReads, 2);
      assert.equal(nestedFailure?.code, 'ClientRequestJournalSqlCleanupPending');
      assert.equal(state.nativeCalls, before + 1);
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(state.nativeCalls, before + 2);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

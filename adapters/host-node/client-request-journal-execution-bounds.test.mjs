import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {existsSync, readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

const primarySqlLimits = {maxPreparedStatements: 1000,
  maxSqlBytes: 65536, maxTotalSqlBytes: 1024 * 1024};
const execution = {maxParameters: 32,
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
const boundedWal = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'boundedJournalWalFrames');
assert.ok(boundedWal);
const boundedOriginalWal = compileFunction([...declarations, boundedWal].map(node =>
  source.slice(node.start, node.end)).join('\n') + '\nreturn boundedJournalWalFrames;', [])();
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

test('exact statement reuse preserves retained limits and rejects oversized operands before the original native method', () => {
  const database = new DatabaseSync(':memory:');
  const prepare = database.prepare;
  let preparations = 0, executions = 0, originalStatement;
  database.prepare = function(sql) {
    assert.equal(this, database); preparations++;
    const statement = Reflect.apply(prepare, this, [sql]);
    const get = statement.get;
    statement.get = function(...values) {executions++; return Reflect.apply(get, this, values);};
    originalStatement ??= statement;
    return statement;
  };
  const port = boundedOriginalSql(database, {...primarySqlLimits, maxPreparedStatements: 2},
    {...execution, maxParameters: 1, maxParameterBytes: 16});
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
    assert.equal(first.get(4).n, 4, 'completed calls create no lifetime issuance debt');
    assert.equal(executions, 4);
    assert.throws(() => first.get(4, 5), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(executions, 4, 'excess parameter count refuses before the original native get');
    assert.throws(() => first.get('界'.repeat(6)), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(executions, 4, 'oversized operands refuse before the original native get');
    assert.equal(first.get(5).n, 5);
    assert.equal(preparations, 2, 'failed execution neither replaces nor enlarges retained statements');
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

test('failed native preparation retains no statement and later success still enforces the original retained limit', () => {
  const database = new DatabaseSync(':memory:');
  const prepare = database.prepare;
  let preparations = 0;
  database.prepare = function(sql) {preparations++; return Reflect.apply(prepare, this, [sql]);};
  const port = boundedOriginalSql(database, {...primarySqlLimits, maxPreparedStatements: 1,
    maxTotalSqlBytes: Buffer.byteLength('SELECT ? AS n')}, execution);
  try {
    for (let index = 0; index < 8; index++) assert.throws(() => port.database.prepare('INVALID SQL'), {code: 'ERR_SQLITE_ERROR'});
    assert.equal(preparations, 8);
    const original = port.database.prepare('SELECT ? AS n');
    assert.equal(original.get(1).n, 1);
    assert.equal(preparations, 9);
    assert.throws(() => port.database.prepare('SELECT ? AS m'), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(preparations, 9);
    assert.strictEqual(port.database.prepare('SELECT ? AS n'), original);
    assert.equal(original.get(2).n, 2);
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

test('cached selected statements preserve current refusal and reentry fences before native use', () => {
  const database = new DatabaseSync(':memory:');
  const prepare = database.prepare;
  let preparations = 0, executions = 0, allowed = true, reenter = false, nested;
  database.prepare = function(sql) {
    preparations++;
    const statement = Reflect.apply(prepare, this, [sql]);
    const get = statement.get;
    statement.get = function(...values) {executions++; return Reflect.apply(get, this, values);};
    return statement;
  };
  const denied = Object.assign(new Error('ExplicitCurrentRefusal'), {code: 'ExplicitCurrentRefusal'});
  const port = boundedOriginalSql(database, primarySqlLimits, execution, () => {
    if (!allowed) throw denied;
    if (reenter) {
      reenter = false;
      try { port.database.prepare('SELECT ? AS n').get(99); }
      catch (error) { nested = error; }
    }
  });
  try {
    const first = port.database.prepare('SELECT ? AS n');
    assert.equal(first.get(0).n, 0);
    allowed = false;
    assert.throws(() => port.database.prepare('SELECT ? AS n'), error => error === denied);
    assert.equal(preparations, 1); assert.equal(executions, 1);
    allowed = true; reenter = true;
    const cached = port.database.prepare('SELECT ? AS n');
    assert.equal(cached, first);
    assert.equal(nested?.code, 'ClientRequestJournalSqlCleanupPending');
    assert.equal(preparations, 1); assert.equal(executions, 1);
    assert.equal(cached.get(1).n, 1);
    allowed = false;
    assert.throws(() => cached.get(2), error => error === denied);
    assert.equal(executions, 2);
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

for (const boundary of ['compilation', 'wal', 'current']) {
  test(`same native rollback remains reachable after ${boundary} work refusal without refilling work`, () => {
    const database = new DatabaseSync(':memory:');
    const exec = database.exec, commands = [];
    database.exec = function(sql) {commands.push(sql); return Reflect.apply(exec, this, [sql]);};
    let allowed = true;
    const refused = Object.assign(new Error('ExplicitCurrentRefusal'), {code: 'ExplicitCurrentRefusal'});
    const primary = new Error('OriginalBodyFailure');
    const wal = boundary === 'wal' ? boundedOriginalWal(54, 0, 4096) : undefined;
    wal?.configure(4096);
    const port = boundedOriginalSql(database,
      {...primarySqlLimits, maxPreparedStatements: boundary === 'compilation' ? 1 : 1000}, execution,
      () => {if (!allowed) throw refused;}, wal);
    if (wal !== undefined) port.prepareWalCheckpoint();
    const transaction = createSqliteTransaction(port.database, 'ClientRequestJournal');
    try {
      assert.throws(() => transaction.run(() => {
        if (boundary === 'compilation') {
          port.database.prepare('SELECT 1 AS retained').get();
          assert.throws(() => port.database.prepare('SELECT 2 AS refused'),
            {code: 'ClientRequestJournalSqlUnavailable'});
        }
        if (boundary === 'wal') {
          port.database.prepare('CREATE TABLE body_work(n INTEGER)').run();
          port.database.prepare('INSERT INTO body_work VALUES (1)').run();
        }
        if (boundary === 'current') allowed = false;
        throw primary;
      }), error => boundary === 'wal' ? error.code === 'ClientRequestJournalWalUnavailable' : error === primary);
      assert.equal(database.isTransaction, false);
      assert.equal(transaction.connectionUsable, true);
      assert.deepEqual(commands, ['BEGIN IMMEDIATE', 'ROLLBACK']);
      assert.throws(() => port.database.prepare(boundary === 'wal'
        ? 'INSERT INTO body_work VALUES (2)' : 'SELECT 2 AS n'), error =>
        boundary === 'compilation' ? error.code === 'ClientRequestJournalSqlUnavailable' :
          boundary === 'wal' ? error.code === 'ClientRequestJournalWalUnavailable' : error === refused);
      assert.deepEqual(commands, ['BEGIN IMMEDIATE', 'ROLLBACK']);
    } finally {
      database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
    }
  });
}

test('rollback cleanup keeps the original native method and synchronous reentry fence', () => {
  const database = new DatabaseSync(':memory:');
  const exec = database.exec;
  let port, nested, rollbacks = 0;
  database.exec = function(sql) {
    assert.equal(this, database);
    if (sql === 'ROLLBACK') {
      rollbacks++;
      try {port.database.prepare('SELECT 9 AS n');} catch (error) {nested = error;}
    }
    return Reflect.apply(exec, this, [sql]);
  };
  port = boundedOriginalSql(database, {...primarySqlLimits, maxPreparedStatements: 1}, execution);
  database.exec = () => {throw new Error('ReplacementMustNotRun');};
  const transaction = createSqliteTransaction(port.database, 'ClientRequestJournal');
  const primary = new Error('OriginalBodyFailure');
  try {
    port.database.prepare('SELECT 1 AS retained').get();
    assert.throws(() => transaction.run(() => {throw primary;}), error => error === primary);
    assert.equal(rollbacks, 1);
    assert.equal(nested?.code, 'ClientRequestJournalSqlCleanupPending');
    assert.equal(database.isTransaction, false);
    assert.throws(() => port.database.prepare('SELECT 2 AS refused'), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(rollbacks, 1);
  } finally {database.close(); port.retireClosedNativeAliases();}
});

test('actual native rollback failure remains original Unknown with no replacement transaction', () => {
  const database = new DatabaseSync(':memory:');
  const exec = database.exec;
  const nativeFailure = new Error('OriginalNativeRollbackFailure');
  const primary = new Error('OriginalBodyFailure');
  let rollbacks = 0;
  database.exec = function(sql) {
    if (sql === 'ROLLBACK') {rollbacks++; throw nativeFailure;}
    return Reflect.apply(exec, this, [sql]);
  };
  const port = boundedOriginalSql(database, primarySqlLimits, execution);
  const transaction = createSqliteTransaction(port.database, 'ClientRequestJournal');
  try {
    assert.throws(() => transaction.run(() => {throw primary;}), error => {
      assert.equal(error.code, 'ClientRequestJournalRollbackFailed');
      assert.equal(error.cause, primary);
      assert.equal(error.rollbackCause, nativeFailure);
      assert.equal(error.outcome, 'unknown');
      assert.equal(error.connectionUsable, false);
      return true;
    });
    assert.equal(database.isTransaction, true);
    assert.equal(rollbacks, 1);
    assert.throws(() => transaction.run(() => {}), {code: 'ClientRequestJournalConnectionUnusable'});
    assert.equal(rollbacks, 1);
  } finally {
    database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();
  }
});

test('owned SELECT metadata reads do not spend live WAL support or change actual WAL bytes', async () => {
  const {scratch} = await fixture();
  const path = join(scratch.path, 'native.sqlite');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode = WAL; CREATE TABLE samples(n INTEGER); INSERT INTO samples VALUES (0)');
  const page = database.prepare('PRAGMA page_size').get().page_size;
  const pages = database.prepare('PRAGMA page_count').get().page_count;
  const sourceBytes = readFileSync(path).length + readFileSync(path + '-wal').length;
  const charge = 2 * pages + Math.ceil(65536 / (page + 24));
  const wal = boundedOriginalWal(Math.floor(sourceBytes / 536) + 3 * charge, sourceBytes, page * pages);
  wal.configure(page);
  const prepare = database.prepare;
  let nativeWrites = 0;
  database.prepare = function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]);
    if (sql.startsWith('INSERT')) {
      const run = statement.run;
      statement.run = function(...values) {nativeWrites++; return Reflect.apply(run, this, values);};
    }
    return statement;
  };
  const port = boundedOriginalSql(database, primarySqlLimits, execution, undefined, wal);
  port.prepareWalCheckpoint();
  try {
    const write = port.database.prepare('INSERT INTO samples VALUES (?)');
    write.run(1);
    const beforeReads = readFileSync(path + '-wal');
    for (let index = 0; index < 32; index++) {
      assert.equal(port.database.prepare(' SELECT n FROM samples WHERE n = ?').get(1).n, 1);
    }
    assert.deepEqual(readFileSync(path + '-wal'), beforeReads);
    write.run(2);
    write.run(3);
    assert.equal(nativeWrites, 3, 'A real native truncation reclaims the old finite WAL extent');
    const afterWrites = readFileSync(path + '-wal');
    assert.deepEqual(port.database.prepare('SELECT n FROM samples ORDER BY n').all().map(row => row.n), [0, 1, 2, 3]);
    assert.deepEqual(readFileSync(path + '-wal'), afterWrites);
  } finally {database.close(); assert.equal(database.isOpen, false); port.retireClosedNativeAliases();}
  scratch.passed();
});

test('a busy real WAL checkpoint preserves its charge until the original reader actually exits', async () => {
  const {scratch} = await fixture();
  const path = join(scratch.path, 'busy.sqlite');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 0; CREATE TABLE samples(n INTEGER); INSERT INTO samples VALUES (0)');
  const page = database.prepare('PRAGMA page_size').get().page_size;
  const pages = database.prepare('PRAGMA page_count').get().page_count;
  const sourceBytes = readFileSync(path).length + readFileSync(path + '-wal').length;
  const charge = 2 * pages + Math.ceil(65536 / (page + 24));
  const wal = boundedOriginalWal(Math.floor(sourceBytes / 536) + 3 * charge, sourceBytes, page * pages);
  wal.configure(page);
  const prepare = database.prepare, checkpoints = [];
  let writes = 0;
  database.prepare = function(sql) {
    const statement = Reflect.apply(prepare, this, [sql]);
    if (sql === 'PRAGMA wal_checkpoint(TRUNCATE)') {
      const get = statement.get;
      statement.get = function() {const result = Reflect.apply(get, this, []); checkpoints.push({...result}); return result;};
    }
    if (sql.startsWith('INSERT')) {
      const run = statement.run;
      statement.run = function(...values) {writes++; return Reflect.apply(run, this, values);};
    }
    return statement;
  };
  const port = boundedOriginalSql(database, primarySqlLimits, execution, undefined, wal);
  port.prepareWalCheckpoint();
  const reader = new DatabaseSync(path);
  try {
    const write = port.database.prepare('INSERT INTO samples VALUES (?)');
    reader.exec('BEGIN');
    assert.equal(reader.prepare('SELECT count(*) AS n FROM samples').get().n, 1);
    write.run(1); write.run(2);
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.throws(() => write.run(3), {code: 'ClientRequestJournalWalUnavailable'});
      assert.equal(writes, 2, 'A busy checkpoint never grants another native write');
    }
    assert.equal(checkpoints.length, 2);
    assert(checkpoints.every(result => result.busy === 1));
    reader.exec('ROLLBACK');
    write.run(3);
    assert.equal(writes, 3);
    assert.deepEqual(checkpoints.at(-1), {busy: 0, log: 0, checkpointed: 0});
    assert.deepEqual(port.database.prepare('SELECT n FROM samples ORDER BY n').all().map(row => row.n), [0, 1, 2, 3]);
  } finally {
    reader.close(); database.close(); port.retireClosedNativeAliases();
    assert.equal(reader.isOpen, false); assert.equal(database.isOpen, false);
  }
  scratch.passed();
});

test('the two original WAL connections fence cross-connection current-callback reentry', () => {
  const databases = [new DatabaseSync(':memory:'), new DatabaseSync(':memory:')];
  const wal = boundedOriginalWal(1000, 0, 4096);
  wal.configure(4096);
  let other, nested;
  const first = boundedOriginalSql(databases[0], primarySqlLimits, execution, () => {
    if (other !== undefined) {
      try {other.database.prepare('SELECT 2 AS n').get();} catch (cause) {nested = cause;}
    }
  }, wal);
  other = boundedOriginalSql(databases[1], primarySqlLimits, execution, undefined, wal);
  first.prepareWalCheckpoint(); other.prepareWalCheckpoint();
  try {
    assert.equal(first.database.prepare('SELECT 1 AS n').get().n, 1);
    assert.equal(nested?.code, 'ClientRequestJournalSqlCleanupPending');
    assert.equal(other.database.prepare('SELECT 2 AS n').get().n, 2);
  } finally {
    databases[0].close(); first.retireClosedNativeAliases();
    databases[1].close(); other.retireClosedNativeAliases();
  }
});

test('WAL reuse needs no new preparation after its original finite statement envelope is full', async () => {
  const {scratch} = await fixture();
  const path = join(scratch.path, 'retained-checkpoint.sqlite');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode = WAL; CREATE TABLE sample(n INTEGER); INSERT INTO sample VALUES (0)');
  const page = database.prepare('PRAGMA page_size').get().page_size;
  const pages = database.prepare('PRAGMA page_count').get().page_count;
  const sourceBytes = readFileSync(path).length + readFileSync(path + '-wal').length;
  const wal = boundedOriginalWal(Math.floor(sourceBytes / 536) +
    4 * (2 * pages + Math.ceil(65536 / (page + 24))), sourceBytes, page * pages);
  wal.configure(page);
  const prepare = database.prepare;
  let preparations = 0, checkpoints = 0;
  database.prepare = function(sql) {
    preparations++;
    const statement = Reflect.apply(prepare, this, [sql]);
    if (sql === 'PRAGMA wal_checkpoint(TRUNCATE)') {
      const get = statement.get;
      statement.get = function() {checkpoints++; return Reflect.apply(get, this, []);};
    }
    return statement;
  };
  const port = boundedOriginalSql(database, {...primarySqlLimits, maxPreparedStatements: 2}, execution, undefined, wal);
  try {
    port.prepareWalCheckpoint();
    const write = port.database.prepare('UPDATE sample SET n = ?');
    for (let index = 1; index <= 100; index++) write.run(index);
    assert.equal(preparations, 2);
    assert(checkpoints > 1);
    assert.throws(() => port.database.prepare('SELECT n FROM sample'), {code: 'ClientRequestJournalSqlUnavailable'});
    assert.equal(preparations, 2);
    assert.equal(Reflect.apply(prepare, database, ['SELECT n FROM sample']).get().n, 100);
  } finally {database.close(); port.retireClosedNativeAliases();}
  scratch.passed();
});

for (const boundary of ['native', 'current']) {
test(`failed ${boundary} checkpoint keeps its original charge and retries only the retained native statement`, async () => {
  const {scratch} = await fixture();
  const path = join(scratch.path, 'partial-checkpoint.sqlite');
  const database = new DatabaseSync(path);
  database.exec('PRAGMA journal_mode = WAL; CREATE TABLE sample(n INTEGER); INSERT INTO sample VALUES (0)');
  const page = database.prepare('PRAGMA page_size').get().page_size;
  const pages = database.prepare('PRAGMA page_count').get().page_count;
  const sourceBytes = readFileSync(path).length + readFileSync(path + '-wal').length;
  const wal = boundedOriginalWal(Math.floor(sourceBytes / 536) +
    3 * (2 * pages + Math.ceil(65536 / (page + 24))), sourceBytes, page * pages);
  wal.configure(page);
  const prepare = database.prepare, original = new Error('OriginalCheckpointFailure');
  let selected = false, currentFailure, preparations = 0, checkpoints = 0, writes = 0;
  database.prepare = function(sql) {
    preparations++;
    const statement = Reflect.apply(prepare, this, [sql]);
    if (sql === 'PRAGMA wal_checkpoint(TRUNCATE)') {
      const get = statement.get;
      statement.get = function() {
        checkpoints++;
        if (selected) {
          selected = false;
          if (boundary === 'native') throw original;
          currentFailure = original;
        }
        return Reflect.apply(get, this, []);
      };
    } else if (sql.startsWith('UPDATE')) {
      const run = statement.run;
      statement.run = function(...values) {writes++; return Reflect.apply(run, this, values);};
    }
    return statement;
  };
  const port = boundedOriginalSql(database, primarySqlLimits, execution, () => {
    if (currentFailure !== undefined) {const cause = currentFailure; currentFailure = undefined; throw cause;}
  }, wal);
  try {
    port.prepareWalCheckpoint();
    const write = port.database.prepare('UPDATE sample SET n = ?');
    write.run(1); write.run(2);
    selected = true;
    assert.throws(() => write.run(3), cause => cause === original);
    assert.equal(writes, 2);
    assert.equal(checkpoints, 1);
    write.run(3);
    assert.equal(checkpoints, 2, 'The failed checkpoint never erased its original charge');
    assert.equal(preparations, 2, 'Retry consumes the same retained native statement');
    assert.equal(writes, 3);
  } finally {database.close(); port.retireClosedNativeAliases();}
  scratch.passed();
});
}

test('WAL terminal work remains available when another write is refused before native acquisition', () => {
  const database = new DatabaseSync(':memory:');
  const wal = boundedOriginalWal(54, 0, 4096);
  wal.configure(4096);
  const port = boundedOriginalSql(database, primarySqlLimits, execution, undefined, wal);
  port.prepareWalCheckpoint();
  try {
    port.database.exec('BEGIN IMMEDIATE');
    port.database.prepare('CREATE TABLE committed(n INTEGER)').run();
    assert.throws(() => port.database.prepare('INSERT INTO committed VALUES (1)'),
      {code: 'ClientRequestJournalWalUnavailable'});
    port.database.exec('COMMIT');
    assert.equal(database.isTransaction, false);
    assert.equal(database.prepare("SELECT count(*) AS n FROM sqlite_master WHERE name = 'committed'").get().n, 1);
    assert.throws(() => port.database.exec('BEGIN IMMEDIATE'), {code: 'ClientRequestJournalWalUnavailable'});
    assert.equal(database.isTransaction, false);
  } finally {database.close(); port.retireClosedNativeAliases();}
});

test('failed native writes keep their WAL write charge and cannot borrow terminal work', () => {
  const database = new DatabaseSync(':memory:');
  database.exec('CREATE TABLE samples(n INTEGER UNIQUE); INSERT INTO samples VALUES (1)');
  const wal = boundedOriginalWal(40, 0, 8192);
  wal.configure(4096);
  const port = boundedOriginalSql(database, primarySqlLimits, execution, undefined, wal);
  port.prepareWalCheckpoint();
  try {
    const write = port.database.prepare('INSERT INTO samples VALUES (?)');
    assert.throws(() => write.run(1), {code: 'ERR_SQLITE_ERROR'});
    assert.throws(() => write.run(2), {code: 'ClientRequestJournalWalUnavailable'});
    assert.equal(database.prepare('SELECT count(*) AS n FROM samples').get().n, 1);
  } finally {database.close(); port.retireClosedNativeAliases();}
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

test('completed cached Journal reads retain one statement and operand refusal leaves the same original usable', async () => {
  const {scratch, directory} = await fixture();
  instrument(state => {
    const journal = openClientRequestJournal(directory, options({...execution, maxParameterBytes: 512}));
    try {
      const calls = state.nativeCalls, prepared = state.preparations.length;
      for (let index = 0; index < 128; index++) {
        assert.equal(journal.lookupReconciliationState(ref), undefined);
      }
      assert.equal(state.nativeCalls, calls + 128);
      assert.equal(state.preparations.length, prepared + 1);
      assert.throws(() => journal.lookupReconciliationState({...ref, namespaceId: '界'.repeat(256)}),
        {code: 'ClientRequestJournalSqlUnavailable'});
      assert.equal(state.nativeCalls, calls + 128);
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(state.nativeCalls, calls + 129);
      assert.equal(state.preparations.length, prepared + 1);
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
    let journal, armed = false, inputRead = false, currentReads = 0, nestedFailure, nestedAttempts = 0;
    const selectedRef = {...ref, get namespaceId() {
      // The facade and ensureOpen current checks precede argument access.
      // Arm once here so the next callback is inside selected preparation,
      // rather than relying on a count of those separate outer checks.
      if (!inputRead) {inputRead = true; armed = true;}
      return ref.namespaceId;
    }};
    journal = openClientRequestJournal(directory, {...options(), primaryCurrent() {
      if (!armed) return;
      currentReads++;
      armed = false;
      nestedAttempts++;
      try { journal.lookupReconciliationState(ref); }
      catch (cause) { nestedFailure = cause; }
    }});
    try {
      const before = state.nativeCalls, prepared = state.preparations.length;
      assert.equal(journal.lookupReconciliationState(selectedRef), undefined);
      assert.equal(inputRead, true);
      assert.equal(nestedAttempts, 1);
      assert.equal(currentReads, 1);
      assert.equal(nestedFailure?.code, 'ClientRequestJournalSqlCleanupPending');
      assert.equal(state.nativeCalls, before + 1);
      assert.equal(state.preparations.length, prepared + 1);
      assert.equal(journal.lookupReconciliationState(ref), undefined);
      assert.equal(state.nativeCalls, before + 2);
    } finally { journal.close(); }
    assert.equal(state.database.isOpen, false);
  });
  scratch.passed();
});

// Completed native calls are not a retained resource; obsolete call ceilings
// cannot silently revive a different admission contract.
test('obsolete statement call ceilings refuse before filesystem acquisition', async () => {
  const {scratch, directory} = await fixture();
  assert.throws(() => openClientRequestJournal(directory,
    options({...execution, maxStatementCalls: 1000})),
    {code: 'InvalidClientRequestJournalConfiguration'});
  assert.equal(existsSync(directory), false);
  scratch.passed();
});

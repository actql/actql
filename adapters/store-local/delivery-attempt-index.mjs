// Private lookup/claim metadata of the existing exclusively owned Store.
// Rows locate admitted originals; they do not authorize Result access.
import {DatabaseSync} from 'node:sqlite';
import {chmod} from 'node:fs/promises';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

const fail = (code, cause) => { throw Object.assign(new Error(code, {cause}), {code}); };
const cid = value => typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value);
const version = 1;

export async function openDeliveryAttemptIndex(path, {create, maxEntries, maxWireBytes}) {
  const database = new DatabaseSync(path, {__proto__: null, open: false,
    readOnly: false, enableForeignKeyConstraints: true, allowExtension: false});
  let closeOriginal, isOpenOriginal, execOriginal, prepareOriginal, transactionState;
  let closed = false, closing = false, mutating = false;
  const exec = sql => Reflect.apply(execOriginal,database,[sql]);
  const prepare = sql => {
    const original = Reflect.apply(prepareOriginal,database,[sql]);
    const get = original.get, run = original.run, all = original.all;
    return Object.freeze({get: (...args) => Reflect.apply(get,original,args),
      run: (...args) => Reflect.apply(run,original,args),
      all: (...args) => Reflect.apply(all,original,args)});
  };
  const captureClose = () => {
    closeOriginal ??= database.close;
    isOpenOriginal ??= Object.getOwnPropertyDescriptor(database, 'isOpen')?.get;
    if (typeof closeOriginal !== 'function' || typeof isOpenOriginal !== 'function') {
      fail('DeliveryAttemptIndexCleanupUnavailable');
    }
  };
  const close = () => {
    if (closed) return true;
    if (closing || mutating) fail('DeliveryAttemptIndexCleanupPending');
    closing = true;
    try {
      captureClose();
      const opened = Reflect.apply(isOpenOriginal, database, []);
      if (typeof opened !== 'boolean') fail('DeliveryAttemptIndexCleanupPending');
      if (opened && (Reflect.apply(closeOriginal, database, []) !== undefined ||
          Reflect.apply(isOpenOriginal, database, []) !== false)) {
        fail('DeliveryAttemptIndexCleanupPending');
      }
      closed = true;
      return true;
    } finally { closing = false; }
  };
  const retainFailure = primary => {
    try { close(); } catch {}
    if (closed) return primary;
    // Opening can also hold a payload/reader duty. Neither close depends on
    // the other; retaining this native wrapper must not hide the first child.
    const child = primary?.cleanupHandle;
    const childStatus = child?.status, childRetry = child?.retry;
    let childPending = child !== undefined, flight;
    const failure = Object.assign(new Error('DeliveryAttemptIndexCleanupPending', {cause: primary}),
      {code: 'DeliveryAttemptIndexCleanupPending', primaryFailure: primary, cleanupPending: true});
    const status = () => Object.freeze({pending: !closed || childPending});
    const retry = () => {
      if (flight !== undefined) return flight;
      flight = Promise.resolve().then(async () => {
        let firstFailure;
        if (childPending) {
          try {
            if (typeof childStatus !== 'function' || typeof childRetry !== 'function') {
              fail('DeliveryAttemptIndexCleanupPending');
            }
            let observation = await Reflect.apply(childStatus,child,[]);
            if (observation?.pending !== false) {
              await Reflect.apply(childRetry,child,[]);
              observation = await Reflect.apply(childStatus,child,[]);
            }
            const pending = observation !== null && typeof observation === 'object'
              ? Object.getOwnPropertyDescriptor(observation,'pending') : undefined;
            if (pending?.value !== false) fail('DeliveryAttemptIndexCleanupPending');
            childPending = false;
          } catch (error) { firstFailure = {error}; }
        }
        try { close(); } catch (error) { firstFailure ??= {error}; }
        failure.cleanupPending = status().pending;
        if (firstFailure !== undefined) throw firstFailure.error;
        return status();
      }).finally(() => { flight = undefined; });
      return flight;
    };
    failure.cleanupHandle = Object.freeze({status, retry});
    return failure;
  };
  try {
    captureClose();
    execOriginal = database.exec;
    prepareOriginal = database.prepare;
    transactionState = Object.getOwnPropertyDescriptor(database,'isTransaction')?.get;
    if (typeof transactionState !== 'function') fail('DeliveryAttemptIndexUnavailable');
    database.open();
    if (create) await chmod(path, 0o600);
    // Match the Store's original durable synchronization boundary on Darwin;
    // FULL alone is not the same as libuv's fullfsync selection there.
    if (create) exec('PRAGMA journal_mode=WAL');
    const mode = prepare('PRAGMA journal_mode').get().journal_mode;
    if (mode !== 'wal') fail('DeliveryAttemptIndexUnavailable');
    exec('PRAGMA synchronous=FULL; PRAGMA fullfsync=ON; PRAGMA checkpoint_fullfsync=ON; PRAGMA mmap_size=0; PRAGMA cache_size=-64; PRAGMA temp_store=MEMORY');
    const transaction = createSqliteTransaction({exec,
      get isTransaction() { return Reflect.apply(transactionState,database,[]); }},
    'DeliveryAttemptIndex');
    const initialize = create && prepare(
      "SELECT name FROM sqlite_schema WHERE type='table' LIMIT 1").get() === undefined;
    if (initialize) transaction.run(() => {
      exec(`CREATE TABLE coverage (
        id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL,
        complete INTEGER NOT NULL CHECK(complete IN (0,1)), entries INTEGER NOT NULL);
        INSERT INTO coverage VALUES(1,1,0,0);
        CREATE TABLE attempts (
          logical_key TEXT PRIMARY KEY, attempt_cid TEXT NOT NULL UNIQUE,
          grant_cid TEXT NOT NULL, run_cid TEXT NOT NULL,
          attempt_wire TEXT NOT NULL, grant_wire TEXT NOT NULL,
          ready INTEGER NOT NULL CHECK(ready IN (0,1))) WITHOUT ROWID;
        CREATE INDEX grant_attempts ON attempts(grant_cid);
        CREATE INDEX pending_attempts ON attempts(ready);
        CREATE INDEX run_attempts ON attempts(run_cid);
        CREATE TABLE grant_uses(grant_cid TEXT PRIMARY KEY, uses INTEGER NOT NULL CHECK(uses>=0)) WITHOUT ROWID;`);
    });
    const state = prepare('SELECT version,complete,entries FROM coverage WHERE id=1');
    const selected = state.get();
    if (selected?.version !== version || ![0,1].includes(selected.complete) ||
        !Number.isSafeInteger(selected.entries) || selected.entries < 0 || selected.entries > maxEntries) {
      fail('DeliveryAttemptIndexUnavailable');
    }
    let complete = selected.complete === 1;
    const lookup = prepare('SELECT * FROM attempts WHERE logical_key=?');
    const pending = prepare('SELECT * FROM attempts WHERE ready=0 LIMIT ?');
    const insert = prepare('INSERT INTO attempts VALUES(?,?,?,?,?,?,?)');
    const uses = prepare('SELECT uses FROM grant_uses WHERE grant_cid=?');
    const addUse = prepare('INSERT INTO grant_uses VALUES(?,1) ON CONFLICT(grant_cid) DO UPDATE SET uses=uses+1');
    const removeUses = prepare('UPDATE grant_uses SET uses=uses-? WHERE grant_cid=?');
    const runUses = prepare('SELECT grant_cid,count(*) AS uses FROM attempts WHERE run_cid=? GROUP BY grant_cid');
    const ready = prepare('UPDATE attempts SET ready=1 WHERE logical_key=? AND attempt_cid=?');
    const remove = prepare('DELETE FROM attempts WHERE run_cid=?');
    const updateCount = prepare('UPDATE coverage SET entries=entries+? WHERE id=1');
    let uncertain = false, uncertainRemoval;
    const run = body => {
      if (mutating) fail('DeliveryAttemptIndexBusy');
      mutating = true;
      try { return transaction.run(body); }
      catch (error) {
        if (error?.outcome === 'unknown') uncertain = true;
        throw error;
      } finally { mutating = false; }
    };
    const requireOpen = () => {
      if (closed || closing) fail('DeliveryAttemptIndexClosed');
      if (mutating) fail('DeliveryAttemptIndexBusy');
      if (uncertain) fail('DeliveryAttemptIndexCommitOutcomeUnknown');
      transaction.assertUsable();
    };
    const requireComplete = () => {
      requireOpen();
      if (!complete) fail('DeliveryAttemptIndexUnavailable');
    };
    const validate = row => {
      if (!row || typeof row.logical_key !== 'string' ||
          Buffer.byteLength(row.logical_key, 'utf8') > 2 * maxWireBytes ||
          ![row.attempt_cid,row.grant_cid,row.run_cid].every(cid) ||
          row.ready !== undefined && ![0,1].includes(row.ready) ||
          ![row.attempt_wire,row.grant_wire].every(wire => typeof wire === 'string' &&
            Buffer.byteLength(wire,'utf8') <= maxWireBytes)) fail('InvalidDeliveryAttemptIndex');
      return row;
    };
    const copy = row => row === undefined ? undefined : Object.freeze({...validate(row)});
    const add = (row, isReady) => {
      validate(row);
      insert.run(row.logical_key,row.attempt_cid,row.grant_cid,row.run_cid,
        row.attempt_wire,row.grant_wire,isReady);
      updateCount.run(1);
      addUse.run(row.grant_cid);
    };
    return Object.freeze({
      needsMigration() { requireOpen(); return !complete; },
      migrate(rows) {
        requireOpen();
        if (complete) fail('DeliveryAttemptIndexAlreadyComplete');
        if (rows.length > maxEntries) fail('DeliveryAttemptIndexLimit');
        run(() => {
          exec('DELETE FROM attempts; DELETE FROM grant_uses; UPDATE coverage SET entries=0 WHERE id=1');
          const keys = new Set();
          for (const row of rows) {
            if (keys.has(row.logical_key)) fail('AmbiguousDeliveryAttemptLookup');
            keys.add(row.logical_key);
            add(row,1);
          }
          exec('UPDATE coverage SET complete=1 WHERE id=1');
        });
        complete = true;
      },
      lookup(key) { requireComplete(); return copy(lookup.get(key)); },
      pending() { requireComplete(); return Object.freeze(pending.all(maxEntries + 1).map(copy)); },
      claim(row,maxUses) {
        requireComplete();
        validate(row);
        const retained = lookup.get(row.logical_key);
        if (retained !== undefined) return Object.freeze({row: copy(retained), created: false});
        return run(() => {
          if ((uses.get(row.grant_cid)?.uses ?? 0) >= maxUses) fail('DeliveryGrantUseLimit');
          if (state.get().entries >= maxEntries) fail('DeliveryAttemptIndexLimit');
          add(row,0);
          return Object.freeze({row: copy({...row,ready:0}), created:true});
        });
      },
      finish(key,attemptCid) {
        requireComplete();
        const row = lookup.get(key);
        if (row === undefined || row.attempt_cid !== attemptCid) fail('DeliveryAttemptConflict');
        if (row.ready === 1) return;
        run(() => {
          if (ready.run(key,attemptCid).changes !== 1) fail('DeliveryAttemptConflict');
        });
      },
      forgetRun(runCid) {
        if (uncertain && uncertainRemoval === runCid) {
          if (closed || closing || mutating || !complete) fail('DeliveryAttemptIndexCleanupPending');
          transaction.assertUsable();
        } else requireComplete();
        try {
          // Retry only this original idempotent metadata removal. A previous
          // COMMIT may already have removed the rows: decrement only the uses
          // still present, never replay a claim or refund an unknown stream.
          run(() => {
            for (const row of runUses.all(runCid)) removeUses.run(row.uses,row.grant_cid);
            updateCount.run(-remove.run(runCid).changes);
          });
          if (uncertainRemoval === runCid) {
            uncertainRemoval = undefined;
            uncertain = false;
          }
        } catch (error) {
          if (error?.outcome === 'unknown') uncertainRemoval = runCid;
          throw error;
        }
      },
      close, retainFailure,
    });
  } catch (primary) { throw retainFailure(primary); }
}

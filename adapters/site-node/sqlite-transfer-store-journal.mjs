import {DatabaseSync} from 'node:sqlite';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  realpathSync,
} from 'node:fs';
import {join} from 'node:path';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;
const equal = (left, right) => left.length === right.length &&
  left.every((value, index) => value === right[index]);

function syncDirectory(path) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
}

function transaction(database, body) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const value = body();
    database.exec('COMMIT');
    return value;
  } catch (error) {
    try { database.exec('ROLLBACK'); }
    catch (rollback) {
      fail('RemoteTransferStoreJournalRollbackFailed', rollback);
    }
    throw error;
  }
}

export function openSqliteTransferStoreJournal(root, {
  maxUses = 100_000,
  maxRequestBytes = 65_536,
  maxManifestBytes = 65_536,
  maxChunks = 4096,
  maxReferencedBytes = 9_007_199_254_740_991n,
} = {}) {
  if (!text(root) || !count(maxUses) || maxUses === 0 ||
      !count(maxRequestBytes) || maxRequestBytes === 0 ||
      !count(maxManifestBytes) || maxManifestBytes === 0 ||
      !count(maxChunks) || typeof maxReferencedBytes !== 'bigint' ||
      maxReferencedBytes < 0n) {
    fail('InvalidRemoteTransferStoreJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'transfer-store-journal.sqlite3');
  const existed = existsSync(path);
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  let closed = false;
  try {
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    database.exec('PRAGMA wal_autocheckpoint = 1000');
    database.exec(`
      CREATE TABLE IF NOT EXISTS journal_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS store_uses (
        use_cid TEXT PRIMARY KEY NOT NULL,
        request_cid TEXT NOT NULL,
        request_json TEXT NOT NULL,
        manifest_cid TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        use_id TEXT NOT NULL,
        destination_site_key TEXT NOT NULL,
        destination_site_generation INTEGER NOT NULL,
        destination_grant_cid TEXT NOT NULL,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        attempt_state INTEGER NOT NULL,
        cleanup_state INTEGER NOT NULL,
        confirmed_chunks INTEGER NOT NULL CHECK (confirmed_chunks >= 0),
        confirmed_bytes TEXT NOT NULL,
        reader_stopped INTEGER NOT NULL,
        destination_receipt_cid TEXT NOT NULL,
        UNIQUE (request_cid, use_id)
      ) STRICT;
    `);
    transaction(database, () => {
      const row = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (row === undefined) {
        database.prepare(`
          INSERT INTO journal_metadata (key, value) VALUES (?, ?)
        `).run('schema_version', 'actql-transfer-store-journal/0.1');
      } else if (row.value !== 'actql-transfer-store-journal/0.1') {
        fail('UnsupportedRemoteTransferStoreJournalVersion');
      }
    });
    if (!existed) syncDirectory(directory);
  } catch (error) {
    database.close();
    throw error;
  }

  const select = database.prepare(
    'SELECT * FROM store_uses WHERE use_cid = ?',
  );
  const selectAll = database.prepare(
    'SELECT * FROM store_uses ORDER BY rowid',
  );
  const total = database.prepare('SELECT COUNT(*) AS count FROM store_uses');
  const insert = database.prepare(`
    INSERT INTO store_uses (
      use_cid,
      request_cid,
      request_json,
      manifest_cid,
      manifest_json,
      use_id,
      destination_site_key,
      destination_site_generation,
      destination_grant_cid,
      revision,
      attempt_state,
      cleanup_state,
      confirmed_chunks,
      confirmed_bytes,
      reader_stopped,
      destination_receipt_cid
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const update = database.prepare(`
    UPDATE store_uses SET
      revision = ?,
      attempt_state = ?,
      cleanup_state = ?,
      confirmed_chunks = ?,
      confirmed_bytes = ?,
      reader_stopped = ?,
      destination_receipt_cid = ?
    WHERE use_cid = ? AND revision = ? AND attempt_state = ?
      AND cleanup_state = ? AND confirmed_chunks = ? AND confirmed_bytes = ?
      AND reader_stopped = ? AND destination_receipt_cid = ?
  `);

  const active = () => {
    if (closed) fail('RemoteTransferStoreJournalClosed');
  };
  const requireControl = control => {
    const storeUse = control?.storeUse;
    if (typeof control?.identity !== 'function' ||
        typeof control?.requestJson !== 'function' ||
        typeof control?.manifestJson !== 'function' ||
        typeof control?.admitJson !== 'function' ||
        storeUse === null || typeof storeUse !== 'object' ||
        typeof storeUse.prepare !== 'function' ||
        typeof storeUse.identity !== 'function' ||
        typeof storeUse.projection !== 'function' ||
        typeof storeUse.open !== 'function' ||
        typeof storeUse.restore !== 'function' ||
        typeof storeUse.recordProjection !== 'function' ||
        typeof storeUse.transitionProjection !== 'function' ||
        typeof storeUse.transitionKey !== 'function' ||
        typeof storeUse.commitTransition !== 'function') {
      fail('MissingRemoteTransferStoreControl');
    }
    return storeUse;
  };
  const state = row => Object.freeze([
    String(row.revision),
    String(row.attempt_state),
    String(row.cleanup_state),
    String(row.confirmed_chunks),
    row.confirmed_bytes,
    String(row.reader_stopped),
    row.destination_receipt_cid,
  ]);
  const restore = (row, control) => {
    const request = control.admitJson(
      row.request_json,
      row.manifest_json,
      row.request_cid,
      row.manifest_cid,
      {maxChunks, maxManifestBytes, maxReferencedBytes},
    );
    const storeUseControl = requireControl(control);
    const storeUse = storeUseControl.prepare(request, row.use_id);
    if (storeUseControl.identity(storeUse) !== row.use_cid) {
      fail('RemoteTransferStoreUseCollision');
    }
    return Object.freeze({
      request,
      storeUse,
      record: storeUseControl.restore(storeUse, state(row)),
    });
  };

  return Object.freeze({
    path,
    accept(request, useId, control) {
      active();
      const storeUseControl = requireControl(control);
      const storeUse = storeUseControl.prepare(request, useId);
      const useCid = storeUseControl.identity(storeUse);
      const projection = storeUseControl.projection(storeUse);
      const requestCid = control.identity(request);
      const requestJson = control.requestJson(request);
      const manifestCid = control.requestProjection(request)[7];
      const manifestJson = control.manifestJson(request);
      if (!Array.isArray(projection) || projection.length !== 6 ||
          projection[0] !== useCid || projection[1] !== requestCid ||
          projection[2] !== useId || !text(manifestCid) ||
          Buffer.byteLength(requestJson, 'utf8') > maxRequestBytes ||
          Buffer.byteLength(manifestJson, 'utf8') > maxManifestBytes) {
        fail('InvalidRemoteTransferStoreUse');
      }
      return transaction(database, () => {
        const existing = select.get(useCid);
        if (existing !== undefined) {
          if (existing.request_cid !== requestCid ||
              existing.request_json !== requestJson ||
              existing.manifest_cid !== manifestCid ||
              existing.manifest_json !== manifestJson ||
              existing.use_id !== useId ||
              existing.destination_site_key !== projection[3] ||
              existing.destination_site_generation !== Number(projection[4]) ||
              existing.destination_grant_cid !== projection[5]) {
            fail('RemoteTransferStoreUseCollision');
          }
          return restore(existing, control);
        }
        if (Number(total.get().count) >= maxUses) {
          fail('RemoteTransferStoreJournalCapacityExceeded');
        }
        const record = storeUseControl.open(storeUse);
        insert.run(
          useCid,
          requestCid,
          requestJson,
          manifestCid,
          manifestJson,
          useId,
          projection[3],
          Number(projection[4]),
          projection[5],
          ...storeUseControl.recordProjection(record),
        );
        return Object.freeze({request, storeUse, record});
      });
    },
    advance(transition, control) {
      active();
      const storeUseControl = requireControl(control);
      const projection = storeUseControl.transitionProjection(transition);
      const key = storeUseControl.transitionKey(transition);
      if (!Array.isArray(projection) || projection.length !== 2 ||
          !projection.every(value => Array.isArray(value) &&
            value.length === 7 &&
            value.every(entry => typeof entry === 'string')) ||
          !Array.isArray(key) || key.length !== 5 ||
          key.some(value => !text(value))) {
        fail('InvalidRemoteTransferStoreTransition');
      }
      transaction(database, () => {
        const row = select.get(key[0]);
        if (row === undefined) fail('RemoteTransferStoreUseMissing');
        const current = state(row);
        if (equal(current, projection[1])) return;
        if (!equal(current, projection[0]) ||
            row.request_cid !== key[1] ||
            row.destination_site_key !== key[2] ||
            row.destination_site_generation !== Number(key[3]) ||
            row.use_id !== key[4]) {
          fail('RemoteTransferStoreStateCollision');
        }
        const result = update.run(
          ...projection[1],
          key[0],
          ...projection[0],
        );
        if (result.changes !== 1) {
          fail('RemoteTransferStoreStateCollision');
        }
      });
      const record = storeUseControl.commitTransition(transition, true);
      if (!equal(storeUseControl.recordProjection(record), projection[1])) {
        fail('RemoteTransferStoreControlDiverged');
      }
      return record;
    },
    recover(control) {
      active();
      requireControl(control);
      return Object.freeze(selectAll.all().map(row => restore(row, control)));
    },
    inspect(storeUse, control) {
      active();
      const storeUseControl = requireControl(control);
      const row = select.get(storeUseControl.identity(storeUse));
      if (row === undefined) return undefined;
      return Object.freeze({
        useCid: row.use_cid,
        requestCid: row.request_cid,
        state: state(row),
      });
    },
    close() {
      if (closed) return false;
      database.close();
      closed = true;
      return true;
    },
  });
}

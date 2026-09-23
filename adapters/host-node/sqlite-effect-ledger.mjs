import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  realpathSync,
} from 'node:fs';
import {dirname, join} from 'node:path';

const fail = code => {
  throw Object.assign(new Error(code), {code});
};
const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/.test(value);
const count = value => Number.isSafeInteger(value) && value >= 0;
const physicalDigest = bytes =>
  createHash('sha256').update(bytes).digest('hex');
const responseDigest = row => createHash('sha256')
  .update('actql-effect-physical-response/0.1\0')
  .update(`${row.logical_item_locator_cid}|${row.dispatch_entry_cid}|`)
  .update(`${row.logical_request_scope_cid}|${row.credential_use_cid}|`)
  .update(`${row.status_code}|`)
  .update(row.response_bytes)
  .digest('hex');

function transaction(database, action) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const result = action();
    database.exec('COMMIT');
    return result;
  } catch (error) {
    try { database.exec('ROLLBACK'); }
    catch { fail('EffectLedgerRollbackFailed'); }
    throw error;
  }
}

// Stores the exact canonical ledger-entry bytes and CAS head pointers. It
// neither constructs CIDs nor decides Effect transitions or retry authority.
export function openSqliteEffectLedger(root, {
  authorityScopeCid,
  maxEntries = 100_000,
  maxEntryBytes = 1_048_576,
  maxResponseBytes = 1_000_000,
  maxStoredBytes = 134_217_728,
} = {}) {
  if (typeof root !== 'string' || root.length === 0 ||
      !cid(authorityScopeCid) || !count(maxEntries) || maxEntries === 0 ||
      !count(maxEntryBytes) || maxEntryBytes === 0 ||
      !count(maxResponseBytes) || maxResponseBytes === 0 ||
      !count(maxStoredBytes) || maxStoredBytes === 0) {
    fail('InvalidEffectLedgerConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'effect-ledger.sqlite3');
  const existed = existsSync(path);
  if (existed && dirname(realpathSync(path)) !== directory) {
    fail('EffectLedgerPathEscapesRoot');
  }
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  let closed = false;
  try {
    database.exec('PRAGMA journal_mode = WAL');
    database.exec('PRAGMA synchronous = FULL');
    transaction(database, () => {
      database.exec(`
        CREATE TABLE IF NOT EXISTS effect_ledger_metadata (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL
        ) STRICT;
        CREATE TABLE IF NOT EXISTS effect_ledger_entries (
          logical_item_locator_cid TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK (revision >= 1),
          entry_cid TEXT NOT NULL UNIQUE,
          entry_json TEXT NOT NULL,
          physical_sha256 TEXT NOT NULL,
          PRIMARY KEY (logical_item_locator_cid, revision)
        ) STRICT;
        CREATE TABLE IF NOT EXISTS effect_ledger_heads (
          logical_item_locator_cid TEXT PRIMARY KEY NOT NULL,
          logical_request_scope_cid TEXT NOT NULL,
          revision INTEGER NOT NULL CHECK (revision >= 1),
          entry_cid TEXT NOT NULL,
          FOREIGN KEY (logical_item_locator_cid, revision)
            REFERENCES effect_ledger_entries
              (logical_item_locator_cid, revision)
        ) STRICT;
        CREATE TABLE IF NOT EXISTS effect_ledger_responses (
          logical_item_locator_cid TEXT NOT NULL,
          dispatch_entry_cid TEXT NOT NULL UNIQUE,
          logical_request_scope_cid TEXT NOT NULL,
          credential_use_cid TEXT NOT NULL,
          status_code INTEGER NOT NULL CHECK
            (status_code >= 100 AND status_code <= 599),
          response_bytes BLOB NOT NULL,
          physical_sha256 TEXT NOT NULL,
          PRIMARY KEY (logical_item_locator_cid, dispatch_entry_cid),
          FOREIGN KEY (dispatch_entry_cid)
            REFERENCES effect_ledger_entries (entry_cid)
        ) STRICT;
      `);
      const metadata = database.prepare(
        'SELECT value FROM effect_ledger_metadata WHERE key = ?',
      );
      const version = metadata.get('schema_version');
      if (version === undefined) {
        const insert = database.prepare(
          'INSERT INTO effect_ledger_metadata (key, value) VALUES (?, ?)',
        );
        insert.run('schema_version', 'actql-effect-ledger-store/0.1');
        insert.run('authority_scope_cid', authorityScopeCid);
      } else if (version.value !== 'actql-effect-ledger-store/0.1' ||
          metadata.get('authority_scope_cid')?.value !== authorityScopeCid) {
        fail('EffectLedgerAuthorityMismatch');
      }
    });
    if (!existed) {
      const descriptor = openSync(directory, 'r');
      try { fsyncSync(descriptor); }
      finally { closeSync(descriptor); }
    }
  } catch (error) {
    database.close();
    throw error;
  }

  const usage = database.prepare(`
    SELECT
      (SELECT COUNT(*) FROM effect_ledger_entries) +
      (SELECT COUNT(*) FROM effect_ledger_responses) AS entries,
      (SELECT COALESCE(SUM(LENGTH(CAST(entry_json AS BLOB))), 0)
        FROM effect_ledger_entries) +
      (SELECT COALESCE(SUM(LENGTH(response_bytes)), 0)
        FROM effect_ledger_responses) AS bytes,
      (SELECT COALESCE(MAX(LENGTH(response_bytes)), 0)
        FROM effect_ledger_responses) AS max_response_bytes
  `);
  const initialUsage = usage.get();
  if (!count(initialUsage.entries) || !count(initialUsage.bytes) ||
      !count(initialUsage.max_response_bytes) ||
      initialUsage.entries > maxEntries ||
      initialUsage.max_response_bytes > maxResponseBytes ||
      initialUsage.bytes > maxStoredBytes) {
    database.close();
    fail('EffectLedgerCapacityExceeded');
  }

  const active = () => { if (closed) fail('EffectLedgerClosed'); };
  const readHead = database.prepare(`
    SELECT logical_request_scope_cid, revision, entry_cid
    FROM effect_ledger_heads WHERE logical_item_locator_cid = ?
  `);
  const readEntry = database.prepare(`
    SELECT logical_item_locator_cid, revision, entry_cid, entry_json,
      physical_sha256 FROM effect_ledger_entries
    WHERE logical_item_locator_cid = ? AND revision = ?
  `);
  const readResponse = database.prepare(`
    SELECT logical_item_locator_cid, dispatch_entry_cid,
      logical_request_scope_cid, credential_use_cid, status_code,
      response_bytes, physical_sha256
    FROM effect_ledger_responses WHERE dispatch_entry_cid = ?
  `);
  const readDispatchEntry = database.prepare(`
    SELECT logical_item_locator_cid FROM effect_ledger_entries
    WHERE entry_cid = ?
  `);
  const materialize = (row, scopeCid) => {
    if (row === undefined) fail('EffectLedgerEntryMissing');
    if (!cid(scopeCid) || !cid(row.entry_cid) || !count(row.revision) ||
        row.revision === 0 || !cid(row.logical_item_locator_cid) ||
        typeof row.entry_json !== 'string' ||
        Buffer.byteLength(row.entry_json) > maxEntryBytes ||
        physicalDigest(row.entry_json) !== row.physical_sha256) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      logicalRequestScopeCid: scopeCid,
      logicalItemLocatorCid: row.logical_item_locator_cid,
      revision: row.revision,
      entryCid: row.entry_cid,
      entryJson: row.entry_json,
    });
  };
  const current = locatorCid => {
    active();
    if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
    const head = readHead.get(locatorCid);
    if (head === undefined) return undefined;
    if (!cid(head.logical_request_scope_cid) ||
        !cid(head.entry_cid) || !count(head.revision) ||
        head.revision === 0) {
      fail('EffectLedgerIntegrityFailed');
    }
    const entry = materialize(
      readEntry.get(locatorCid, head.revision),
      head.logical_request_scope_cid,
    );
    if (entry.entryCid !== head.entry_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    return entry;
  };
  const materializeResponse = row => {
    if (row === undefined) return undefined;
    if (!cid(row.logical_item_locator_cid) ||
        !cid(row.dispatch_entry_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !cid(row.credential_use_cid) ||
        !count(row.status_code) || row.status_code < 100 ||
        row.status_code > 599 ||
        !(row.response_bytes instanceof Uint8Array) ||
        row.response_bytes.byteLength > maxResponseBytes ||
        responseDigest(row) !== row.physical_sha256 ||
        readDispatchEntry.get(row.dispatch_entry_cid)
          ?.logical_item_locator_cid !== row.logical_item_locator_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      logicalItemLocatorCid: row.logical_item_locator_cid,
      dispatchEntryCid: row.dispatch_entry_cid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      credentialUseCid: row.credential_use_cid,
      statusCode: row.status_code,
      responseBytes: Buffer.from(row.response_bytes),
    });
  };
  return Object.freeze({
    current,
    response(dispatchEntryCid) {
      active();
      if (!cid(dispatchEntryCid)) fail('InvalidEffectDispatchEntry');
      return materializeResponse(readResponse.get(dispatchEntryCid));
    },
    recordResponse({logicalRequestScopeCid, logicalItemLocatorCid,
      dispatchEntryCid, credentialUseCid, statusCode, responseBytes}) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(dispatchEntryCid) ||
          !cid(credentialUseCid) || !count(statusCode) ||
          statusCode < 100 || statusCode > 599 ||
          !(responseBytes instanceof Uint8Array) ||
          responseBytes.byteLength > maxResponseBytes) {
        fail('InvalidEffectPhysicalResponse');
      }
      return transaction(database, () => {
        const existing = materializeResponse(
          readResponse.get(dispatchEntryCid));
        if (existing !== undefined) {
          if (existing.logicalRequestScopeCid !== logicalRequestScopeCid ||
              existing.logicalItemLocatorCid !== logicalItemLocatorCid ||
              existing.credentialUseCid !== credentialUseCid ||
              existing.statusCode !== statusCode ||
              !existing.responseBytes.equals(Buffer.from(responseBytes))) {
            fail('EffectPhysicalResponseCollision');
          }
          return Object.freeze({response: existing, created: false});
        }
        const head = readHead.get(logicalItemLocatorCid);
        if (head?.logical_request_scope_cid !== logicalRequestScopeCid ||
            head.entry_cid !== dispatchEntryCid) {
          fail('EffectDispatchNotCurrent');
        }
        const currentUsage = usage.get();
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - responseBytes.byteLength) {
          fail('EffectLedgerCapacityExceeded');
        }
        database.prepare(`
          INSERT INTO effect_ledger_responses (
            logical_item_locator_cid, dispatch_entry_cid,
            logical_request_scope_cid, credential_use_cid,
            status_code, response_bytes, physical_sha256
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(logicalItemLocatorCid, dispatchEntryCid,
          logicalRequestScopeCid, credentialUseCid,
          statusCode, responseBytes, responseDigest({
            logical_item_locator_cid: logicalItemLocatorCid,
            dispatch_entry_cid: dispatchEntryCid,
            logical_request_scope_cid: logicalRequestScopeCid,
            credential_use_cid: credentialUseCid,
            status_code: statusCode,
            response_bytes: responseBytes,
          }));
        return Object.freeze({
          response: materializeResponse(readResponse.get(dispatchEntryCid)),
          created: true,
        });
      });
    },
    append({
      logicalRequestScopeCid,
      logicalItemLocatorCid,
      expectedRevision,
      entryCid,
      entryJson,
    }) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(entryCid) ||
          !count(expectedRevision) ||
          expectedRevision >= Number.MAX_SAFE_INTEGER ||
          typeof entryJson !== 'string' || entryJson.length === 0 ||
          Buffer.byteLength(entryJson) > maxEntryBytes) {
        fail('InvalidEffectLedgerAppend');
      }
      return transaction(database, () => {
        const head = readHead.get(logicalItemLocatorCid);
        const revision = head?.revision ?? 0;
        if (head !== undefined &&
            head.logical_request_scope_cid !== logicalRequestScopeCid) {
          fail('EffectLedgerAuthorityMismatch');
        }
        if (revision === expectedRevision + 1 &&
            head.entry_cid === entryCid) {
          const existing = current(logicalItemLocatorCid);
          if (existing.entryJson !== entryJson) {
            fail('EffectLedgerEntryCollision');
          }
          return Object.freeze({entry: existing, created: false});
        }
        if (revision !== expectedRevision) {
          return Object.freeze({
            entry: current(logicalItemLocatorCid),
            created: false,
            conflict: true,
          });
        }
        const currentUsage = usage.get();
        const entryBytes = Buffer.byteLength(entryJson);
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - entryBytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const nextRevision = revision + 1;
        try {
          database.prepare(`
            INSERT INTO effect_ledger_entries (
              logical_item_locator_cid, revision, entry_cid,
              entry_json, physical_sha256
            ) VALUES (?, ?, ?, ?, ?)
          `).run(logicalItemLocatorCid, nextRevision, entryCid,
            entryJson, physicalDigest(entryJson));
        } catch (error) {
          if (error.code === 'ERR_SQLITE_ERROR' &&
              (error.errcode === 2067 || error.errcode === 1555)) {
            fail('EffectLedgerEntryCollision');
          }
          throw error;
        }
        if (head === undefined) {
          database.prepare(`
            INSERT INTO effect_ledger_heads (
              logical_item_locator_cid, logical_request_scope_cid,
              revision, entry_cid
            ) VALUES (?, ?, ?, ?)
          `).run(logicalItemLocatorCid, logicalRequestScopeCid,
            nextRevision, entryCid);
        } else {
          const result = database.prepare(`
            UPDATE effect_ledger_heads SET revision = ?, entry_cid = ?
            WHERE logical_item_locator_cid = ? AND revision = ?
              AND entry_cid = ?
          `).run(nextRevision, entryCid, logicalItemLocatorCid,
            expectedRevision, head.entry_cid);
          if (result.changes !== 1) fail('EffectLedgerCASFailed');
        }
        return Object.freeze({
          entry: current(logicalItemLocatorCid),
          created: true,
        });
      });
    },
    history(locatorCid, maxRevisions) {
      active();
      if (!cid(locatorCid) || !count(maxRevisions) || maxRevisions === 0 ||
          maxRevisions > maxEntries) {
        fail('InvalidEffectLedgerHistory');
      }
      const head = readHead.get(locatorCid);
      if (head === undefined) return Object.freeze([]);
      if (head.revision > maxRevisions) {
        fail('EffectLedgerHistoryLimitExceeded');
      }
      const rows = database.prepare(`
        SELECT logical_item_locator_cid, revision, entry_cid, entry_json,
          physical_sha256 FROM effect_ledger_entries
        WHERE logical_item_locator_cid = ? ORDER BY revision ASC
      `).all(locatorCid);
      if (rows.length !== head.revision) fail('EffectLedgerIntegrityFailed');
      return Object.freeze(rows.map((row, index) => {
        if (row.revision !== index + 1) fail('EffectLedgerIntegrityFailed');
        return materialize(row, head.logical_request_scope_cid);
      }));
    },
    close() {
      if (closed) return false;
      closed = true;
      database.close();
      return true;
    },
  });
}

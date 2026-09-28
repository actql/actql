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
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
const count = value => Number.isSafeInteger(value) && value >= 0;

function syncDirectory(path) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
}

const equal = (left, right) => left.length === right.length &&
  left.every((value, index) => value === right[index]);

export function openSqliteTransferJournal(root, {
  destinationSiteKey,
  destinationSiteGeneration,
  maxTransfers = 100_000,
  maxRequestBytes = 65_536,
  maxManifestBytes = 65_536,
  maxChunks = 4096,
  maxReferencedBytes = 9_007_199_254_740_991n,
} = {}) {
  if (!text(root) || !text(destinationSiteKey) ||
      !count(destinationSiteGeneration) || !count(maxTransfers) ||
      maxTransfers === 0 || !count(maxRequestBytes) || maxRequestBytes === 0 ||
      !count(maxManifestBytes) || maxManifestBytes === 0 ||
      !count(maxChunks) || typeof maxReferencedBytes !== 'bigint' ||
      maxReferencedBytes < 0n) {
    fail('InvalidRemoteTransferJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'transfer-journal.sqlite3');
  const existed = existsSync(path);
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  const transaction = createSqliteTransaction(database,
    'RemoteTransferJournal');
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
      CREATE TABLE IF NOT EXISTS transfers (
        coordinator_authority TEXT NOT NULL,
        destination_site_key TEXT NOT NULL,
        destination_site_generation INTEGER NOT NULL,
        transfer_attempt TEXT NOT NULL,
        request_cid TEXT NOT NULL,
        request_json TEXT NOT NULL,
        manifest_cid TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        attempt_state INTEGER NOT NULL,
        object_state INTEGER NOT NULL,
        integrity_state INTEGER NOT NULL,
        cleanup_state INTEGER NOT NULL,
        source_access_stopped INTEGER NOT NULL,
        destination_temporary_reclaimed INTEGER NOT NULL,
        object_use_released INTEGER NOT NULL,
        destination_material_available INTEGER NOT NULL,
        PRIMARY KEY (
          coordinator_authority,
          destination_site_key,
          destination_site_generation,
          transfer_attempt
        )
      ) STRICT;
      CREATE TABLE IF NOT EXISTS destination_receipts (
        coordinator_authority TEXT NOT NULL,
        destination_site_key TEXT NOT NULL,
        destination_site_generation INTEGER NOT NULL,
        transfer_attempt TEXT NOT NULL,
        request_cid TEXT NOT NULL,
        receipt_cid TEXT NOT NULL,
        receipt_json TEXT NOT NULL,
        PRIMARY KEY (
          coordinator_authority,
          destination_site_key,
          destination_site_generation,
          transfer_attempt
        ),
        FOREIGN KEY (
          coordinator_authority,
          destination_site_key,
          destination_site_generation,
          transfer_attempt
        ) REFERENCES transfers (
          coordinator_authority,
          destination_site_key,
          destination_site_generation,
          transfer_attempt
        )
      ) STRICT;
    `);
    transaction.run(() => {
      const version = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (version === undefined) {
        const insert = database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        );
        insert.run('schema_version', 'actql-remote-transfer-journal/0.2');
        insert.run('destination_site_key', destinationSiteKey);
        insert.run(
          'destination_site_generation',
          String(destinationSiteGeneration),
        );
      } else if (version.value === 'actql-remote-transfer-journal/0.1') {
        database.prepare(`
          UPDATE journal_metadata SET value = ? WHERE key = ?
        `).run('actql-remote-transfer-journal/0.2', 'schema_version');
      } else if (version.value !== 'actql-remote-transfer-journal/0.2') {
        fail('UnsupportedRemoteTransferJournalVersion');
      }
      const metadata = Object.fromEntries(database.prepare(`
        SELECT key, value FROM journal_metadata
        WHERE key IN (
          'destination_site_key',
          'destination_site_generation'
        )
      `).all().map(row => [row.key, row.value]));
      if (metadata.destination_site_key !== destinationSiteKey ||
          metadata.destination_site_generation !==
            String(destinationSiteGeneration)) {
        fail('RemoteTransferJournalGenerationMismatch');
      }
    });
    if (!existed) syncDirectory(directory);
  } catch (error) {
    database.close();
    throw error;
  }

  const select = database.prepare(`
    SELECT * FROM transfers
    WHERE coordinator_authority = ? AND destination_site_key = ?
      AND destination_site_generation = ? AND transfer_attempt = ?
  `);
  const selectAll = database.prepare(`
    SELECT * FROM transfers ORDER BY rowid
  `);
  const total = database.prepare('SELECT COUNT(*) AS count FROM transfers');
  const insert = database.prepare(`
    INSERT INTO transfers (
      coordinator_authority,
      destination_site_key,
      destination_site_generation,
      transfer_attempt,
      request_cid,
      request_json,
      manifest_cid,
      manifest_json,
      revision,
      attempt_state,
      object_state,
      integrity_state,
      cleanup_state,
      source_access_stopped,
      destination_temporary_reclaimed,
      object_use_released,
      destination_material_available
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const update = database.prepare(`
    UPDATE transfers SET
      revision = ?,
      attempt_state = ?,
      object_state = ?,
      integrity_state = ?,
      cleanup_state = ?,
      source_access_stopped = ?,
      destination_temporary_reclaimed = ?,
      object_use_released = ?,
      destination_material_available = ?
    WHERE coordinator_authority = ? AND destination_site_key = ?
      AND destination_site_generation = ? AND transfer_attempt = ?
      AND revision = ? AND attempt_state = ? AND object_state = ?
      AND integrity_state = ? AND cleanup_state = ?
      AND source_access_stopped = ?
      AND destination_temporary_reclaimed = ?
      AND object_use_released = ? AND destination_material_available = ?
  `);
  const selectDestinationReceipt = database.prepare(`
    SELECT request_cid, receipt_cid, receipt_json
    FROM destination_receipts
    WHERE coordinator_authority = ? AND destination_site_key = ?
      AND destination_site_generation = ? AND transfer_attempt = ?
  `);
  const insertDestinationReceipt = database.prepare(`
    INSERT INTO destination_receipts (
      coordinator_authority,
      destination_site_key,
      destination_site_generation,
      transfer_attempt,
      request_cid,
      receipt_cid,
      receipt_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  const ensureOpen = () => {
    if (closed) fail('RemoteTransferJournalClosed');
    transaction.assertUsable();
  };
  const state = row => Object.freeze([
    row.revision,
    row.attempt_state,
    row.object_state,
    row.integrity_state,
    row.cleanup_state,
    row.source_access_stopped,
    row.destination_temporary_reclaimed,
    row.object_use_released,
    row.destination_material_available,
  ]);
  const checkedKey = (request, control) => {
    const key = control.journalKey(request);
    if (!Array.isArray(key) || key.length !== 4 ||
        key.some(value => !text(value)) ||
        key[1] !== destinationSiteKey ||
        Number(key[2]) !== destinationSiteGeneration) {
      fail('ForeignRemoteTransferJournalSite');
    }
    return Object.freeze({key, generation: Number(key[2])});
  };
  const requireControl = control => {
    if (control === null || typeof control !== 'object' ||
        typeof control.identity !== 'function' ||
        typeof control.requestJson !== 'function' ||
        typeof control.manifestJson !== 'function' ||
        typeof control.admitJson !== 'function' ||
        typeof control.journalKey !== 'function' ||
        typeof control.open !== 'function' ||
        typeof control.restore !== 'function' ||
        typeof control.recordProjection !== 'function' ||
        typeof control.revision !== 'function' ||
        typeof control.transitionProjection !== 'function' ||
        typeof control.transitionKey !== 'function' ||
        typeof control.commitTransition !== 'function') {
      fail('MissingRemoteTransferControl');
    }
  };
  const restore = (row, control) => {
    const request = control.admitJson(
      row.request_json,
      row.manifest_json,
      row.request_cid,
      row.manifest_cid,
      {maxChunks, maxManifestBytes, maxReferencedBytes},
    );
    return Object.freeze({request, record: control.restore(request, state(row))});
  };

  return Object.freeze({
    path,
    accept(request, control) {
      ensureOpen();
      requireControl(control);
      const {key, generation} = checkedKey(request, control);
      const requestCid = control.identity(request);
      const requestJson = control.requestJson(request);
      const manifestJson = control.manifestJson(request);
      const manifestCid = control.requestProjection(request)[7];
      if (!text(requestCid) || !text(requestJson) || !text(manifestJson) ||
          !text(manifestCid) ||
          Buffer.byteLength(requestJson, 'utf8') > maxRequestBytes ||
          Buffer.byteLength(manifestJson, 'utf8') > maxManifestBytes) {
        fail('InvalidRemoteTransferJournalRequest');
      }
      return transaction.run(() => {
        const existing = select.get(key[0], key[1], generation, key[3]);
        if (existing !== undefined) {
          if (existing.request_cid !== requestCid ||
              existing.request_json !== requestJson ||
              existing.manifest_cid !== manifestCid ||
              existing.manifest_json !== manifestJson) {
            fail('RemoteTransferCollision');
          }
          return Object.freeze({...restore(existing, control), created: false});
        }
        const foundTotal = Number(total.get().count);
        if (!count(foundTotal) || foundTotal >= maxTransfers) {
          fail('RemoteTransferJournalCapacityExceeded');
        }
        const record = control.open(request);
        const current = control.recordProjection(record);
        insert.run(
          key[0],
          key[1],
          generation,
          key[3],
          requestCid,
          requestJson,
          manifestCid,
          manifestJson,
          ...current,
        );
        return Object.freeze({request, record, created: true});
      });
    },
    advance(transition, control) {
      ensureOpen();
      requireControl(control);
      const projection = control.transitionProjection(transition);
      if (!Array.isArray(projection) || projection.length !== 2 ||
          !projection.every(value => Array.isArray(value) &&
            value.length === 9 &&
            value.every(Number.isSafeInteger))) {
        fail('InvalidRemoteTransferTransition');
      }
      const key = control.transitionKey(transition);
      const generation = Number(key?.[3]);
      if (!Array.isArray(key) || key.length !== 5 ||
          key.some(value => !text(value)) ||
          key[2] !== destinationSiteKey ||
          generation !== destinationSiteGeneration) {
        fail('ForeignRemoteTransferJournalSite');
      }
      transaction.run(() => {
        const row = select.get(key[1], key[2], generation, key[4]);
        if (row === undefined) fail('RemoteTransferJournalRecordMissing');
        if (row.request_cid !== key[0]) fail('RemoteTransferCollision');
        const current = state(row);
        if (equal(current, projection[1])) return;
        if (!equal(current, projection[0])) {
          fail('RemoteTransferStateCollision');
        }
        const result = update.run(
          ...projection[1],
          key[1],
          key[2],
          generation,
          key[4],
          ...projection[0],
        );
        if (result.changes !== 1) fail('RemoteTransferStateCollision');
      });
      const record = control.commitTransition(transition, true);
      if (!equal(control.recordProjection(record), projection[1]) ||
          control.revision(record) !== projection[1][0]) {
        fail('RemoteTransferJournalControlDiverged');
      }
      return record;
    },
    commitDestinationReceipt(receipt, request, control) {
      ensureOpen();
      requireControl(control);
      if (typeof control.destinationReceiptJson !== 'function' ||
          typeof control.destinationReceiptIdentity !== 'function' ||
          typeof control.admitDestinationReceiptJson !== 'function' ||
          typeof control.destinationReceiptProjection !== 'function' ||
          typeof control.prepareDestinationCommit !== 'function') {
        fail('MissingRemoteTransferControl');
      }
      const {key, generation} = checkedKey(request, control);
      const requestCid = control.identity(request);
      const receiptCid = control.destinationReceiptIdentity(receipt);
      const receiptJson = control.destinationReceiptJson(receipt);
      const projection = control.destinationReceiptProjection(receipt);
      const requestProjection = control.requestProjection(request);
      if (!Array.isArray(projection) || projection.length !== 7 ||
          projection.some(value => !text(value)) ||
          projection[0] !== receiptCid || projection[1] !== requestCid ||
          projection[2] !== key[1] || Number(projection[3]) !== generation ||
          projection[5] !== requestProjection[7] ||
          projection[6] !== requestProjection[11] ||
          Buffer.byteLength(receiptJson, 'utf8') > 4096) {
        fail('InvalidRemoteTransferDestinationReceipt');
      }
      return transaction.run(() => {
        const transfer = select.get(key[0], key[1], generation, key[3]);
        if (transfer === undefined || transfer.request_cid !== requestCid) {
          fail('RemoteTransferJournalRecordMissing');
        }
        const existing = selectDestinationReceipt.get(
          key[0], key[1], generation, key[3],
        );
        if (existing !== undefined) {
          if (existing.request_cid !== requestCid ||
              existing.receipt_cid !== receiptCid ||
              existing.receipt_json !== receiptJson) {
            fail('RemoteTransferDestinationReceiptCollision');
          }
          return control.admitDestinationReceiptJson(
            existing.receipt_json,
            request,
            existing.receipt_cid,
          );
        }
        control.prepareDestinationCommit(restore(transfer, control).record);
        insertDestinationReceipt.run(
          key[0],
          key[1],
          generation,
          key[3],
          requestCid,
          receiptCid,
          receiptJson,
        );
        return control.admitDestinationReceiptJson(
          receiptJson,
          request,
          receiptCid,
        );
      });
    },
    inspectDestinationReceipt(request, control) {
      ensureOpen();
      requireControl(control);
      if (typeof control.admitDestinationReceiptJson !== 'function') {
        fail('MissingRemoteTransferControl');
      }
      const {key, generation} = checkedKey(request, control);
      const row = selectDestinationReceipt.get(
        key[0], key[1], generation, key[3],
      );
      if (row === undefined) return undefined;
      if (row.request_cid !== control.identity(request)) {
        fail('RemoteTransferCollision');
      }
      return control.admitDestinationReceiptJson(
        row.receipt_json,
        request,
        row.receipt_cid,
      );
    },
    recover(control) {
      ensureOpen();
      requireControl(control);
      return Object.freeze(selectAll.all().map(row => restore(row, control)));
    },
    inspect(request, control) {
      ensureOpen();
      requireControl(control);
      const {key, generation} = checkedKey(request, control);
      const row = select.get(key[0], key[1], generation, key[3]);
      if (row === undefined) return undefined;
      if (row.request_cid !== control.identity(request) ||
          row.request_json !== control.requestJson(request)) {
        fail('RemoteTransferCollision');
      }
      return Object.freeze({
        requestCid: row.request_cid,
        manifestCid: row.manifest_cid,
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

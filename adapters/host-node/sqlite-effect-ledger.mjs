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
const batchResponseDigest = (row, members) => {
  const hash = createHash('sha256')
    .update('actql-effect-physical-batch-response/0.1\0')
    .update(`${row.batch_owner_cid}|${row.logical_request_scope_cid}|`)
    .update(`${row.credential_use_cid}|${row.status_code}|`)
    .update(`${members.length}|`);
  for (const member of members) {
    hash.update(`${member.position}|${member.logical_item_locator_cid}|`)
      .update(`${member.dispatch_entry_cid}|`);
  }
  return hash.update(row.response_bytes).digest('hex');
};
const outcomeDigest = row => createHash('sha256')
  .update('actql-effect-physical-outcome/0.1\0')
  .update(`${row.logical_item_locator_cid}|${row.dispatch_entry_cid}|`)
  .update(`${row.logical_request_scope_cid}|`)
  .update(`${row.response_physical_sha256}|${row.outcome_cid}|`)
  .update(row.outcome_json)
  .digest('hex');
const sha256Hex = value => typeof value === 'string' &&
  /^[0-9a-f]{64}$/.test(value);

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
        CREATE TABLE IF NOT EXISTS effect_ledger_batch_responses (
          batch_owner_cid TEXT PRIMARY KEY NOT NULL,
          logical_request_scope_cid TEXT NOT NULL,
          credential_use_cid TEXT NOT NULL,
          status_code INTEGER NOT NULL CHECK
            (status_code >= 100 AND status_code <= 599),
          response_bytes BLOB NOT NULL,
          member_count INTEGER NOT NULL CHECK (member_count >= 1),
          physical_sha256 TEXT NOT NULL
        ) STRICT;
        CREATE TABLE IF NOT EXISTS effect_ledger_batch_members (
          dispatch_entry_cid TEXT PRIMARY KEY NOT NULL,
          batch_owner_cid TEXT NOT NULL,
          position INTEGER NOT NULL CHECK (position >= 0),
          logical_item_locator_cid TEXT NOT NULL,
          UNIQUE (batch_owner_cid, position),
          FOREIGN KEY (batch_owner_cid)
            REFERENCES effect_ledger_batch_responses (batch_owner_cid),
          FOREIGN KEY (dispatch_entry_cid)
            REFERENCES effect_ledger_entries (entry_cid)
        ) STRICT;
        CREATE TABLE IF NOT EXISTS effect_ledger_outcomes (
          dispatch_entry_cid TEXT PRIMARY KEY NOT NULL,
          logical_item_locator_cid TEXT NOT NULL,
          logical_request_scope_cid TEXT NOT NULL,
          response_physical_sha256 TEXT NOT NULL,
          outcome_cid TEXT NOT NULL UNIQUE,
          outcome_json TEXT NOT NULL,
          physical_sha256 TEXT NOT NULL,
          FOREIGN KEY (dispatch_entry_cid)
            REFERENCES effect_ledger_entries (entry_cid)
        ) STRICT;
        CREATE UNIQUE INDEX IF NOT EXISTS effect_response_locator
          ON effect_ledger_responses (logical_item_locator_cid);
        CREATE UNIQUE INDEX IF NOT EXISTS effect_batch_member_locator
          ON effect_ledger_batch_members (logical_item_locator_cid);
        CREATE UNIQUE INDEX IF NOT EXISTS effect_outcome_locator
          ON effect_ledger_outcomes (logical_item_locator_cid);
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
      (SELECT COUNT(*) FROM effect_ledger_responses) +
      (SELECT COUNT(*) FROM effect_ledger_batch_responses) +
      (SELECT COUNT(*) FROM effect_ledger_batch_members) +
      (SELECT COUNT(*) FROM effect_ledger_outcomes) AS entries,
      (SELECT COALESCE(SUM(LENGTH(CAST(entry_json AS BLOB))), 0)
        FROM effect_ledger_entries) +
      (SELECT COALESCE(SUM(LENGTH(response_bytes)), 0)
        FROM effect_ledger_responses) +
      (SELECT COALESCE(SUM(LENGTH(response_bytes)), 0)
        FROM effect_ledger_batch_responses) +
      (SELECT COALESCE(SUM(LENGTH(CAST(outcome_json AS BLOB))), 0)
        FROM effect_ledger_outcomes) AS bytes,
      MAX(
        (SELECT COALESCE(MAX(LENGTH(response_bytes)), 0)
          FROM effect_ledger_responses),
        (SELECT COALESCE(MAX(LENGTH(response_bytes)), 0)
          FROM effect_ledger_batch_responses)
      ) AS max_response_bytes
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
  const readResponseLocators = database.prepare(`
    SELECT dispatch_entry_cid FROM effect_ledger_responses
    WHERE logical_item_locator_cid = ? LIMIT 2
  `);
  const readDispatchEntry = database.prepare(`
    SELECT logical_item_locator_cid FROM effect_ledger_entries
    WHERE entry_cid = ?
  `);
  const readBatchMember = database.prepare(`
    SELECT dispatch_entry_cid, batch_owner_cid, position,
      logical_item_locator_cid FROM effect_ledger_batch_members
    WHERE dispatch_entry_cid = ?
  `);
  const readBatchLocators = database.prepare(`
    SELECT dispatch_entry_cid FROM effect_ledger_batch_members
    WHERE logical_item_locator_cid = ? LIMIT 2
  `);
  const readBatchResponse = database.prepare(`
    SELECT batch_owner_cid, logical_request_scope_cid,
      credential_use_cid, status_code, response_bytes, member_count,
      physical_sha256 FROM effect_ledger_batch_responses
    WHERE batch_owner_cid = ?
  `);
  const readBatchMembers = database.prepare(`
    SELECT dispatch_entry_cid, batch_owner_cid, position,
      logical_item_locator_cid FROM effect_ledger_batch_members
    WHERE batch_owner_cid = ? ORDER BY position ASC
  `);
  const readOutcome = database.prepare(`
    SELECT dispatch_entry_cid, logical_item_locator_cid,
      logical_request_scope_cid, response_physical_sha256,
      outcome_cid, outcome_json, physical_sha256
    FROM effect_ledger_outcomes WHERE dispatch_entry_cid = ?
  `);
  const readOutcomeLocators = database.prepare(`
    SELECT dispatch_entry_cid FROM effect_ledger_outcomes
    WHERE logical_item_locator_cid = ? LIMIT 2
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
      responsePhysicalSha256: row.physical_sha256,
    });
  };
  const dataVersion = database.prepare('PRAGMA data_version');
  const currentDataVersion = () => dataVersion.get().data_version;
  const verifiedBatchResponses = new WeakMap();
  const materializeBatchResponse = dispatchEntryCid => {
    const member = readBatchMember.get(dispatchEntryCid);
    if (member === undefined) return undefined;
    const row = readBatchResponse.get(member.batch_owner_cid);
    const members = readBatchMembers.all(member.batch_owner_cid);
    if (row === undefined || !cid(row.batch_owner_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !cid(row.credential_use_cid) ||
        !count(row.status_code) || row.status_code < 100 ||
        row.status_code > 599 ||
        !(row.response_bytes instanceof Uint8Array) ||
        row.response_bytes.byteLength > maxResponseBytes ||
        !count(row.member_count) || row.member_count === 0 ||
        row.member_count !== members.length ||
        row.batch_owner_cid !== members[0].dispatch_entry_cid ||
        members.some((item, index) =>
          !cid(item.dispatch_entry_cid) ||
          !cid(item.logical_item_locator_cid) ||
          item.batch_owner_cid !== row.batch_owner_cid ||
          item.position !== index ||
          readDispatchEntry.get(item.dispatch_entry_cid)
            ?.logical_item_locator_cid !== item.logical_item_locator_cid) ||
        batchResponseDigest(row, members) !== row.physical_sha256 ||
        readHead.get(member.logical_item_locator_cid)
          ?.logical_request_scope_cid !== row.logical_request_scope_cid) {
      fail('EffectLedgerIntegrityFailed');
    }
    const verified = Object.freeze({
      logicalItemLocatorCid: member.logical_item_locator_cid,
      dispatchEntryCid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      credentialUseCid: row.credential_use_cid,
      statusCode: row.status_code,
      responseBytes: Buffer.from(row.response_bytes),
      responsePhysicalSha256: row.physical_sha256,
      batchOwnerCid: row.batch_owner_cid,
      batchPosition: member.position,
      batchCount: row.member_count,
      batchMembers: Object.freeze(members.map(item => Object.freeze({
        dispatchEntryCid: item.dispatch_entry_cid,
        logicalItemLocatorCid: item.logical_item_locator_cid,
      }))),
    });
    verifiedBatchResponses.set(verified, currentDataVersion());
    return verified;
  };
  const response = dispatchEntryCid => {
    active();
    if (!cid(dispatchEntryCid)) fail('InvalidEffectDispatchEntry');
    const single = materializeResponse(readResponse.get(dispatchEntryCid));
    const batch = materializeBatchResponse(dispatchEntryCid);
    if (single !== undefined && batch !== undefined) {
      fail('EffectLedgerIntegrityFailed');
    }
    return single ?? batch;
  };
  const uniqueLocatorDispatch = (locatorCid, singles, batches) => {
    const rows = [...singles.all(locatorCid), ...batches.all(locatorCid)];
    if (rows.length > 1) fail('EffectLedgerIntegrityFailed');
    return rows[0]?.dispatch_entry_cid;
  };
  const responseForLocator = locatorCid => {
    active();
    if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
    const dispatchCid = uniqueLocatorDispatch(locatorCid,
      readResponseLocators, readBatchLocators);
    return dispatchCid === undefined ? undefined : response(dispatchCid);
  };
  const materializeOutcome = (row, observed) => {
    if (row === undefined) return undefined;
    if (!cid(row.dispatch_entry_cid) ||
        !cid(row.logical_item_locator_cid) ||
        !cid(row.logical_request_scope_cid) ||
        !sha256Hex(row.response_physical_sha256) ||
        !cid(row.outcome_cid) ||
        typeof row.outcome_json !== 'string' ||
        Buffer.byteLength(row.outcome_json) > maxEntryBytes ||
        !sha256Hex(row.physical_sha256) ||
        outcomeDigest(row) !== row.physical_sha256 ||
        !(observed?.batchMembers === undefined
          ? observed?.logicalItemLocatorCid === row.logical_item_locator_cid
          : observed.batchMembers.some(member =>
            member.dispatchEntryCid === row.dispatch_entry_cid &&
            member.logicalItemLocatorCid === row.logical_item_locator_cid)) ||
        observed.logicalRequestScopeCid !== row.logical_request_scope_cid ||
        observed.responsePhysicalSha256 !==
          row.response_physical_sha256) {
      fail('EffectLedgerIntegrityFailed');
    }
    return Object.freeze({
      dispatchEntryCid: row.dispatch_entry_cid,
      logicalItemLocatorCid: row.logical_item_locator_cid,
      logicalRequestScopeCid: row.logical_request_scope_cid,
      responsePhysicalSha256: row.response_physical_sha256,
      outcomeCid: row.outcome_cid,
      outcomeJson: row.outcome_json,
    });
  };
  const outcome = dispatchEntryCid => {
    active();
    if (!cid(dispatchEntryCid)) fail('InvalidEffectDispatchEntry');
    const row = readOutcome.get(dispatchEntryCid);
    return row === undefined ? undefined :
      materializeOutcome(row, response(dispatchEntryCid));
  };
  return Object.freeze({
    current,
    // One SQLite read transaction gives every member the same durable head
    // snapshot. A missing head remains distinct from an unknown dispatch.
    currentSnapshot(locatorCids) {
      active();
      if (!Array.isArray(locatorCids) || locatorCids.length > maxEntries ||
          locatorCids.some(value => !cid(value)) ||
          new Set(locatorCids).size !== locatorCids.length) {
        fail('InvalidEffectLedgerSnapshot');
      }
      database.exec('BEGIN');
      try {
        const rows = Object.freeze(locatorCids.map(current));
        database.exec('COMMIT');
        return rows;
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch { fail('EffectLedgerRollbackFailed'); }
        throw error;
      }
    },
    response,
    dispatchForLocator(locatorCid) {
      active();
      if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
      return uniqueLocatorDispatch(locatorCid,
        readResponseLocators, readBatchLocators);
    },
    responseForLocator,
    outcome,
    outcomeForLocator(locatorCid, batchEvidence) {
      active();
      if (!cid(locatorCid)) fail('InvalidEffectItemLocator');
      if (batchEvidence !== undefined &&
          !verifiedBatchResponses.has(batchEvidence)) {
        fail('EffectPhysicalResponseNotOwned');
      }
      const rows = readOutcomeLocators.all(locatorCid);
      if (rows.length > 1) fail('EffectLedgerIntegrityFailed');
      if (rows.length === 0) return undefined;
      const dispatchEntryCid = rows[0].dispatch_entry_cid;
      const reused = batchEvidence !== undefined &&
        verifiedBatchResponses.get(batchEvidence) === currentDataVersion();
      const observed = reused ? batchEvidence : response(dispatchEntryCid);
      return materializeOutcome(readOutcome.get(dispatchEntryCid), observed);
    },
    // This is physical custody, not semantic outcome admission. The common
    // MoonBit issuer must bind and classify the stored response before use.
    recordOutcome({logicalRequestScopeCid, logicalItemLocatorCid,
      dispatchEntryCid, responsePhysicalSha256, outcomeCid, outcomeJson,
      batchEvidence}) {
      active();
      if (!cid(logicalRequestScopeCid) ||
          !cid(logicalItemLocatorCid) || !cid(dispatchEntryCid) ||
          !sha256Hex(responsePhysicalSha256) || !cid(outcomeCid) ||
          typeof outcomeJson !== 'string' ||
          Buffer.byteLength(outcomeJson) > maxEntryBytes) {
        fail('InvalidEffectPhysicalOutcome');
      }
      if (batchEvidence !== undefined &&
          !verifiedBatchResponses.has(batchEvidence)) {
        fail('EffectPhysicalResponseNotOwned');
      }
      return transaction(database, () => {
        // A write through another connection invalidates the short-lived
        // verified view. Re-read and re-hash before accepting its custody.
        const reused = batchEvidence !== undefined &&
          verifiedBatchResponses.get(batchEvidence) === currentDataVersion();
        const observed = reused ? batchEvidence : response(dispatchEntryCid);
        if (batchEvidence !== undefined &&
            (!batchEvidence.batchMembers.some(member =>
              member.dispatchEntryCid === dispatchEntryCid &&
              member.logicalItemLocatorCid === logicalItemLocatorCid) ||
              readBatchResponse.get(batchEvidence.batchOwnerCid)
                ?.physical_sha256 !== batchEvidence.responsePhysicalSha256)) {
          fail('EffectPhysicalResponseNotOwned');
        }
        if (!(observed?.batchMembers === undefined
          ? observed?.logicalItemLocatorCid === logicalItemLocatorCid
          : observed.batchMembers.some(member =>
            member.dispatchEntryCid === dispatchEntryCid &&
            member.logicalItemLocatorCid === logicalItemLocatorCid)) ||
            observed.logicalRequestScopeCid !== logicalRequestScopeCid ||
            observed.responsePhysicalSha256 !== responsePhysicalSha256) {
          fail('EffectPhysicalResponseNotOwned');
        }
        const existing = batchEvidence === undefined
          ? outcome(dispatchEntryCid)
          : materializeOutcome(readOutcome.get(dispatchEntryCid), observed);
        if (existing !== undefined) {
          if (existing.outcomeCid !== outcomeCid ||
              existing.outcomeJson !== outcomeJson) {
            fail('EffectPhysicalOutcomeCollision');
          }
          return Object.freeze({outcome: existing, created: false});
        }
        const currentUsage = usage.get();
        const bytes = Buffer.byteLength(outcomeJson);
        if (currentUsage.entries >= maxEntries ||
            currentUsage.bytes > maxStoredBytes - bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const record = {
          logical_item_locator_cid: logicalItemLocatorCid,
          dispatch_entry_cid: dispatchEntryCid,
          logical_request_scope_cid: logicalRequestScopeCid,
          response_physical_sha256: responsePhysicalSha256,
          outcome_cid: outcomeCid,
          outcome_json: outcomeJson,
        };
        try {
          database.prepare(`
            INSERT INTO effect_ledger_outcomes (
              dispatch_entry_cid, logical_item_locator_cid,
              logical_request_scope_cid, response_physical_sha256,
              outcome_cid, outcome_json, physical_sha256
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
          `).run(dispatchEntryCid, logicalItemLocatorCid,
            logicalRequestScopeCid, responsePhysicalSha256, outcomeCid,
            outcomeJson, outcomeDigest(record));
        } catch (error) {
          if (error.code === 'ERR_SQLITE_ERROR' &&
              (error.errcode === 2067 || error.errcode === 1555)) {
            fail('EffectPhysicalOutcomeCollision');
          }
          throw error;
        }
        return Object.freeze({outcome: batchEvidence === undefined
          ? outcome(dispatchEntryCid)
          : materializeOutcome(readOutcome.get(dispatchEntryCid), observed),
          created: true});
      });
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
        if (readBatchMember.get(dispatchEntryCid) !== undefined) {
          fail('EffectPhysicalResponseCollision');
        }
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
        const dispatchEntry = readDispatchEntry.get(dispatchEntryCid);
        if (head?.logical_request_scope_cid !== logicalRequestScopeCid ||
            dispatchEntry?.logical_item_locator_cid !==
              logicalItemLocatorCid) {
          fail('EffectDispatchNotOwned');
        }
        const locatorDispatch = uniqueLocatorDispatch(logicalItemLocatorCid,
          readResponseLocators, readBatchLocators);
        if (locatorDispatch !== undefined) {
          fail('EffectPhysicalResponseCollision');
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
    recordBatchResponse({logicalRequestScopeCid, credentialUseCid,
      statusCode, responseBytes, members}) {
      active();
      if (!cid(logicalRequestScopeCid) || !cid(credentialUseCid) ||
          !count(statusCode) || statusCode < 100 || statusCode > 599 ||
          !(responseBytes instanceof Uint8Array) ||
          responseBytes.byteLength > maxResponseBytes ||
          !Array.isArray(members) || members.length === 0 ||
          members.length > maxEntries) {
        fail('InvalidEffectPhysicalBatchResponse');
      }
      const seenLocators = new Set();
      const seenDispatches = new Set();
      const indexed = members.map((member, position) => {
        if (!cid(member?.logicalItemLocatorCid) ||
            !cid(member.dispatchEntryCid) ||
            seenLocators.has(member.logicalItemLocatorCid) ||
            seenDispatches.has(member.dispatchEntryCid)) {
          fail('InvalidEffectPhysicalBatchResponse');
        }
        seenLocators.add(member.logicalItemLocatorCid);
        seenDispatches.add(member.dispatchEntryCid);
        return {
          logical_item_locator_cid: member.logicalItemLocatorCid,
          dispatch_entry_cid: member.dispatchEntryCid,
          position,
        };
      });
      const batchOwnerCid = indexed[0].dispatch_entry_cid;
      return transaction(database, () => {
        const existing = readBatchResponse.get(batchOwnerCid);
        if (existing !== undefined) {
          const stored = materializeBatchResponse(batchOwnerCid);
          const storedMembers = readBatchMembers.all(batchOwnerCid);
          if (stored === undefined ||
              stored.logicalRequestScopeCid !== logicalRequestScopeCid ||
              stored.credentialUseCid !== credentialUseCid ||
              stored.statusCode !== statusCode ||
              !stored.responseBytes.equals(Buffer.from(responseBytes)) ||
              storedMembers.length !== indexed.length ||
              storedMembers.some((member, index) =>
                member.logical_item_locator_cid !==
                  indexed[index].logical_item_locator_cid ||
                member.dispatch_entry_cid !==
                  indexed[index].dispatch_entry_cid)) {
            fail('EffectPhysicalResponseCollision');
          }
          return Object.freeze({created: false, batchOwnerCid});
        }
        for (const member of indexed) {
          if (uniqueLocatorDispatch(member.logical_item_locator_cid,
              readResponseLocators, readBatchLocators) !== undefined ||
              readResponse.get(member.dispatch_entry_cid) !== undefined ||
              readBatchMember.get(member.dispatch_entry_cid) !== undefined ||
              readHead.get(member.logical_item_locator_cid)
                ?.logical_request_scope_cid !== logicalRequestScopeCid ||
              readDispatchEntry.get(member.dispatch_entry_cid)
                ?.logical_item_locator_cid !==
                  member.logical_item_locator_cid) {
            fail('EffectDispatchNotOwned');
          }
        }
        const currentUsage = usage.get();
        if (indexed.length + 1 > maxEntries - currentUsage.entries ||
            responseBytes.byteLength > maxStoredBytes - currentUsage.bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        const record = {
          batch_owner_cid: batchOwnerCid,
          logical_request_scope_cid: logicalRequestScopeCid,
          credential_use_cid: credentialUseCid,
          status_code: statusCode,
          response_bytes: responseBytes,
        };
        database.prepare(`
          INSERT INTO effect_ledger_batch_responses (
            batch_owner_cid, logical_request_scope_cid,
            credential_use_cid, status_code, response_bytes,
            member_count, physical_sha256
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(batchOwnerCid, logicalRequestScopeCid, credentialUseCid,
          statusCode, responseBytes, indexed.length,
          batchResponseDigest(record, indexed));
        const insertMember = database.prepare(`
          INSERT INTO effect_ledger_batch_members (
            dispatch_entry_cid, batch_owner_cid, position,
            logical_item_locator_cid
          ) VALUES (?, ?, ?, ?)
        `);
        for (const member of indexed) {
          insertMember.run(member.dispatch_entry_cid, batchOwnerCid,
            member.position, member.logical_item_locator_cid);
        }
        return Object.freeze({created: true, batchOwnerCid});
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
    // Atomically advance every row covered by one physical request. The
    // caller has already admitted each typed transition in MoonBit; this
    // adapter only fences heads and reserves the aggregate physical storage.
    appendBatch(operations) {
      active();
      if (!Array.isArray(operations) || operations.length === 0 ||
          operations.length > maxEntries) {
        fail('InvalidEffectLedgerBatch');
      }
      const seen = new Set();
      let additionalEntries = 0;
      let additionalBytes = 0;
      for (const operation of operations) {
        if (!cid(operation?.logicalRequestScopeCid) ||
            !cid(operation.logicalItemLocatorCid) ||
            !count(operation.expectedRevision) ||
            operation.expectedRevision >= Number.MAX_SAFE_INTEGER - 1 ||
            (operation.expectedRevision === 0
              ? operation.expectedEntryCid !== null
              : !cid(operation.expectedEntryCid)) ||
            !Array.isArray(operation.entries) ||
            operation.entries.length < 1 || operation.entries.length > 2 ||
            (operation.expectedRevision !== 0 &&
              operation.entries.length !== 1) ||
            seen.has(operation.logicalItemLocatorCid)) {
          fail('InvalidEffectLedgerBatch');
        }
        seen.add(operation.logicalItemLocatorCid);
        for (const entry of operation.entries) {
          if (!cid(entry?.entryCid) || typeof entry.entryJson !== 'string' ||
              entry.entryJson.length === 0 ||
              Buffer.byteLength(entry.entryJson) > maxEntryBytes) {
            fail('InvalidEffectLedgerBatch');
          }
          additionalEntries += 1;
          additionalBytes += Buffer.byteLength(entry.entryJson);
        }
      }
      return transaction(database, () => {
        for (const operation of operations) {
          const head = readHead.get(operation.logicalItemLocatorCid);
          if ((head?.revision ?? 0) !== operation.expectedRevision ||
              (head?.entry_cid ?? null) !== operation.expectedEntryCid) {
            return Object.freeze({created: false, conflict: true});
          }
          if (head !== undefined && head.logical_request_scope_cid !==
              operation.logicalRequestScopeCid) {
            fail('EffectLedgerAuthorityMismatch');
          }
        }
        const currentUsage = usage.get();
        if (additionalEntries > maxEntries - currentUsage.entries ||
            additionalBytes > maxStoredBytes - currentUsage.bytes) {
          fail('EffectLedgerCapacityExceeded');
        }
        for (const operation of operations) {
          let revision = operation.expectedRevision;
          for (const entry of operation.entries) {
            revision += 1;
            database.prepare(`
              INSERT INTO effect_ledger_entries (
                logical_item_locator_cid, revision, entry_cid,
                entry_json, physical_sha256
              ) VALUES (?, ?, ?, ?, ?)
            `).run(operation.logicalItemLocatorCid, revision, entry.entryCid,
              entry.entryJson, physicalDigest(entry.entryJson));
          }
          const lastCid = operation.entries.at(-1).entryCid;
          if (operation.expectedRevision === 0) {
            database.prepare(`
              INSERT INTO effect_ledger_heads (
                logical_item_locator_cid, logical_request_scope_cid,
                revision, entry_cid
              ) VALUES (?, ?, ?, ?)
            `).run(operation.logicalItemLocatorCid,
              operation.logicalRequestScopeCid, revision, lastCid);
          } else {
            const updated = database.prepare(`
              UPDATE effect_ledger_heads SET revision = ?, entry_cid = ?
              WHERE logical_item_locator_cid = ? AND revision = ?
                AND entry_cid = ?
            `).run(revision, lastCid, operation.logicalItemLocatorCid,
              operation.expectedRevision, operation.expectedEntryCid);
            if (updated.changes !== 1) fail('EffectLedgerCASFailed');
          }
        }
        return Object.freeze({created: true, entries: Object.freeze(
          operations.map(operation => current(operation.logicalItemLocatorCid)),
        )});
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

import {createHash} from 'node:crypto';

import type {BinaryLike} from 'node:crypto';
import type {DatabaseSync} from 'node:sqlite';

type StorageDatabase = Pick<DatabaseSync, 'prepare' | 'exec'>;
type UsageTotals = Readonly<{entries: number; bytes: number}>;
type InitialUsage = UsageTotals & Readonly<{max_response_bytes: number}>;
type UsageStamp = UsageTotals & Readonly<{data_version: number}>;
type DataVersion = Pick<UsageStamp, 'data_version'>;

type EntryBinding = Readonly<{
  logical_item_locator_cid: string;
  dispatch_entry_cid: string;
}>;
type ResponseBody = Readonly<{
  logical_request_scope_cid: string;
  credential_use_cid: string;
  status_code: number;
  response_bytes: Uint8Array;
}>;
type BatchResponse = ResponseBody & Readonly<{batch_owner_cid: string}>;
type BatchMember = EntryBinding & Readonly<{position: number}>;
type Outcome = EntryBinding & Readonly<{
  logical_request_scope_cid: string;
  response_physical_sha256: string;
  outcome_cid: string;
  outcome_json: string;
}>;

export const fail: (code: string) => never = code => {
  throw Object.assign(new Error(code), {code});
};
export const cid = (value: unknown): value is string => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/.test(value);
export const count = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) >= 0;
export const physicalDigest = (bytes: BinaryLike) =>
  createHash('sha256').update(bytes).digest('hex');
export const responseDigest = (row: ResponseBody & EntryBinding) => createHash('sha256')
  .update('actql-effect-physical-response/0.1\0')
  .update(`${row.logical_item_locator_cid}|${row.dispatch_entry_cid}|`)
  .update(`${row.logical_request_scope_cid}|${row.credential_use_cid}|`)
  .update(`${row.status_code}|`)
  .update(row.response_bytes)
  .digest('hex');
export const batchResponseDigest = (row: BatchResponse, members: readonly BatchMember[]) => {
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
export const outcomeDigest = (row: Outcome) => createHash('sha256')
  .update('actql-effect-physical-outcome/0.1\0')
  .update(`${row.logical_item_locator_cid}|${row.dispatch_entry_cid}|`)
  .update(`${row.logical_request_scope_cid}|`)
  .update(`${row.response_physical_sha256}|${row.outcome_cid}|`)
  .update(row.outcome_json)
  .digest('hex');
export const sha256Hex = (value: unknown): value is string => typeof value === 'string' &&
  /^[0-9a-f]{64}$/.test(value);

// This connection's transactional projection of the SAME Store facts. TEMP
// rows share commit/rollback with the business mutation and disappear on close;
// no JS usage snapshot or new persistent format/permission owner is introduced.
// SQLite data_version changes on another connection's commit, not our own:
// https://www.sqlite.org/pragma.html#pragma_data_version
function prepareEffectLedgerUsage(database: StorageDatabase) {
  const original = database.prepare(`
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
  const version = database.prepare('PRAGMA main.data_version');
  database.exec(`CREATE TEMP TABLE effect_ledger_usage (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    data_version INTEGER NOT NULL,
    entries INTEGER NOT NULL CHECK (entries >= 0),
    bytes INTEGER NOT NULL CHECK (bytes >= 0)
  ) STRICT`);
  const read = database.prepare(`SELECT data_version, entries, bytes
    FROM temp.effect_ledger_usage WHERE singleton = 1`);
  const retain = database.prepare(`INSERT INTO temp.effect_ledger_usage
    (singleton, data_version, entries, bytes) VALUES (1, ?, ?, ?)
    ON CONFLICT(singleton) DO UPDATE SET data_version = excluded.data_version,
      entries = excluded.entries, bytes = excluded.bytes`);
  const advance = database.prepare(`UPDATE temp.effect_ledger_usage
    SET entries = entries + ?, bytes = bytes + ? + LENGTH(CAST(? AS BLOB))
    WHERE singleton = 1`);
  const refresh = (selectedVersion: number) => {
    const observed = original.get() as InitialUsage;
    retain.run(selectedVersion, observed.entries, observed.bytes);
    return observed;
  };
  const initial = refresh((version.get() as DataVersion).data_version);
  return Object.freeze({initial,
    get() {
      // All calls run inside the existing BEGIN IMMEDIATE. An external writer
      // cannot change this cut between version observation and quota mutation.
      const selectedVersion = (version.get() as DataVersion).data_version;
      const observed = read.get() as UsageStamp | undefined;
      return observed?.data_version === selectedVersion
        ? observed : refresh(selectedVersion);
    },
    add(entries: number, bytes: number, text = '') {
      // Preflight keeps its original encoded-input-byte rule. Retained totals
      // must use SQLite's original native text encoding, just like SUM(CAST),
      // including existing UTF16 databases. No JS byte-model replaces SQLite.
      // Failed inserts/CAS/reads and uncertain COMMIT keep their original
      // rollback/connection semantics, including rollback of this version stamp.
      if (advance.run(entries, bytes, text).changes !== 1) {
        fail('EffectLedgerIntegrityFailed');
      }
    },
  });
}

export function initializeEffectLedgerStorage(database: StorageDatabase, authorityScopeCid: string) {
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
    // Both accepted values are fixed ASCII: schema version and 71-unit
    // authority CID. Two native bytes per unit also covers UTF16 stores.
    // Bound before returning text; oversized metadata keeps the original
    // authority refusal rather than returning an unbounded JavaScript String.
    'SELECT CASE WHEN LENGTH(CAST(value AS BLOB)) <= 142 THEN value ELSE NULL END AS value FROM effect_ledger_metadata WHERE key = ?',
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
  return prepareEffectLedgerUsage(database);
}

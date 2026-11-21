// Physical format and metadata for the original Client Request Journal.
import {randomBytes} from 'node:crypto';
import {closeSync, constants, existsSync, fstatSync, fsyncSync, lstatSync, openSync, readSync,
  writeFileSync, type BigIntStats} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import type {SQLOutputValue} from 'node:sqlite';
import {inspectSqliteSnapshot, inspectJournalDirectory} from '../host-common/sqlite-format-inspection.mjs';
import {inspectHostJournalDirectory} from './host-journal-directory.mjs';
import {inspectClientSourceOperationStorage, sourceOperationTable} from './client-source-operation.mjs';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
// @ts-expect-error TS7016: remove when the original Publication Store is authored in TypeScript.
import {assertOriginalPreparedLocalPublicationStoreOwnership} from '../store-local/publication-store.mjs';
import {applyOriginal, boundedPrimarySql, fail, type JournalSqlConnection} from './client-request-journal-sql.mjs';

type Row = Record<string, SQLOutputValue>;
type OwnerReceipt = Readonly<{token?: unknown; anchor?: Readonly<{identity?: unknown; device?: unknown; inode?: unknown}>}>;
type Usage = Readonly<{n: number; bytes: number; revision?: number}>;
type FormatFeatures = ReturnType<typeof readJournalFormatFeatures>;
type SnapshotOptions = NonNullable<Parameters<typeof inspectSqliteSnapshot>[2]>;
type InspectionSql = ReturnType<typeof boundedPrimarySql>;
type CleanupCarrier = {cleanupHandle?: unknown};
type InspectionFailure = {cleanupPending?: unknown; code?: string} | null | undefined;

// Originals of the existing checked keyed Source on this Request Journal.
// The bound canonical schedule limits each batch; no Scope/Run or physical
// authority is issued by this additive durable index.
export const keyedLookupOriginalTable = `CREATE TABLE client_keyed_lookup_originals (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),
  batch_plan_cid TEXT NOT NULL,
  call_slot_cid TEXT NOT NULL,
  batch_index INTEGER NOT NULL CHECK (batch_index >= 0),
  batch_count INTEGER NOT NULL CHECK (batch_count > 0 AND batch_index < batch_count),
  activation_wire TEXT NOT NULL,
  page_wire TEXT,
  PRIMARY KEY (namespace_id, authority_scope_cid, run_definition_cid, call_slot_cid),
  UNIQUE (namespace_id, authority_scope_cid, run_definition_cid, batch_plan_cid, batch_index)
) STRICT`;

// Optional structural compiler metadata, associated with the existing first
// Plan admission. The old client_requests body/format is never rewritten.
// Table presence and this exact DDL are its additive SQLite format boundary;
// the value itself uses the existing closed Explanation Facts 0.1 family.
export const explanationOriginalTable = `CREATE TABLE client_run_explanation_originals (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  facts_wire TEXT NOT NULL
) STRICT`;
export function inspectExplanationOriginalStorage(database: JournalSqlConnection) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_run_explanation_originals'")
    .get(explanationOriginalTable.length + 1);
  if (row !== undefined && row.sql !== explanationOriginalTable) fail('UnknownClientRequestJournalFormat');
  return row !== undefined;
}

// This is an inspection-work ceiling, not a stored-request limit, format
// rule, physical capacity supplier or permission. Never materialize a complete
// unbounded listing before checking it. Preserve the exact full-name snapshot
// (including unrelated retained entries) for the existing currentness check.
export function journalDirectoryEntries(directory: string, maxInspectionEntries: number, primaryDirectoryInspection: unknown) {
  if (primaryDirectoryInspection !== undefined) {
    return inspectHostJournalDirectory(primaryDirectoryInspection, directory, maxInspectionEntries);
  }
  return inspectJournalDirectory(directory, {maxEntries: maxInspectionEntries,
    unavailableCode: 'ClientRequestJournalInspectionUnavailable',
    cleanupCode: 'ClientRequestJournalInspectionCleanupPending'});
}

// Closed format markers have a fixed exact length. A prior pathname stat
// cannot bound a later readFile allocation: acquire one non-following original
// FD, inspect it, and read only the fixed body plus one byte of lookahead.
// Both classification and the final snapshot fence use this same operation.
export function journalMarkerMatches(path: string, expected: Buffer) {
  let original: number | undefined = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW |
    constants.O_NONBLOCK);
  const originalClose = closeSync;
  let closeAttempted = false;
  const close = () => {
    if (original === undefined || closeAttempted) return;
    // A numeric FD is not a retryable object. Latch before the original
    // syscall: an error/ambiguous return may already have consumed it, and
    // the same integer can now name another Owner's descriptor.
    closeAttempted = true;
    if (applyOriginal(originalClose, undefined, [original]) !== undefined) {
      throw new TypeError('JournalMarkerCleanupPending');
    }
    original = undefined;
  };
  let failed = false, primary, matches = false;
  try {
    const first = fstatSync(original, {bigint: true});
    if (first.isFile() && first.size === BigInt(expected.length)) {
      const body = Buffer.alloc(expected.length), lookahead = Buffer.alloc(1);
      let offset = 0;
      while (offset < body.length) {
        const count = readSync(original, body, offset, body.length - offset, null);
        if (!Number.isSafeInteger(count) || count <= 0 || count > body.length - offset) {
          fail('UnknownClientRequestJournalFormat');
        }
        offset += count;
      }
      const end = readSync(original, lookahead, 0, 1, null);
      const last = fstatSync(original, {bigint: true});
      matches = end === 0 && body.equals(expected) &&
        ['dev', 'ino', 'size', 'mtimeNs', 'ctimeNs'].every(name => first[name as keyof BigIntStats] === last[name as keyof BigIntStats]);
    }
  } catch (cause) { failed = true; primary = cause; }
  try { close(); }
  catch (cause) {
    const observation = Object.freeze({pending: true, closeAttempted: true,
      outcome: 'unknown', errors: Object.freeze([cause])});
    const status = () => {
      void original; void originalClose;
      return observation;
    };
    const carrier = Object.assign(new Error('ClientRequestJournalInspectionCleanupPending',
      {cause: failed ? primary : cause}), {
      code: 'ClientRequestJournalInspectionCleanupPending',
      primaryFailure: failed ? primary : cause,
      // Retry only observes this same unresolved original outcome. Neither
      // EBADF, restoration, Promise settlement nor a reused FD is its ACK.
      cleanupHandle: Object.freeze({status, retry: status}),
    });
    Object.defineProperty(carrier, 'cleanupPending', {get: () => status().pending});
    throw carrier;
  }
  if (failed) throw primary;
  return matches;
}
export function syncDirectory(path: string) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
}

export const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  namespace_id, run_definition_cid, run_definition_wire, revision,
  lookup_expires_at, result_names_json, run_admission_evidence_json`;
export const selectColumns = `${columns}, dispatch_reserved,
  pre_dispatch_failure_confirmed, physical_start_reserved,
  cancellation_requested, physical_close_confirmed,
  observed_terminal_outcome, state_revision, state_observation_key`;
export const journalMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1',
  isolation: 'execution-namespace',
}), 'utf8');
const journalColumns = [...columns.split(',').map(name => name.trim()),
  'dispatch_reserved', 'pre_dispatch_failure_confirmed',
  'physical_start_reserved', 'cancellation_requested',
  'physical_close_confirmed', 'observed_terminal_outcome',
  'reconciliation_state_wire', 'state_revision', 'state_observation_key'].sort();

// One bounded receipt per already admitted Run, committed with its first
// physical-start claim. This is private observation data, not a start/retry
// permission. Old journals/rows without it retain their unknown outcome.
export const localExecutionOwnerTable = `CREATE TABLE client_local_execution_owners (
  namespace_id TEXT NOT NULL,
  authority_scope_cid TEXT NOT NULL,
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_requests(run_definition_cid) ON DELETE CASCADE,
  owner_token TEXT NOT NULL CHECK (length(owner_token) = 36),
  anchor_identity TEXT NOT NULL CHECK (length(anchor_identity) = 36),
  anchor_device TEXT NOT NULL CHECK (length(anchor_device) BETWEEN 1 AND 32),
  anchor_inode TEXT NOT NULL CHECK (length(anchor_inode) BETWEEN 1 AND 32)
) STRICT`;
export function inspectLocalExecutionOwnerStorage(database: JournalSqlConnection) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_local_execution_owners'")
    .get(localExecutionOwnerTable.length + 1);
  if (row !== undefined && row.sql !== localExecutionOwnerTable) {
    fail('UnknownClientRequestJournalFormat');
  }
}
export function validLocalExecutionOwnerReceipt(value: OwnerReceipt | null | undefined) {
  const uuid = (value: unknown) => typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(value);
  const coordinate = (value: unknown) => typeof value === 'string' && /^[0-9]{1,32}$/u.test(value);
  return uuid(value?.token) && uuid(value?.anchor?.identity) &&
    coordinate(value?.anchor?.device) && coordinate(value?.anchor?.inode);
}

// Additive custody in the existing request journal. The original format marker
// is retained byte-for-byte; partially introduced custody is never reset.
export const cancellationMarkerName = 'cancellation-operations-format.json';
export const cancellationMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'cancellation_operations',
}));
const cancellationColumns = ['namespace_id', 'authority_scope_cid', 'cancel_id',
  'run_definition_cid', 'expected_revision', 'intent_fingerprint_cid',
  'outcome_wire', 'outcome_cid'].sort();

// Retain issuance independently of replay rows in this same journal. Losing
// a row cannot turn its consumed identity into a fresh admission opportunity.
export const submissionMarkerName = 'submission-custody-format.json';
export const submissionMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_custody',
}));
function inspectSubmissionStorage(database: JournalSqlConnection, enabled: boolean) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_custody'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_custody)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT singleton, issued_count FROM client_submission_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['issued_count', 'singleton']) ||
      records.length !== 1 || records[0].singleton !== 1 ||
      !Number.isSafeInteger(records[0].issued_count) || (records[0].issued_count as number) < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
  // A lost replay row fences writes, but does not erase surviving individual
  // observations. Reopening must not reset this counter to the remaining rows.
}

export const epochMarkerName = 'submission-epoch-format.json';
export const intentMarkerName = 'submitted-intent-format.json';
export const retirementMarkerName = 'submitted-intent-retirement-format.json';
export const restartMarkerName = 'submission-restart-format.json';
export const nameMarkerName = 'submission-name-format.json';
// Retained only to recognize the earlier two-step derived-metadata adoption.
// New adoption commits its private format transition inside SQLite instead.
export const usageMarkerName = 'submission-usage-format.json';
// These are lookup/quota metadata of the SAME Journal, not admission receipts.
// Native triggers update them in the original row mutation's transaction.
const submissionUsageSources = [
  ['client_submitted_intent_usage','client_submitted_intents','intent_wire'],
  ['client_submission_restart_usage','client_submission_restarts','link_wire'],
];
const submissionUsageTables = submissionUsageSources.map(([name]) => [name,
  `CREATE TABLE ${name} (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991),
    retained_bytes INTEGER NOT NULL CHECK (retained_bytes >= 0 AND retained_bytes <= 9007199254740991),
    revision INTEGER NOT NULL CHECK (revision >= 0 AND revision <= 9007199254740991)
  ) STRICT`]);
// Exact earlier private format, recognized only for same-transaction adoption.
const legacySubmissionUsageTables = submissionUsageTables.map(([name,sql]) => [name,
  sql.replace('retained_bytes <= 9007199254740991','retained_bytes <= 67108864')]);
const submissionUsageTriggers = submissionUsageSources.flatMap(([usage,table,wire]) => [
  [`${usage}_insert`, `CREATE TRIGGER ${usage}_insert AFTER INSERT ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count + 1,
      retained_bytes = retained_bytes + length(CAST(NEW.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
  [`${usage}_delete`, `CREATE TRIGGER ${usage}_delete AFTER DELETE ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count - 1,
      retained_bytes = retained_bytes - length(CAST(OLD.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
  [`${usage}_update`, `CREATE TRIGGER ${usage}_update AFTER UPDATE OF ${wire} ON ${table} BEGIN
    UPDATE ${usage} SET retained_bytes = retained_bytes
      - length(CAST(OLD.${wire} AS BLOB)) + length(CAST(NEW.${wire} AS BLOB)),
      revision = revision + 1 WHERE singleton = 1;
  END`],
]);
const validSubmissionUsage = (row: Row | undefined): row is Row & {retained_bytes: number} => row?.singleton === 1 &&
  Number.isSafeInteger(row.retained_count) && (row.retained_count as number) >= 0 &&
  Number.isSafeInteger(row.retained_bytes) && (row.retained_bytes as number) >= 0 &&
  Number.isSafeInteger(row.revision) && (row.revision as number) >= 0;
const journalRowUsageSources = [
  ['client_request_row_usage','client_requests','client_submission_custody'],
  ['client_cancellation_row_usage','client_cancellation_operations','client_cancellation_custody'],
];
const journalRowUsageTables = journalRowUsageSources.map(([usage]) => [usage,`CREATE TABLE ${usage} (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  retained_count INTEGER NOT NULL CHECK (retained_count >= 0 AND retained_count <= 9007199254740991)
) STRICT`]);
const journalRowUsageTriggers = journalRowUsageSources.flatMap(([usage,table]) => [
  [`${usage}_insert`,`CREATE TRIGGER ${usage}_insert AFTER INSERT ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count + 1 WHERE singleton = 1;
  END`],
  [`${usage}_delete`,`CREATE TRIGGER ${usage}_delete AFTER DELETE ON ${table} BEGIN
    UPDATE ${usage} SET retained_count = retained_count - 1 WHERE singleton = 1;
  END`],
]);
export const validJournalRowUsage = (row: Row | undefined): row is Row & {retained_count: number} => row?.singleton === 1 &&
  Number.isSafeInteger(row.retained_count) && (row.retained_count as number) >= 0;
function inspectJournalRowUsage(database: JournalSqlConnection, version: number) {
  const originals=[...journalRowUsageTables,...journalRowUsageTriggers], names=originals.map(([name])=>name);
  const schema=database.prepare(`SELECT name,sql FROM sqlite_master
    WHERE name IN (${names.map(()=>'?').join(',')})`).all(...names);
  if(version<2 && schema.length===0) return;
  if(![2,3].includes(version) || schema.length!==originals.length || originals.some(([name,sql])=>
    schema.find(row=>row.name===name)?.sql!==sql)) fail('UnknownClientRequestJournalFormat');
  for(const [table] of journalRowUsageTables) {
    if(!validJournalRowUsage(database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get())) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
}
function inspectSubmissionUsageStorage(database: JournalSqlConnection, enabled: boolean) {
  const version = database.prepare('PRAGMA user_version').get()?.user_version;
  if (![0,1,2,3].includes(version as number)) fail('UnknownClientRequestJournalFormat');
  inspectJournalRowUsage(database,version as number);
  const tables = (version as number) < 3 ? legacySubmissionUsageTables : submissionUsageTables;
  const originals = [...tables,...submissionUsageTriggers];
  const names = originals.map(([name]) => name);
  const schema = database.prepare(`SELECT name,sql FROM sqlite_master
    WHERE name IN (${names.map(() => '?').join(',')})`).all(...names);
  if (!enabled && version === 0 && schema.length === 0) return false;
  if (schema.length !== originals.length || originals.some(([name,sql]) =>
    schema.find(row => row.name === name)?.sql !== sql)) fail('UnknownClientRequestJournalFormat');
  for (const [table] of submissionUsageTables) {
    const row = database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get();
    if (!validSubmissionUsage(row) || (version as number) < 3 && row.retained_bytes > 67108864) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
  return true;
}

function createSubmissionUsageStorage(database: JournalSqlConnection, retained: readonly Usage[]) {
  database.exec(submissionUsageTables.map(([,sql]) => `${sql};`).join('\n'));
  for (let i=0;i<submissionUsageTables.length;i++) {
    database.prepare(`INSERT INTO ${submissionUsageTables[i][0]} VALUES(1,?,?,?)`)
      .run(retained[i].n,retained[i].bytes,retained[i].revision ?? 0);
  }
  database.exec(submissionUsageTriggers.map(([,sql]) => `${sql};`).join('\n'));
}
function createJournalRowUsageStorage(database: JournalSqlConnection, retainedRows: readonly number[]) {
  database.exec(journalRowUsageTables.map(([,sql])=>`${sql};`).join('\n'));
  for(let i=0;i<journalRowUsageTables.length;i++) {
    database.prepare(`INSERT INTO ${journalRowUsageTables[i][0]} VALUES(1,?)`).run(retainedRows[i]);
  }
  database.exec(journalRowUsageTriggers.map(([,sql])=>`${sql};`).join('\n'));
}
export function adoptSubmissionUsageStorage(database: JournalSqlConnection, transact: (action: () => void) => void,
  previousMarker: boolean, fresh: boolean, parentByteLimit: number) {
  const version = database.prepare('PRAGMA user_version').get()?.user_version;
  const complete = !fresh && inspectSubmissionUsageStorage(database,previousMarker);
  transact(() => {
    if (fresh) {
      // No previous custody exists; both counters belong to this same creation.
      createSubmissionUsageStorage(database,[{n:0,bytes:0},{n:0,bytes:0}]);
      createJournalRowUsageStorage(database,[0,0]);
      database.exec('PRAGMA user_version=3');
      return;
    }
    const issued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton=1').get()?.issued_count;
    const retired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton=1').get()?.retired_count;
    const restarts = database.prepare('SELECT issued_count FROM client_submission_restart_custody WHERE singleton=1').get()?.issued_count;
    if (![issued,retired,restarts].every(n => Number.isSafeInteger(n) && (n as number) >= 0) ||
        (retired as number) > (issued as number) || (issued as number) - (retired as number) === Number.MAX_SAFE_INTEGER || restarts === Number.MAX_SAFE_INTEGER) {
      fail('ClientSubmittedIntentCustodyLost');
    }
    const counts = [(issued as number)-(retired as number),restarts as number];
    const retained = complete ? submissionUsageTables.map(([table],index) => {
      const row = database.prepare(`SELECT retained_count AS n,retained_bytes AS bytes,revision FROM ${table} WHERE singleton=1`).get();
      if (row?.n !== counts[index] || !Number.isSafeInteger(row!.bytes) || (row!.bytes as number) < 0 ||
          !Number.isSafeInteger(row!.revision) || (row!.revision as number) < 0) fail('ClientSubmittedIntentCustodyLost');
      return row as Usage;
    }) : submissionUsageSources.map(([,table,wire],index) => {
      // Existing one-time legacy census only; adopted histories never rescan.
      const row = database.prepare(`SELECT COUNT(*) AS n,COALESCE(SUM(length(CAST(${wire} AS BLOB))),0) AS bytes
        FROM (SELECT ${wire} FROM ${table} LIMIT ?)` ).get(counts[index]+1)!;
      if (row.n !== counts[index] || !Number.isSafeInteger(row.bytes) || (row.bytes as number) < 0) {
        fail(index === 0 ? 'ClientSubmittedIntentCustodyLost' : 'ClientSubmissionRestartCustodyLost');
      }
      return row as Usage;
    });
    // This is the same selected durable/inspection parent, not another byte
    // allowance per counter. Refuse before DDL or native operand construction.
    if (retained[0].bytes > parentByteLimit || retained[1].bytes > parentByteLimit - retained[0].bytes) {
      fail('ClientSubmittedIntentCapacity');
    }
    if (complete) {
      // Replace ONLY two derived counter rows under the existing transaction.
      // No history, original wire, count, revision, issuance or retirement resets.
      for (const [name] of submissionUsageTriggers) database.exec(`DROP TRIGGER ${name}`);
      for (const [name] of legacySubmissionUsageTables) database.exec(`DROP TABLE ${name}`);
    }
    createSubmissionUsageStorage(database,retained);
    if ((version as number) < 2) {
      // The previous format lacks these indices. Its original issuance bounds
      // this one-time census; v2->v3 keeps the exact existing indices untouched.
      const retainedRows=journalRowUsageSources.map(([,table,custody])=>{
        const issued=database.prepare(`SELECT issued_count FROM ${custody} WHERE singleton=1`).get()?.issued_count;
        if(!Number.isSafeInteger(issued) || (issued as number) <0 || issued===Number.MAX_SAFE_INTEGER) fail('ClientRequestSubmissionCustodyLost');
        const n=database.prepare(`SELECT COUNT(*) AS n FROM (SELECT 1 FROM ${table} LIMIT ?)`).get((issued as number)+1)!.n;
        if(n!==issued) fail(table==='client_requests'?'ClientRequestSubmissionCustodyLost':'ClientRequestJournalCorrupt');
        return n as number;
      });
      createJournalRowUsageStorage(database,retainedRows);
    }
    database.exec('PRAGMA user_version=3');
  });
}

export const nameMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'scoped_submission_names',
}));
export const nameTables = [
  ['client_submission_names', `CREATE TABLE client_submission_names (
          namespace_id TEXT NOT NULL,
          actor_id TEXT NOT NULL,
          name TEXT NOT NULL,
          authority_scope_cid TEXT NOT NULL,
          submission_id TEXT NOT NULL UNIQUE,
          intent_cid TEXT NOT NULL,
          binding_authenticator TEXT NOT NULL,
          PRIMARY KEY (namespace_id, actor_id, name)
        ) STRICT`],
  ['client_submission_name_custody', `CREATE TABLE client_submission_name_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0),
          retained_count INTEGER NOT NULL CHECK (retained_count >= 0)
        ) STRICT`],
];
export const nameTriggers = [
  ['client_submission_name_insert_count', `CREATE TRIGGER client_submission_name_insert_count
    AFTER INSERT ON client_submission_names BEGIN
      UPDATE client_submission_name_custody SET retained_count = retained_count + 1 WHERE singleton = 1;
    END`],
  ['client_submission_name_delete_count', `CREATE TRIGGER client_submission_name_delete_count
    AFTER DELETE ON client_submission_names BEGIN
      UPDATE client_submission_name_custody SET retained_count = retained_count - 1 WHERE singleton = 1;
    END`],
];
export const restartMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_restarts',
}));
export const retirementMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intent_retirement',
}));
export const intentMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intents',
}));
export const epochMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_epochs',
}));
export const maxEpochTtlMs = 7 * 24 * 60 * 60 * 1000;
export const hexKey = (value: unknown) => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value);
export function validEpochAuthority(row: Row | undefined) {
  return row?.singleton === 1 && hexKey(row.authentication_key) &&
    Number.isSafeInteger(row.observed_at) && (row.observed_at as number) >= 0 &&
    (row.observed_at as number) <= Number.MAX_SAFE_INTEGER - maxEpochTtlMs;
}
function inspectEpochStorage(database: JournalSqlConnection, enabled: boolean) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_epoch_authority'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_epoch_authority)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT * FROM client_submission_epoch_authority').all();
  if (JSON.stringify(fields) !== JSON.stringify(['authentication_key', 'observed_at', 'singleton']) ||
      records.length !== 1 || !validEpochAuthority(records[0])) {
    fail('UnknownClientRequestJournalFormat');
  }
}
function inspectIntentStorage(database: JournalSqlConnection, enabled: boolean) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submitted_intents', 'client_submitted_intent_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intents)').all()
    .map(field => field.name).sort();
  const expected = ['authority_scope_cid', 'submission_id', 'nonce', 'epoch_wire',
    'intent_cid', 'intent_wire', 'accepted_at', 'phase', 'outcome_wire', 'revision'].sort();
  const custody = database.prepare('SELECT singleton, issued_count FROM client_submitted_intent_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(expected) || custody.length !== 1 ||
      custody[0].singleton !== 1 || !Number.isSafeInteger(custody[0].issued_count) ||
    (custody[0].issued_count as number) < 0) fail('UnknownClientRequestJournalFormat');
}

function inspectIntentRetirementStorage(database: JournalSqlConnection, enabled: boolean) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submitted_intent_retirement'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intent_retirement)')
    .all().map(field => field.name).sort();
  const rows = database.prepare('SELECT * FROM client_submitted_intent_retirement').all();
  if (JSON.stringify(fields) !== JSON.stringify(['retired_count', 'singleton']) ||
      rows.length !== 1 || rows[0].singleton !== 1 ||
      !Number.isSafeInteger(rows[0].retired_count) || (rows[0].retired_count as number) < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectRestartStorage(database: JournalSqlConnection, enabled: boolean) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_restarts', 'client_submission_restart_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_restarts)').all()
    .map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_submission_restart_custody)').all()
    .map(field => field.name).sort();
  const custody = database.prepare('SELECT * FROM client_submission_restart_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['fresh_submission_id', 'original_submission_id', 'link_wire'].sort()) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || (custody[0].issued_count as number) < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectNameStorage(database: JournalSqlConnection, enabled: boolean) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_names', 'client_submission_name_custody')`).all();
  if (!enabled && names.length === 0) return;
  if (!enabled || names.length !== 2) fail('UnknownClientRequestJournalFormat');
  for (const [name, sql] of nameTables) {
    if (database.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?")
      .get(name)?.sql !== sql) fail('UnknownClientRequestJournalFormat');
  }
  const fields = database.prepare('PRAGMA table_info(client_submission_names)').all()
    .map(field => field.name).sort();
  const counters = database.prepare('PRAGMA table_info(client_submission_name_custody)').all()
    .map(field => field.name).sort();
  const custody = database.prepare('SELECT * FROM client_submission_name_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['namespace_id', 'actor_id', 'name',
    'authority_scope_cid', 'submission_id', 'intent_cid', 'binding_authenticator'].sort()) ||
      JSON.stringify(counters) !== JSON.stringify(['issued_count', 'retained_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || (custody[0].issued_count as number) < 0 ||
      !Number.isSafeInteger(custody[0].retained_count) || (custody[0].retained_count as number) < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
  for (const [name, sql] of nameTriggers) {
    if (database.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = ?")
      .get(name)?.sql !== sql) fail('UnknownClientRequestJournalFormat');
  }
  // Exact schema/triggers and the original singleton are checked here;
  // target resolution and mutation check retained vs issued custody. Ordinary
  // open does not recount unrelated historical name rows.
}

function inspectCancellationStorage(database: JournalSqlConnection, enabled: boolean) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_cancellation_operations', 'client_cancellation_custody')`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_cancellation_operations)')
    .all().map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_cancellation_custody)')
    .all().map(field => field.name).sort();
  const indexed=[2,3].includes(database.prepare('PRAGMA user_version').get()!.user_version as number);
  const usage=indexed?database.prepare('SELECT * FROM client_cancellation_row_usage WHERE singleton=1').get():undefined;
  if(indexed && !validJournalRowUsage(usage)) fail('UnknownClientRequestJournalFormat');
  // A legacy database is counted once by the bounded adoption transaction,
  // not once in this copy and again in the original. Adopted metadata is O(1).
  const records = indexed ? usage!.retained_count : undefined;
  const custody = database.prepare('SELECT singleton, issued_count FROM client_cancellation_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(cancellationColumns) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || (custody[0].issued_count as number) < 0 ||
      indexed && custody[0].issued_count !== records) fail('UnknownClientRequestJournalFormat');
}

export function readJournalFormatFeatures(directory: string, entries: readonly string[]) {
  const featurePath = join(directory, cancellationMarkerName);
  const enabled = entries.includes(cancellationMarkerName);
  if (enabled && (!lstatSync(featurePath).isFile() ||
      !journalMarkerMatches(featurePath, cancellationMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const submissionPath = join(directory, submissionMarkerName);
  const submissionEnabled = entries.includes(submissionMarkerName);
  if (submissionEnabled && (!lstatSync(submissionPath).isFile() ||
      !journalMarkerMatches(submissionPath, submissionMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const epochPath = join(directory, epochMarkerName);
  const epochEnabled = entries.includes(epochMarkerName);
  if (epochEnabled && (!lstatSync(epochPath).isFile() ||
      !journalMarkerMatches(epochPath, epochMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const intentPath = join(directory, intentMarkerName);
  const intentEnabled = entries.includes(intentMarkerName);
  if (intentEnabled && (!lstatSync(intentPath).isFile() ||
      !journalMarkerMatches(intentPath, intentMarker))) fail('UnknownClientRequestJournalFormat');
  const retirementPath = join(directory, retirementMarkerName);
  const retirementEnabled = entries.includes(retirementMarkerName);
  if (retirementEnabled && (!intentEnabled || !lstatSync(retirementPath).isFile() ||
      !journalMarkerMatches(retirementPath, retirementMarker))) fail('UnknownClientRequestJournalFormat');
  const restartPath = join(directory, restartMarkerName);
  const restartEnabled = entries.includes(restartMarkerName);
  if (restartEnabled && (!intentEnabled || !lstatSync(restartPath).isFile() ||
      !journalMarkerMatches(restartPath, restartMarker))) fail('UnknownClientRequestJournalFormat');
  const namePath = join(directory, nameMarkerName);
  const nameEnabled = entries.includes(nameMarkerName);
  if (nameEnabled && (!intentEnabled || !lstatSync(namePath).isFile() ||
      !journalMarkerMatches(namePath, nameMarker))) fail('UnknownClientRequestJournalFormat');
  const usagePath = join(directory, usageMarkerName);
  const usageEnabled = entries.includes(usageMarkerName);
  if (usageEnabled && (!intentEnabled || !retirementEnabled || !restartEnabled ||
      !lstatSync(usagePath).isFile())) {
    fail('UnknownClientRequestJournalFormat');
  }
  return Object.freeze({enabled, submissionEnabled, epochEnabled, intentEnabled,
    retirementEnabled, restartEnabled, nameEnabled, usageEnabled,
    featurePath, submissionPath, epochPath, intentPath, retirementPath, restartPath, namePath});
}

export function inspectJournalNativeStorage(database: JournalSqlConnection, features: FormatFeatures) {
  const fields = database.prepare('PRAGMA table_info(client_requests)')
    .all().map(field => field.name).sort();
  if (JSON.stringify(fields) !== JSON.stringify(journalColumns)) {
    fail('UnknownClientRequestJournalFormat');
  }
  inspectCancellationStorage(database, features.enabled);
  inspectSubmissionStorage(database, features.submissionEnabled);
  inspectEpochStorage(database, features.epochEnabled);
  inspectIntentStorage(database, features.intentEnabled);
  inspectIntentRetirementStorage(database, features.retirementEnabled);
  inspectRestartStorage(database, features.restartEnabled);
  inspectNameStorage(database, features.nameEnabled);
  inspectSubmissionUsageStorage(database, features.usageEnabled);
  inspectClientSourceOperationStorage(database);
  inspectLocalExecutionOwnerStorage(database);
}

// Unowned/standalone inspection still needs an isolated snapshot: merely
// opening a read-only connection can create SHM beside an unclassified file.
export function inspectJournalSnapshot(directory: string, databasePath: string, markerPath: string,
  maxInspectionEntries: number, maxInspectionBytes: number, primarySqlLimits: Parameters<typeof boundedPrimarySql>[1] | undefined,
  primaryExecutionLimits: Parameters<typeof boundedPrimarySql>[2], primarySchemaLimits: unknown, primarySchemaSqlSupport: unknown,
  primaryCurrent: SnapshotOptions['assertCurrent'], primaryDirectoryInspection: unknown, inspectionTemporaryDirectory: string | undefined) {
  const entries = journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection);
  const features = readJournalFormatFeatures(directory, entries);
  const {enabled, submissionEnabled, epochEnabled, intentEnabled,
    retirementEnabled, restartEnabled, nameEnabled,
    featurePath, submissionPath, epochPath, intentPath, retirementPath, restartPath, namePath} = features;
  let inspectionSql: InspectionSql | undefined;
  try {
  inspectSqliteSnapshot(databasePath, originalDatabase => {
    // The isolated primary-Journal inspection precedes the writable original.
    // Apply the same selected support conditions to its owned metadata reads;
    // no native All() vector may precede the bounded cursor path.
    if (primaryExecutionLimits !== undefined) {
      inspectionSql = boundedPrimarySql(originalDatabase, primarySqlLimits!, primaryExecutionLimits, primaryCurrent);
    }
    const database = inspectionSql?.database ?? originalDatabase;
    inspectJournalNativeStorage(database, features);
  }, {code: 'UnknownClientRequestJournalFormat', maxSourceBytes: maxInspectionBytes,
    unavailableCode: 'ClientRequestJournalInspectionUnavailable',
    schemaReadLimits: primarySchemaLimits,
    schemaSqlSupport: primarySchemaSqlSupport,
    assertCurrent: primaryCurrent,
    temporaryDirectory: inspectionTemporaryDirectory,
    validateSource: () => journalMarkerMatches(markerPath, journalMarker) &&
      (!enabled || journalMarkerMatches(featurePath, cancellationMarker)) &&
      (!submissionEnabled || journalMarkerMatches(submissionPath, submissionMarker)) &&
      (!epochEnabled || journalMarkerMatches(epochPath, epochMarker)) &&
      (!intentEnabled || journalMarkerMatches(intentPath, intentMarker)) &&
      (!retirementEnabled || journalMarkerMatches(retirementPath, retirementMarker)) &&
      (!restartEnabled || journalMarkerMatches(restartPath, restartMarker)) &&
      (!nameEnabled || journalMarkerMatches(namePath, nameMarker)) &&
      JSON.stringify(journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection)) === JSON.stringify(entries)});
  } catch (error) {
    if (inspectionSql !== undefined) {
      const handleField = error !== null && typeof error === 'object'
        ? Object.getOwnPropertyDescriptor(error, 'cleanupHandle') : undefined;
      const handle = handleField !== undefined && Object.hasOwn(handleField, 'value')
        ? handleField.value : undefined;
      if (handle === undefined) {
        // inspectSqliteSnapshot forwards a primary error without a carrier
        // only after its actual database/FD/copy cleanup has completed.
        inspectionSql.retireClosedNativeAliases();
      } else {
        const status = Object.getOwnPropertyDescriptor(handle, 'status')?.value;
        const retry = Object.getOwnPropertyDescriptor(handle, 'retry')?.value;
        const observe = (value: unknown) => {
          const pending = value !== null && typeof value === 'object'
            ? Object.getOwnPropertyDescriptor(value, 'pending') : undefined;
          if (pending !== undefined && Object.hasOwn(pending, 'value') && pending.value === false) {
            inspectionSql!.retireClosedNativeAliases();
          }
          return value;
        };
        // Retain this same selected statement/cursor custody beside the
        // original copy/FD cleanup. No replacement close or synthetic ACK.
        (error as CleanupCarrier).cleanupHandle = Object.freeze({
          status: () => observe(applyOriginal(status, handle, [])),
          retry: () => observe(applyOriginal(retry, handle, [])),
        });
      }
    }
    throw error;
  }
  inspectionSql?.retireClosedNativeAliases();
}

export function admitJournalDirectory(directory: string, maxInspectionEntries: number,
  maxInspectionBytes: number, primarySqlLimits: Parameters<typeof inspectJournalSnapshot>[5],
  primaryExecutionLimits: Parameters<typeof inspectJournalSnapshot>[6], primarySchemaLimits: unknown,
  primarySchemaSqlSupport: unknown, primaryCurrent: SnapshotOptions['assertCurrent'],
  primaryDirectoryInspection: unknown, inspectionTemporaryDirectory: string | undefined,
  ownedOriginal: unknown): false | true | FormatFeatures {
  if (!existsSync(directory)) return false;
  const state = lstatSync(directory);
  if (!state.isDirectory() || state.isSymbolicLink()) {
    fail('UnknownClientRequestJournalFormat');
  }
  const entries = journalDirectoryEntries(directory, maxInspectionEntries, primaryDirectoryInspection);
  if (entries.length === 0) return false;
  const markerPath = join(directory, 'journal-format.json');
  if (!entries.includes('journal-format.json')) {
    fail(entries.includes('client-requests.sqlite3') ?
      'LegacyClientRequestJournalFormat' :
      'UnknownClientRequestJournalFormat');
  }
  if (!entries.includes('client-requests.sqlite3') ||
      !lstatSync(markerPath).isFile() ||
      !journalMarkerMatches(markerPath, journalMarker)) {
    fail('UnknownClientRequestJournalFormat');
  }
  const databasePath = join(directory, 'client-requests.sqlite3');
  if (!lstatSync(databasePath).isFile()) {
    fail('UnknownClientRequestJournalFormat');
  }
  if (ownedOriginal !== undefined) {
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
    if (existsSync(`${databasePath}-journal`)) fail('UnknownClientRequestJournalFormat');
    let bytes = 0n;
    for (const path of [databasePath, `${databasePath}-wal`, `${databasePath}-shm`]) {
      if (!existsSync(path)) continue;
      const original = lstatSync(path, {bigint: true});
      if (!original.isFile() || original.isSymbolicLink()) fail('UnknownClientRequestJournalFormat');
      if (path.endsWith('-shm')) continue;
      bytes += original.size;
      if (bytes > BigInt(maxInspectionBytes)) fail('ClientRequestJournalInspectionUnavailable');
    }
    return readJournalFormatFeatures(directory, entries);
  }
  try {
    inspectJournalSnapshot(directory, databasePath, markerPath, maxInspectionEntries, maxInspectionBytes,
      primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
      primaryDirectoryInspection, inspectionTemporaryDirectory);
  } catch (cause) {
    if ((cause as InspectionFailure)?.cleanupPending) throw cause;
    if (['HostJournalDirectoryUnavailable', 'HostJournalDirectoryCurrentUnavailable',
      'HostJournalDirectoryBoundsUnavailable', 'HostJournalDirectoryReadUnavailable',
      'HostJournalDirectoryRecordUnavailable'].includes((cause as InspectionFailure)?.code as string)) throw cause;
    if ((cause as InspectionFailure)?.code === 'ClientRequestJournalInspectionUnavailable') throw cause;
    if ((cause as InspectionFailure)?.code === 'ClientRequestJournalSqlUnavailable' ||
        (cause as InspectionFailure)?.code === 'ClientRequestJournalSqlCleanupPending') throw cause;
    if ((cause as InspectionFailure)?.code === 'SqliteSchemaPreparationUnavailable') throw cause;
    if ((cause as InspectionFailure)?.code === 'UnknownClientRequestJournalFormat') throw cause;
    fail('UnknownClientRequestJournalFormat', cause);
  }
  return true;
}

export function initializeJournalSchema(database: JournalSqlConnection,
  transaction: ReturnType<typeof createSqliteTransaction>, root: string, existed: boolean,
  inspectionBytes: number, sourceOperationLimits: unknown, ownedOriginal: unknown): void {
  // A fresh initialization is unpublished until its final directory ACK.
  // Existing-database format upgrades keep their original immediate ACKs.
  const syncFormatDirectory = () => {if (existed) syncDirectory(root);};
    // Fresh schema is one unpublished FULL transaction. Reuse these same DDL
    // statements for retained older formats; only those upgrades acknowledge
    // their separate durable feature transitions as before.
    const pendingFormatMarkers: [string, Buffer][] = [];
    const writeFormatMarker = (name: string, bytes: Buffer) => {
      const marker=openSync(join(root,name),'wx',0o600);
      try {writeFileSync(marker,bytes);fsyncSync(marker);}
      finally {closeSync(marker);}
      syncFormatDirectory();
    };
    const publishFormatMarker = (name: string, bytes: Buffer) => {
      if (existed) writeFormatMarker(name,bytes);
      else pendingFormatMarkers.push([name,bytes]);
    };
    const initializeFeature = (action: () => void) => existed ? transaction.run(action as () => undefined) : action();
    const initializeSchema = (): undefined => {
    database.exec(`
      CREATE TABLE IF NOT EXISTS client_requests (
        authority_scope_cid TEXT NOT NULL,
        caller_request_id TEXT NOT NULL,
        logical_request_scope_cid TEXT NOT NULL UNIQUE,
        intent_fingerprint_cid TEXT NOT NULL,
        program_definition_cid TEXT NOT NULL,
        parameter_values_cid TEXT NOT NULL,
        caller_input_intent_cid TEXT NOT NULL,
        namespace_id TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL UNIQUE,
        run_definition_wire TEXT,
        run_admission_evidence_json TEXT,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        state_revision INTEGER NOT NULL DEFAULT 0
          CHECK (state_revision >= 0 AND state_revision <= 9007199254740991),
        state_observation_key TEXT,
        lookup_expires_at TEXT NOT NULL,
        result_names_json TEXT,
        dispatch_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (dispatch_reserved IN (0, 1)),
        pre_dispatch_failure_confirmed INTEGER NOT NULL DEFAULT 0
          CHECK (pre_dispatch_failure_confirmed IN (0, 1)),
        physical_start_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (physical_start_reserved IN (0, 1)),
        cancellation_requested INTEGER NOT NULL DEFAULT 0
          CHECK (cancellation_requested IN (0, 1)),
        physical_close_confirmed INTEGER NOT NULL DEFAULT 0
          CHECK (physical_close_confirmed IN (0, 1)),
        observed_terminal_outcome TEXT
          CHECK (observed_terminal_outcome IN ('failed', 'cancelled')),
        reconciliation_state_wire TEXT,
        PRIMARY KEY (authority_scope_cid, caller_request_id)
      ) STRICT;
    `);
    if (!existed) publishFormatMarker('journal-format.json',journalMarker);
    if (!existsSync(join(root, submissionMarkerName))) {
      // Adopt only the retained original rows of an admitted prior format.
      // This cannot certify missing pre-upgrade history or issue an epoch.
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submission_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_custody
          SELECT 1, COUNT(*) FROM client_requests;
      `));
      publishFormatMarker(submissionMarkerName,submissionMarker);
    }
    if (!existsSync(join(root, epochMarkerName))) {
      // One retained authentication key and monotonic expiry watermark suffice
      // to validate bounded-lifetime tickets. No per-epoch history is evicted.
      initializeFeature(() => {
        database.exec(`CREATE TABLE client_submission_epoch_authority (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          authentication_key TEXT NOT NULL,
          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)
        ) STRICT;`);
        database.prepare('INSERT INTO client_submission_epoch_authority VALUES (1, ?, 0)')
          .run(randomBytes(32).toString('hex'));
      });
      publishFormatMarker(epochMarkerName,epochMarker);
    }
    if (!existsSync(join(root, intentMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submitted_intents (
          submission_id TEXT PRIMARY KEY,
          authority_scope_cid TEXT NOT NULL,
          nonce TEXT NOT NULL,
          epoch_wire TEXT NOT NULL,
          intent_cid TEXT NOT NULL,
          intent_wire TEXT NOT NULL,
          accepted_at INTEGER NOT NULL,
          phase TEXT NOT NULL CHECK (phase IN ('preparing', 'not_accepted', 'preparation_failed', 'ready', 'held')),
          outcome_wire TEXT,
          revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0)
        ) STRICT;
        CREATE TABLE client_submitted_intent_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_custody VALUES (1, 0);
      `));
      publishFormatMarker(intentMarkerName,intentMarker);
    }
    if (!existsSync(join(root, retirementMarkerName))) {
      // Adoption records zero formal retirements; it never resets issuance
      // or repairs a missing original row in a previously admitted journal.
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submitted_intent_retirement (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_retirement VALUES (1, 0);
      `));
      publishFormatMarker(retirementMarkerName,retirementMarker);
    }
    if (!existsSync(join(root, restartMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_submission_restarts (
          fresh_submission_id TEXT PRIMARY KEY,
          original_submission_id TEXT NOT NULL,
          link_wire TEXT NOT NULL
        ) STRICT;
        CREATE TABLE client_submission_restart_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_restart_custody VALUES (1, 0);
      `));
      publishFormatMarker(restartMarkerName,restartMarker);
    }
    if (!existsSync(join(root, cancellationMarkerName))) {
      initializeFeature(() => database.exec(`
        CREATE TABLE client_cancellation_operations (
          namespace_id TEXT NOT NULL,
          authority_scope_cid TEXT NOT NULL,
          cancel_id TEXT NOT NULL,
          run_definition_cid TEXT NOT NULL REFERENCES client_requests(run_definition_cid),
          expected_revision INTEGER NOT NULL CHECK (expected_revision >= 0),
          intent_fingerprint_cid TEXT NOT NULL,
          outcome_wire TEXT,
          outcome_cid TEXT,
          CHECK ((outcome_wire IS NULL) = (outcome_cid IS NULL)),
          PRIMARY KEY (namespace_id, authority_scope_cid, cancel_id)
        ) STRICT;
        CREATE TABLE client_cancellation_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_cancellation_custody VALUES (1, 0);
      `));
      publishFormatMarker(cancellationMarkerName,cancellationMarker);
    }
    if (!existsSync(join(root, nameMarkerName))) {
      // Old nonces are not names. This empty additive index never adopts or
      // searches their history. Once issued, a name is not evicted or reused.
      initializeFeature(() => database.exec(`
        ${nameTables.map(([, sql]) => `${sql};`).join('\n')}
        INSERT INTO client_submission_name_custody VALUES (1, 0, 0);
        ${nameTriggers.map(([, sql]) => `${sql};`).join('\n')}
      `));
      publishFormatMarker(nameMarkerName,nameMarker);
    }
    if ((database.prepare('PRAGMA user_version').get()!.user_version as number) < 3) {
      adoptSubmissionUsageStorage(database,initializeFeature,existsSync(join(root,usageMarkerName)),!existed,inspectionBytes);
    }
    // This optional original-operation storage belongs to this same Journal.
    // Legacy absence grants no new dispatch: live scope issuance additionally
    // requires the existing confirmed first physical-start transaction.
    inspectClientSourceOperationStorage(database);
    if (sourceOperationLimits !== undefined && database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'client_source_operation_originals'").get() === undefined) {
      initializeFeature(() => database.exec(sourceOperationTable));
    }
    const keyedSchema = database.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'client_keyed_lookup_originals'").get();
    if (keyedSchema !== undefined && keyedSchema.sql !== keyedLookupOriginalTable) {
      fail('UnknownClientRequestJournalFormat');
    }
    if (keyedSchema === undefined) initializeFeature(() => database.exec(keyedLookupOriginalTable));
    inspectLocalExecutionOwnerStorage(database);
    if (ownedOriginal !== undefined && database.prepare(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'client_local_execution_owners'").get() === undefined) {
      initializeFeature(() => database.exec(localExecutionOwnerTable));
    }
    };
    if (existed) initializeSchema();
    else {
      transaction.run(initializeSchema);
      // No format marker claims an uncommitted current schema. Each original
      // file keeps its fsync; the existing final directory ACK precedes ready.
      for (const [name,bytes] of pendingFormatMarkers) writeFormatMarker(name,bytes);
    }
}

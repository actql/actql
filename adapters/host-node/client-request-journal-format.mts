// Physical format and metadata for the original Client Request Journal.
import {createHash, createHmac, randomBytes} from 'node:crypto';
import {closeSync, constants, existsSync, fstatSync, fsyncSync, lstatSync, openSync, readSync,
  writeFileSync, type BigIntStats} from 'node:fs';
import {basename, dirname, isAbsolute, join, resolve} from 'node:path';
import type {SQLOutputValue} from 'node:sqlite';
import type {WireRunRef} from '../../packages/client-wire/index.js';
import {cid, structuralExplanationOriginalShape, text, type ExplanationOriginal} from './client-request-journal-records.mjs';
import {inspectSqliteSnapshot, inspectJournalDirectory} from '../host-common/sqlite-format-inspection.mjs';
import {assertHostJournalDirectoryInspector, inspectHostJournalDirectory} from './host-journal-directory.mjs';
import {inspectClientSourceOperationStorage, snapshotClientSourceOperationLimits, sourceOperationTable} from './client-source-operation.mjs';
import {inspectRelationSampleStartStorage, inspectRelationSampleAdoptionStorage}
  from './client-relation-sample-adoption.mjs';
import type {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {assertOriginalPreparedLocalPublicationStoreOwnership} from '../store-local/prepared-publication-store-ownership.mjs';
import {snapshotSqliteSchemaReadLimits, snapshotSqliteSchemaSqlSupport}
  from '../host-common/sqlite-schema-resource-bounds.mjs';
import {applyOriginal, boundedJournalWalFrames, boundedPrimarySql, boundJournalDatabaseExtent, fail,
  journalDatabaseGeometry, selectJournalTemporaryStorage, snapshotPrimaryExecutionLimits, snapshotPrimarySqlLimits,
  type JournalSqlConnection} from './client-request-journal-sql.mjs';

type Row = Record<string, SQLOutputValue>;
type JournalStatement = ReturnType<JournalSqlConnection['prepare']>;
type IsSafeInteger = (value: unknown) => value is number;
type Usage = Readonly<{n: number; bytes: number; revision: number}>;
type OwnerReceipt = Readonly<{token?: unknown; anchor?: Readonly<{identity?: unknown; device?: unknown; inode?: unknown}>}>;
type SnapshotOptions = NonNullable<Parameters<typeof inspectSqliteSnapshot>[2]>;
type InspectionSql = ReturnType<typeof boundedPrimarySql>;
type CleanupCarrier = {cleanupHandle?: unknown};
type InspectionFailure = {cleanupPending?: unknown; code?: string} | null | undefined;
type JournalConfigurationInput = Readonly<{
  maxRecords?: number; maxInspectionEntries?: number; maxInspectionBytes?: number;
  maxDatabaseBytes?: number; maxWalFrames?: number;
  primarySqlLimits?: unknown; primaryExecutionLimits?: unknown;
  primarySchemaLimits?: unknown; primarySchemaSqlSupport?: unknown;
  primaryCurrent?: Parameters<typeof boundedPrimarySql>[3]; primaryDirectoryInspection?: unknown;
  inspectionTemporaryDirectory?: string;
  maxRunDefinitionWireBytes?: number; submissionEpochTtlMs?: number; submissionEpochNow?: () => number;
  updateOriginalControl?: unknown; sourceOperationLimits?: unknown;
}>;


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

// The Context companion carries the original Invocation Template for bounded
// cold validation against the committed Run Definition.
// Keep the deployed Facts table unchanged so a pre-Context journal remains
// readable without migration, and never create the companion on a read.
export const explanationContextOriginalTable = `CREATE TABLE client_run_explanation_context_originals (
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_run_explanation_originals(run_definition_cid) ON DELETE CASCADE,
  context_wire TEXT NOT NULL,
  context_wire_sha256 TEXT NOT NULL,
  invocation_template_wire TEXT NOT NULL
) STRICT`;
export function inspectExplanationContextOriginalStorage(database: JournalSqlConnection) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_run_explanation_context_originals'")
    .get(explanationContextOriginalTable.length + 1);
  if (row !== undefined && row.sql !== explanationContextOriginalTable) fail('UnknownClientRequestJournalFormat');
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
  return row !== undefined;
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
function inspectSubmissionStorage(database: JournalSqlConnection) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_custody'`).all();
  if (tables.length !== 1) fail('UnknownClientRequestJournalFormat');
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
export function assertJournalSubmissionCustody(requestUsage: JournalStatement, submissionIssued: JournalStatement) {
  const usage = requestUsage.get(), n = usage?.retained_count;
  if (!validJournalRowUsage(usage) || submissionIssued.get()?.issued_count !== n) {
    fail('ClientRequestSubmissionCustodyLost');
  }
  return n as number;
}

export function assertJournalCancellationCustody(cancellationUsage: JournalStatement, cancellationIssued: JournalStatement) {
  const usage = cancellationUsage.get(), n = usage?.retained_count;
  if (!validJournalRowUsage(usage) || cancellationIssued.get()?.issued_count !== n) fail('ClientRequestJournalCorrupt');
  return n as number;
}

export function assertJournalRestartCustody(restartUsage: JournalStatement, restartIssued: JournalStatement,
  inspectionBytes: number) {
  const retained = restartUsage.get();
  if (!retained || !(Number.isSafeInteger as IsSafeInteger)(retained.n) || retained.n < 0 ||
      !(Number.isSafeInteger as IsSafeInteger)(retained.bytes) || retained.bytes < 0 || retained.bytes > inspectionBytes ||
      !(Number.isSafeInteger as IsSafeInteger)(retained.revision) || retained.revision < 0 ||
      restartIssued.get()?.issued_count !== retained.n) {
    fail('ClientSubmissionRestartCustodyLost');
  }
  return retained as Row & Usage;
}

export function assertJournalIntentCustody(intentUsage: JournalStatement, intentIssued: JournalStatement, intentRetired: JournalStatement,
  inspectionBytes: number) {
  const retained = intentUsage.get();
  const issued = intentIssued.get()?.issued_count;
  const retired = intentRetired.get()?.retired_count;
  if (!retained || !(Number.isSafeInteger as IsSafeInteger)(retained.n) || retained.n < 0 ||
      !(Number.isSafeInteger as IsSafeInteger)(retained.bytes) || retained.bytes < 0 || retained.bytes > inspectionBytes ||
      !(Number.isSafeInteger as IsSafeInteger)(retained.revision) || retained.revision < 0 ||
      !(Number.isSafeInteger as IsSafeInteger)(issued) || !(Number.isSafeInteger as IsSafeInteger)(retired) || retired < 0 ||
      !(Number.isSafeInteger as IsSafeInteger)(retained.n + retired) || retained.n + retired !== issued) {
    fail('ClientSubmittedIntentCustodyLost');
  }
  return {...retained, issued, retired} as Row & Usage & {issued: number; retired: number};
}

export function assertJournalNameCustody(nameCustody: JournalStatement) {
  const row = nameCustody.get();
  if (row?.singleton !== 1 || !(Number.isSafeInteger as IsSafeInteger)(row.issued_count) ||
      row.issued_count < 0 || row.issued_count !== row.retained_count) {
    fail('ClientSubmissionNameCustodyLost');
  }
  return row.issued_count;
}

// Current-version durable input is read under this Journal's selected
// opaque Host service, never a retired preparation token or Store grant.
// Native SQL still sums ALL operands against the same statement envelope.
export function journalIntentWireBytes(wire: unknown, maxInspectionBytes: number, maxDatabaseBytes: number | undefined,
  primaryExecutionLimits: ReturnType<typeof snapshotPrimaryExecutionLimits>) {
  if (typeof wire !== 'string') fail('InvalidClientSubmittedIntent');
  const bytes = Buffer.byteLength(wire, 'utf8');
  const selected = Math.min(maxInspectionBytes,
    maxDatabaseBytes ?? maxInspectionBytes,
    primaryExecutionLimits?.maxParameterBytes ?? maxInspectionBytes);
  // The shared Core constructor needs +128 bytes/+4 nodes/+1 depth headroom.
  // This is its actual signed-Int representation boundary, not a profile cap.
  if (bytes < 1 || bytes > selected || bytes > 2147483519) {
    fail('ClientSubmittedIntentCapacity');
  }
  return bytes;
}

function inspectJournalUsageStorage(database: JournalSqlConnection) {
  for (const [table] of journalRowUsageTables) {
    if (!validJournalRowUsage(database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get())) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
  for (const [table] of submissionUsageTables) {
    if (!validSubmissionUsage(database.prepare(`SELECT * FROM ${table} WHERE singleton=1`).get())) {
      fail('UnknownClientRequestJournalFormat');
    }
  }
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
export function validEpochAuthority(row: Row | undefined): row is Row & {authentication_key: string; observed_at: number} {
  return row?.singleton === 1 && hexKey(row.authentication_key) &&
    Number.isSafeInteger(row.observed_at) && (row.observed_at as number) >= 0 &&
    (row.observed_at as number) <= Number.MAX_SAFE_INTEGER - maxEpochTtlMs;
}
export function authenticateJournalName(row: Row, epochAuthority: JournalStatement) {
  const authority = epochAuthority.get();
  if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
  // This is private storage authentication, not a new public CID domain or
  // authority token. Every original scope and intent component is included.
  return createHmac('sha256', Buffer.from(authority.authentication_key, 'hex'))
    .update(JSON.stringify(['scoped-submission-name', row.namespace_id, row.actor_id,
      row.name, row.authority_scope_cid, row.submission_id, row.intent_cid]), 'utf8').digest('hex');
}

function inspectEpochStorage(database: JournalSqlConnection) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_epoch_authority'`).all();
  if (tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_epoch_authority)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT * FROM client_submission_epoch_authority').all();
  if (JSON.stringify(fields) !== JSON.stringify(['authentication_key', 'observed_at', 'singleton']) ||
      records.length !== 1 || !validEpochAuthority(records[0])) {
    fail('UnknownClientRequestJournalFormat');
  }
}
function inspectIntentStorage(database: JournalSqlConnection) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submitted_intents', 'client_submitted_intent_custody')`).all();
  if (names.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intents)').all()
    .map(field => field.name).sort();
  const expected = ['authority_scope_cid', 'submission_id', 'nonce', 'epoch_wire',
    'intent_cid', 'intent_wire', 'accepted_at', 'phase', 'outcome_wire', 'revision'].sort();
  const custody = database.prepare('SELECT singleton, issued_count FROM client_submitted_intent_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(expected) || custody.length !== 1 ||
      custody[0].singleton !== 1 || !Number.isSafeInteger(custody[0].issued_count) ||
    (custody[0].issued_count as number) < 0) fail('UnknownClientRequestJournalFormat');
}

function inspectIntentRetirementStorage(database: JournalSqlConnection) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submitted_intent_retirement'`).all();
  if (tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intent_retirement)')
    .all().map(field => field.name).sort();
  const rows = database.prepare('SELECT * FROM client_submitted_intent_retirement').all();
  if (JSON.stringify(fields) !== JSON.stringify(['retired_count', 'singleton']) ||
      rows.length !== 1 || rows[0].singleton !== 1 ||
      !Number.isSafeInteger(rows[0].retired_count) || (rows[0].retired_count as number) < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectRestartStorage(database: JournalSqlConnection) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_restarts', 'client_submission_restart_custody')`).all();
  if (names.length !== 2) fail('UnknownClientRequestJournalFormat');
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

function inspectNameStorage(database: JournalSqlConnection) {
  const names = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_submission_names', 'client_submission_name_custody')`).all();
  if (names.length !== 2) fail('UnknownClientRequestJournalFormat');
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

function inspectCancellationStorage(database: JournalSqlConnection) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_cancellation_operations', 'client_cancellation_custody')`).all();
  if (tables.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_cancellation_operations)')
    .all().map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_cancellation_custody)')
    .all().map(field => field.name).sort();
  const usage = database.prepare('SELECT * FROM client_cancellation_row_usage WHERE singleton=1').get();
  if (!validJournalRowUsage(usage)) fail('UnknownClientRequestJournalFormat');
  const custody = database.prepare('SELECT singleton, issued_count FROM client_cancellation_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(cancellationColumns) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || (custody[0].issued_count as number) < 0 ||
      custody[0].issued_count !== usage.retained_count) fail('UnknownClientRequestJournalFormat');
}

const currentJournalMarkers = [
  ['journal-format.json', journalMarker],
  [submissionMarkerName, submissionMarker],
  [epochMarkerName, epochMarker],
  [intentMarkerName, intentMarker],
  [retirementMarkerName, retirementMarker],
  [restartMarkerName, restartMarker],
  [cancellationMarkerName, cancellationMarker],
  [nameMarkerName, nameMarker],
] as const;
const currentJournalSchema = [
  ['client_requests', `CREATE TABLE client_requests (
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
      ) STRICT`],
  ['client_submission_custody', `CREATE TABLE client_submission_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT`],
  ['client_submission_epoch_authority', `CREATE TABLE client_submission_epoch_authority (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          authentication_key TEXT NOT NULL,
          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)
        ) STRICT`],
  ['client_submitted_intents', `CREATE TABLE client_submitted_intents (
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
        ) STRICT`],
  ['client_submitted_intent_custody', `CREATE TABLE client_submitted_intent_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT`],
  ['client_submitted_intent_retirement', `CREATE TABLE client_submitted_intent_retirement (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)
        ) STRICT`],
  ['client_submission_restarts', `CREATE TABLE client_submission_restarts (
          fresh_submission_id TEXT PRIMARY KEY,
          original_submission_id TEXT NOT NULL,
          link_wire TEXT NOT NULL
        ) STRICT`],
  ['client_submission_restart_custody', `CREATE TABLE client_submission_restart_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT`],
  ['client_cancellation_operations', `CREATE TABLE client_cancellation_operations (
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
        ) STRICT`],
  ['client_cancellation_custody', `CREATE TABLE client_cancellation_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT`],
  ['client_keyed_lookup_originals', keyedLookupOriginalTable],
  ...nameTables, ...nameTriggers,
  ...submissionUsageTables, ...submissionUsageTriggers,
  ...journalRowUsageTables, ...journalRowUsageTriggers,
] as const;
const currentJournalVersion = 3;

function requireCurrentJournalVersion(version: SQLOutputValue | undefined) {
  if (version === 0 || version === 1 || version === 2) fail('LegacyClientRequestJournalFormat');
  if (version !== currentJournalVersion) fail('UnknownClientRequestJournalFormat');
}

function currentJournalMarkersMatch(directory: string, entries: readonly string[]) {
  return currentJournalMarkers.every(([name, bytes]) => entries.includes(name) &&
    lstatSync(join(directory, name)).isFile() && journalMarkerMatches(join(directory, name), bytes));
}

export function inspectJournalNativeStorage(database: JournalSqlConnection,
  requireSourceOperations: boolean, requireLocalExecutionOwners: boolean) {
  requireCurrentJournalVersion(database.prepare('PRAGMA user_version').get()?.user_version);
  const select = database.prepare('SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE name = ?');
  for (const [name, sql] of currentJournalSchema) {
    if (select.get(sql.length + 1, name)?.sql !== sql) fail('UnknownClientRequestJournalFormat');
  }
  inspectSubmissionStorage(database);
  inspectEpochStorage(database);
  inspectIntentStorage(database);
  inspectIntentRetirementStorage(database);
  inspectRestartStorage(database);
  inspectNameStorage(database);
  inspectJournalUsageStorage(database);
  inspectCancellationStorage(database);
  const source = inspectClientSourceOperationStorage(database);
  const localOwner = inspectLocalExecutionOwnerStorage(database);
  if (requireSourceOperations && !source || requireLocalExecutionOwners && !localOwner) {
    fail('UnknownClientRequestJournalFormat');
  }
  const explanation = inspectExplanationOriginalStorage(database);
  if (inspectExplanationContextOriginalStorage(database) && !explanation) {
    fail('UnknownClientRequestJournalFormat');
  }
  inspectExplanationPlanOriginalStorage(database);
  inspectRelationSampleStartStorage(database);
  inspectRelationSampleAdoptionStorage(database);
}

// Classify before acquiring the writable original. SQLite may create SHM
// even on a read-only WAL open, so inspect a retained WAL in isolation.
export function inspectJournalSnapshot(directory: string, databasePath: string, entries: readonly string[],
  maxInspectionEntries: number, maxInspectionBytes: number, primarySqlLimits: Parameters<typeof boundedPrimarySql>[1] | undefined,
  primaryExecutionLimits: Parameters<typeof boundedPrimarySql>[2], primarySchemaLimits: unknown, primarySchemaSqlSupport: unknown,
  primaryCurrent: SnapshotOptions['assertCurrent'], primaryDirectoryInspection: unknown, inspectionTemporaryDirectory: string | undefined,
  requireSourceOperations: boolean, assertExclusiveSource: SnapshotOptions['assertExclusiveSource']) {
  let inspectionSql: InspectionSql | undefined;
  try {
    inspectSqliteSnapshot(databasePath, originalDatabase => {
      // Apply the selected support conditions to the preflight metadata reads.
      // No native All() vector may precede the bounded cursor path.
      if (primaryExecutionLimits !== undefined) {
        inspectionSql = boundedPrimarySql(originalDatabase, primarySqlLimits!, primaryExecutionLimits, primaryCurrent);
      }
      const database = inspectionSql?.database ?? originalDatabase;
      inspectJournalNativeStorage(database, requireSourceOperations, assertExclusiveSource !== undefined);
    }, {code: 'UnknownClientRequestJournalFormat', maxSourceBytes: maxInspectionBytes,
      unavailableCode: 'ClientRequestJournalInspectionUnavailable',
      schemaReadLimits: primarySchemaLimits,
      schemaSqlSupport: primarySchemaSqlSupport,
      assertCurrent: primaryCurrent,
      assertExclusiveSource,
      checkUserVersion: requireCurrentJournalVersion,
      temporaryDirectory: inspectionTemporaryDirectory,
      validateSource: () => currentJournalMarkersMatch(directory, entries) &&
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

const pathText = (value: unknown): value is string => typeof value === 'string' && value.length > 0;

// Snapshot the original Journal options once, in the caller's argument order,
// before any selected directory or SQLite acquisition.
export function snapshotJournalConfiguration(directory: unknown, {
  maxRecords = 100_000,
  maxInspectionEntries = 100_000,
  maxInspectionBytes = 64 * 1024 * 1024,
  maxDatabaseBytes,
  maxWalFrames,
  primarySqlLimits: rawPrimarySqlLimits,
  primaryExecutionLimits: rawPrimaryExecutionLimits,
  primarySchemaLimits: rawPrimarySchemaLimits,
  primarySchemaSqlSupport: rawPrimarySchemaSqlSupport,
  primaryCurrent,
  primaryDirectoryInspection,
  inspectionTemporaryDirectory,
  maxRunDefinitionWireBytes = 65_536,
  submissionEpochTtlMs = maxEpochTtlMs,
  submissionEpochNow = Date.now,
  updateOriginalControl,
  sourceOperationLimits: rawSourceOperationLimits,
}: JournalConfigurationInput = {}, ownedOriginal?: unknown) {
  if (ownedOriginal !== undefined) {
    if (!pathText(directory) || basename(resolve(directory)) !== 'requests') {
      fail('InvalidClientRequestJournalConfiguration');
    }
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
  }
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      !Number.isSafeInteger(maxInspectionEntries) || maxInspectionEntries < 1 ||
      !Number.isSafeInteger(maxInspectionBytes) || maxInspectionBytes < 1 ||
      maxDatabaseBytes !== undefined &&
        (!Number.isSafeInteger(maxDatabaseBytes) || maxDatabaseBytes < 1) ||
      maxWalFrames !== undefined &&
        (!Number.isSafeInteger(maxWalFrames) || maxWalFrames < 1) ||
      maxRecords < 1 || !Number.isSafeInteger(maxRunDefinitionWireBytes) ||
      maxRunDefinitionWireBytes < 1024 ||
      !Number.isSafeInteger(submissionEpochTtlMs) || submissionEpochTtlMs < 1 ||
      submissionEpochTtlMs > maxEpochTtlMs || typeof submissionEpochNow !== 'function') {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const sourceOperationLimits = snapshotClientSourceOperationLimits(rawSourceOperationLimits);
  if (primaryCurrent !== undefined && typeof primaryCurrent !== 'function') {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (inspectionTemporaryDirectory !== undefined &&
      (typeof inspectionTemporaryDirectory !== 'string' ||
        inspectionTemporaryDirectory.length === 0 || inspectionTemporaryDirectory.length > 4096 ||
        !isAbsolute(inspectionTemporaryDirectory) || inspectionTemporaryDirectory.includes('\0'))) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (primaryDirectoryInspection !== undefined) {
    // Validate the same private view and exact selected bound BEFORE any
    // directory/format/native acquisition. No fallback on selected refusal.
    assertHostJournalDirectoryInspector(primaryDirectoryInspection, maxInspectionEntries);
  }
  const primarySqlLimits = snapshotPrimarySqlLimits(rawPrimarySqlLimits);
  const primaryExecutionLimits = snapshotPrimaryExecutionLimits(rawPrimaryExecutionLimits);
  const primarySchemaLimits = snapshotSqliteSchemaReadLimits(rawPrimarySchemaLimits);
  const primarySchemaSqlSupport = snapshotSqliteSchemaSqlSupport(rawPrimarySchemaSqlSupport, primarySchemaLimits);
  if (primaryExecutionLimits !== undefined &&
      (primarySqlLimits === undefined || maxDatabaseBytes === undefined)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (primarySchemaLimits !== undefined && maxDatabaseBytes === undefined) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  if (maxWalFrames !== undefined && (maxDatabaseBytes === undefined ||
      primarySqlLimits === undefined || primaryExecutionLimits === undefined)) {
    fail('InvalidClientRequestJournalConfiguration');
  }
  // An optional selected-facility support bound is not a format rule or a
  // capacity issuer. Refuse original DB/WAL extent before its copy/SQLite
  // inspection, not after materializing rows. Unselected callers are unchanged.
  const inspectionBytes = maxDatabaseBytes === undefined ? maxInspectionBytes :
    Math.min(maxInspectionBytes, maxDatabaseBytes);
  const walFrames = boundedJournalWalFrames(maxWalFrames, inspectionBytes, maxDatabaseBytes);
  return {maxRecords, maxInspectionEntries, maxInspectionBytes, maxDatabaseBytes,
    primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport,
    primaryCurrent, primaryDirectoryInspection, inspectionTemporaryDirectory,
    maxRunDefinitionWireBytes, submissionEpochTtlMs, submissionEpochNow, updateOriginalControl,
    sourceOperationLimits, inspectionBytes, walFrames};
}

export function admitJournalDirectory(directory: string, maxInspectionEntries: number,
  maxInspectionBytes: number, primarySqlLimits: Parameters<typeof inspectJournalSnapshot>[5],
  primaryExecutionLimits: Parameters<typeof inspectJournalSnapshot>[6], primarySchemaLimits: unknown,
  primarySchemaSqlSupport: unknown, primaryCurrent: SnapshotOptions['assertCurrent'],
  primaryDirectoryInspection: unknown, inspectionTemporaryDirectory: string | undefined,
  ownedOriginal: unknown, requireSourceOperations: boolean): boolean {
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
  const assertExclusiveSource = ownedOriginal === undefined ? undefined : () =>
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
  if (assertExclusiveSource !== undefined) {
    assertExclusiveSource();
    if (entries.includes('client-requests.sqlite3-journal')) fail('UnknownClientRequestJournalFormat');
    let bytes = 0n;
    for (const path of [databasePath, `${databasePath}-wal`, `${databasePath}-shm`]) {
      if (!entries.includes(basename(path))) continue;
      const original = lstatSync(path, {bigint: true});
      if (!original.isFile() || original.isSymbolicLink()) fail('UnknownClientRequestJournalFormat');
      if (path.endsWith('-shm')) continue;
      bytes += original.size;
      if (bytes > BigInt(maxInspectionBytes)) fail('ClientRequestJournalInspectionUnavailable');
    }
  }
  try {
    inspectJournalSnapshot(directory, databasePath, entries, maxInspectionEntries, maxInspectionBytes,
      primarySqlLimits, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport, primaryCurrent,
      primaryDirectoryInspection, inspectionTemporaryDirectory, requireSourceOperations, assertExclusiveSource);
  } catch (cause) {
    if ((cause as InspectionFailure)?.cleanupPending) throw cause;
    if (['HostJournalDirectoryUnavailable', 'HostJournalDirectoryCurrentUnavailable',
      'HostJournalDirectoryBoundsUnavailable', 'HostJournalDirectoryReadUnavailable',
      'HostJournalDirectoryRecordUnavailable'].includes((cause as InspectionFailure)?.code as string)) throw cause;
    if ((cause as InspectionFailure)?.code === 'ClientRequestJournalInspectionUnavailable') throw cause;
    if ((cause as InspectionFailure)?.code === 'ClientRequestJournalSqlUnavailable' ||
        (cause as InspectionFailure)?.code === 'ClientRequestJournalSqlCleanupPending') throw cause;
    if ((cause as InspectionFailure)?.code === 'SqliteSchemaPreparationUnavailable') throw cause;
    if ((cause as InspectionFailure)?.code === 'UnknownClientRequestJournalFormat' ||
        (cause as InspectionFailure)?.code === 'LegacyClientRequestJournalFormat') throw cause;
    fail('UnknownClientRequestJournalFormat', cause);
  }
  return true;
}

export function initializeJournalPrimaryStorage(database: JournalSqlConnection,
  transaction: ReturnType<typeof createSqliteTransaction>, root: string, directory: string, existed: boolean,
  configuration: ReturnType<typeof snapshotJournalConfiguration>, selectedSql: InspectionSql | undefined,
  ownedOriginal: unknown) {
  const {maxDatabaseBytes, walFrames, primaryExecutionLimits, primarySchemaLimits, primarySchemaSqlSupport,
    maxInspectionEntries, inspectionBytes, sourceOperationLimits} = configuration;
  let temporarySelected = false;
  let retainedGeometry;
  if (existed && ownedOriginal !== undefined) {
    assertOriginalPreparedLocalPublicationStoreOwnership(ownedOriginal,
      join(dirname(resolve(directory)), 'publication'));
    if (maxDatabaseBytes !== undefined) {
      retainedGeometry = journalDatabaseGeometry(database, maxDatabaseBytes, walFrames);
    }
    selectJournalTemporaryStorage(database, primaryExecutionLimits);
    selectedSql?.prepareWalCheckpoint();
    temporarySelected = true;
    // SQLite is the format authority for this already-owned database.
    // Bound only schema metadata here; do not materialize historical rows.
    const schema = database.prepare(`SELECT COUNT(*) AS entries,
        COALESCE(SUM(length(CAST(sql AS BLOB))),0) AS bytes FROM sqlite_master`).get();
    const schemaLimits = primarySchemaLimits ?? {
      maxSchemaEntries: maxInspectionEntries, maxSchemaBytes: inspectionBytes};
    if (!(Number.isSafeInteger as IsSafeInteger)(schema?.entries) || schema.entries < 1 ||
        schema.entries > schemaLimits.maxSchemaEntries ||
        !(Number.isSafeInteger as IsSafeInteger)(schema?.bytes) || schema.bytes < 0 ||
        schema.bytes > schemaLimits.maxSchemaBytes) {
      fail('SqliteSchemaPreparationUnavailable');
    }
    if (primarySchemaSqlSupport !== undefined) {
      const statements = database.prepare('SELECT sql FROM sqlite_master WHERE sql IS NOT NULL').all();
      if (statements.some(row => !primarySchemaSqlSupport.includes(row.sql as string))) {
        fail('SqliteSchemaPreparationUnavailable');
      }
    }
    inspectJournalNativeStorage(database, sourceOperationLimits !== undefined, true);
  }
  boundJournalDatabaseExtent(database, maxDatabaseBytes, primaryExecutionLimits, walFrames,
    temporarySelected, retainedGeometry, selectedSql?.prepareWalCheckpoint);
  database.exec('PRAGMA journal_mode = WAL');
  database.exec('PRAGMA synchronous = FULL');
  if (!existed) initializeJournalSchema(database, transaction, root, sourceOperationLimits, ownedOriginal);
}

export function initializeJournalSchema(database: JournalSqlConnection,
  transaction: ReturnType<typeof createSqliteTransaction>, root: string,
  sourceOperationLimits: unknown, ownedOriginal: unknown): void {
  transaction.run(() => {
    for (const [, sql] of currentJournalSchema) database.exec(sql);
    database.prepare('INSERT INTO client_submission_epoch_authority VALUES (1, ?, 0)')
      .run(randomBytes(32).toString('hex'));
    database.exec(`
      INSERT INTO client_submission_custody VALUES (1, 0);
      INSERT INTO client_submitted_intent_custody VALUES (1, 0);
      INSERT INTO client_submitted_intent_retirement VALUES (1, 0);
      INSERT INTO client_submission_restart_custody VALUES (1, 0);
      INSERT INTO client_cancellation_custody VALUES (1, 0);
      INSERT INTO client_submission_name_custody VALUES (1, 0, 0);
      INSERT INTO client_submitted_intent_usage VALUES (1, 0, 0, 0);
      INSERT INTO client_submission_restart_usage VALUES (1, 0, 0, 0);
      INSERT INTO client_request_row_usage VALUES (1, 0);
      INSERT INTO client_cancellation_row_usage VALUES (1, 0);
      PRAGMA user_version = ${currentJournalVersion};
    `);
    if (sourceOperationLimits !== undefined) database.exec(sourceOperationTable);
    if (ownedOriginal !== undefined) database.exec(localExecutionOwnerTable);
    return undefined;
  });
  // Publish the markers only after the single current-schema COMMIT. The
  // existing final directory acknowledgement still precedes returning ready.
  for (const [name, bytes] of currentJournalMarkers) {
    const marker = openSync(join(root, name), 'wx', 0o600);
    try {writeFileSync(marker, bytes); fsyncSync(marker);}
    finally {closeSync(marker);}
  }
}

// Context-bearing Effect runs retain the exact Plan under their structural
// allowance. The first admission commits this companion with the other
// facets. Ordinary Plan-only and Facts-only admissions keep their own shape.
export const explanationPlanOriginalTable = `CREATE TABLE client_run_explanation_plan_originals (
  run_definition_cid TEXT PRIMARY KEY REFERENCES client_run_explanation_context_originals(run_definition_cid) ON DELETE CASCADE,
  compiled_plan_wire TEXT NOT NULL,
  plan_view_wire TEXT NOT NULL
) STRICT`;
function inspectExplanationPlanOriginalStorage(database: JournalSqlConnection) {
  const row = database.prepare("SELECT substr(sql, 1, ?) AS sql FROM sqlite_master WHERE type = 'table' AND name = 'client_run_explanation_plan_originals'")
    .get(explanationPlanOriginalTable.length + 1);
  if (row !== undefined && row.sql !== explanationPlanOriginalTable) fail('UnknownClientRequestJournalFormat');
  return row !== undefined;
}

// These are the scalar and text projections of the two exact SELECTs below.
// Their existing binding, length and NULL checks still decide admission.
type ExplanationExtent = Readonly<{
  definitionBytes: number; evidenceBytes: number; factsBytes: number; storedBytes: number;
  contextBytes?: number; invocationTemplateBytes?: number; compiledPlanBytes?: number; planViewBytes?: number;
}>;
type ExplanationProbeRow = Readonly<{
  facts_present: number; facet_matches: number; bindings_bounded: number;
  definition_bytes: number; evidence_bytes: number; facts_bytes: number;
  plan_present: number; plan_matches: number; compiled_plan_bytes: number; plan_view_bytes: number;
  context_present?: number; context_bytes?: number; context_hash_bytes?: number; invocation_template_bytes?: number;
}>;
type ExplanationOriginalRow = Readonly<{
  facts_present: number; facet_matches: number; evidence_present: number;
  definition_wire: string | null; evidence_wire: string | null;
  program_cid: string | null; parameters_cid: string | null; facts_wire: string | null;
  plan_present: number; plan_matches: number; compiled_plan_wire: string | null; plan_view_wire: string | null;
  context_present?: number; context_wire: string | null; context_wire_sha256: string | null; invocation_template_wire: string | null;
}>;

// Explicit Explanation operations only. Ordinary status/Plan reads neither
// fetch these bytes nor silently create this optional feature. The installed
// caller must pre-admit its schema/statement and row/codec construction.
export function readJournalExplanationOriginal(database: JournalSqlConnection,
  ref: WireRunRef, maxRunDefinitionWireBytes: number) {
  if (!inspectExplanationOriginalStorage(database)) return undefined;
  // Compare binding scalars inside SQLite instead of returning potentially
  // corrupt unbounded strings. Byte length includes UTF-8 expansion and NUL;
  // an over-limit row returns NULL, never a valid-looking truncated original.
  // Native file/statement work still belongs to the original physical owner.
  const row = database.prepare(`SELECT
      namespace_id = ? AND authority_scope_cid = ? AS original_ref_matches,
      CASE WHEN typeof(facts_wire) = 'text' AND
        length(CAST(facts_wire AS BLOB)) BETWEEN 1 AND ?
        THEN facts_wire ELSE NULL END AS facts_wire
      FROM client_run_explanation_originals WHERE run_definition_cid = ?`)
    .get(ref.namespaceId, ref.authorityScopeCid, maxRunDefinitionWireBytes, ref.runDefinitionCid);
  if (row === undefined) return undefined;
  if (row.original_ref_matches !== 1) {
    fail('ClientRequestJournalCorrupt');
  }
  const original = {factsWire: row.facts_wire};
  if (!structuralExplanationOriginalShape(original) || Buffer.byteLength(original.factsWire) > maxRunDefinitionWireBytes) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze(original);
}
// The explicit structural reader first asks only for scalar byte extents.
// No accepted-row string (including binding CIDs) crosses this probe. The
// same connection retains/prepares these fixed SQL statements under its
// existing selected statement/SQL/operand ownership, not the read's codec.
export function explanationReadSelection(database: JournalSqlConnection,
  ensureOpen: () => undefined, ref: WireRunRef, includeContext: boolean) {
  ensureOpen();
  if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid)) {
    fail('InvalidClientRunLookup');
  }
  const facet = inspectExplanationOriginalStorage(database);
  const plan = inspectExplanationPlanOriginalStorage(database);
  const context = inspectExplanationContextOriginalStorage(database);
  if ((context && !facet) || (plan && !context)) fail('ClientRequestJournalCorrupt');
  const contextPresent = context ? 'c.run_definition_cid IS NOT NULL' : '0';
  const planPresent = plan ? 'p.run_definition_cid IS NOT NULL' : '0';
  const selected: {facet: boolean; from: string; facts: string; present: string; matches: string;
    plan: string; planMatches: string; compiledPlan: string; planView: string; context?: string; contextHash?: string;
    template?: string; contextPresent?: string} = {facet, from: `FROM client_requests r${facet
    ? ' LEFT JOIN client_run_explanation_originals f ON f.run_definition_cid = r.run_definition_cid' : ''}${context
    ? ' LEFT JOIN client_run_explanation_context_originals c ON c.run_definition_cid = r.run_definition_cid' : ''}${plan
    ? ' LEFT JOIN client_run_explanation_plan_originals p ON p.run_definition_cid = r.run_definition_cid' : ''}
    WHERE r.namespace_id = ? AND r.authority_scope_cid = ? AND r.run_definition_cid = ?`,
  facts: facet ? 'f.facts_wire' : 'NULL',
  present: facet ? 'f.run_definition_cid IS NOT NULL' : '0',
  matches: facet ? '(f.run_definition_cid IS NULL OR (f.namespace_id = r.namespace_id AND f.authority_scope_cid = r.authority_scope_cid))' : '1',
  plan: planPresent,
  planMatches: plan ? `((${planPresent}) = (${contextPresent}) AND (NOT (${planPresent}) OR f.run_definition_cid IS NOT NULL))`
    : `(NOT (${contextPresent}))`,
  compiledPlan: plan ? 'p.compiled_plan_wire' : 'NULL',
  planView: plan ? 'p.plan_view_wire' : 'NULL'};
  if (includeContext) {
    selected.context = context ? 'c.context_wire' : 'NULL';
    selected.contextHash = context ? 'c.context_wire_sha256' : 'NULL';
    selected.template = context ? 'c.invocation_template_wire' : 'NULL';
    selected.contextPresent = contextPresent;
  }
  return selected;
}
export function probeJournalExplanation(database: JournalSqlConnection,
  ensureOpen: () => undefined, ref: WireRunRef, maxRunDefinitionWireBytes: number,
  includeContext: boolean, maxOriginalExplanationWireBytes: number) {
  const sql = explanationReadSelection(database, ensureOpen, ref, includeContext);
  const row = database.prepare(`SELECT
    ${sql.present} AS facts_present, ${sql.matches} AS facet_matches,
    CASE WHEN typeof(r.run_definition_wire)='text' THEN length(CAST(r.run_definition_wire AS BLOB)) ELSE -1 END AS definition_bytes,
    CASE WHEN r.run_admission_evidence_json IS NULL THEN 0 WHEN typeof(r.run_admission_evidence_json)='text'
      THEN length(CAST(r.run_admission_evidence_json AS BLOB)) ELSE -1 END AS evidence_bytes,
    CASE WHEN typeof(r.program_definition_cid)='text' AND length(CAST(r.program_definition_cid AS BLOB))=71
      AND typeof(r.parameter_values_cid)='text' AND length(CAST(r.parameter_values_cid AS BLOB))=71 THEN 1 ELSE 0 END AS bindings_bounded,
    CASE WHEN ${sql.present} THEN CASE WHEN typeof(${sql.facts})='text'
      THEN length(CAST(${sql.facts} AS BLOB)) ELSE -1 END ELSE 0 END AS facts_bytes,
    ${sql.plan} AS plan_present, ${sql.planMatches} AS plan_matches,
    CASE WHEN ${sql.plan} THEN CASE WHEN typeof(${sql.compiledPlan})='text'
      THEN length(CAST(${sql.compiledPlan} AS BLOB)) ELSE -1 END ELSE 0 END AS compiled_plan_bytes,
    CASE WHEN ${sql.plan} THEN CASE WHEN typeof(${sql.planView})='text'
      THEN length(CAST(${sql.planView} AS BLOB)) ELSE -1 END ELSE 0 END AS plan_view_bytes
    ${includeContext ? `, ${sql.contextPresent} AS context_present,
      CASE WHEN ${sql.contextPresent} THEN CASE WHEN typeof(${sql.context})='text'
        THEN length(CAST(${sql.context} AS BLOB)) ELSE -1 END ELSE 0 END AS context_bytes,
      CASE WHEN ${sql.contextPresent} THEN CASE WHEN typeof(${sql.contextHash})='text'
        THEN length(CAST(${sql.contextHash} AS BLOB)) ELSE -1 END ELSE 0 END AS context_hash_bytes,
      CASE WHEN ${sql.contextPresent} THEN CASE WHEN typeof(${sql.template})='text'
        THEN length(CAST(${sql.template} AS BLOB)) ELSE -1 END ELSE 0 END AS invocation_template_bytes` : ''}
    ${sql.from}`).get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid) as ExplanationProbeRow | undefined;
  if (row === undefined) return undefined;
  if (row.facet_matches !== 1 || row.bindings_bounded !== 1 || row.plan_matches !== 1 ||
      ![row.definition_bytes, row.evidence_bytes, row.facts_bytes, row.compiled_plan_bytes, row.plan_view_bytes].every(value =>
        Number.isSafeInteger(value) && value >= 0 && value <= maxRunDefinitionWireBytes) ||
      row.definition_bytes < 1 || row.facts_present === 1 && row.facts_bytes < 1 ||
      row.plan_present === 1 && (row.compiled_plan_bytes < 1 || row.plan_view_bytes < 1 ||
        row.facts_present !== 1)) {
    fail('ClientRequestJournalCorrupt');
  }
  const contextBytes = includeContext ? row.context_bytes! : 0;
  const invocationTemplateBytes = includeContext ? row.invocation_template_bytes! : 0;
  const planBytes = row.compiled_plan_bytes + row.plan_view_bytes;
  if (!Number.isSafeInteger(contextBytes) || contextBytes < 0 ||
      !Number.isSafeInteger(invocationTemplateBytes) || invocationTemplateBytes < 0 ||
      row.facts_bytes + contextBytes + invocationTemplateBytes > maxRunDefinitionWireBytes ||
      row.plan_present === 1 &&
        row.facts_bytes + planBytes + contextBytes + invocationTemplateBytes > maxOriginalExplanationWireBytes ||
      row.context_present === 1 &&
        (contextBytes < 1 || row.context_hash_bytes !== 64 ||
          invocationTemplateBytes < 1 || row.facts_present !== 1)) {
    fail('ClientRequestJournalCorrupt');
  }
  const extent: {-readonly [Key in keyof ExplanationExtent]: ExplanationExtent[Key]} = {definitionBytes: row.definition_bytes, evidenceBytes: row.evidence_bytes,
    factsBytes: row.facts_bytes,
    storedBytes: row.definition_bytes + row.evidence_bytes + row.facts_bytes +
      contextBytes + invocationTemplateBytes + planBytes + (contextBytes > 0 ? 64 : 0) + 142};
  if (row.plan_present === 1) {
    extent.compiledPlanBytes = row.compiled_plan_bytes;
    extent.planViewBytes = row.plan_view_bytes;
  }
  if (includeContext) {
    extent.contextBytes = contextBytes;
    extent.invocationTemplateBytes = invocationTemplateBytes;
  }
  return Object.freeze(extent);
}
export function readJournalExplanation(database: JournalSqlConnection,
  ensureOpen: () => undefined, ref: WireRunRef, extent: ExplanationExtent, maxRunDefinitionWireBytes: number,
  includeContext: boolean, maxOriginalExplanationWireBytes: number) {
  const compiledPlanBytes = extent?.compiledPlanBytes ?? 0, planViewBytes = extent?.planViewBytes ?? 0;
  const planBytes = compiledPlanBytes + planViewBytes;
  const bounds = [extent?.definitionBytes, extent?.evidenceBytes, extent?.factsBytes, compiledPlanBytes, planViewBytes];
  if (includeContext) bounds.push(extent?.contextBytes!, extent?.invocationTemplateBytes!);
  if (!bounds.every(value => Number.isSafeInteger(value) && value >= 0 && value <= maxRunDefinitionWireBytes) ||
      includeContext && (extent.factsBytes + extent.contextBytes! + extent.invocationTemplateBytes! > maxRunDefinitionWireBytes ||
        (extent.contextBytes === 0) !== (extent.invocationTemplateBytes === 0) ||
        extent.contextBytes! > 0 && extent.factsBytes === 0) ||
      (compiledPlanBytes === 0) !== (planViewBytes === 0) ||
      planBytes > 0 && (extent.factsBytes === 0 ||
        extent.factsBytes + planBytes + (includeContext ? extent.contextBytes! + extent.invocationTemplateBytes! : 0) > maxOriginalExplanationWireBytes) ||
      extent.definitionBytes < 1 || extent.storedBytes !== bounds.reduce((sum, value) => sum + value,
        142 + (includeContext && extent.contextBytes! > 0 ? 64 : 0))) {
    fail('InvalidClientRunExplanationExtent');
  }
  const sql = explanationReadSelection(database, ensureOpen, ref, includeContext);
  // Recheck EACH scalar/wire inside the same native full-row SELECT. A
  // changed/corrupt row cannot return oversized text after a small probe;
  // NULL is an explicit rejected original, never truncated valid evidence.
  const statement = database.prepare(`SELECT ${sql.present} AS facts_present, ${sql.matches} AS facet_matches,
    CASE WHEN typeof(r.run_definition_wire)='text' AND length(CAST(r.run_definition_wire AS BLOB)) BETWEEN 1 AND ?
      THEN r.run_definition_wire ELSE NULL END AS definition_wire,
    CASE WHEN r.run_admission_evidence_json IS NULL THEN NULL WHEN typeof(r.run_admission_evidence_json)='text'
      AND length(CAST(r.run_admission_evidence_json AS BLOB)) BETWEEN 1 AND ? THEN r.run_admission_evidence_json ELSE NULL END AS evidence_wire,
    r.run_admission_evidence_json IS NOT NULL AS evidence_present,
    CASE WHEN typeof(r.program_definition_cid)='text' AND length(CAST(r.program_definition_cid AS BLOB))=71
      THEN r.program_definition_cid ELSE NULL END AS program_cid,
    CASE WHEN typeof(r.parameter_values_cid)='text' AND length(CAST(r.parameter_values_cid AS BLOB))=71
      THEN r.parameter_values_cid ELSE NULL END AS parameters_cid,
    CASE WHEN ${sql.present} AND typeof(${sql.facts})='text' AND length(CAST(${sql.facts} AS BLOB)) BETWEEN 1 AND ?
      THEN ${sql.facts} ELSE NULL END AS facts_wire,
    ${sql.plan} AS plan_present, ${sql.planMatches} AS plan_matches,
    CASE WHEN ${sql.plan} AND typeof(${sql.compiledPlan})='text'
      AND length(CAST(${sql.compiledPlan} AS BLOB)) = ? THEN ${sql.compiledPlan} ELSE NULL END AS compiled_plan_wire,
    CASE WHEN ${sql.plan} AND typeof(${sql.planView})='text'
      AND length(CAST(${sql.planView} AS BLOB)) = ? THEN ${sql.planView} ELSE NULL END AS plan_view_wire
    ${includeContext ? `, ${sql.contextPresent} AS context_present,
      CASE WHEN ${sql.contextPresent} AND typeof(${sql.context})='text'
        AND length(CAST(${sql.context} AS BLOB)) = ? THEN ${sql.context} ELSE NULL END AS context_wire,
      CASE WHEN ${sql.contextPresent} AND typeof(${sql.contextHash})='text'
        AND length(CAST(${sql.contextHash} AS BLOB)) = 64 THEN ${sql.contextHash} ELSE NULL END AS context_wire_sha256,
      CASE WHEN ${sql.contextPresent} AND typeof(${sql.template})='text'
        AND length(CAST(${sql.template} AS BLOB)) = ? THEN ${sql.template} ELSE NULL END AS invocation_template_wire` : ''}
    ${sql.from}`);
  const row = (includeContext
    ? statement.get(extent.definitionBytes, extent.evidenceBytes, extent.factsBytes, compiledPlanBytes, planViewBytes,
      extent.contextBytes!, extent.invocationTemplateBytes!,
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid)
    : statement.get(extent.definitionBytes, extent.evidenceBytes, extent.factsBytes, compiledPlanBytes, planViewBytes,
      ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid)) as ExplanationOriginalRow | undefined;
  if (row === undefined) return undefined;
  if (row.facet_matches !== 1 || row.plan_matches !== 1 || row.definition_wire === null || !cid(row.program_cid) || !cid(row.parameters_cid) ||
      row.evidence_present === 1 && row.evidence_wire === null || row.facts_present === 1 && row.facts_wire === null ||
      (row.plan_present === 1) !== (planBytes > 0) ||
      row.plan_present === 1 && (row.compiled_plan_wire === null || row.plan_view_wire === null || row.facts_present !== 1) ||
      includeContext && ((row.context_present === 1) !== (extent.contextBytes! > 0) ||
        row.context_present === 1 && (row.context_wire === null ||
          typeof row.context_wire_sha256 !== 'string' || !/^[0-9a-f]{64}$/u.test(row.context_wire_sha256) ||
          row.invocation_template_wire === null || row.facts_present !== 1))) {
    fail('ClientRequestJournalCorrupt');
  }
  if (includeContext && row.context_present === 1 &&
      createHash('sha256').update(ref.runDefinitionCid).update(row.context_wire!).digest('hex') !== row.context_wire_sha256) {
    fail('ClientRequestJournalCorrupt');
  }
  const result: {definitionWire: string; admissionEvidenceWire?: string;
    programDefinitionCid: string; parameterValuesCid: string; factsWire?: string;
    contextWire?: string; invocationTemplateWire?: string; compiledPlanWire?: string; planViewWire?: string} = {definitionWire: row.definition_wire, admissionEvidenceWire: row.evidence_wire ?? undefined,
    programDefinitionCid: row.program_cid, parameterValuesCid: row.parameters_cid,
    factsWire: row.facts_present === 1 ? row.facts_wire! : undefined};
  if (row.plan_present === 1) {
    result.compiledPlanWire = row.compiled_plan_wire!;
    result.planViewWire = row.plan_view_wire!;
  }
  if (includeContext) {
    result.contextWire = row.context_present === 1 ? row.context_wire! : undefined;
    result.invocationTemplateWire = row.context_present === 1 ? row.invocation_template_wire! : undefined;
  }
  return Object.freeze(result);
}
export function insertJournalExplanationOriginal(database: JournalSqlConnection,
  ref: WireRunRef, original: ExplanationOriginal): void {
  // This runs inside the SAME semantic acceptance transaction, after the
  // original request row and before its COMMIT. No backfill path calls it.
  if (!inspectExplanationOriginalStorage(database)) database.exec(explanationOriginalTable);
  database.prepare(`INSERT INTO client_run_explanation_originals
      (namespace_id, authority_scope_cid, run_definition_cid, facts_wire) VALUES (?, ?, ?, ?)`)
    .run(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, original.factsWire);
  if (original.contextWire !== undefined) {
    if (!inspectExplanationContextOriginalStorage(database)) database.exec(explanationContextOriginalTable);
    database.prepare(`INSERT INTO client_run_explanation_context_originals
        (run_definition_cid, context_wire, context_wire_sha256, invocation_template_wire) VALUES (?, ?, ?, ?)`)
      .run(ref.runDefinitionCid, original.contextWire, original.contextWireSha256!, original.invocationTemplateWire!);
  }
  if (original.plan !== undefined) {
    if (!inspectExplanationPlanOriginalStorage(database)) database.exec(explanationPlanOriginalTable);
    database.prepare(`INSERT INTO client_run_explanation_plan_originals
      (run_definition_cid, compiled_plan_wire, plan_view_wire) VALUES (?, ?, ?)`)
      .run(ref.runDefinitionCid, original.plan.compiledPlanWire, original.plan.planViewWire);
  }
}

// The existing acceptance transaction compares the companion in SQLite. A
// duplicate cannot backfill absent Context or project a second copy of it.
export function verifyJournalExplanationContext(database: JournalSqlConnection,
  runDefinitionCid: string, original: ExplanationOriginal): void {
  if (!inspectExplanationContextOriginalStorage(database)) fail('ClientRequestExplanationEvidenceMissing');
  const context = database.prepare(`SELECT
              (context_wire = ? AND context_wire_sha256 = ? AND invocation_template_wire = ?) AS original_matches
              FROM client_run_explanation_context_originals WHERE run_definition_cid = ?`)
    .get(original.contextWire!, original.contextWireSha256!, original.invocationTemplateWire!, runDefinitionCid);
  if (context === undefined) fail('ClientRequestExplanationEvidenceMissing');
  if (context.original_matches !== 1) fail('ClientRequestExplanationEvidenceMismatch');
}

// An idempotent acceptance may compare the exact original companion only.
export function verifyJournalExplanationPlan(database: JournalSqlConnection,
  runDefinitionCid: string, original: NonNullable<ExplanationOriginal['plan']>): void {
  const stored = inspectExplanationPlanOriginalStorage(database) ?
    database.prepare(`SELECT (compiled_plan_wire = ? AND plan_view_wire = ?) AS original_matches
      FROM client_run_explanation_plan_originals WHERE run_definition_cid = ?`)
      .get(original.compiledPlanWire, original.planViewWire, runDefinitionCid) : undefined;
  if (stored === undefined) fail('ClientRequestPlanEvidenceMissing');
  if (stored.original_matches !== 1) fail('ClientRequestPlanEvidenceMismatch');
}

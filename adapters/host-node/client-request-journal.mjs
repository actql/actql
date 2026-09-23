// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import {DatabaseSync} from 'node:sqlite';
import {closeSync, existsSync, fsyncSync, mkdirSync, openSync,
  realpathSync} from 'node:fs';
import {join} from 'node:path';

const cid = value => typeof value === 'string' &&
  /^sha256:[0-9a-f]{64}$/u.test(value);
const text = value => typeof value === 'string' &&
  value.length > 0 && value.length <= 256 &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const pathText = value => typeof value === 'string' && value.length > 0;
const instant = value => typeof value === 'string' &&
  /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/u.test(value) &&
  Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value;
const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};

function syncDirectory(path) {
  const descriptor = openSync(path, 'r');
  try { fsyncSync(descriptor); }
  finally { closeSync(descriptor); }
}

function checkedIdentity(handle, control) {
  const fields = {
    authorityScopeCid: control.clientRequestAuthorityScopeCid(handle),
    requestId: control.clientRequestCallerId(handle),
    logicalRequestScopeCid: control.clientRequestScopeCid(handle),
    intentFingerprintCid: control.clientRequestIntentCid(handle),
    programDefinitionCid: control.clientRequestProgramCid(handle),
    parameterValuesCid: control.clientRequestParametersCid(handle),
    callerInputIntentCid: control.clientRequestInputCid(handle),
  };
  if (!text(fields.requestId) ||
      ![fields.authorityScopeCid, fields.logicalRequestScopeCid,
        fields.intentFingerprintCid, fields.programDefinitionCid,
        fields.parameterValuesCid, fields.callerInputIntentCid].every(cid) ||
      control.clientRequestAdmitRecord(
        fields.authorityScopeCid, fields.requestId,
        fields.programDefinitionCid, fields.parameterValuesCid,
        fields.callerInputIntentCid, fields.logicalRequestScopeCid,
        fields.intentFingerprintCid) === undefined) {
    fail('InvalidClientRequestIdentity');
  }
  return Object.freeze(fields);
}

function retainedIdentity(row, control) {
  const value = control.clientRequestAdmitRecord(
    row.authority_scope_cid, row.caller_request_id,
    row.program_definition_cid, row.parameter_values_cid,
    row.caller_input_intent_cid, row.logical_request_scope_cid,
    row.intent_fingerprint_cid,
  );
  if (value === undefined) fail('ClientRequestJournalCorrupt');
  return value;
}

function admission(row) {
  if (!text(row.tenant_id) || !cid(row.authority_scope_cid) ||
      !cid(row.run_definition_cid) ||
      !Number.isSafeInteger(row.revision) || row.revision < 0 ||
      !instant(row.lookup_expires_at)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    ref: Object.freeze({
      tenantId: row.tenant_id,
      authorityScopeCid: row.authority_scope_cid,
      runDefinitionCid: row.run_definition_cid,
    }),
    durability: 'durable',
    revision: Number(row.revision),
    lookupExpiresAt: row.lookup_expires_at,
  });
}

const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  tenant_id, run_definition_cid, revision, lookup_expires_at`;

export function openClientRequestJournal(directory, {
  maxRecords = 100_000,
} = {}) {
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      maxRecords < 1) fail('InvalidClientRequestJournalConfiguration');
  mkdirSync(directory, {recursive: true, mode: 0o700});
  const root = realpathSync(directory);
  const path = join(root, 'client-requests.sqlite3');
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
    database.exec(`
      CREATE TABLE IF NOT EXISTS client_requests (
        authority_scope_cid TEXT NOT NULL,
        caller_request_id TEXT NOT NULL,
        logical_request_scope_cid TEXT NOT NULL UNIQUE,
        intent_fingerprint_cid TEXT NOT NULL,
        program_definition_cid TEXT NOT NULL,
        parameter_values_cid TEXT NOT NULL,
        caller_input_intent_cid TEXT NOT NULL,
        tenant_id TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL UNIQUE,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        lookup_expires_at TEXT NOT NULL,
        PRIMARY KEY (authority_scope_cid, caller_request_id)
      ) STRICT;
    `);
    if (!existed) syncDirectory(root);
  } catch (error) {
    database.close();
    throw error;
  }
  const ensureOpen = () => {
    if (closed) fail('ClientRequestJournalClosed');
  };
  const select = database.prepare(`SELECT ${columns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`);
  const selectRun = database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_requests');
  const insert = database.prepare(`INSERT INTO client_requests (${columns})
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);

  return Object.freeze({
    // The transaction owns uniqueness and durable acceptance; no task is
    // started here. A duplicate is interpreted only by the common MoonBit
    // relation, never by comparing transport JSON or a local retry counter.
    accept(identity, {tenantId, runDefinitionCid, revision = 0,
      lookupExpiresAt}, control) {
      ensureOpen();
      if (!control || typeof control.clientRequestAdmitRecord !== 'function' ||
          typeof control.clientRequestRelation !== 'function') {
        fail('InvalidClientRequestJournalControl');
      }
      const fields = checkedIdentity(identity, control);
      if (!text(tenantId) || !cid(runDefinitionCid) ||
          !Number.isSafeInteger(revision) || revision < 0 ||
          !instant(lookupExpiresAt) ||
          Date.parse(lookupExpiresAt) <= Date.now()) {
        fail('InvalidClientRequestAdmission');
      }
      database.exec('BEGIN IMMEDIATE');
      try {
        const existing = select.get(fields.authorityScopeCid,
          fields.requestId);
        if (existing !== undefined) {
          if (existing.tenant_id !== tenantId) {
            fail('ClientRequestOwnerMismatch');
          }
          const relation = control.clientRequestRelation(identity,
            retainedIdentity(existing, control));
          if (relation !== 1) {
            fail(relation === 2 ? 'ClientRequestIntentConflict' :
              'ClientRequestJournalCorrupt');
          }
          database.exec('COMMIT');
          return Object.freeze({inserted: false, ...admission(existing)});
        }
        if (Number(count.get().n) >= maxRecords) {
          fail('ClientRequestJournalCapacity');
        }
        if (selectRun.get(runDefinitionCid) !== undefined) {
          fail('ClientRequestRunAlreadyAssigned');
        }
        insert.run(fields.authorityScopeCid, fields.requestId,
          fields.logicalRequestScopeCid, fields.intentFingerprintCid,
          fields.programDefinitionCid, fields.parameterValuesCid,
          fields.callerInputIntentCid, tenantId, runDefinitionCid, revision,
          lookupExpiresAt);
        database.exec('COMMIT');
        return Object.freeze({inserted: true, ref: Object.freeze({
          tenantId, authorityScopeCid: fields.authorityScopeCid,
          runDefinitionCid,
        }), durability: 'durable', revision, lookupExpiresAt});
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          fail('ClientRequestAcceptanceUnknown', rollback);
        }
        if (typeof error?.code === 'string' &&
            error.code.startsWith('ClientRequest')) throw error;
        fail('ClientRequestAcceptanceUnknown', error);
      }
    },
    // Authorization and retention policy are performed by the Host before
    // exposing a found record. Physical lookup never starts Compute.
    lookup({tenantId, authorityScopeCid, requestId}, control) {
      ensureOpen();
      if (!text(tenantId) || !cid(authorityScopeCid) || !text(requestId) ||
          !control || typeof control.clientRequestAdmitRecord !== 'function') {
        fail('InvalidClientRequestLookup');
      }
      let row;
      try { row = select.get(authorityScopeCid, requestId); }
      catch (error) { fail('ClientRequestLookupUnknown', error); }
      if (row === undefined || row.tenant_id !== tenantId) return undefined;
      const identity = retainedIdentity(row, control);
      if (control.clientRequestScopeCid(identity) !==
          row.logical_request_scope_cid) {
        fail('ClientRequestJournalCorrupt');
      }
      return Object.freeze({
        requestId: row.caller_request_id,
        ...admission(row),
      });
    },
    close() {
      if (closed) return;
      closed = true;
      database.close();
    },
  });
}

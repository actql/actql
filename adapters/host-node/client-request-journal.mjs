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

function checkedRunDefinition(value, control, maxBytes) {
  if (value === null || typeof value !== 'object' ||
      value.name !== 'run_definition' || !cid(value.identity) ||
      typeof value.wire !== 'string' ||
      Buffer.byteLength(value.wire, 'utf8') > maxBytes ||
      control === null || typeof control !== 'object' ||
      typeof control.admit !== 'function') {
    fail('InvalidClientRunDefinition');
  }
  let admitted;
  try {
    admitted = control.admit('run_definition', value.wire, {
      maxWireBytes: maxBytes, maxNodes: 4096, maxDepth: 64,
    });
  } catch (cause) { fail('InvalidClientRunDefinition', cause); }
  if (admitted?.name !== 'run_definition' ||
      admitted.identity !== value.identity ||
      admitted.wire !== value.wire) {
    fail('InvalidClientRunDefinition');
  }
  return admitted;
}

function retainedRunDefinition(row, control, maxBytes) {
  if (typeof row.run_definition_wire !== 'string') {
    fail('ClientRequestDefinitionMissing');
  }
  let admitted;
  try {
    admitted = checkedRunDefinition({
      name: 'run_definition',
      identity: row.run_definition_cid,
      wire: row.run_definition_wire,
    }, control, maxBytes);
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return admitted;
}

const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  tenant_id, run_definition_cid, run_definition_wire, revision,
  lookup_expires_at`;

export function openClientRequestJournal(directory, {
  maxRecords = 100_000,
  maxRunDefinitionWireBytes = 65_536,
} = {}) {
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      maxRecords < 1 || !Number.isSafeInteger(maxRunDefinitionWireBytes) ||
      maxRunDefinitionWireBytes < 1024) {
    fail('InvalidClientRequestJournalConfiguration');
  }
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
        run_definition_wire TEXT,
        revision INTEGER NOT NULL CHECK (revision >= 0),
        lookup_expires_at TEXT NOT NULL,
        PRIMARY KEY (authority_scope_cid, caller_request_id)
      ) STRICT;
    `);
    const fields = database.prepare('PRAGMA table_info(client_requests)')
      .all();
    if (!fields.some(field => field.name === 'run_definition_wire')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'run_definition_wire TEXT');
    }
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
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);

  const acceptRecord = (identity, {tenantId, runDefinitionCid,
    runDefinitionWire, revision = 0, lookupExpiresAt}, control) => {
    ensureOpen();
    if (!control || typeof control.clientRequestAdmitRecord !== 'function' ||
        typeof control.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestJournalControl');
    }
    const fields = checkedIdentity(identity, control);
    if (!text(tenantId) || !cid(runDefinitionCid) ||
        runDefinitionWire !== undefined &&
          (typeof runDefinitionWire !== 'string' ||
            Buffer.byteLength(runDefinitionWire, 'utf8') >
              maxRunDefinitionWireBytes) ||
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
        if (runDefinitionWire !== undefined &&
            existing.run_definition_wire === null) {
          fail('ClientRequestDefinitionMissing');
        }
        database.exec('COMMIT');
        return Object.freeze({inserted: false, ...admission(existing),
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire})});
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
        fields.callerInputIntentCid, tenantId, runDefinitionCid,
        runDefinitionWire ?? null, revision, lookupExpiresAt);
      database.exec('COMMIT');
      return Object.freeze({inserted: true, ref: Object.freeze({
        tenantId, authorityScopeCid: fields.authorityScopeCid,
        runDefinitionCid,
      }), durability: 'durable', revision, lookupExpiresAt,
      ...(runDefinitionWire === undefined ? {} : {runDefinitionWire})});
    } catch (error) {
      try { database.exec('ROLLBACK'); }
      catch (rollback) {
        fail('ClientRequestAcceptanceUnknown', rollback);
      }
      if (typeof error?.code === 'string' &&
          error.code.startsWith('ClientRequest')) throw error;
      fail('ClientRequestAcceptanceUnknown', error);
    }
  };

  const lookupRecord = ({tenantId, authorityScopeCid, requestId}, control) => {
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
    return Object.freeze({row, found: Object.freeze({
      requestId: row.caller_request_id,
      ...admission(row),
    })});
  };

  const journal = Object.freeze({
    // The transaction owns uniqueness and durable acceptance; no task is
    // started here. A duplicate is interpreted only by the common MoonBit
    // relation, never by comparing transport JSON or a local retry counter.
    accept(identity, {tenantId, runDefinitionCid, revision = 0,
      lookupExpiresAt}, control) {
      return acceptRecord(identity, {tenantId, runDefinitionCid,
        revision, lookupExpiresAt}, control);
    },
    // The complete canonical Run Definition is retained in the same
    // transaction as the request. The caller must have obtained it from the
    // shared Run issuer; re-admission here checks identity, not authority.
    // Reattachment never reissues this identity.
    acceptDefinition(identity, {tenantId, runDefinition, revision = 0,
      lookupExpiresAt}, requestControl, publicationControl) {
      const definition = checkedRunDefinition(runDefinition,
        publicationControl, maxRunDefinitionWireBytes);
      const accepted = acceptRecord(identity, {tenantId,
        runDefinitionCid: definition.identity,
        runDefinitionWire: definition.wire,
        revision, lookupExpiresAt}, requestControl);
      return Object.freeze({
        inserted: accepted.inserted,
        ref: accepted.ref,
        durability: accepted.durability,
        revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt,
        runDefinition: retainedRunDefinition({
          run_definition_cid: accepted.ref.runDefinitionCid,
          run_definition_wire: accepted.runDefinitionWire,
        }, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // Authorization and retention policy are performed by the Host before
    // exposing a found record. Physical lookup never starts Compute.
    lookup(key, control) {
      return lookupRecord(key, control)?.found;
    },
    lookupDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        runDefinition: retainedRunDefinition(
          retained.row, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // A resend can resolve an already accepted request before issuing a new
    // plan or Run Definition. The shared owner compares the checked intent;
    // absence does not prove that a concurrent submission cannot still land.
    resolveDefinition(identity, {tenantId}, requestControl,
      publicationControl) {
      ensureOpen();
      if (!text(tenantId) || !requestControl ||
          typeof requestControl.clientRequestRelation !== 'function') {
        fail('InvalidClientRequestLookup');
      }
      const fields = checkedIdentity(identity, requestControl);
      const retained = lookupRecord({tenantId,
        authorityScopeCid: fields.authorityScopeCid,
        requestId: fields.requestId}, requestControl);
      if (retained === undefined) return undefined;
      const relation = requestControl.clientRequestRelation(identity,
        retainedIdentity(retained.row, requestControl));
      if (relation !== 1) {
        fail(relation === 2 ? 'ClientRequestIntentConflict' :
          'ClientRequestJournalCorrupt');
      }
      return Object.freeze({...retained.found,
        runDefinition: retainedRunDefinition(
          retained.row, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // Physical admit-or-lookup ordering for a checked request. The common
    // MoonBit relation decides whether a retained intent is the same request;
    // the callback may issue authority but must not start Compute. A racing
    // issuer is discarded when the atomic insert finds an existing Run.
    async admitOrLookupDefinition(identity, {tenantId, lookupExpiresAt,
      issueDefinition}, requestControl, publicationControl) {
      if (!text(tenantId) || !instant(lookupExpiresAt) ||
          Date.parse(lookupExpiresAt) <= Date.now() ||
          typeof issueDefinition !== 'function') {
        fail('InvalidClientRequestAdmission');
      }
      const retained = journal.resolveDefinition(identity, {tenantId},
        requestControl, publicationControl);
      if (retained !== undefined) {
        return Object.freeze({inserted: false, ...retained});
      }
      const runDefinition = await issueDefinition();
      return journal.acceptDefinition(identity, {tenantId, runDefinition,
        lookupExpiresAt}, requestControl, publicationControl);
    },
    close() {
      if (closed) return;
      closed = true;
      database.close();
    },
  });
  return journal;
}

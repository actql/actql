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
const failRollback = (code, operation, cause, rollbackCause) => {
  throw Object.assign(new Error(code, {cause}), {
    code, operation, rollbackCause, outcome: 'unknown',
  });
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

// Private replay evidence is stored atomically with acceptance. Its semantic
// admission remains with the common MoonBit owner before any physical start.
function evidenceJson(value, maxBytes) {
  if (value === undefined) return null;
  if (value === null || typeof value !== 'object' ||
      Object.keys(value).sort().join(',') !== 'authorization,prepared' ||
      typeof value.prepared !== 'string' ||
      typeof value.authorization !== 'string') {
    fail('InvalidClientRunAdmissionEvidence');
  }
  const wire = JSON.stringify(value);
  if (Buffer.byteLength(wire) > maxBytes) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  return wire;
}

function retainedEvidence(row) {
  return row.run_admission_evidence_json == null ? undefined :
    Object.freeze(JSON.parse(row.run_admission_evidence_json));
}

const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  tenant_id, run_definition_cid, run_definition_wire, revision,
  lookup_expires_at, result_names_json, run_admission_evidence_json`;
const selectColumns = `${columns}, dispatch_reserved,
  pre_dispatch_failure_confirmed, physical_start_reserved,
  cancellation_requested, physical_close_confirmed`;

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
        result_names_json TEXT,
        dispatch_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (dispatch_reserved IN (0, 1)),
        pre_dispatch_failure_confirmed INTEGER NOT NULL DEFAULT 0
          CHECK (pre_dispatch_failure_confirmed IN (0, 1)),
        physical_start_reserved INTEGER NOT NULL DEFAULT 0
          CHECK (physical_start_reserved IN (0, 1)),
        PRIMARY KEY (authority_scope_cid, caller_request_id)
      ) STRICT;
    `);
    const fields = database.prepare('PRAGMA table_info(client_requests)')
      .all();
    if (!fields.some(field => field.name === 'run_admission_evidence_json')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'run_admission_evidence_json TEXT');
    }
    if (!fields.some(field => field.name === 'run_definition_wire')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'run_definition_wire TEXT');
    }
    if (!fields.some(field => field.name === 'result_names_json')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'result_names_json TEXT');
    }
    if (!fields.some(field => field.name === 'dispatch_reserved')) {
      // An older journal may already have dispatched its accepted Runs.
      // Migration must never reinterpret them as safe to start again.
      database.exec('BEGIN IMMEDIATE');
      try {
        database.exec('ALTER TABLE client_requests ADD COLUMN '
          + 'dispatch_reserved INTEGER NOT NULL DEFAULT 0 '
          + 'CHECK (dispatch_reserved IN (0, 1))');
        database.exec('UPDATE client_requests SET dispatch_reserved = 1');
        database.exec('COMMIT');
      } catch (error) {
        database.exec('ROLLBACK');
        throw error;
      }
    }
    if (!fields.some(field => field.name ===
        'pre_dispatch_failure_confirmed')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'pre_dispatch_failure_confirmed INTEGER NOT NULL DEFAULT 0 '
        + 'CHECK (pre_dispatch_failure_confirmed IN (0, 1))');
    }
    if (!fields.some(field => field.name === 'physical_start_reserved')) {
      // Existing reserved Runs may have started physical work. Keep their
      // observation unknown, while new rows default to confirmed unstarted.
      database.exec('BEGIN IMMEDIATE');
      try {
        database.exec('ALTER TABLE client_requests ADD COLUMN '
          + 'physical_start_reserved INTEGER DEFAULT 0 '
          + 'CHECK (physical_start_reserved IN (0, 1))');
        database.exec('UPDATE client_requests SET physical_start_reserved = '
          + 'NULL WHERE dispatch_reserved = 1');
        database.exec('COMMIT');
      } catch (error) {
        database.exec('ROLLBACK');
        throw error;
      }
    }
    for (const field of ['cancellation_requested', 'physical_close_confirmed']) {
      if (!fields.some(item => item.name === field)) {
        database.exec(`ALTER TABLE client_requests ADD COLUMN ${field} ` +
          `INTEGER NOT NULL DEFAULT 0 CHECK (${field} IN (0, 1))`);
      }
    }
    if (!fields.some(field => field.name === 'reconciliation_state_wire')) {
      database.exec('ALTER TABLE client_requests ADD COLUMN '
        + 'reconciliation_state_wire TEXT');
    }
    if (!existed) syncDirectory(root);
  } catch (error) {
    database.close();
    throw error;
  }
  const ensureOpen = () => {
    if (closed) fail('ClientRequestJournalClosed');
  };
  const select = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`);
  const selectRef = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE tenant_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ?`);
  const selectRun = database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_requests');
  const insert = database.prepare(`INSERT INTO client_requests (${columns})
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const reserve = database.prepare(`UPDATE client_requests
    SET dispatch_reserved = 1, revision = revision + 1
    WHERE authority_scope_cid = ? AND caller_request_id = ? AND
      dispatch_reserved = 0`);
  const confirmPreDispatchFailure = database.prepare(`UPDATE client_requests
    SET pre_dispatch_failure_confirmed = 1, revision = revision + 1
    WHERE tenant_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);
  const reservePhysicalStart = database.prepare(`UPDATE client_requests
    SET physical_start_reserved = 1, revision = revision + 1
    WHERE tenant_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);

  const acceptRecord = (identity, {tenantId, runDefinitionCid,
    runDefinitionWire, resultNames, runAdmissionEvidence, revision = 0, lookupExpiresAt}, control) => {
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
        resultNames !== undefined && (!Array.isArray(resultNames) ||
          resultNames.length === 0 || resultNames.length > 100 ||
          resultNames.some(name => typeof name !== 'string' || !name) ||
          new Set(resultNames).size !== resultNames.length ||
          Buffer.byteLength(JSON.stringify(resultNames)) > 8192) ||
        !instant(lookupExpiresAt) ||
        Date.parse(lookupExpiresAt) <= Date.now()) {
      fail('InvalidClientRequestAdmission');
    }
    const admissionEvidence = evidenceJson(runAdmissionEvidence,
      maxRunDefinitionWireBytes);
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
        if (resultNames !== undefined &&
            existing.result_names_json !== null &&
            existing.result_names_json !== JSON.stringify(resultNames)) {
          fail('ClientRequestResultInventoryMismatch');
        }
        database.exec('COMMIT');
        return Object.freeze({inserted: false, ...admission(existing),
          runAdmissionEvidence: retainedEvidence(existing),
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire}),
          resultNames: existing.result_names_json === null ? undefined :
            JSON.parse(existing.result_names_json)});
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
        runDefinitionWire ?? null, revision, lookupExpiresAt,
        resultNames === undefined ? null : JSON.stringify(resultNames),
        admissionEvidence);
      database.exec('COMMIT');
      return Object.freeze({inserted: true, ref: Object.freeze({
        tenantId, authorityScopeCid: fields.authorityScopeCid,
        runDefinitionCid,
      }), durability: 'durable', revision, lookupExpiresAt,
      ...(runDefinitionWire === undefined ? {} : {runDefinitionWire}),
      resultNames, runAdmissionEvidence: admissionEvidence === null ? undefined :
        Object.freeze(JSON.parse(admissionEvidence))});
    } catch (error) {
      try { database.exec('ROLLBACK'); }
      catch (rollback) {
        failRollback('ClientRequestAcceptanceUnknown', 'accept', error,
          rollback);
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
    return Object.freeze({row, identity, found: Object.freeze({
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
    acceptDefinition(identity, {tenantId, runDefinition, resultNames, runAdmissionEvidence,
      revision = 0, lookupExpiresAt}, requestControl, publicationControl) {
      const definition = checkedRunDefinition(runDefinition,
        publicationControl, maxRunDefinitionWireBytes);
      const accepted = acceptRecord(identity, {tenantId,
        runDefinitionCid: definition.identity,
        runDefinitionWire: definition.wire,
        resultNames, runAdmissionEvidence, revision, lookupExpiresAt}, requestControl);
      return Object.freeze({
        inserted: accepted.inserted,
        ref: accepted.ref,
        durability: accepted.durability,
        revision: accepted.revision,
        lookupExpiresAt: accepted.lookupExpiresAt,
        resultNames: accepted.resultNames,
        runAdmissionEvidence: accepted.runAdmissionEvidence,
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
    // Internal owner recovery, not a wire credential or current permission.
    // Both logical keys are re-admitted before the caller can reuse the scope.
    lookupIdentity(key, control) {
      return lookupRecord(key, control)?.identity;
    },
    lookupDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        runDefinition: retainedRunDefinition(
          retained.row, publicationControl, maxRunDefinitionWireBytes),
        resultNames: retained.row.result_names_json === null ? undefined :
          JSON.parse(retained.row.result_names_json),
        runAdmissionEvidence: retainedEvidence(retained.row),
        cancellationRequested: retained.row.cancellation_requested === 1,
        physicalCloseConfirmed: retained.row.physical_close_confirmed === 1,
        dispatchReserved: retained.row.dispatch_reserved === 1,
        preDispatchFailureConfirmed:
          retained.row.pre_dispatch_failure_confirmed === 1,
        physicalStartReserved: retained.row.physical_start_reserved === null
          ? undefined : retained.row.physical_start_reserved === 1,
      });
    },
    // Attach reads the original accepted Run Definition by its exact ref.
    // It does not infer authority from a CID alone or create another Run.
    lookupRunDefinition(ref, requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof requestControl?.clientRequestAdmitRecord !== 'function') {
        fail('InvalidClientRunLookup');
      }
      let row;
      try {
        row = selectRef.get(ref.tenantId, ref.authorityScopeCid,
          ref.runDefinitionCid);
      } catch (error) { fail('ClientRequestLookupUnknown', error); }
      if (row === undefined) return undefined;
      const retained = retainedIdentity(row, requestControl);
      if (requestControl.clientRequestScopeCid(retained) !==
          row.logical_request_scope_cid) {
        fail('ClientRequestJournalCorrupt');
      }
      const accepted = admission(row);
      return Object.freeze({
        ref: accepted.ref, durability: accepted.durability,
        revision: accepted.revision,
        resultNames: row.result_names_json === null ? undefined :
          JSON.parse(row.result_names_json),
        runAdmissionEvidence: retainedEvidence(row),
        cancellationRequested: row.cancellation_requested === 1,
        physicalCloseConfirmed: row.physical_close_confirmed === 1,
        dispatchReserved: row.dispatch_reserved === 1,
        preDispatchFailureConfirmed:
          row.pre_dispatch_failure_confirmed === 1,
        physicalStartReserved: row.physical_start_reserved === null
          ? undefined : row.physical_start_reserved === 1,
        runDefinition: retainedRunDefinition(
          row, publicationControl, maxRunDefinitionWireBytes),
      });
    },
    // Recover identity and Definition from one physical journal observation.
    // This internal owner must not be projected as a Client wire response.
    lookupOwnedDefinition(key, requestControl, publicationControl) {
      const retained = lookupRecord(key, requestControl);
      if (retained === undefined) return undefined;
      return Object.freeze({...retained.found,
        requestIdentity: retained.identity,
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
        resultNames: retained.row.result_names_json === null ? undefined :
          JSON.parse(retained.row.result_names_json),
        runAdmissionEvidence: retainedEvidence(retained.row),
        cancellationRequested: retained.row.cancellation_requested === 1,
        physicalCloseConfirmed: retained.row.physical_close_confirmed === 1,
        dispatchReserved: retained.row.dispatch_reserved === 1,
        preDispatchFailureConfirmed:
          retained.row.pre_dispatch_failure_confirmed === 1,
        physicalStartReserved: retained.row.physical_start_reserved === null
          ? undefined : retained.row.physical_start_reserved === 1,
      });
    },
    // Physical admit-or-lookup ordering for a checked request. The common
    // MoonBit relation decides whether a retained intent is the same request;
    // the callback may issue authority but must not start Compute. A racing
    // issuer is discarded when the atomic insert finds an existing Run.
    async admitOrLookupDefinition(identity, {tenantId, lookupExpiresAt,
      issueDefinition, resultNames}, requestControl, publicationControl) {
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
      const issued = await issueDefinition();
      const runDefinition = issued.runDefinition ?? issued;
      return journal.acceptDefinition(identity, {tenantId, runDefinition,
        runAdmissionEvidence: issued.runAdmissionEvidence,
        lookupExpiresAt, resultNames: issued.resultNames ?? resultNames}, requestControl, publicationControl);
    },
    // One physical transaction applies the common MoonBit start decision.
    // A committed reservation records possible dispatch before any work. A
    // later caller must reconcile that Run rather than run Compute again.
    reserveDispatch(identity, {tenantId, currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(tenantId) || typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunStartAction !== 'function') {
        fail('InvalidClientRunStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      database.exec('BEGIN IMMEDIATE');
      try {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.tenant_id !== tenantId) {
          fail('ClientRunStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunStartAction(identity, retained,
          definition, row.run_definition_cid, row.dispatch_reserved === 1,
          currentAuthorization);
        if (action === 0) {
          if (reserve.run(fields.authorityScopeCid, fields.requestId)
            .changes !== 1) {
            fail('ClientRequestJournalCorrupt');
          }
          database.exec('COMMIT');
          return Object.freeze({kind: 'reserved',
            ...admission({...row, revision: Number(row.revision) + 1})});
        }
        if (action === 1) {
          database.exec('COMMIT');
          return Object.freeze({kind: 'reconcile', ...admission(row)});
        }
        fail(action === 3 ? 'ClientRequestIntentConflict' :
          action === 5 ? 'ClientRunStartDenied' :
          'ClientRequestJournalCorrupt');
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          failRollback('ClientRunStartUnknown', 'start', error, rollback);
        }
        if (typeof error?.code === 'string' &&
            (error.code.startsWith('ClientRequest') ||
              error.code.startsWith('ClientRun'))) throw error;
        fail('ClientRunStartUnknown', error);
      }
    },
    // The exact durable claim precedes the call that can start physical
    // Compute. A missing claim is safe to resume; a claim or legacy unknown
    // is never evidence that Compute did not run.
    reservePhysicalStart(identity, {tenantId, ref, currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(tenantId) || !text(ref?.tenantId) ||
          !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunPhysicalStartWithCancellationAction !==
            'function') {
        fail('InvalidClientRunPhysicalStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      database.exec('BEGIN IMMEDIATE');
      try {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.tenant_id !== tenantId ||
            ref.tenantId !== tenantId ||
            ref.authorityScopeCid !== fields.authorityScopeCid ||
            ref.runDefinitionCid !== row.run_definition_cid) {
          fail('ClientRunPhysicalStartDenied');
        }
        const retained = retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunPhysicalStartWithCancellationAction(
          identity, retained, definition, row.run_definition_cid,
          row.dispatch_reserved === 1,
          row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved === 0,
          currentAuthorization, row.cancellation_requested === 1);
        if (action === 0) {
          database.exec('COMMIT');
          return false;
        }
        if (action !== 1) {
          fail(action === 3 ? 'ClientRequestIntentConflict' :
            action === 5 ? 'ClientRunPhysicalStartDenied' :
            'ClientRequestJournalCorrupt');
        }
        if (reservePhysicalStart.run(ref.tenantId,
          ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
        database.exec('COMMIT');
        return true;
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          failRollback('ClientRunPhysicalStartUnknown', 'physical_start',
            error, rollback);
        }
        if (typeof error?.code === 'string' &&
            (error.code.startsWith('ClientRun') ||
              error.code.startsWith('ClientRequest'))) throw error;
        fail('ClientRunPhysicalStartUnknown', error);
      }
    },
    // Persist the common cancellation decision under the physical-start lock.
    // The Host observes publication separately; a racing commit can still win.
    requestCancellation(ref, {currentAuthorization, publicationCommitted},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') {
        fail('InvalidClientRunCancellation');
      }
      database.exec('BEGIN IMMEDIATE');
      try {
        const row = selectRef.get(ref.tenantId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined) fail('ClientRunCancellationDenied');
        retainedIdentity(row, requestControl);
        const definition = retainedRunDefinition(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunCancellationAction(definition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || row.pre_dispatch_failure_confirmed === 1,
          row.cancellation_requested === 1);
        if (![0, 1, 2].includes(action)) fail('ClientRunCancellationDenied');
        if (action === 0) {
          database.prepare(`UPDATE client_requests SET
            cancellation_requested = 1, revision = revision + 1
            WHERE tenant_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(ref.tenantId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
        database.exec('COMMIT');
        return Object.freeze({ref: admission(row).ref,
          kind: ['accepted', 'already_requested', 'already_terminal'][action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          failRollback('ClientRunCancellationUnknown', 'cancel', error,
            rollback);
        }
        if (error?.code === 'ClientRunCancellationDenied') throw error;
        fail('ClientRunCancellationUnknown', error);
      }
    },
    // Only the live execution owner may report a completed physical close.
    // A restarted process cannot infer this from its empty worker map.
    markPhysicalClose(ref) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunStopObservation');
      }
      database.prepare(`UPDATE client_requests SET
        physical_close_confirmed = 1, revision = revision + 1
        WHERE tenant_id = ? AND authority_scope_cid = ? AND
          run_definition_cid = ? AND physical_start_reserved = 1 AND
          physical_close_confirmed = 0`).run(ref.tenantId,
        ref.authorityScopeCid, ref.runDefinitionCid);
    },
    // Physical Host evidence only: a failure before invoking Site execution
    // is confirmed. A lost reply or absent worker cannot call this method.
    markPreDispatchFailure(ref) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunFailureObservation');
      }
      database.exec('BEGIN IMMEDIATE');
      try {
        const row = selectRef.get(ref.tenantId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.dispatch_reserved !== 1 ||
            row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved !== 0) {
          fail('ClientRunFailureObservationDenied');
        }
        if (row.pre_dispatch_failure_confirmed === 0 &&
            confirmPreDispatchFailure.run(ref.tenantId,
              ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
        database.exec('COMMIT');
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          failRollback('ClientRunFailureObservationUnknown',
            'failure_observation', error, rollback);
        }
        if (typeof error?.code === 'string' &&
            (error.code.startsWith('ClientRun') ||
              error.code.startsWith('ClientRequest'))) throw error;
        fail('ClientRunFailureObservationUnknown', error);
      }
    },
    // Keep the owner-issued `needs_reconciliation` state of a started Run
    // whose Effect outcomes are unknown. It is recorded once and never
    // replaced: a different state for the same Run is a conflict.
    recordReconciliationState(ref, wire) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) || typeof wire !== 'string' ||
          Buffer.byteLength(wire, 'utf8') > maxRunDefinitionWireBytes) {
        fail('InvalidClientRunReconciliation');
      }
      let state;
      try { state = JSON.parse(wire); }
      catch { fail('InvalidClientRunReconciliation'); }
      if (state?.status !== 'needs_reconciliation' ||
          state?.next_action?.kind !== 'reconcile') {
        fail('InvalidClientRunReconciliation');
      }
      database.exec('BEGIN IMMEDIATE');
      try {
        const row = database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE tenant_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`).get(ref.tenantId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1) {
          fail('ClientRunReconciliationDenied');
        }
        if (row.reconciliation_state_wire !== null &&
            row.reconciliation_state_wire !== wire) {
          fail('ClientRunReconciliationConflict');
        }
        if (row.reconciliation_state_wire === null) {
          database.prepare(`UPDATE client_requests SET
            reconciliation_state_wire = ?, revision = revision + 1
            WHERE tenant_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(wire, ref.tenantId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
        database.exec('COMMIT');
      } catch (error) {
        try { database.exec('ROLLBACK'); }
        catch (rollback) {
          failRollback('ClientRunReconciliationUnknown', 'reconciliation',
            error, rollback);
        }
        if (typeof error?.code === 'string' &&
            error.code.startsWith('ClientRun')) throw error;
        fail('ClientRunReconciliationUnknown', error);
      }
    },
    lookupReconciliationState(ref) {
      ensureOpen();
      if (!text(ref?.tenantId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunLookup');
      }
      const row = database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE tenant_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`).get(
        ref.tenantId, ref.authorityScopeCid, ref.runDefinitionCid);
      return row?.reconciliation_state_wire ?? undefined;
    },
    close() {
      if (closed) return;
      closed = true;
      database.close();
    },
  });
  return journal;
}

// Physical durable storage for an owner-issued Client request and Run ref.
// MoonBit supplies and re-admits the identity and decides intent conflicts.
import {DatabaseSync} from 'node:sqlite';
import {createHash, createHmac, randomBytes, timingSafeEqual} from 'node:crypto';
import {closeSync, existsSync, fsyncSync, lstatSync,
  mkdirSync, openSync, readFileSync, readdirSync,
  realpathSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createSqliteTransaction, throwSqliteInitializationFailure} from
  '../host-common/sqlite-transaction.mjs';
import {inspectSqliteSnapshot} from '../host-common/sqlite-format-inspection.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';
import {isHostObservationProjection} from '../host-common/observation.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {canonicalJson as canonicalValueJson} from '../../packages/sdk/host-port.mjs';
import {valuesExecutionContextCid} from './local-values-capacity.mjs';
import {sameSubmissionRef, validSubmissionOutcome, validStoredSubmissionOutcome} from '../../packages/client-wire/index.mjs';

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
  if (!text(row.namespace_id) || !cid(row.authority_scope_cid) ||
      !cid(row.run_definition_cid) ||
      !Number.isSafeInteger(row.revision) || row.revision < 0 ||
      !instant(row.lookup_expires_at)) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    ref: Object.freeze({
      namespaceId: row.namespace_id,
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

// A bounded Host-private physical inventory. Its immutable canonical string
// stays in the existing Run admission row; it is not caller input identity,
// a permission token, or a second execution journal.
function validateSourceInventory(wire) {
  if (typeof wire !== 'string' || Buffer.byteLength(wire) > 256 * 1024) {
    fail('InvalidClientSourceInventory');
  }
  let value;
  try { value = JSON.parse(wire); } catch (cause) { fail('InvalidClientSourceInventory', cause); }
  const keys = (object, expected) => object !== null && typeof object === 'object' &&
    !Array.isArray(object) && Object.keys(object).sort().join(',') === expected.split(',').sort().join(',');
  if (!keys(value, 'version,environmentCid,acquisitions') ||
      value.version !== 'actql-client-source-inventory/0.1' || !cid(value.environmentCid) ||
      !Array.isArray(value.acquisitions) || value.acquisitions.length !== 2 ||
      canonicalJson(value) !== wire) fail('InvalidClientSourceInventory');
  const requirements = new Set();
  const validPhysicalBinding = binding => {
    if (keys(binding, 'version,database,schema,table,utf8_hex') &&
        binding.version === 'actql-installed-duckdb-target/0.1') {
      return keys(binding.utf8_hex, 'database,schema,table') &&
        !['database','schema','table'].some(key => typeof binding[key] !== 'string' ||
          !binding[key] || typeof binding.utf8_hex[key] !== 'string' ||
          !/^(?:[0-9a-f]{2})+$/u.test(binding.utf8_hex[key]) ||
          Buffer.from(Buffer.from(binding.utf8_hex[key], 'hex').toString('utf8'), 'utf8').toString('hex') !== binding.utf8_hex[key] ||
          Buffer.from(binding.utf8_hex[key], 'hex').toString('utf8').normalize('NFC') !== binding[key]);
    }
    if (keys(binding, 'version,org_id,instance_origin,site_key,site_generation,connection_revision,catalog_cid,resource,fields') &&
        binding.version === 'actql-installed-salesforce-target/0.1') {
      let origin;
      try { origin = new URL(binding.instance_origin); } catch { return false; }
      return origin.protocol === 'https:' && origin.origin === binding.instance_origin &&
        [binding.org_id, binding.site_key, binding.connection_revision,
          binding.resource].every(value => typeof value === 'string' && value !== '') &&
        Number.isSafeInteger(binding.site_generation) && binding.site_generation >= 0 &&
        cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
        binding.fields.length > 0 && binding.fields.length <= 100 &&
        binding.fields.every(value => typeof value === 'string' && value !== '') &&
        new Set(binding.fields).size === binding.fields.length;
    }
    // This is a Host-private physical target, not a new common Engine
    // identity. The installed Site checks it again against its publication.
    let origin;
    try { origin = new URL(binding?.api_origin); } catch { return false; }
    return keys(binding, 'version,api_origin,repository_id,repository_node_id,owner,repo,catalog_cid,resource,fields') &&
      binding.version === 'actql-installed-github-target/0.1' &&
      origin.protocol === 'https:' && origin.origin === binding.api_origin &&
      Number.isSafeInteger(binding.repository_id) && binding.repository_id > 0 &&
      [binding.repository_node_id, binding.owner, binding.repo,
        binding.resource].every(value => typeof value === 'string' && value !== '') &&
      cid(binding.catalog_cid) && Array.isArray(binding.fields) &&
      binding.fields.length > 0 && binding.fields.length <= 100 &&
      binding.fields.every(value => typeof value === 'string' && value !== '') &&
      new Set(binding.fields).size === binding.fields.length;
  };
  for (const [index, occurrence] of value.acquisitions.entries()) {
    if (!keys(occurrence, 'stage,input,task,checkedSource,readTuple,physicalBinding') ||
        occurrence.stage !== index || occurrence.input !== 0 || occurrence.task !== index ||
        !keys(occurrence.checkedSource, 'requirementCid,sourceRef,sourceContractCid,carrierSchemaContractCid,sourceDataPolicyCid,dataClassification,sourceViewContractCid,inputContractCid,outputContractCid') ||
        !keys(occurrence.readTuple, 'connection,resource,operation') ||
        !validPhysicalBinding(occurrence.physicalBinding)) {
      fail('InvalidClientSourceInventory');
    }
    const source = occurrence.checkedSource, binding = occurrence.physicalBinding;
    if (![source.requirementCid, source.sourceContractCid, source.carrierSchemaContractCid,
      source.sourceDataPolicyCid, source.sourceViewContractCid, source.inputContractCid,
      source.outputContractCid].every(cid) || typeof source.sourceRef !== 'string' ||
      !source.sourceRef || !['public', 'internal', 'confidential', 'restricted', 'unknown']
        .includes(source.dataClassification) || requirements.has(source.requirementCid) ||
      occurrence.readTuple.operation !== 'read' ||
      typeof occurrence.readTuple.connection !== 'string' || !occurrence.readTuple.connection ||
      typeof occurrence.readTuple.resource !== 'string' || !occurrence.readTuple.resource ||
      !validPhysicalBinding(binding) ||
      (binding.version === 'actql-installed-github-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !==
           `github:${new URL(binding.api_origin).host}/${binding.owner}/${binding.repo}`)) ||
      (binding.version === 'actql-installed-salesforce-target/0.1' &&
        (binding.resource !== occurrence.readTuple.resource ||
         occurrence.readTuple.connection !== `salesforce:${binding.org_id}`))) {
      fail('InvalidClientSourceInventory');
    }
    requirements.add(source.requirementCid);
  }
  return wire;
}

function admissionEvidenceShape(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  if (Object.keys(value).some(key => !['authorization', 'prepared',
    'sourceInventory', 'resultPolicyOriginal', 'modelOriginalRunWire',
    'valuesHostPolicyOriginal'].includes(key)) ||
      !Object.hasOwn(value, 'prepared') || !Object.hasOwn(value, 'authorization') ||
      typeof value.prepared !== 'string' || typeof value.authorization !== 'string') return false;
  if (value.sourceInventory !== undefined) validateSourceInventory(value.sourceInventory);
  if (value.valuesHostPolicyOriginal !== undefined) {
    const original = value.valuesHostPolicyOriginal;
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !== 'cid,wire' ||
        !cid(original.cid) || typeof original.wire !== 'string') return false;
    let body, prepared, authorization;
    try {
      body = JSON.parse(original.wire);
      prepared = JSON.parse(value.prepared);
      authorization = JSON.parse(value.authorization);
    } catch { return false; }
    if (body === null || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).sort().join(',') !== 'max_rows,name,version' ||
        body.version !== 'actql-installed-local-policy/0.1' ||
        body.name !== 'source-free-values' ||
        !Number.isSafeInteger(body.max_rows) || body.max_rows < 1 || body.max_rows > 10000 ||
        canonicalJson(body) !== original.wire ||
        `sha256:${createHash('sha256').update(original.wire).digest('hex')}` !== original.cid ||
        prepared?.host_policy_cid !== original.cid ||
        authorization?.host_policy_cid !== original.cid) return false;
  }
  if (value.resultPolicyOriginal !== undefined &&
      (value.resultPolicyOriginal === null ||
       typeof value.resultPolicyOriginal !== 'object' ||
       Array.isArray(value.resultPolicyOriginal) ||
       Object.keys(value.resultPolicyOriginal).sort().join(',') !== 'cid,kind,wire' ||
       value.resultPolicyOriginal.kind !== 'data_policy' ||
       typeof value.resultPolicyOriginal.cid !== 'string' ||
       typeof value.resultPolicyOriginal.wire !== 'string')) return false;
  if (value.modelOriginalRunWire !== undefined) {
    if (typeof value.modelOriginalRunWire !== 'string') return false;
    let original;
    try { original = JSON.parse(value.modelOriginalRunWire); } catch { return false; }
    if (original === null || typeof original !== 'object' || Array.isArray(original) ||
        Object.keys(original).sort().join(',') !==
          'boundInvocationTemplateWire,compiledPlanWire,preparedInvocationWire,runAuthorizationWire,runDefinitionWire' ||
        Object.values(original).some(wire => typeof wire !== 'string' || wire === '') ||
        canonicalValueJson(original) !== value.modelOriginalRunWire ||
        original.preparedInvocationWire !== value.prepared ||
        original.runAuthorizationWire !== value.authorization) return false;
  }
  return true;
}

function assertSourceInventory(retained, proposed) {
  if (proposed !== undefined) validateSourceInventory(proposed);
  // A physical start can only be reconciled through its retained owner; a
// later configuration never becomes authority to restart its sources.
  if (retained.physicalStartReserved === true) return;
  if (retained.runAdmissionEvidence?.sourceInventory !== proposed) {
    fail('ClientRequestSourceInventoryMismatch');
  }
}

// Private replay evidence is stored atomically with acceptance. Its semantic
// admission remains with the common MoonBit owner before any physical start.
function evidenceJson(value, maxBytes) {
  if (value === undefined) return null;
  if (!admissionEvidenceShape(value)) fail('InvalidClientRunAdmissionEvidence');
  const wire = JSON.stringify(value);
  if (Buffer.byteLength(wire) > maxBytes) {
    fail('InvalidClientRunAdmissionEvidence');
  }
  return wire;
}

function retainedEvidence(row) {
  if (row.run_admission_evidence_json === null) return undefined;
  let value;
  try { value = JSON.parse(row.run_admission_evidence_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  try {
    if (!admissionEvidenceShape(value)) fail('ClientRequestJournalCorrupt');
  } catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  return Object.freeze(value);
}

function retainedResultNames(row) {
  if (row.result_names_json === null) return undefined;
  let names;
  try { names = JSON.parse(row.result_names_json); }
  catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
  if (!Array.isArray(names) || names.length === 0 || names.length > 100 ||
      names.some(name => typeof name !== 'string' || !name) ||
      new Set(names).size !== names.length) {
    fail('ClientRequestJournalCorrupt');
  }
  return names;
}

function retainedRunFacts(row, publicationControl, maxWireBytes) {
  if (![0, 1].includes(row.dispatch_reserved) ||
      ![0, 1].includes(row.pre_dispatch_failure_confirmed) ||
      ![null, 0, 1].includes(row.physical_start_reserved) ||
      ![0, 1].includes(row.cancellation_requested) ||
      ![0, 1].includes(row.physical_close_confirmed) ||
      ![null, 'failed', 'cancelled'].includes(
        row.observed_terminal_outcome)) {
    fail('ClientRequestJournalCorrupt');
  }
  const runAdmissionEvidence = retainedEvidence(row);
  const runDefinition = retainedRunDefinition(row, publicationControl,
    maxWireBytes);
  if (runAdmissionEvidence?.valuesHostPolicyOriginal !== undefined &&
      JSON.parse(row.run_definition_wire).authorization_context_cid !==
        valuesExecutionContextCid(row.authority_scope_cid,
          runAdmissionEvidence.valuesHostPolicyOriginal)) {
    fail('ClientRequestJournalCorrupt');
  }
  if (runAdmissionEvidence?.modelOriginalRunWire !== undefined &&
      JSON.parse(runAdmissionEvidence.modelOriginalRunWire).runDefinitionWire !== row.run_definition_wire) {
    fail('ClientRequestJournalCorrupt');
  }
  return Object.freeze({
    runDefinition,
    resultNames: retainedResultNames(row),
    runAdmissionEvidence,
    cancellationRequested: row.cancellation_requested === 1,
    physicalCloseConfirmed: row.physical_close_confirmed === 1,
    dispatchReserved: row.dispatch_reserved === 1,
    preDispatchFailureConfirmed:
      row.pre_dispatch_failure_confirmed === 1,
    physicalStartReserved: row.physical_start_reserved === null
      ? undefined : row.physical_start_reserved === 1,
    observedTerminalOutcome: row.observed_terminal_outcome,
  });
}

const columns = `authority_scope_cid, caller_request_id,
  logical_request_scope_cid, intent_fingerprint_cid,
  program_definition_cid, parameter_values_cid, caller_input_intent_cid,
  namespace_id, run_definition_cid, run_definition_wire, revision,
  lookup_expires_at, result_names_json, run_admission_evidence_json`;
const selectColumns = `${columns}, dispatch_reserved,
  pre_dispatch_failure_confirmed, physical_start_reserved,
  cancellation_requested, physical_close_confirmed,
  observed_terminal_outcome`;
const journalMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1',
  isolation: 'execution-namespace',
}), 'utf8');
const journalColumns = [...columns.split(',').map(name => name.trim()),
  'dispatch_reserved', 'pre_dispatch_failure_confirmed',
  'physical_start_reserved', 'cancellation_requested',
  'physical_close_confirmed', 'observed_terminal_outcome',
  'reconciliation_state_wire'].sort();

// Additive custody in the existing request journal. The original format marker
// is retained byte-for-byte; partially introduced custody is never reset.
const cancellationMarkerName = 'cancellation-operations-format.json';
const cancellationMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'cancellation_operations',
}));
const cancellationColumns = ['namespace_id', 'authority_scope_cid', 'cancel_id',
  'run_definition_cid', 'expected_revision', 'intent_fingerprint_cid',
  'outcome_wire', 'outcome_cid'].sort();

// Retain issuance independently of replay rows in this same journal. Losing
// a row cannot turn its consumed identity into a fresh admission opportunity.
const submissionMarkerName = 'submission-custody-format.json';
const submissionMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_custody',
}));
function inspectSubmissionStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submission_custody'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submission_custody)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT singleton, issued_count FROM client_submission_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(['issued_count', 'singleton']) ||
      records.length !== 1 || records[0].singleton !== 1 ||
      !Number.isSafeInteger(records[0].issued_count) || records[0].issued_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
  // A lost replay row fences writes, but does not erase surviving individual
  // observations. Reopening must not reset this counter to the remaining rows.
}

const epochMarkerName = 'submission-epoch-format.json';
const intentMarkerName = 'submitted-intent-format.json';
const retirementMarkerName = 'submitted-intent-retirement-format.json';
const retirementMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intent_retirement',
}));
const intentMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submitted_intents',
}));
const epochMarker = Buffer.from(JSON.stringify({
  version: 'actql-client-request-journal/0.1', feature: 'submission_epochs',
}));
const maxEpochTtlMs = 7 * 24 * 60 * 60 * 1000;
const hexKey = value => typeof value === 'string' && /^[0-9a-f]{64}$/u.test(value);
function validEpochAuthority(row) {
  return row?.singleton === 1 && hexKey(row.authentication_key) &&
    Number.isSafeInteger(row.observed_at) && row.observed_at >= 0 &&
    row.observed_at <= Number.MAX_SAFE_INTEGER - maxEpochTtlMs;
}
function inspectEpochStorage(database, enabled) {
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
function inspectIntentStorage(database, enabled) {
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
      custody[0].issued_count < 0) fail('UnknownClientRequestJournalFormat');
}

function inspectIntentRetirementStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name = 'client_submitted_intent_retirement'`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 1) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_submitted_intent_retirement)')
    .all().map(field => field.name).sort();
  const rows = database.prepare('SELECT * FROM client_submitted_intent_retirement').all();
  if (JSON.stringify(fields) !== JSON.stringify(['retired_count', 'singleton']) ||
      rows.length !== 1 || rows[0].singleton !== 1 ||
      !Number.isSafeInteger(rows[0].retired_count) || rows[0].retired_count < 0) {
    fail('UnknownClientRequestJournalFormat');
  }
}

function inspectCancellationStorage(database, enabled) {
  const tables = database.prepare(`SELECT name FROM sqlite_master WHERE type = 'table'
    AND name IN ('client_cancellation_operations', 'client_cancellation_custody')`).all();
  if (!enabled && tables.length === 0) return;
  if (!enabled || tables.length !== 2) fail('UnknownClientRequestJournalFormat');
  const fields = database.prepare('PRAGMA table_info(client_cancellation_operations)')
    .all().map(field => field.name).sort();
  const custodyFields = database.prepare('PRAGMA table_info(client_cancellation_custody)')
    .all().map(field => field.name).sort();
  const records = database.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations').get().n;
  const custody = database.prepare('SELECT singleton, issued_count FROM client_cancellation_custody').all();
  if (JSON.stringify(fields) !== JSON.stringify(cancellationColumns) ||
      JSON.stringify(custodyFields) !== JSON.stringify(['issued_count', 'singleton']) ||
      custody.length !== 1 || custody[0].singleton !== 1 ||
      !Number.isSafeInteger(custody[0].issued_count) || custody[0].issued_count < 0 ||
      custody[0].issued_count !== records) fail('UnknownClientRequestJournalFormat');
}

// A read-only SQLite connection can still create -shm beside a WAL database.
// Inspect a private copy and refuse a source that changes during inspection.
function inspectJournalSnapshot(directory, databasePath, markerPath) {
  const entries = readdirSync(directory).sort();
  const featurePath = join(directory, cancellationMarkerName);
  const enabled = entries.includes(cancellationMarkerName);
  if (enabled && (!lstatSync(featurePath).isFile() ||
      !readFileSync(featurePath).equals(cancellationMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const submissionPath = join(directory, submissionMarkerName);
  const submissionEnabled = entries.includes(submissionMarkerName);
  if (submissionEnabled && (!lstatSync(submissionPath).isFile() ||
      !readFileSync(submissionPath).equals(submissionMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const epochPath = join(directory, epochMarkerName);
  const epochEnabled = entries.includes(epochMarkerName);
  if (epochEnabled && (!lstatSync(epochPath).isFile() ||
      !readFileSync(epochPath).equals(epochMarker))) {
    fail('UnknownClientRequestJournalFormat');
  }
  const intentPath = join(directory, intentMarkerName);
  const intentEnabled = entries.includes(intentMarkerName);
  if (intentEnabled && (!lstatSync(intentPath).isFile() ||
      !readFileSync(intentPath).equals(intentMarker))) fail('UnknownClientRequestJournalFormat');
  const retirementPath = join(directory, retirementMarkerName);
  const retirementEnabled = entries.includes(retirementMarkerName);
  if (retirementEnabled && (!intentEnabled || !lstatSync(retirementPath).isFile() ||
      !readFileSync(retirementPath).equals(retirementMarker))) fail('UnknownClientRequestJournalFormat');
  inspectSqliteSnapshot(databasePath, database => {
    const fields = database.prepare('PRAGMA table_info(client_requests)')
      .all().map(field => field.name).sort();
    if (JSON.stringify(fields) !== JSON.stringify(journalColumns)) {
      fail('UnknownClientRequestJournalFormat');
    }
    inspectCancellationStorage(database, enabled);
    inspectSubmissionStorage(database, submissionEnabled);
    inspectEpochStorage(database, epochEnabled);
    inspectIntentStorage(database, intentEnabled);
    inspectIntentRetirementStorage(database, retirementEnabled);
  }, {code: 'UnknownClientRequestJournalFormat',
    validateSource: () => readFileSync(markerPath).equals(journalMarker) &&
      (!enabled || readFileSync(featurePath).equals(cancellationMarker)) &&
      (!submissionEnabled || readFileSync(submissionPath).equals(submissionMarker)) &&
      (!epochEnabled || readFileSync(epochPath).equals(epochMarker)) &&
      (!intentEnabled || readFileSync(intentPath).equals(intentMarker)) &&
      (!retirementEnabled || readFileSync(retirementPath).equals(retirementMarker)) &&
      JSON.stringify(readdirSync(directory).sort()) === JSON.stringify(entries)});
}

function admitJournalDirectory(directory) {
  if (!existsSync(directory)) return false;
  const state = lstatSync(directory);
  if (!state.isDirectory() || state.isSymbolicLink()) {
    fail('UnknownClientRequestJournalFormat');
  }
  const entries = readdirSync(directory);
  if (entries.length === 0) return false;
  const markerPath = join(directory, 'journal-format.json');
  if (!entries.includes('journal-format.json')) {
    fail(entries.includes('client-requests.sqlite3') ?
      'LegacyClientRequestJournalFormat' :
      'UnknownClientRequestJournalFormat');
  }
  if (!entries.includes('client-requests.sqlite3') ||
      !lstatSync(markerPath).isFile() ||
      !readFileSync(markerPath).equals(journalMarker)) {
    fail('UnknownClientRequestJournalFormat');
  }
  const databasePath = join(directory, 'client-requests.sqlite3');
  if (!lstatSync(databasePath).isFile()) {
    fail('UnknownClientRequestJournalFormat');
  }
  try {
    inspectJournalSnapshot(directory, databasePath, markerPath);
  } catch (cause) {
    if (cause?.cleanupPending) throw cause;
    if (cause?.code === 'UnknownClientRequestJournalFormat') throw cause;
    fail('UnknownClientRequestJournalFormat', cause);
  }
  return true;
}

export function openClientRequestJournal(directory, {
  maxRecords = 100_000,
  maxRunDefinitionWireBytes = 65_536,
  submissionEpochTtlMs = maxEpochTtlMs,
  submissionEpochNow = Date.now,
} = {}) {
  if (!pathText(directory) || !Number.isSafeInteger(maxRecords) ||
      maxRecords < 1 || !Number.isSafeInteger(maxRunDefinitionWireBytes) ||
      maxRunDefinitionWireBytes < 1024 ||
      !Number.isSafeInteger(submissionEpochTtlMs) || submissionEpochTtlMs < 1 ||
      submissionEpochTtlMs > maxEpochTtlMs || typeof submissionEpochNow !== 'function') {
    fail('InvalidClientRequestJournalConfiguration');
  }
  const current = admitJournalDirectory(directory);
  mkdirSync(directory, {recursive: true, mode: 0o700});
  const root = realpathSync(directory);
  const path = join(root, 'client-requests.sqlite3');
  const existed = existsSync(path);
  if (current !== existed) fail('UnknownClientRequestJournalFormat');
  const database = new DatabaseSync(path, {
    open: true,
    readOnly: false,
    enableForeignKeyConstraints: true,
  });
  const transaction = createSqliteTransaction(database,
    'ClientRequestJournal');
  let closed = false;
  let databaseClosed = false;
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
        namespace_id TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL UNIQUE,
        run_definition_wire TEXT,
        run_admission_evidence_json TEXT,
        revision INTEGER NOT NULL CHECK (revision >= 0),
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
    if (!existed) {
      syncDirectory(root);
      const marker = openSync(join(root, 'journal-format.json'), 'wx', 0o600);
      try {
        writeFileSync(marker, journalMarker);
        fsyncSync(marker);
      } finally {
        closeSync(marker);
      }
      syncDirectory(root);
    }
    if (!existsSync(join(root, submissionMarkerName))) {
      // Adopt only the retained original rows of an admitted prior format.
      // This cannot certify missing pre-upgrade history or issue an epoch.
      transaction.run(() => database.exec(`
        CREATE TABLE client_submission_custody (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          issued_count INTEGER NOT NULL CHECK (issued_count >= 0)
        ) STRICT;
        INSERT INTO client_submission_custody
          SELECT 1, COUNT(*) FROM client_requests;
      `));
      const marker = openSync(join(root, submissionMarkerName), 'wx', 0o600);
      try { writeFileSync(marker, submissionMarker); fsyncSync(marker); }
      finally { closeSync(marker); }
      syncDirectory(root);
    }
    if (!existsSync(join(root, epochMarkerName))) {
      // One retained authentication key and monotonic expiry watermark suffice
      // to validate bounded-lifetime tickets. No per-epoch history is evicted.
      transaction.run(() => {
        database.exec(`CREATE TABLE client_submission_epoch_authority (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          authentication_key TEXT NOT NULL,
          observed_at INTEGER NOT NULL CHECK (observed_at >= 0)
        ) STRICT;`);
        database.prepare('INSERT INTO client_submission_epoch_authority VALUES (1, ?, 0)')
          .run(randomBytes(32).toString('hex'));
      });
      const marker = openSync(join(root, epochMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, epochMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, intentMarkerName))) {
      transaction.run(() => database.exec(`
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
      const marker = openSync(join(root, intentMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, intentMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, retirementMarkerName))) {
      // Adoption records zero formal retirements; it never resets issuance
      // or repairs a missing original row in a previously admitted journal.
      transaction.run(() => database.exec(`
        CREATE TABLE client_submitted_intent_retirement (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          retired_count INTEGER NOT NULL CHECK (retired_count >= 0)
        ) STRICT;
        INSERT INTO client_submitted_intent_retirement VALUES (1, 0);
      `));
      const marker = openSync(join(root, retirementMarkerName), 'wx', 0o600);
      try {writeFileSync(marker, retirementMarker); fsyncSync(marker);}
      finally {closeSync(marker);}
      syncDirectory(root);
    }
    if (!existsSync(join(root, cancellationMarkerName))) {
      transaction.run(() => database.exec(`
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
      const marker = openSync(join(root, cancellationMarkerName), 'wx', 0o600);
      try { writeFileSync(marker, cancellationMarker); fsyncSync(marker); }
      finally { closeSync(marker); }
      syncDirectory(root);
    }
  // Statement preparation is part of initialization: no journal owner has
  // been returned yet. Keep it under the same single cleanup boundary.
  const ensureOpen = () => {
    if (closed) fail('ClientRequestJournalClosed');
    transaction.assertUsable();
  };
  const transact = (operation, unknownCode, known, action) => {
    try { return transaction.run(action); }
    catch (error) {
      const transactionFailure = [
        'ClientRequestJournalCommitOutcomeUnknown',
        'ClientRequestJournalRollbackFailed',
        'ClientRequestJournalConnectionUnusable',
      ].includes(error?.code);
      if (!transactionFailure && known(error) &&
          error.outcome !== 'unknown' &&
          transaction.connectionUsable) throw error;
      throw Object.assign(new Error(unknownCode, {
        cause: error.cause ?? error,
      }), {
        code: unknownCode, operation,
        outcome: error.outcome ?? 'failed',
        rollbackCause: error.rollbackCause,
        stateCause: error.stateCause,
        connectionUsable: transaction.connectionUsable,
      });
    }
  };
  const select = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE authority_scope_cid = ? AND caller_request_id = ?`);
  const selectRef = database.prepare(`SELECT ${selectColumns} FROM client_requests
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ?`);
  const selectRun = database.prepare(`SELECT run_definition_cid
    FROM client_requests WHERE run_definition_cid = ?`);
  const count = database.prepare('SELECT COUNT(*) AS n FROM client_requests');
  const submissionIssued = database.prepare('SELECT issued_count FROM client_submission_custody WHERE singleton = 1');
  const advanceSubmissionCustody = database.prepare('UPDATE client_submission_custody SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?');
  const assertSubmissionCustody = () => {
    const n = Number(count.get().n);
    if (!Number.isSafeInteger(n) || submissionIssued.get()?.issued_count !== n) {
      fail('ClientRequestSubmissionCustodyLost');
    }
    return n;
  };
  const epochAuthority = database.prepare('SELECT * FROM client_submission_epoch_authority WHERE singleton = 1');
  const advanceEpochTime = database.prepare('UPDATE client_submission_epoch_authority SET observed_at = ? WHERE singleton = 1');
  const epochClock = () => {
    const row = epochAuthority.get();
    if (!validEpochAuthority(row)) fail('ClientSubmissionEpochCustodyLost');
    const now = submissionEpochNow();
    if (!Number.isSafeInteger(now) || now < 0 ||
        now > Number.MAX_SAFE_INTEGER - maxEpochTtlMs) fail('ClientSubmissionEpochClockInvalid');
    const observedAt = Math.max(now, row.observed_at);
    advanceEpochTime.run(observedAt);
    return {...row, observed_at: observedAt};
  };
  const epochHandle = (epoch, control) => {
    if (epoch === null || typeof epoch !== 'object' || Array.isArray(epoch) ||
        JSON.stringify(Object.keys(epoch).sort()) !== JSON.stringify([
          'authenticator', 'authorityScopeCid', 'epochNonce', 'expiresAt', 'notBefore', 'version',
        ])) fail('ClientSubmissionEpochUnverifiable');
    const captured = Object.freeze({...epoch});
    if (captured.version !== 'actql-submission-epoch/0.1' ||
        !cid(captured.authorityScopeCid) || !hexKey(captured.epochNonce) ||
        !Number.isSafeInteger(captured.notBefore) || !Number.isSafeInteger(captured.expiresAt) ||
        Object.is(captured.notBefore, -0) || Object.is(captured.expiresAt, -0) ||
        !hexKey(captured.authenticator)) fail('ClientSubmissionEpochUnverifiable');
    const handle = control.clientSubmissionEpoch(captured.authorityScopeCid,
      captured.epochNonce, captured.notBefore, captured.expiresAt);
    if (handle === undefined) fail('ClientSubmissionEpochUnverifiable');
    return {captured, handle};
  };
  const authenticateEpoch = (key, wire) => createHmac('sha256',
    Buffer.from(key, 'hex')).update(wire, 'utf8').digest('hex');
  const verifyEpochLocked = (epoch, {authorityScopeCid, currentAuthorization,
    purpose}, control) => {
    ensureOpen();
    if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
    if (!cid(authorityScopeCid) || !['admit', 'lookup'].includes(purpose)) {
      fail('InvalidClientSubmissionEpochOperation');
    }
    const {captured, handle} = epochHandle(epoch, control);
    const clock = epochClock();
    const authenticated = authenticateEpoch(clock.authentication_key,
      control.clientSubmissionEpochWire(handle));
    if (!timingSafeEqual(Buffer.from(authenticated, 'hex'),
      Buffer.from(captured.authenticator, 'hex'))) fail('ClientSubmissionEpochUnverifiable');
    if (captured.authorityScopeCid !== authorityScopeCid) {
      fail('ClientSubmissionEpochScopeMismatch');
    }
    const validity = control.clientSubmissionEpochValidity(handle, clock.observed_at);
    if (validity === undefined) fail('ClientSubmissionEpochClockInvalid');
    return {handle, epoch: captured, validity,
      epochCid: control.clientSubmissionEpochCid(handle)};
  };
  const verifyEpoch = (epoch, fields, control) =>
    transaction.run(() => verifyEpochLocked(epoch, fields, control));
  const checkSubmissionBinding = (fields, submission, control, locked = false) => {
    if (submission === undefined) return 'admissible';
    const verify = locked ? verifyEpochLocked : verifyEpoch;
    const verified = verify(submission.epoch, {authorityScopeCid: fields.authorityScopeCid,
      currentAuthorization: submission.currentAuthorization, purpose: 'admit'}, control);
    const requestId = control.clientSubmissionRequestId(verified.handle, submission.nonce);
    if (requestId === undefined) fail('InvalidClientSubmissionNonce');
    if (requestId !== fields.requestId) fail('ClientSubmissionIdentityMismatch');
    if (submission.intentCid !== undefined) {
      // Expiry stops new admission, not preparation of an already accepted
      // intent. The persisted receipt, rather than a caller flag, supplies
      // this fact. Rejection and failed preparation cannot acquire a Run.
      assertIntentCustody();
      const row = intentSelect.get(requestId);
      if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
      const retained = retainedIntent(row, control);
      if (retained.intentCid !== submission.intentCid ||
          !['preparing', 'held', 'ready'].includes(retained.phase)) {
        fail('ClientSubmittedIntentConflict');
      }
      return 'admissible';
    }
    return verified.validity;
  };
  const refuseEpoch = validity => {
    if (validity !== 'admissible') fail(validity === 'expired'
      ? 'ClientSubmissionEpochExpired' : 'ClientSubmissionEpochNotYetValid');
  };
  const intentSelect = database.prepare('SELECT * FROM client_submitted_intents WHERE submission_id = ?');
  const intentCount = database.prepare('SELECT COUNT(*) AS n, COALESCE(SUM(length(CAST(intent_wire AS BLOB))), 0) AS bytes FROM client_submitted_intents');
  const intentIssued = database.prepare('SELECT issued_count FROM client_submitted_intent_custody WHERE singleton = 1');
  const intentRetired = database.prepare('SELECT retired_count FROM client_submitted_intent_retirement WHERE singleton = 1');
  const assertIntentCustody = () => {
    const retained = intentCount.get();
    const issued = intentIssued.get()?.issued_count;
    const retired = intentRetired.get()?.retired_count;
    if (!Number.isSafeInteger(issued) || !Number.isSafeInteger(retired) || retired < 0 ||
        !Number.isSafeInteger(retained.n + retired) || retained.n + retired !== issued) {
      fail('ClientSubmittedIntentCustodyLost');
    }
    return {...retained, issued, retired};
  };
  const originalIntent = (intent, control) => {
    const wire = control.clientSubmittedIntentWire(intent);
    const identity = control.clientSubmittedIntentCid(intent);
    const checked = control.clientSubmittedIntent(wire, 1048576, 65536, 64);
    if (checked === undefined || control.clientSubmittedIntentCid(checked) !== identity ||
        control.clientSubmittedIntentWire(checked) !== wire) fail('InvalidClientSubmittedIntent');
    return {wire, identity};
  };
  const retainedIntent = (row, control) => {
    const intent = control.clientSubmittedIntent(row.intent_wire, 1048576, 65536, 64);
    if (intent === undefined || control.clientSubmittedIntentCid(intent) !== row.intent_cid ||
        control.clientSubmittedIntentWire(intent) !== row.intent_wire) fail('ClientSubmittedIntentCorrupt');
    const epoch = JSON.parse(row.epoch_wire);
    const {handle} = epochHandle(epoch, control);
    const authority = epochAuthority.get();
    if (!validEpochAuthority(authority)) fail('ClientSubmissionEpochCustodyLost');
    if (authenticateEpoch(authority.authentication_key, control.clientSubmissionEpochWire(handle)) !==
        epoch.authenticator) fail('ClientSubmittedIntentCorrupt');
    if (control.clientSubmissionRequestId(handle, row.nonce) !== row.submission_id ||
        epoch.authorityScopeCid !== row.authority_scope_cid ||
        !Number.isSafeInteger(row.accepted_at) || row.accepted_at < epoch.notBefore ||
        row.accepted_at >= epoch.expiresAt || !Number.isSafeInteger(row.revision) || row.revision < 0 ||
        !control.clientSubmittedIntentTransition(row.phase, row.phase)) fail('ClientSubmittedIntentCorrupt');
    const submissionRef = Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce});
    const outcome = row.outcome_wire === null ? undefined : JSON.parse(row.outcome_wire);
    if (outcome === undefined && row.phase !== 'preparing' ||
        outcome !== undefined && (outcome.kind !== row.phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, row.intent_cid))) {
      fail('ClientSubmittedIntentCorrupt');
    }
    if (row.phase === 'ready') {
      const run = select.get(row.authority_scope_cid, row.submission_id);
      if (run === undefined || run.run_definition_cid !== outcome.admission.ref.runDefinitionCid ||
          run.namespace_id !== outcome.admission.ref.namespaceId) fail('ClientSubmittedIntentCorrupt');
    }
    return Object.freeze({submissionRef: Object.freeze({epoch: Object.freeze(epoch), nonce: row.nonce}),
      requestId: row.submission_id, intentCid: row.intent_cid, intentWire: row.intent_wire,
      phase: row.phase, revision: row.revision, outcome});
  };
  const cancellationCount = database.prepare('SELECT COUNT(*) AS n FROM client_cancellation_operations');
  const cancellationIssued = database.prepare('SELECT issued_count FROM client_cancellation_custody WHERE singleton = 1');
  const cancellationSelect = database.prepare(`SELECT * FROM client_cancellation_operations
    WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?`);
  const cancellationInsert = database.prepare(`INSERT INTO client_cancellation_operations
    (namespace_id, authority_scope_cid, cancel_id, run_definition_cid,
     expected_revision, intent_fingerprint_cid) VALUES (?, ?, ?, ?, ?, ?)`);
  const assertCancellationCustody = () => {
    const n = Number(cancellationCount.get().n);
    if (cancellationIssued.get()?.issued_count !== n) fail('ClientRequestJournalCorrupt');
    return n;
  };
  const insert = database.prepare(`INSERT INTO client_requests (${columns})
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  const reserve = database.prepare(`UPDATE client_requests
    SET dispatch_reserved = 1, revision = revision + 1
    WHERE authority_scope_cid = ? AND caller_request_id = ? AND
      dispatch_reserved = 0`);
  const confirmPreDispatchFailure = database.prepare(`UPDATE client_requests
    SET pre_dispatch_failure_confirmed = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);
  const reservePhysicalStart = database.prepare(`UPDATE client_requests
    SET physical_start_reserved = 1, revision = revision + 1
    WHERE namespace_id = ? AND authority_scope_cid = ? AND
      run_definition_cid = ? AND dispatch_reserved = 1 AND
      pre_dispatch_failure_confirmed = 0 AND physical_start_reserved = 0 AND
      cancellation_requested = 0`);

  const validCancellationRef = ref => text(ref?.namespaceId) &&
    cid(ref?.authorityScopeCid) && cid(ref?.runDefinitionCid) &&
    text(ref?.cancelId) && Number.isInteger(ref?.expectedRevision) &&
    ref.expectedRevision >= 0 && ref.expectedRevision <= 2147483647;
  const ownedCancellationRef = ref => Object.freeze({namespaceId: ref.namespaceId,
    authorityScopeCid: ref.authorityScopeCid, runDefinitionCid: ref.runDefinitionCid,
    cancelId: ref.cancelId, expectedRevision: ref.expectedRevision});
  const cancellationKnownFailure = error => [
    'ClientCancellationDenied', 'ClientCancellationIntentConflict',
    'ClientCancellationRevisionConflict', 'ClientRequestJournalCapacity',
  ].includes(error?.code);
  const cancellationDefinition = (ref, requestControl, publicationControl) => {
    const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
    if (row === undefined) fail('ClientCancellationDenied');
    retainedIdentity(row, requestControl);
    if (!Number.isInteger(row.revision) || row.revision < 0 || row.revision > 2147483647) {
      fail('ClientCancellationRevisionConflict');
    }
    return {row, facts: retainedRunFacts(row, publicationControl, maxRunDefinitionWireBytes)};
  };
  const cancellationIdentity = (ref, definition, control) => {
    const identity = control.clientCancellationAdmitRecord(ref.namespaceId,
      ref.authorityScopeCid, ref.cancelId, definition, ref.expectedRevision);
    if (identity === undefined) fail('ClientCancellationDenied');
    return identity;
  };
  const cancellationReadmission = (record, requestControl, publicationControl) => {
    const cancelRef = Object.freeze({namespaceId: record.namespace_id,
      authorityScopeCid: record.authority_scope_cid,
      runDefinitionCid: record.run_definition_cid, cancelId: record.cancel_id,
      expectedRevision: record.expected_revision});
    if (!validCancellationRef(cancelRef)) fail('ClientRequestJournalCorrupt');
    const {facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
    const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
    if (requestControl.clientCancellationIntentCid(identity) !== record.intent_fingerprint_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    if (record.outcome_wire === null && record.outcome_cid === null) {
      return {identity, cancelRef, outcome: undefined};
    }
    if (typeof record.outcome_wire !== 'string' ||
        Buffer.byteLength(record.outcome_wire) > 4096 || !cid(record.outcome_cid) ||
        `sha256:${createHash('sha256').update(record.outcome_wire).digest('hex')}` !== record.outcome_cid) {
      fail('ClientRequestJournalCorrupt');
    }
    let outcome;
    try { outcome = JSON.parse(record.outcome_wire); }
    catch (cause) { fail('ClientRequestJournalCorrupt', cause); }
    if (outcome === null || typeof outcome !== 'object' ||
        Object.keys(outcome).sort().join(',') !== 'cancelRef,kind,ref,revision' ||
        !['accepted', 'already_requested', 'already_terminal'].includes(outcome.kind) ||
        !Number.isInteger(outcome.revision) || outcome.revision < cancelRef.expectedRevision ||
        outcome.kind === 'accepted' && outcome.revision === cancelRef.expectedRevision ||
        outcome.revision > 2147483647 ||
        canonicalValueJson(outcome.cancelRef) !== canonicalValueJson(cancelRef) ||
        canonicalValueJson(outcome.ref) !== canonicalValueJson({namespaceId: cancelRef.namespaceId,
          authorityScopeCid: cancelRef.authorityScopeCid, runDefinitionCid: cancelRef.runDefinitionCid}) ||
        canonicalValueJson(outcome) !== record.outcome_wire) fail('ClientRequestJournalCorrupt');
    return {identity, cancelRef, outcome: Object.freeze({...outcome,
      ref: Object.freeze(outcome.ref), cancelRef})};
  };
  const cancellationAction = (requested, retained, facts, row, currentAuthorization,
    publicationCommitted, requestControl) => {
    const action = requestControl.clientCancellationOperationAction(requested,
      retained ?? requested, retained !== undefined, facts.runDefinition,
      Number(row.revision), currentAuthorization,
      publicationCommitted || facts.preDispatchFailureConfirmed ||
        facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
      facts.cancellationRequested);
    if (action === 4) fail('ClientCancellationIntentConflict');
    if (action === 6) fail('ClientCancellationRevisionConflict');
    if (![0, 1, 2, 3].includes(action)) fail('ClientCancellationDenied');
    return action;
  };

  const acceptRecord = (identity, {namespaceId, runDefinitionCid,
    runDefinitionWire, resultNames, runAdmissionEvidence, revision = 0, lookupExpiresAt,
    submission}, control) => {
    ensureOpen();
    if (!control || typeof control.clientRequestAdmitRecord !== 'function' ||
        typeof control.clientRequestRelation !== 'function') {
      fail('InvalidClientRequestJournalControl');
    }
    const fields = checkedIdentity(identity, control);
    if (!text(namespaceId) || !cid(runDefinitionCid) ||
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
    if (runAdmissionEvidence?.valuesHostPolicyOriginal !== undefined &&
        (typeof runDefinitionWire !== 'string' ||
         JSON.parse(runDefinitionWire).authorization_context_cid !==
           valuesExecutionContextCid(fields.authorityScopeCid,
             runAdmissionEvidence.valuesHostPolicyOriginal))) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    if (runAdmissionEvidence?.modelOriginalRunWire !== undefined &&
        JSON.parse(runAdmissionEvidence.modelOriginalRunWire).runDefinitionWire !== runDefinitionWire) {
      fail('InvalidClientRunAdmissionEvidence');
    }
    // Retain observed expiry even if another admission fact later conflicts
    // and rolls its transaction back. The atomic check below still decides
    // whether this particular Run may be inserted.
    checkSubmissionBinding(fields, submission, control);
    const outcome = transact('accept', 'ClientRequestAcceptanceUnknown',
      error => typeof error?.code === 'string' &&
        (error.code.startsWith('ClientRequest') || error.code.startsWith('ClientSubmission')), () => {
      const retainedCount = assertSubmissionCustody();
      const existing = select.get(fields.authorityScopeCid,
        fields.requestId);
      if (existing !== undefined) {
        // An expired identity may still identify its retained outcome. This
        // path performs no new issuance; authenticate the original binding.
        checkSubmissionBinding(fields, submission, control, true);
        if (existing.namespace_id !== namespaceId) {
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
        assertSourceInventory({physicalStartReserved: existing.physical_start_reserved === 1,
          runAdmissionEvidence: retainedEvidence(existing)},
          admissionEvidence === null ? undefined : JSON.parse(admissionEvidence).sourceInventory);
        return Object.freeze({inserted: false, ...admission(existing),
          runAdmissionEvidence: retainedEvidence(existing),
          ...(runDefinitionWire === undefined ? {} :
            {runDefinitionWire: existing.run_definition_wire}),
          resultNames: retainedResultNames(existing)});
      }
      const epochValidity = checkSubmissionBinding(fields, submission, control, true);
      if (epochValidity !== 'admissible') {
        // Commit the expiry watermark without admitting a Run. Throwing inside
        // this transaction would roll the watermark back and let a backwards
        // clock revive the identity after an awaited issuance.
        return {epochRejected: epochValidity};
      }
      if (Number(count.get().n) + assertCancellationCustody() >= maxRecords) {
        fail('ClientRequestJournalCapacity');
      }
      if (selectRun.get(runDefinitionCid) !== undefined) {
        fail('ClientRequestRunAlreadyAssigned');
      }
      insert.run(fields.authorityScopeCid, fields.requestId,
        fields.logicalRequestScopeCid, fields.intentFingerprintCid,
        fields.programDefinitionCid, fields.parameterValuesCid,
        fields.callerInputIntentCid, namespaceId, runDefinitionCid,
        runDefinitionWire ?? null, revision, lookupExpiresAt,
        resultNames === undefined ? null : JSON.stringify(resultNames),
        admissionEvidence);
      if (Number(advanceSubmissionCustody.run(retainedCount).changes) !== 1) {
        fail('ClientRequestSubmissionCustodyLost');
      }
      return Object.freeze({inserted: true, ref: Object.freeze({
        namespaceId, authorityScopeCid: fields.authorityScopeCid,
        runDefinitionCid,
      }), durability: 'durable', revision, lookupExpiresAt,
      ...(runDefinitionWire === undefined ? {} : {runDefinitionWire}),
      resultNames, runAdmissionEvidence: admissionEvidence === null ? undefined :
        Object.freeze(JSON.parse(admissionEvidence))});
    });
    if (outcome.epochRejected !== undefined) refuseEpoch(outcome.epochRejected);
    return outcome;
  };

  const lookupRecord = ({namespaceId, authorityScopeCid, requestId}, control) => {
    ensureOpen();
    if (!text(namespaceId) || !cid(authorityScopeCid) || !text(requestId) ||
        !control || typeof control.clientRequestAdmitRecord !== 'function') {
      fail('InvalidClientRequestLookup');
    }
    let row;
    try { row = select.get(authorityScopeCid, requestId); }
    catch (error) { fail('ClientRequestLookupUnknown', error); }
    if (row === undefined || row.namespace_id !== namespaceId) return undefined;
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

  let observationStorage;
  let observationDatabase;
  let observationStorageAttempted = false;
  let observationProjection;
  const closeObservationStorage = () => {
    if (observationStorage !== undefined) observationStorage.close();
    else if (observationDatabase !== undefined) {
      observationDatabase.close();
      observationDatabase = undefined;
    }
  };
  const journal = Object.freeze({
    closeObservationStorage,
    observationStorage() {
      ensureOpen();
      if (observationStorageAttempted) {
        if (observationStorage === undefined) throw new Error('ObservationBudgetUnavailable');
        return observationStorage;
      }
      observationStorageAttempted = true;
      // Separate connection/transaction custody prevents an observation's
      // unknown COMMIT from poisoning the semantic journal connection.
      observationDatabase = new DatabaseSync(path);
      observationDatabase.exec('PRAGMA busy_timeout = 0');
      const storage = openClientObservationStorage(observationDatabase,
        createSqliteTransaction(observationDatabase, 'ClientObservation'));
      let ended = false;
      observationStorage = Object.freeze({...storage, close() {
        if (!ended) { observationDatabase.close(); ended = true; }
      }});
      return observationStorage;
    },
    installObservationProjection(projection) {
      if (!isHostObservationProjection(projection) || observationProjection !== undefined) {
        throw new TypeError('ForeignHostObservationProjection');
      }
      observationProjection = projection;
    },
    // Intent custody is separate from Run-definition custody. A preparing
    // receipt contains no invented execution CID and performs no dispatch.
    recordSubmittedIntent(submissionRef, intent, {authorityScopeCid,
      currentAuthorization, phase = 'preparing', outcome}, control) {
      ensureOpen();
      const original = originalIntent(intent, control);
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'admit'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !['preparing', 'not_accepted'].includes(phase)) {
        fail('InvalidClientSubmittedIntent');
      }
      if (phase === 'not_accepted' && (outcome?.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      if (phase === 'preparing' && outcome !== undefined && (outcome.kind !== phase ||
          !validStoredSubmissionOutcome(outcome, submissionRef, original.identity))) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      const result = transaction.run(() => {
        const retained = assertIntentCustody();
        const existing = intentSelect.get(requestId);
        if (existing !== undefined) {
          const previous = retainedIntent(existing, control);
          if (previous.intentCid !== original.identity) fail('ClientSubmittedIntentConflict');
          return {inserted: false, ...previous};
        }
        const current = verifyEpochLocked(submissionRef.epoch, {authorityScopeCid,
          currentAuthorization, purpose: 'admit'}, control);
        if (current.validity !== 'admissible') return {epochRejected: current.validity};
        if (retained.n >= maxRecords || retained.issued === Number.MAX_SAFE_INTEGER ||
            retained.bytes + Buffer.byteLength(original.wire) > 64 * 1024 * 1024) {
          fail('ClientSubmittedIntentCapacity');
        }
        database.prepare(`INSERT INTO client_submitted_intents VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`)
          .run(requestId, authorityScopeCid, submissionRef.nonce,
            canonicalValueJson(current.epoch, {dataKeys: true}), original.identity,
            original.wire, epochAuthority.get().observed_at, phase,
            outcome === undefined ? null : canonicalValueJson(outcome, {dataKeys: true}));
        if (Number(database.prepare(`UPDATE client_submitted_intent_custody
          SET issued_count = issued_count + 1 WHERE singleton = 1 AND issued_count = ?`)
          .run(retained.issued).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
        return {inserted: true, ...retainedIntent(intentSelect.get(requestId), control)};
      });
      if (result.epochRejected !== undefined) refuseEpoch(result.epochRejected);
      return Object.freeze(result);
    },
    lookupSubmittedIntent(submissionRef, {authorityScopeCid, currentAuthorization}, control) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      const row = intentSelect.get(requestId);
      return row === undefined ? undefined : retainedIntent(row, control);
    },
    // Explicit trusted-Host retention operation, not a Client cancellation
    // or evidence of nonexecution. In-progress and Run-connected custody stays
    // with its existing owners. No automatic eviction during new admission.
    retireSubmittedIntent(submissionRef, {authorityScopeCid, currentAuthorization,
      expectedRevision}, control) {
      ensureOpen();
      const fields = {authorityScopeCid, currentAuthorization, purpose: 'lookup'};
      const verified = verifyEpoch(submissionRef.epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentRetirement');
      }
      return Object.freeze(transaction.run(() => {
        const custody = assertIntentCustody();
        const current = verifyEpochLocked(submissionRef.epoch, fields, control);
        if (current.validity !== 'expired') fail('ClientSubmittedIntentNotRetirable');
        const row = intentSelect.get(requestId);
        if (row === undefined) return {retired: false};
        const original = retainedIntent(row, control);
        if (original.revision !== expectedRevision) fail('ClientSubmittedIntentRetirementConflict');
        if (!['not_accepted', 'preparation_failed'].includes(original.phase) ||
            select.get(authorityScopeCid, requestId) !== undefined) {
          fail('ClientSubmittedIntentNotRetirable');
        }
        if (Number(database.prepare(`DELETE FROM client_submitted_intents
          WHERE submission_id = ? AND revision = ?`).run(requestId, expectedRevision).changes) !== 1 ||
            Number(database.prepare(`UPDATE client_submitted_intent_retirement
              SET retired_count = retired_count + 1 WHERE singleton = 1 AND retired_count = ?`)
              .run(custody.retired).changes) !== 1) fail('ClientSubmittedIntentCustodyLost');
        return {retired: true};
      }));
    },
    completeSubmittedIntent(submissionRef, outcome, {authorityScopeCid,
      currentAuthorization, expectedRevision, connection}, control) {
      ensureOpen();
      const verified = verifyEpoch(submissionRef.epoch, {authorityScopeCid,
        currentAuthorization, purpose: 'lookup'}, control);
      const requestId = control.clientSubmissionRequestId(verified.handle, submissionRef.nonce);
      if (requestId === undefined || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
        fail('InvalidClientSubmittedIntentOutcome');
      }
      return transaction.run(() => {
        assertIntentCustody();
        const row = intentSelect.get(requestId);
        if (row === undefined) fail('ClientSubmittedIntentCustodyLost');
        const retained = retainedIntent(row, control);
        if (!sameSubmissionRef(retained.submissionRef, submissionRef) ||
            !validSubmissionOutcome(outcome, connection, submissionRef, retained.intentCid)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (retained.revision !== expectedRevision) return retained;
        if (!control.clientSubmittedIntentTransition(retained.phase, outcome.kind)) {
          fail('InvalidClientSubmittedIntentOutcome');
        }
        if (['ready', 'not_accepted', 'preparation_failed'].includes(retained.phase)) return retained;
        if (outcome.kind === 'ready') {
          const run = select.get(authorityScopeCid, requestId);
          if (run === undefined || run.run_definition_cid !== outcome.admission.ref.runDefinitionCid ||
              run.namespace_id !== outcome.admission.ref.namespaceId) fail('InvalidClientSubmittedIntentOutcome');
        }
        database.prepare(`UPDATE client_submitted_intents SET phase = ?, outcome_wire = ?, revision = revision + 1
          WHERE submission_id = ? AND revision = ?`).run(outcome.kind,
          canonicalValueJson(outcome, {dataKeys: true}), requestId, expectedRevision);
        return retainedIntent(intentSelect.get(requestId), control);
      });
    },
    issueSubmissionEpoch({authorityScopeCid, currentAuthorization}, control) {
      ensureOpen();
      if (currentAuthorization !== true) fail('ClientSubmissionEpochUnauthorized');
      if (!cid(authorityScopeCid)) fail('InvalidClientSubmissionEpochOperation');
      return transaction.run(() => {
        const clock = epochClock();
        const epoch = {version: 'actql-submission-epoch/0.1', authorityScopeCid,
          epochNonce: randomBytes(32).toString('hex'), notBefore: clock.observed_at,
          expiresAt: clock.observed_at + submissionEpochTtlMs};
        const handle = control.clientSubmissionEpoch(authorityScopeCid,
          epoch.epochNonce, epoch.notBefore, epoch.expiresAt);
        if (handle === undefined) fail('InvalidClientSubmissionEpochOperation');
        return Object.freeze({...epoch, authenticator: authenticateEpoch(
          clock.authentication_key, control.clientSubmissionEpochWire(handle))});
      });
    },
    verifySubmissionEpoch(epoch, fields, control) {
      const {handle: _handle, ...verified} = verifyEpoch(epoch, fields, control);
      return Object.freeze(verified);
    },
    submissionIdentity(epoch, nonce, fields, control) {
      const {handle, ...verified} = verifyEpoch(epoch, fields, control);
      const requestId = control.clientSubmissionRequestId(handle, nonce);
      if (requestId === undefined) fail('InvalidClientSubmissionNonce');
      return Object.freeze({...verified, requestId});
    },
    // The transaction owns uniqueness and durable acceptance; no task is
    // started here. A duplicate is interpreted only by the common MoonBit
    // relation, never by comparing transport JSON or a local retry counter.
    accept(identity, {namespaceId, runDefinitionCid, revision = 0,
      lookupExpiresAt, submission}, control) {
      return acceptRecord(identity, {namespaceId, runDefinitionCid,
        revision, lookupExpiresAt, submission}, control);
    },
    // The complete canonical Run Definition is retained in the same
    // transaction as the request. The caller must have obtained it from the
    // shared Run issuer; re-admission here checks identity, not authority.
    // Reattachment never reissues this identity.
    acceptDefinition(identity, {namespaceId, runDefinition, resultNames, runAdmissionEvidence,
      revision = 0, lookupExpiresAt, submission}, requestControl, publicationControl) {
      const definition = checkedRunDefinition(runDefinition,
        publicationControl, maxRunDefinitionWireBytes);
      const accepted = acceptRecord(identity, {namespaceId,
        runDefinitionCid: definition.identity,
        runDefinitionWire: definition.wire,
        resultNames, runAdmissionEvidence, revision, lookupExpiresAt, submission}, requestControl);
      // This optional projection runs after the semantic transaction. Only
      // its branded bounded queue is reachable here, never user delivery.
      observationProjection?.accepted(accepted,
        requestControl.clientRequestCallerId(identity));
      observationProjection?.emit('run', 'definition_admitted',
        {ref: accepted.ref, revision: accepted.revision});
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
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes),
      });
    },
    // Attach reads the original accepted Run Definition by its exact ref.
    // It does not infer authority from a CID alone or create another Run.
    lookupRunDefinition(ref, requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof requestControl?.clientRequestAdmitRecord !== 'function') {
        fail('InvalidClientRunLookup');
      }
      let row;
      try {
        row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
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
        revision: accepted.revision, requestId: row.caller_request_id,
        ...retainedRunFacts(row, publicationControl,
          maxRunDefinitionWireBytes),
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
    resolveDefinition(identity, {namespaceId}, requestControl,
      publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || !requestControl ||
          typeof requestControl.clientRequestRelation !== 'function') {
        fail('InvalidClientRequestLookup');
      }
      const fields = checkedIdentity(identity, requestControl);
      const retained = lookupRecord({namespaceId,
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
        ...retainedRunFacts(retained.row, publicationControl,
          maxRunDefinitionWireBytes),
      });
    },
    // Physical admit-or-lookup ordering for a checked request. The common
    // MoonBit relation decides whether a retained intent is the same request;
    // the callback may issue authority but must not start Compute. A racing
    // issuer is discarded when the atomic insert finds an existing Run.
    async admitOrLookupDefinition(identity, {namespaceId, lookupExpiresAt,
      issueDefinition, resultNames, sourceInventory, submission}, requestControl, publicationControl) {
      if (!text(namespaceId) || !instant(lookupExpiresAt) ||
          Date.parse(lookupExpiresAt) <= Date.now() ||
          typeof issueDefinition !== 'function') {
        fail('InvalidClientRequestAdmission');
      }
      if (sourceInventory !== undefined) validateSourceInventory(sourceInventory);
      ensureOpen();
      assertSubmissionCustody();
      const fields = checkedIdentity(identity, requestControl);
      const epochValidity = checkSubmissionBinding(fields, submission, requestControl);
      const retained = journal.resolveDefinition(identity, {namespaceId},
        requestControl, publicationControl);
      if (retained !== undefined) {
        assertSourceInventory(retained, sourceInventory);
        return Object.freeze({inserted: false, ...retained});
      }
      refuseEpoch(epochValidity);
      const issued = await issueDefinition();
      const runDefinition = issued.runDefinition ?? issued;
      if (issued.runAdmissionEvidence?.sourceInventory !== sourceInventory) {
        fail('ClientRequestSourceInventoryMismatch');
      }
      return journal.acceptDefinition(identity, {namespaceId, runDefinition,
        runAdmissionEvidence: issued.runAdmissionEvidence,
        lookupExpiresAt, resultNames: issued.resultNames ?? resultNames, submission}, requestControl, publicationControl);
    },
    // One physical transaction applies the common MoonBit start decision.
    // A committed reservation records possible dispatch before any work. A
    // later caller must reconcile that Run rather than run Compute again.
    reserveDispatch(identity, {namespaceId, currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunStartAction !== 'function') {
        fail('InvalidClientRunStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      return transact('start', 'ClientRunStartUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRequest') ||
            error.code.startsWith('ClientRun')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.namespace_id !== namespaceId) {
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
          return Object.freeze({kind: 'reserved',
            ...admission({...row, revision: Number(row.revision) + 1})});
        }
        if (action === 1) {
          return Object.freeze({kind: 'reconcile', ...admission(row)});
        }
        fail(action === 3 ? 'ClientRequestIntentConflict' :
          action === 5 ? 'ClientRunStartDenied' :
          'ClientRequestJournalCorrupt');
      });
    },
    // The exact durable claim precedes the call that can start physical
    // Compute. A missing claim is safe to resume; a claim or legacy unknown
    // is never evidence that Compute did not run.
    reservePhysicalStart(identity, {namespaceId, ref, currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(namespaceId) || !text(ref?.namespaceId) ||
          !cid(ref?.authorityScopeCid) || !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof requestControl?.clientRunPhysicalStartWithCancellationAction !==
            'function') {
        fail('InvalidClientRunPhysicalStart');
      }
      const fields = checkedIdentity(identity, requestControl);
      return transact('physical_start', 'ClientRunPhysicalStartUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRun') ||
            error.code.startsWith('ClientRequest')), () => {
        const row = select.get(fields.authorityScopeCid, fields.requestId);
        if (row === undefined || row.namespace_id !== namespaceId ||
            ref.namespaceId !== namespaceId ||
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
          return false;
        }
        if (action !== 1) {
          fail(action === 3 ? 'ClientRequestIntentConflict' :
            action === 5 ? 'ClientRunPhysicalStartDenied' :
            'ClientRequestJournalCorrupt');
        }
        if (reservePhysicalStart.run(ref.namespaceId,
          ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
        return true;
      });
    },
    // Persist the common cancellation decision under the physical-start lock.
    // The Host observes publication separately; a racing commit can still win.
    requestCancellation(ref, {currentAuthorization, publicationCommitted},
      requestControl, publicationControl) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') {
        fail('InvalidClientRunCancellation');
      }
      return transact('cancel', 'ClientRunCancellationUnknown',
        error => error?.code === 'ClientRunCancellationDenied', () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined) fail('ClientRunCancellationDenied');
        retainedIdentity(row, requestControl);
        const facts = retainedRunFacts(row, publicationControl,
          maxRunDefinitionWireBytes);
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed &&
              facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientRunCancellationDenied');
        if (action === 0) {
          database.prepare(`UPDATE client_requests SET
            cancellation_requested = 1, revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
        return Object.freeze({ref: admission(row).ref,
          kind: ['accepted', 'already_requested', 'already_terminal'][action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
      });
    },
    // Persist the immutable operation before touching the Model fence journal.
    // Pending custody is unknown, not acceptance. The final outcome and Run
    // cancellation flag commit together in this existing physical owner.
    recordCancellationOperation(ref, {cancelId, expectedRevision,
      currentAuthorization, publicationCommitted, modelCancellationOwner},
      requestControl, publicationControl) {
      ensureOpen();
      const cancelRef = ownedCancellationRef({...ref, cancelId, expectedRevision});
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean' ||
          typeof publicationCommitted !== 'boolean') fail('InvalidClientCancellationOperation');
      if (!currentAuthorization) fail('ClientCancellationDenied');
      const pending = transact('cancel_admission', 'ClientCancellationUnknown',
        cancellationKnownFailure, () => {
          const custodyCount = assertCancellationCustody();
          const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
          const identity = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
          const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId);
          const retained = record === undefined ? undefined :
            cancellationReadmission(record, requestControl, publicationControl);
          const action = cancellationAction(identity, retained?.identity, facts, row,
            currentAuthorization, publicationCommitted, requestControl);
          if (retained !== undefined) return {...retained, facts, action};
          if (Number(count.get().n) + custodyCount >= maxRecords) fail('ClientRequestJournalCapacity');
          cancellationInsert.run(ref.namespaceId, ref.authorityScopeCid, cancelId,
            ref.runDefinitionCid, expectedRevision, requestControl.clientCancellationIntentCid(identity));
          database.prepare(`UPDATE client_cancellation_custody SET issued_count = issued_count + 1
            WHERE singleton = 1`).run();
          return {identity, cancelRef, outcome: undefined, facts, action};
        });
      if (pending.outcome !== undefined) return Object.freeze({cancellation: pending.outcome, recorded: false});
      const originalRunWire = pending.facts.runAdmissionEvidence?.modelOriginalRunWire;
      if (originalRunWire !== undefined && !publicationCommitted &&
          !pending.facts.preDispatchFailureConfirmed &&
          !(pending.facts.physicalCloseConfirmed && pending.facts.observedTerminalOutcome !== null)) {
        try {
          if (typeof modelCancellationOwner?.fenceRunCancellation !== 'function' ||
              typeof modelCancellationOwner?.modelCancellationFenced !== 'function') {
            fail('ClientCancellationModelFenceUnavailable');
          }
          // Only the checkpoint Owner can establish the fence, using the
          // retained original input rather than the current Host configuration.
          modelCancellationOwner.fenceRunCancellation({originalRunWire});
          const runId = publicationControl.runDefinitionRunId(pending.facts.runDefinition);
          if (modelCancellationOwner.modelCancellationFenced(runId, ref.runDefinitionCid) !== true) {
            fail('ClientCancellationModelFenceUnconfirmed');
          }
        } catch (cause) { fail('ClientCancellationUnknown', cause); }
      }
      return transact('cancel_commit', 'ClientCancellationUnknown', cancellationKnownFailure, () => {
        assertCancellationCustody();
        const record = cancellationSelect.get(ref.namespaceId, ref.authorityScopeCid, cancelId);
        if (record === undefined) fail('ClientRequestJournalCorrupt');
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        const {row, facts} = cancellationDefinition(ref, requestControl, publicationControl);
        cancellationAction(pending.identity, retained.identity, facts, row,
          currentAuthorization, publicationCommitted, requestControl);
        if (retained.outcome !== undefined) return Object.freeze({cancellation: retained.outcome, recorded: false});
        const action = requestControl.clientRunCancellationAction(facts.runDefinition,
          ref.runDefinitionCid, currentAuthorization,
          publicationCommitted || facts.preDispatchFailureConfirmed ||
            facts.physicalCloseConfirmed && facts.observedTerminalOutcome !== null,
          facts.cancellationRequested);
        if (![0, 1, 2].includes(action)) fail('ClientCancellationDenied');
        if (action === 0 && row.revision >= 2147483647) fail('ClientCancellationRevisionConflict');
        if (action === 0) database.prepare(`UPDATE client_requests SET
          cancellation_requested = 1, revision = revision + 1
          WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`).run(
          ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
        const outcome = Object.freeze({ref: admission(row).ref, cancelRef: retained.cancelRef,
          kind: ['accepted', 'already_requested', 'already_terminal'][action],
          revision: Number(row.revision) + (action === 0 ? 1 : 0)});
        const wire = canonicalValueJson(outcome);
        const checksum = `sha256:${createHash('sha256').update(wire).digest('hex')}`;
        if (database.prepare(`UPDATE client_cancellation_operations SET outcome_wire = ?, outcome_cid = ?
          WHERE namespace_id = ? AND authority_scope_cid = ? AND cancel_id = ?
            AND outcome_wire IS NULL`).run(wire, checksum, ref.namespaceId,
          ref.authorityScopeCid, cancelId).changes !== 1) fail('ClientRequestJournalCorrupt');
        return Object.freeze({cancellation: outcome, recorded: true});
      });
    },
    // An exact, authorized observation. It never fences, starts execution or
    // completes a pending operation; absent custody is not proof of rejection.
    lookupCancellationOperation(cancelRef, {currentAuthorization},
      requestControl, publicationControl) {
      ensureOpen();
      if (!validCancellationRef(cancelRef) || typeof currentAuthorization !== 'boolean') {
        fail('InvalidClientCancellationLookup');
      }
      if (!currentAuthorization) fail('ClientCancellationDenied');
      return transact('cancel_lookup', 'ClientCancellationLookupUnknown', cancellationKnownFailure, () => {
        assertCancellationCustody();
        const {row, facts} = cancellationDefinition(cancelRef, requestControl, publicationControl);
        const requested = cancellationIdentity(cancelRef, facts.runDefinition, requestControl);
        const record = cancellationSelect.get(cancelRef.namespaceId, cancelRef.authorityScopeCid, cancelRef.cancelId);
        if (record === undefined) return Object.freeze({kind: 'unknown',
          cancelRef: ownedCancellationRef(cancelRef)});
        const retained = cancellationReadmission(record, requestControl, publicationControl);
        cancellationAction(requested, retained.identity, facts, row, currentAuthorization, false, requestControl);
        return retained.outcome === undefined ? Object.freeze({kind: 'unknown', cancelRef: retained.cancelRef}) :
          Object.freeze({kind: 'found', cancellation: retained.outcome});
      });
    },
    // Only the live execution owner may report a completed physical close.
    // A restarted process cannot infer this from its empty worker map.
    markPhysicalClose(ref, terminalOutcome = null) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid) ||
          terminalOutcome !== null &&
            !['failed', 'cancelled'].includes(terminalOutcome)) {
        fail('InvalidClientRunStopObservation');
      }
      return transact('stop_observation', 'ClientRunStopObservationUnknown',
        error => error?.code === 'ClientRunStopObservationDenied', () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.physical_start_reserved !== 1 ||
            row.physical_close_confirmed === 1 &&
              row.observed_terminal_outcome !== terminalOutcome) {
          fail('ClientRunStopObservationDenied');
        }
        if (row.physical_close_confirmed === 0) {
          database.prepare(`UPDATE client_requests SET
            physical_close_confirmed = 1, observed_terminal_outcome = ?,
            revision = revision + 1
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ? AND physical_start_reserved = 1 AND
              physical_close_confirmed = 0`).run(terminalOutcome,
            ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
        }
      });
    },
    // Physical Host evidence only: a failure before invoking Site execution
    // is confirmed. A lost reply or absent worker cannot call this method.
    markPreDispatchFailure(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunFailureObservation');
      }
      return transact('failure_observation',
        'ClientRunFailureObservationUnknown',
        error => typeof error?.code === 'string' &&
          (error.code.startsWith('ClientRun') ||
            error.code.startsWith('ClientRequest')), () => {
        const row = selectRef.get(ref.namespaceId, ref.authorityScopeCid,
          ref.runDefinitionCid);
        if (row === undefined || row.dispatch_reserved !== 1 ||
            row.pre_dispatch_failure_confirmed === 0 &&
            row.physical_start_reserved !== 0) {
          fail('ClientRunFailureObservationDenied');
        }
        if (row.pre_dispatch_failure_confirmed === 0 &&
            confirmPreDispatchFailure.run(ref.namespaceId,
              ref.authorityScopeCid, ref.runDefinitionCid).changes !== 1) {
          fail('ClientRequestJournalCorrupt');
        }
      });
    },
    // Keep the owner-issued `needs_reconciliation` state of a started Run
    // whose Effect outcomes are unknown. It is recorded once and never
    // replaced: a different state for the same Run is a conflict.
    recordReconciliationState(ref, wire) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
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
      return transact('reconciliation', 'ClientRunReconciliationUnknown',
        error => typeof error?.code === 'string' &&
          error.code.startsWith('ClientRun'), () => {
        const row = database.prepare(`SELECT physical_start_reserved,
          reconciliation_state_wire FROM client_requests
          WHERE namespace_id = ? AND authority_scope_cid = ? AND
            run_definition_cid = ?`).get(ref.namespaceId, ref.authorityScopeCid,
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
            WHERE namespace_id = ? AND authority_scope_cid = ? AND
              run_definition_cid = ?`).run(wire, ref.namespaceId,
            ref.authorityScopeCid, ref.runDefinitionCid);
        }
      });
    },
    lookupReconciliationState(ref) {
      ensureOpen();
      if (!text(ref?.namespaceId) || !cid(ref?.authorityScopeCid) ||
          !cid(ref?.runDefinitionCid)) {
        fail('InvalidClientRunLookup');
      }
      const row = database.prepare(`SELECT reconciliation_state_wire
        FROM client_requests WHERE namespace_id = ? AND
          authority_scope_cid = ? AND run_definition_cid = ?`).get(
        ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid);
      return row?.reconciliation_state_wire ?? undefined;
    },
    close() {
      closed = true;
      if (!databaseClosed) {
        database.close();
        databaseClosed = true;
      }
      // Observation cleanup is optional and never changes Run cleanup facts.
      // Its projection retains the handle and may retry after this close.
      try { closeObservationStorage(); }
      catch { /* The observation projection owns this separate connection. */ }
    },
  });
  return journal;
  } catch (error) {
    throwSqliteInitializationFailure(database, error, 'client-request-journal');
  }
}

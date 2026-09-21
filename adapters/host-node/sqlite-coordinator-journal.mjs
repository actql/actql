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
import {
  admitRemoteDispatchJson,
  admitRemoteExecutionEvidenceJson,
  admitRemoteManagedOutputMeasurementJson,
  admitRemoteManagedOutputSubjectJson,
} from
  '../host-common/remote-dispatch-wire.mjs';

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

function transaction(database, body) {
  database.exec('BEGIN IMMEDIATE');
  try {
    const value = body();
    database.exec('COMMIT');
    return value;
  } catch (error) {
    try { database.exec('ROLLBACK'); }
    catch (rollback) { fail('CoordinatorJournalRollbackFailed', rollback); }
    throw error;
  }
}

export function openSqliteCoordinatorDispatchJournal(root, {
  coordinatorAuthority,
  maxDispatches = 100_000,
  maxRequestBytes = 65_536,
  maxEvidenceBytes = 65_536,
  maxOutputOperations = 100_000,
  maxOutputBytes = 1_048_576,
  maxTransferChunks = 65_536,
  maxTransferManifestBytes = 16_777_216,
  maxTransferReferencedBytes = Number.MAX_SAFE_INTEGER,
} = {}) {
  if (!text(root) || !text(coordinatorAuthority) || !count(maxDispatches) ||
      maxDispatches === 0 || !count(maxRequestBytes) ||
      maxRequestBytes === 0 || !count(maxEvidenceBytes) ||
      maxEvidenceBytes === 0 || !count(maxOutputOperations) ||
      maxOutputOperations === 0 || !count(maxOutputBytes) ||
      maxOutputBytes === 0 || !count(maxTransferChunks) ||
      maxTransferChunks === 0 || !count(maxTransferManifestBytes) ||
      maxTransferManifestBytes === 0 ||
      !count(maxTransferReferencedBytes) ||
      maxTransferReferencedBytes === 0) {
    fail('InvalidCoordinatorJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'coordinator-dispatch-journal.sqlite3');
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
      CREATE TABLE IF NOT EXISTS journal_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS dispatch_intents (
        coordinator_authority TEXT NOT NULL,
        site_key TEXT NOT NULL,
        site_generation INTEGER NOT NULL,
        dispatch_id TEXT NOT NULL,
        dispatch_request_cid TEXT NOT NULL,
        run_definition_cid TEXT NOT NULL,
        task_key TEXT NOT NULL,
        task_attempt INTEGER NOT NULL,
        request_json TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
        progress_state INTEGER NOT NULL DEFAULT 0,
        site_revision INTEGER NOT NULL DEFAULT -1,
        site_execution INTEGER NOT NULL DEFAULT -1,
        site_evidence INTEGER NOT NULL DEFAULT -1,
        site_cleanup INTEGER NOT NULL DEFAULT -1,
        site_material_available INTEGER NOT NULL DEFAULT 0,
        site_quarantined_capacity INTEGER NOT NULL DEFAULT 0,
        accepted_evidence_cid TEXT NOT NULL DEFAULT '',
        accepted_evidence_json TEXT NOT NULL DEFAULT '',
        accepted_subject_cid TEXT NOT NULL DEFAULT '',
        accepted_subject_json TEXT NOT NULL DEFAULT '',
        accepted_measurement_cid TEXT NOT NULL DEFAULT '',
        accepted_measurement_json TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (
          coordinator_authority,
          site_key,
          site_generation,
          dispatch_id
        ),
        UNIQUE (
          coordinator_authority,
          run_definition_cid,
          task_key,
          task_attempt
        ),
        UNIQUE (dispatch_request_cid)
      ) STRICT;
      CREATE TABLE IF NOT EXISTS output_operations (
        coordinator_authority TEXT NOT NULL,
        site_key TEXT NOT NULL,
        site_generation INTEGER NOT NULL,
        dispatch_id TEXT NOT NULL,
        dispatch_request_cid TEXT NOT NULL,
        result_definition_cid TEXT NOT NULL,
        output_intent_cid TEXT NOT NULL,
        output_json TEXT NOT NULL,
        payload_request_cid TEXT NOT NULL,
        payload_request_json TEXT NOT NULL,
        transfer_request_cid TEXT NOT NULL,
        transfer_request_json TEXT NOT NULL,
        transfer_manifest_cid TEXT NOT NULL,
        transfer_manifest_json TEXT NOT NULL,
        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision >= 0),
        progress_state INTEGER NOT NULL DEFAULT 0,
        result_cid TEXT NOT NULL DEFAULT '',
        result_json TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (
          coordinator_authority,
          site_key,
          site_generation,
          dispatch_id,
          result_definition_cid
        ),
        UNIQUE (output_intent_cid),
        FOREIGN KEY (
          coordinator_authority,
          site_key,
          site_generation,
          dispatch_id
        ) REFERENCES dispatch_intents (
          coordinator_authority,
          site_key,
          site_generation,
          dispatch_id
        )
      ) STRICT;
    `);
    transaction(database, () => {
      const version = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (version === undefined) {
        const insert = database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        );
        insert.run('schema_version', 'actql-remote-coordinator-journal/0.5');
        insert.run('coordinator_authority', coordinatorAuthority);
      } else if (version.value ===
          'actql-remote-coordinator-journal/0.1') {
        database.exec(`
          ALTER TABLE dispatch_intents ADD COLUMN revision INTEGER NOT NULL
            DEFAULT 0 CHECK (revision >= 0);
          ALTER TABLE dispatch_intents ADD COLUMN progress_state INTEGER
            NOT NULL DEFAULT 0;
          ALTER TABLE dispatch_intents ADD COLUMN site_revision INTEGER
            NOT NULL DEFAULT -1;
          ALTER TABLE dispatch_intents ADD COLUMN site_execution INTEGER
            NOT NULL DEFAULT -1;
          ALTER TABLE dispatch_intents ADD COLUMN site_evidence INTEGER
            NOT NULL DEFAULT -1;
          ALTER TABLE dispatch_intents ADD COLUMN site_cleanup INTEGER
            NOT NULL DEFAULT -1;
          ALTER TABLE dispatch_intents ADD COLUMN site_material_available
            INTEGER NOT NULL DEFAULT 0;
          ALTER TABLE dispatch_intents ADD COLUMN
            site_quarantined_capacity INTEGER NOT NULL DEFAULT 0;
          ALTER TABLE dispatch_intents ADD COLUMN accepted_evidence_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_evidence_json TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_subject_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_subject_json TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_json TEXT
            NOT NULL DEFAULT '';
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-coordinator-journal/0.5', 'schema_version');
      } else if (version.value ===
          'actql-remote-coordinator-journal/0.2') {
        database.exec(`
          ALTER TABLE dispatch_intents ADD COLUMN accepted_subject_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_subject_json TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_json TEXT
            NOT NULL DEFAULT '';
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-coordinator-journal/0.5', 'schema_version');
      } else if (version.value ===
          'actql-remote-coordinator-journal/0.3') {
        const unverifiable = database.prepare(`
          SELECT COUNT(*) AS count FROM dispatch_intents
          WHERE accepted_subject_cid != '' OR accepted_subject_json != ''
        `).get();
        if (Number(unverifiable.count) !== 0) {
          fail('CoordinatorJournalMeasurementMigrationRequired');
        }
        database.exec(`
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_cid TEXT
            NOT NULL DEFAULT '';
          ALTER TABLE dispatch_intents ADD COLUMN accepted_measurement_json TEXT
            NOT NULL DEFAULT ''
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-coordinator-journal/0.5', 'schema_version');
      } else if (version.value ===
          'actql-remote-coordinator-journal/0.4') {
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-coordinator-journal/0.5', 'schema_version');
      } else if (version.value !==
          'actql-remote-coordinator-journal/0.5') {
        fail('UnsupportedCoordinatorJournalVersion');
      }
      const authority = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('coordinator_authority');
      if (authority?.value !== coordinatorAuthority) {
        fail('CoordinatorJournalAuthorityMismatch');
      }
    });
    if (!existed) syncDirectory(directory);
  } catch (error) {
    database.close();
    throw error;
  }

  const selectDispatch = database.prepare(`
    SELECT dispatch_request_cid, request_json, revision, progress_state,
      site_revision, site_execution, site_evidence, site_cleanup,
      site_material_available, site_quarantined_capacity,
      accepted_evidence_cid, accepted_evidence_json,
      accepted_subject_cid, accepted_subject_json,
      accepted_measurement_cid, accepted_measurement_json
    FROM dispatch_intents
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
  `);
  const selectAttempt = database.prepare(`
    SELECT dispatch_request_cid
    FROM dispatch_intents
    WHERE coordinator_authority = ? AND run_definition_cid = ?
      AND task_key = ? AND task_attempt = ?
  `);
  const selectAll = database.prepare(`
    SELECT dispatch_request_cid, request_json, revision, progress_state,
      site_revision, site_execution, site_evidence, site_cleanup,
      site_material_available, site_quarantined_capacity,
      accepted_evidence_cid, accepted_evidence_json,
      accepted_subject_cid, accepted_subject_json,
      accepted_measurement_cid, accepted_measurement_json
    FROM dispatch_intents
    ORDER BY run_definition_cid, task_key, task_attempt
  `);
  const countDispatches = database.prepare(
    'SELECT COUNT(*) AS count FROM dispatch_intents',
  );
  const insertDispatch = database.prepare(`
    INSERT INTO dispatch_intents (
      coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, run_definition_cid, task_key, task_attempt,
      request_json, revision, progress_state, site_revision, site_execution,
      site_evidence, site_cleanup, site_material_available,
      site_quarantined_capacity, accepted_evidence_cid,
      accepted_evidence_json, accepted_subject_cid, accepted_subject_json
      , accepted_measurement_cid, accepted_measurement_json
    ) VALUES (
      ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, -1, -1, -1, -1, 0, 0,
      '', '', '', '', '', ''
    )
  `);
  const updateDispatch = database.prepare(`
    UPDATE dispatch_intents SET
      revision = ?, progress_state = ?, site_revision = ?,
      site_execution = ?, site_evidence = ?, site_cleanup = ?,
      site_material_available = ?, site_quarantined_capacity = ?,
      accepted_evidence_cid = ?, accepted_evidence_json = ?,
      accepted_subject_cid = ?, accepted_subject_json = ?,
      accepted_measurement_cid = ?, accepted_measurement_json = ?
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
      AND revision = ? AND progress_state = ? AND site_revision = ?
      AND site_execution = ? AND site_evidence = ? AND site_cleanup = ?
      AND site_material_available = ? AND site_quarantined_capacity = ?
      AND accepted_evidence_cid = ? AND accepted_evidence_json = ?
      AND accepted_subject_cid = ? AND accepted_subject_json = ?
      AND accepted_measurement_cid = ? AND accepted_measurement_json = ?
  `);
  const selectOutput = database.prepare(`
    SELECT dispatch_request_cid, output_intent_cid, output_json,
      payload_request_cid, payload_request_json, transfer_request_cid,
      transfer_request_json, transfer_manifest_cid,
      transfer_manifest_json, revision, progress_state, result_cid,
      result_json
    FROM output_operations
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
      AND result_definition_cid = ?
  `);
  const selectAllOutputs = database.prepare(`
    SELECT coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, result_definition_cid, output_intent_cid,
      output_json, payload_request_cid, payload_request_json,
      transfer_request_cid, transfer_request_json, transfer_manifest_cid,
      transfer_manifest_json, revision, progress_state, result_cid,
      result_json
    FROM output_operations
    ORDER BY coordinator_authority, site_key, site_generation, dispatch_id,
      result_definition_cid
  `);
  const countOutputs = database.prepare(
    'SELECT COUNT(*) AS count FROM output_operations',
  );
  const insertOutput = database.prepare(`
    INSERT INTO output_operations (
      coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, result_definition_cid, output_intent_cid,
      output_json, payload_request_cid, payload_request_json,
      transfer_request_cid, transfer_request_json, transfer_manifest_cid,
      transfer_manifest_json, revision, progress_state, result_cid,
      result_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, '', '')
  `);
  const updateOutput = database.prepare(`
    UPDATE output_operations SET revision = ?, progress_state = ?,
      result_cid = ?, result_json = ?
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
      AND result_definition_cid = ? AND output_intent_cid = ?
      AND revision = ? AND progress_state = ? AND result_cid = ?
      AND result_json = ?
  `);

  const ensureOpen = () => {
    if (closed) fail('CoordinatorJournalClosed');
  };
  const integer = value => Number.isSafeInteger(value);
  const bit = value => value === 0 || value === 1;
  const rowState = row => Object.freeze([
    row.revision,
    row.progress_state,
    row.site_revision,
    row.site_execution,
    row.site_evidence,
    row.site_cleanup,
    row.site_material_available,
    row.site_quarantined_capacity,
    row.accepted_evidence_cid,
    row.accepted_subject_cid,
    row.accepted_measurement_cid,
  ]);
  const restoredState = row => {
    const state = rowState(row);
    if (state.slice(0, 6).some(value => !integer(value)) ||
        !bit(state[6]) || !bit(state[7]) ||
        typeof state[8] !== 'string' || typeof state[9] !== 'string' ||
        typeof state[10] !== 'string' ||
        typeof row.accepted_evidence_json !== 'string' ||
        typeof row.accepted_subject_json !== 'string' ||
        typeof row.accepted_measurement_json !== 'string') {
      fail('InvalidCoordinatorJournalState');
    }
    return Object.freeze([
      ...state.slice(0, 6),
      state[6] === 1,
      state[7] === 1,
      state[8],
      state[9],
      state[10],
    ]);
  };
  const parseProjection = value => {
    if (!Array.isArray(value) || value.length !== 22 ||
        value.some(item => typeof item !== 'string')) {
      fail('InvalidCoordinatorJournalTransition');
    }
    const parseInteger = item => {
      if (!/^-?(0|[1-9][0-9]*)$/.test(item)) {
        fail('InvalidCoordinatorJournalTransition');
      }
      const parsed = Number(item);
      if (!integer(parsed)) fail('InvalidCoordinatorJournalTransition');
      return parsed;
    };
    const parseBit = item => {
      if (item !== '0' && item !== '1') {
        fail('InvalidCoordinatorJournalTransition');
      }
      return Number(item);
    };
    const state = offset => Object.freeze([
      parseInteger(value[offset]),
      parseInteger(value[offset + 1]),
      parseInteger(value[offset + 2]),
      parseInteger(value[offset + 3]),
      parseInteger(value[offset + 4]),
      parseInteger(value[offset + 5]),
      parseBit(value[offset + 6]),
      parseBit(value[offset + 7]),
      value[offset + 8],
      value[offset + 9],
      value[offset + 10],
    ]);
    return Object.freeze({expected: state(0), next: state(11)});
  };
  const sameState = (left, right) => left.length === right.length &&
    left.every((value, index) => value === right[index]);
  const prepareTransition = (transition, record, control) => {
    if (control === null || typeof control !== 'object' ||
        typeof control.coordinatorTransitionKey !== 'function' ||
        typeof control.coordinatorTransitionProjection !== 'function' ||
        typeof control.commitCoordinatorTransition !== 'function' ||
        typeof control.coordinatorRecordRevision !== 'function') {
      fail('MissingRemoteCoordinatorControl');
    }
    const key = control.coordinatorTransitionKey(transition);
    const generation = Number(key?.[2]);
    if (!Array.isArray(key) || key.length !== 7 ||
        key.some(value => !text(value)) || key[0] !== coordinatorAuthority ||
        !count(generation)) {
      fail('InvalidCoordinatorJournalTransition');
    }
    const states = parseProjection(
      control.coordinatorTransitionProjection(transition),
    );
    if (control.coordinatorRecordRevision(record) !== states.expected[0]) {
      fail('CoordinatorDispatchStateCollision');
    }
    return Object.freeze({key, generation, states});
  };
  const persistTransition = (
    prepared,
    evidenceJson,
    subjectJson,
    measurementJson,
  ) => {
    const {key, generation, states} = prepared;
    const found = selectDispatch.get(key[0], key[1], generation, key[3]);
    if (found === undefined) fail('CoordinatorJournalRecordMissing');
    const current = rowState(found);
    if (sameState(current, states.next)) {
      if (evidenceJson !== undefined &&
          found.accepted_evidence_json !== evidenceJson) {
        fail('CoordinatorDispatchStateCollision');
      }
      if (subjectJson !== undefined &&
          found.accepted_subject_json !== subjectJson) {
        fail('CoordinatorDispatchStateCollision');
      }
      if (measurementJson !== undefined &&
          found.accepted_measurement_json !== measurementJson) {
        fail('CoordinatorDispatchStateCollision');
      }
      return states;
    }
    if (!sameState(current, states.expected)) {
      fail('CoordinatorDispatchStateCollision');
    }
    let nextEvidenceJson = found.accepted_evidence_json;
    if (evidenceJson !== undefined) {
      if (!text(evidenceJson) ||
          Buffer.byteLength(evidenceJson, 'utf8') > maxEvidenceBytes ||
          !text(states.next[8])) {
        fail('InvalidRemoteExecutionEvidence');
      }
      nextEvidenceJson = evidenceJson;
    } else if (states.next[8] !== states.expected[8]) {
      fail('RemoteExecutionEvidenceMissing');
    }
    let nextSubjectJson = found.accepted_subject_json;
    if (subjectJson !== undefined) {
      if (!text(subjectJson) ||
          Buffer.byteLength(subjectJson, 'utf8') > maxEvidenceBytes ||
          !text(states.next[9]) || evidenceJson === undefined) {
        fail('InvalidRemoteManagedOutputSubject');
      }
      nextSubjectJson = subjectJson;
    } else if (states.next[9] !== states.expected[9]) {
      fail('RemoteManagedOutputSubjectMissing');
    }
    let nextMeasurementJson = found.accepted_measurement_json;
    if (measurementJson !== undefined) {
      if (!text(measurementJson) ||
          Buffer.byteLength(measurementJson, 'utf8') > maxEvidenceBytes ||
          !text(states.next[10]) || subjectJson === undefined) {
        fail('InvalidRemoteManagedOutputMeasurement');
      }
      nextMeasurementJson = measurementJson;
    } else if (states.next[10] !== states.expected[10]) {
      fail('RemoteManagedOutputMeasurementMissing');
    }
    const result = updateDispatch.run(
      ...states.next.slice(0, 9), nextEvidenceJson,
      states.next[9], nextSubjectJson,
      states.next[10], nextMeasurementJson,
      key[0], key[1], generation, key[3],
      ...states.expected.slice(0, 9), found.accepted_evidence_json,
      states.expected[9], found.accepted_subject_json,
      states.expected[10], found.accepted_measurement_json,
    );
    if (result.changes !== 1) fail('CoordinatorDispatchStateCollision');
    return states;
  };
  const advanceTransition = (
    transition,
    evidence,
    subject,
    measurement,
    record,
    control,
  ) => {
    ensureOpen();
    const prepared = prepareTransition(transition, record, control);
    let evidenceJson;
    let subjectJson;
    let measurementJson;
    if (evidence !== undefined) {
      if (typeof control.evidenceIdentity !== 'function' ||
          typeof control.evidenceJson !== 'function' ||
          control.evidenceIdentity(evidence) !== prepared.states.next[8]) {
        fail('RemoteExecutionEvidenceMismatch');
      }
      evidenceJson = control.evidenceJson(evidence);
    }
    if (subject !== undefined) {
      if (evidence === undefined ||
          typeof control.managedOutputSubjectIdentity !== 'function' ||
          typeof control.managedOutputSubjectJson !== 'function' ||
          control.managedOutputSubjectIdentity(subject) !==
            prepared.states.next[9]) {
        fail('RemoteManagedOutputEvidenceMismatch');
      }
      subjectJson = control.managedOutputSubjectJson(subject);
    }
    if (measurement !== undefined) {
      if (subject === undefined ||
          typeof control.managedOutputMeasurementIdentity !== 'function' ||
          typeof control.managedOutputMeasurementJson !== 'function' ||
          control.managedOutputMeasurementIdentity(measurement) !==
            prepared.states.next[10]) {
        fail('RemoteManagedOutputMeasurementMismatch');
      }
      measurementJson = control.managedOutputMeasurementJson(measurement);
    }
    transaction(database, () => persistTransition(
      prepared,
      evidenceJson,
      subjectJson,
      measurementJson,
    ));
    control.commitCoordinatorTransition(transition, true);
    if (control.coordinatorRecordRevision(record) !==
        prepared.states.next[0]) {
      fail('CoordinatorJournalControlDiverged');
    }
    return record;
  };
  const install = (request, requestJson, control) => {
    ensureOpen();
    if (!text(requestJson) || Buffer.byteLength(requestJson, 'utf8') >
        maxRequestBytes || control === null || typeof control !== 'object' ||
        typeof control.identity !== 'function' ||
        typeof control.journalKey !== 'function') {
      fail('InvalidCoordinatorJournalRequest');
    }
    const identity = control.identity(request);
    const key = control.journalKey(request);
    if (!text(identity) || !Array.isArray(key) || key.length !== 7 ||
        key.some(value => !text(value)) || key[0] !== coordinatorAuthority) {
      fail('InvalidCoordinatorJournalRequest');
    }
    const generation = Number(key[2]);
    const attempt = Number(key[6]);
    if (!count(generation) || !count(attempt) || attempt === 0) {
      fail('InvalidCoordinatorJournalRequest');
    }
    return transaction(database, () => {
      const existing = selectDispatch.get(
        key[0], key[1], generation, key[3],
      );
      if (existing !== undefined) {
        if (existing.dispatch_request_cid !== identity ||
            existing.request_json !== requestJson) {
          fail('RemoteDispatchCollision');
        }
        return false;
      }
      const prior = selectAttempt.get(key[0], key[4], key[5], attempt);
      if (prior !== undefined) fail('RemoteAttemptAlreadyDispatched');
      const total = Number(countDispatches.get().count);
      if (!count(total) || total >= maxDispatches) {
        fail('CoordinatorJournalCapacityExceeded');
      }
      insertDispatch.run(
        key[0], key[1], generation, key[3], identity,
        key[4], key[5], attempt, requestJson,
      );
      return true;
    });
  };

  const outputRowState = row => Object.freeze([
    row.revision,
    row.progress_state,
    row.result_cid,
  ]);
  const parseOutputTransition = value => {
    if (!Array.isArray(value) || value.length !== 6 ||
        value.some(item => typeof item !== 'string')) {
      fail('InvalidCoordinatorOutputTransition');
    }
    const parseInteger = item => {
      if (!/^(0|[1-9][0-9]*)$/.test(item)) {
        fail('InvalidCoordinatorOutputTransition');
      }
      const parsed = Number(item);
      if (!count(parsed)) fail('InvalidCoordinatorOutputTransition');
      return parsed;
    };
    return Object.freeze({
      expected: Object.freeze([
        parseInteger(value[0]),
        parseInteger(value[1]),
        value[2],
      ]),
      next: Object.freeze([
        parseInteger(value[3]),
        parseInteger(value[4]),
        value[5],
      ]),
    });
  };
  const checkedOutputKey = (value, code) => {
    if (!Array.isArray(value) || value.length !== 7 ||
        value.some(item => !text(item)) ||
        value[0] !== coordinatorAuthority) {
      fail(code);
    }
    const generation = Number(value[2]);
    if (!count(generation)) fail(code);
    return Object.freeze({value, generation});
  };
  const outputWire = (
    admission,
    payloadRequest,
    transferRequest,
    control,
    transferControl,
  ) => {
    if (control === null || typeof control !== 'object' ||
        typeof control.coordinatorOutputAdmissionKey !== 'function' ||
        typeof control.coordinatorOutputAdmissionJson !== 'function' ||
        typeof control.outputExpectedIdentity !== 'function' ||
        typeof control.publicationPayloadJson !== 'function' ||
        transferControl === null || typeof transferControl !== 'object' ||
        typeof transferControl.identity !== 'function' ||
        typeof transferControl.requestJson !== 'function' ||
        typeof transferControl.manifestJson !== 'function' ||
        typeof transferControl.requestProjection !== 'function') {
      fail('MissingRemoteCoordinatorOutputControl');
    }
    const key = checkedOutputKey(
      control.coordinatorOutputAdmissionKey(admission),
      'InvalidCoordinatorOutputIntent',
    );
    const outputJson = control.coordinatorOutputAdmissionJson(admission);
    const expected = control.outputExpectedIdentity(
      payloadRequest,
      transferRequest,
    );
    const payloadJson = control.publicationPayloadJson(payloadRequest);
    const transferJson = transferControl.requestJson(transferRequest);
    const manifestJson = transferControl.manifestJson(transferRequest);
    const transferProjection = transferControl.requestProjection(
      transferRequest,
    );
    if (!Array.isArray(expected) || expected.length !== 2 ||
        expected.some(value => !text(value)) ||
        expected[1] !== transferControl.identity(transferRequest) ||
        !Array.isArray(transferProjection) ||
        transferProjection.length !== 13 ||
        !text(transferProjection[7]) ||
        [outputJson, payloadJson, transferJson, manifestJson].some(
          value => !text(value),
        ) || Buffer.byteLength(outputJson, 'utf8') > maxOutputBytes ||
        Buffer.byteLength(payloadJson, 'utf8') > maxOutputBytes ||
        Buffer.byteLength(transferJson, 'utf8') > maxOutputBytes ||
        Buffer.byteLength(manifestJson, 'utf8') >
          maxTransferManifestBytes) {
      fail('InvalidCoordinatorOutputIntent');
    }
    return Object.freeze({
      key,
      outputJson,
      payloadCid: expected[0],
      payloadJson,
      transferCid: expected[1],
      transferJson,
      manifestCid: transferProjection[7],
      manifestJson,
    });
  };
  const installOutput = wire => transaction(
    database,
    () => {
      const key = wire.key.value;
      const existing = selectOutput.get(
        key[0], key[1], wire.key.generation, key[3], key[5],
      );
      if (existing !== undefined) {
        if (existing.dispatch_request_cid !== key[4] ||
            existing.output_intent_cid !== key[6] ||
            existing.output_json !== wire.outputJson ||
            existing.payload_request_cid !== wire.payloadCid ||
            existing.payload_request_json !== wire.payloadJson ||
            existing.transfer_request_cid !== wire.transferCid ||
            existing.transfer_request_json !== wire.transferJson ||
            existing.transfer_manifest_cid !== wire.manifestCid ||
            existing.transfer_manifest_json !== wire.manifestJson) {
          fail('CoordinatorOutputCollision');
        }
      } else {
        const total = Number(countOutputs.get().count);
        if (!count(total) || total >= maxOutputOperations) {
          fail('CoordinatorJournalCapacityExceeded');
        }
        insertOutput.run(
          key[0], key[1], wire.key.generation, key[3], key[4], key[5],
          key[6], wire.outputJson, wire.payloadCid, wire.payloadJson,
          wire.transferCid, wire.transferJson, wire.manifestCid,
          wire.manifestJson,
        );
      }
      return existing === undefined;
    },
  );
  const advanceOutput = (transition, result, record, control) => {
    ensureOpen();
    if (control === null || typeof control !== 'object' ||
        typeof control.coordinatorOutputTransitionKey !== 'function' ||
        typeof control.coordinatorOutputTransitionProjection !== 'function' ||
        typeof control.commitCoordinatorOutputTransition !== 'function' ||
        typeof control.coordinatorOutputRecordRevision !== 'function') {
      fail('MissingRemoteCoordinatorOutputControl');
    }
    const key = checkedOutputKey(
      control.coordinatorOutputTransitionKey(transition),
      'InvalidCoordinatorOutputTransition',
    );
    const states = parseOutputTransition(
      control.coordinatorOutputTransitionProjection(transition),
    );
    if (control.coordinatorOutputRecordRevision(record) !==
        states.expected[0]) {
      fail('CoordinatorOutputStateCollision');
    }
    let resultJson = '';
    if (result !== undefined) {
      if (typeof control.outputResultIdentity !== 'function' ||
          typeof control.outputResultJson !== 'function' ||
          control.outputResultIdentity(result) !== states.next[2]) {
        fail('CoordinatorOutputResultMismatch');
      }
      resultJson = control.outputResultJson(result);
      if (!text(resultJson) ||
          Buffer.byteLength(resultJson, 'utf8') > maxOutputBytes) {
        fail('InvalidCoordinatorOutputResult');
      }
    } else if (states.next[2] !== '') {
      fail('CoordinatorOutputResultMissing');
    }
    transaction(database, () => {
      const values = key.value;
      const found = selectOutput.get(
        values[0], values[1], key.generation, values[3], values[5],
      );
      if (found === undefined || found.output_intent_cid !== values[6]) {
        fail('CoordinatorOutputRecordMissing');
      }
      const current = outputRowState(found);
      if (sameState(current, states.next)) {
        if (found.result_json !== resultJson) {
          fail('CoordinatorOutputStateCollision');
        }
        return;
      }
      if (!sameState(current, states.expected)) {
        fail('CoordinatorOutputStateCollision');
      }
      const changed = updateOutput.run(
        states.next[0], states.next[1], states.next[2], resultJson,
        values[0], values[1], key.generation, values[3], values[5],
        values[6], states.expected[0], states.expected[1],
        states.expected[2], found.result_json,
      );
      if (changed.changes !== 1) fail('CoordinatorOutputStateCollision');
    });
    control.commitCoordinatorOutputTransition(transition, true);
    if (control.coordinatorOutputRecordRevision(record) !== states.next[0]) {
      fail('CoordinatorJournalControlDiverged');
    }
    return record;
  };

  return Object.freeze({
    path,
    recoverJournal(journal, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.restoreCoordinatorIntent !== 'function' ||
          typeof control.restoreCoordinatorRecord !== 'function') {
        fail('MissingRemoteCoordinatorControl');
      }
      const recovered = [];
      for (const row of selectAll.all()) {
        let request;
        try {
          request = admitRemoteDispatchJson(
            control,
            row.request_json,
            row.dispatch_request_cid,
            maxRequestBytes,
          );
        } catch (error) {
          fail('InvalidCoordinatorJournalRequest', error);
        }
        const record = control.restoreCoordinatorIntent(journal, request);
        control.restoreCoordinatorRecord(record, restoredState(row));
        let evidence;
        if (text(row.accepted_evidence_cid)) {
          if (!text(row.accepted_evidence_json)) {
            fail('InvalidCoordinatorJournalEvidence');
          }
          try {
            evidence = admitRemoteExecutionEvidenceJson(
              control,
              row.accepted_evidence_json,
              row.accepted_evidence_cid,
              request,
              maxEvidenceBytes,
            );
          } catch (error) {
            fail('InvalidCoordinatorJournalEvidence', error);
          }
        } else if (row.accepted_evidence_json !== '') {
          fail('InvalidCoordinatorJournalEvidence');
        }
        let subject;
        if (text(row.accepted_subject_cid)) {
          if (evidence === undefined || !text(row.accepted_subject_json)) {
            fail('InvalidCoordinatorJournalSubject');
          }
          try {
            subject = admitRemoteManagedOutputSubjectJson(
              control,
              row.accepted_subject_json,
              row.accepted_subject_cid,
              request,
              maxEvidenceBytes,
            );
            if (!control.managedOutputSubjectMatchesEvidence(
              subject,
              evidence,
              request,
            )) {
              fail('InvalidCoordinatorJournalSubject');
            }
          } catch (error) {
            fail('InvalidCoordinatorJournalSubject', error);
          }
        } else if (row.accepted_subject_json !== '') {
          fail('InvalidCoordinatorJournalSubject');
        }
        let measurement;
        if (text(row.accepted_measurement_cid)) {
          if (subject === undefined ||
              !text(row.accepted_measurement_json)) {
            fail('InvalidCoordinatorJournalMeasurement');
          }
          try {
            measurement = admitRemoteManagedOutputMeasurementJson(
              control,
              row.accepted_measurement_json,
              row.accepted_measurement_cid,
              maxEvidenceBytes,
            );
            if (!control.managedOutputSubjectMatchesMeasurement(
              subject,
              measurement,
            )) {
              fail('InvalidCoordinatorJournalMeasurement');
            }
          } catch (error) {
            fail('InvalidCoordinatorJournalMeasurement', error);
          }
        } else if (row.accepted_measurement_json !== '') {
          fail('InvalidCoordinatorJournalMeasurement');
        }
        recovered.push(Object.freeze({
          request,
          record,
          evidence,
          evidenceWire: row.accepted_evidence_json || undefined,
          subject,
          subjectWire: row.accepted_subject_json || undefined,
          measurement,
          measurementWire: row.accepted_measurement_json || undefined,
        }));
      }
      return Object.freeze(recovered);
    },
    recoverOutputs(journal, control, transferControl) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.admitPollOutput !== 'function' ||
          typeof control.admitPublicationPayloadJson !== 'function' ||
          typeof control.prepareCoordinatorOutput !== 'function' ||
          typeof control.commitCoordinatorOutput !== 'function' ||
          typeof control.restoreCoordinatorOutputRecord !== 'function' ||
          transferControl === null || typeof transferControl !== 'object' ||
          typeof transferControl.admitJson !== 'function') {
        fail('MissingRemoteCoordinatorOutputControl');
      }
      const recovered = [];
      for (const row of selectAllOutputs.all()) {
        try {
          if (!text(row.output_json) || !text(row.output_intent_cid) ||
              !text(row.payload_request_json) ||
              !text(row.payload_request_cid) ||
              !text(row.transfer_request_json) ||
              !text(row.transfer_request_cid) ||
              !text(row.transfer_manifest_json) ||
              !text(row.transfer_manifest_cid) ||
              Buffer.byteLength(row.output_json, 'utf8') > maxOutputBytes ||
              Buffer.byteLength(row.payload_request_json, 'utf8') >
                maxOutputBytes ||
              Buffer.byteLength(row.transfer_request_json, 'utf8') >
                maxOutputBytes ||
              Buffer.byteLength(row.transfer_manifest_json, 'utf8') >
                maxTransferManifestBytes || !count(row.revision) ||
              !count(row.progress_state) ||
              typeof row.result_cid !== 'string' ||
              typeof row.result_json !== 'string') {
            fail('InvalidCoordinatorOutputRecord');
          }
          const output = control.admitPollOutput(row.output_json);
          const payloadRequest = control.admitPublicationPayloadJson(
            row.payload_request_json,
            row.payload_request_cid,
          );
          const transferRequest = transferControl.admitJson(
            row.transfer_request_json,
            row.transfer_manifest_json,
            row.transfer_request_cid,
            row.transfer_manifest_cid,
            {
              maxChunks: maxTransferChunks,
              maxManifestBytes: maxTransferManifestBytes,
              maxReferencedBytes: maxTransferReferencedBytes,
            },
          );
          const admission = control.prepareCoordinatorOutput(
            journal,
            output,
            payloadRequest,
            transferRequest,
          );
          const key = checkedOutputKey(
            control.coordinatorOutputAdmissionKey(admission),
            'InvalidCoordinatorOutputRecord',
          ).value;
          if (key[0] !== row.coordinator_authority ||
              key[1] !== row.site_key ||
              Number(key[2]) !== row.site_generation ||
              key[3] !== row.dispatch_id ||
              key[4] !== row.dispatch_request_cid ||
              key[5] !== row.result_definition_cid ||
              key[6] !== row.output_intent_cid) {
            fail('InvalidCoordinatorOutputRecord');
          }
          const record = control.commitCoordinatorOutput(admission, true);
          control.restoreCoordinatorOutputRecord(
            record,
            row.revision,
            row.progress_state,
            row.result_json,
          );
          const status = control.coordinatorOutputRecordStatus(record);
          if (!Array.isArray(status) || status.length !== 3 ||
              Number(status[0]) !== row.revision ||
              Number(status[1]) !== row.progress_state ||
              status[2] !== row.result_cid) {
            fail('InvalidCoordinatorOutputRecord');
          }
          recovered.push(Object.freeze({
            output,
            payloadRequest,
            transferRequest,
            record,
          }));
        } catch (error) {
          fail('InvalidCoordinatorOutputRecord', error);
        }
      }
      return Object.freeze(recovered);
    },
    accept(admission, request, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.coordinatorIntentJson !== 'function' ||
          typeof control.commitCoordinatorIntent !== 'function' ||
          typeof control.coordinatorIntentMatches !== 'function') {
        fail('MissingRemoteCoordinatorControl');
      }
      const requestJson = control.coordinatorIntentJson(admission);
      if (requestJson !== control.requestJson(request)) {
        fail('CoordinatorIntentRequestMismatch');
      }
      install(request, requestJson, control);
      const record = control.commitCoordinatorIntent(admission, true);
      if (!control.coordinatorIntentMatches(record, request)) {
        fail('CoordinatorJournalControlDiverged');
      }
      return record;
    },
    acceptOutput(
      admission,
      payloadRequest,
      transferRequest,
      control,
      transferControl,
    ) {
      ensureOpen();
      if (typeof control?.commitCoordinatorOutput !== 'function' ||
          typeof control?.coordinatorOutputRecordKey !== 'function') {
        fail('MissingRemoteCoordinatorOutputControl');
      }
      const wire = outputWire(
        admission,
        payloadRequest,
        transferRequest,
        control,
        transferControl,
      );
      installOutput(wire);
      const record = control.commitCoordinatorOutput(admission, true);
      const recordKey = control.coordinatorOutputRecordKey(record);
      if (!Array.isArray(recordKey) ||
          !sameState(recordKey, wire.key.value)) {
        fail('CoordinatorJournalControlDiverged');
      }
      return record;
    },
    advanceOutputUnknown(transition, record, control) {
      return advanceOutput(transition, undefined, record, control);
    },
    advanceOutputSuccess(transition, result, record, control) {
      return advanceOutput(transition, result, record, control);
    },
    inspectOutput(outputRecord, control) {
      ensureOpen();
      if (typeof control?.coordinatorOutputRecordKey !== 'function') {
        fail('MissingRemoteCoordinatorOutputControl');
      }
      const key = checkedOutputKey(
        control.coordinatorOutputRecordKey(outputRecord),
        'InvalidCoordinatorOutputRecord',
      );
      const row = selectOutput.get(
        key.value[0], key.value[1], key.generation, key.value[3],
        key.value[5],
      );
      if (row === undefined || row.output_intent_cid !== key.value[6]) {
        return undefined;
      }
      return Object.freeze({
        revision: row.revision,
        progress: row.progress_state,
        resultCid: row.result_cid || undefined,
        resultJson: row.result_json || undefined,
      });
    },
    hasOutputOperations() {
      ensureOpen();
      const total = Number(countOutputs.get().count);
      if (!count(total)) fail('InvalidCoordinatorJournalState');
      return total !== 0;
    },
    advance(transition, record, control) {
      return advanceTransition(
        transition,
        undefined,
        undefined,
        undefined,
        record,
        control,
      );
    },
    advanceEvidence(
      transition,
      evidence,
      subject,
      measurement,
      record,
      control,
    ) {
      return advanceTransition(
        transition,
        evidence,
        subject,
        measurement,
        record,
        control,
      );
    },
    contains(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const row = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      return row !== undefined &&
        row.dispatch_request_cid === control.identity(request) &&
        row.request_json === control.requestJson(request);
    },
    inspectState(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const row = selectDispatch.get(
        key[0], key[1], Number(key[2]), key[3],
      );
      return row === undefined ? undefined : restoredState(row);
    },
    inspectEvidence(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const row = selectDispatch.get(
        key[0], key[1], Number(key[2]), key[3],
      );
      if (row === undefined || !text(row.accepted_evidence_cid) ||
          !text(row.accepted_evidence_json)) {
        return undefined;
      }
      return Object.freeze({
        evidenceCid: row.accepted_evidence_cid,
        evidenceWire: row.accepted_evidence_json,
        subjectCid: row.accepted_subject_cid || undefined,
        subjectWire: row.accepted_subject_json || undefined,
        measurementCid: row.accepted_measurement_cid || undefined,
        measurementWire: row.accepted_measurement_json || undefined,
      });
    },
    close() {
      if (closed) return false;
      closed = true;
      database.close();
      return true;
    },
  });
}

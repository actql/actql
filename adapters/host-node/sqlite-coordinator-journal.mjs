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
} = {}) {
  if (!text(root) || !text(coordinatorAuthority) || !count(maxDispatches) ||
      maxDispatches === 0 || !count(maxRequestBytes) ||
      maxRequestBytes === 0 || !count(maxEvidenceBytes) ||
      maxEvidenceBytes === 0) {
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
    `);
    transaction(database, () => {
      const version = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (version === undefined) {
        const insert = database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        );
        insert.run('schema_version', 'actql-remote-coordinator-journal/0.2');
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
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-coordinator-journal/0.2', 'schema_version');
      } else if (version.value !==
          'actql-remote-coordinator-journal/0.2') {
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
      accepted_evidence_cid, accepted_evidence_json
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
      accepted_evidence_cid, accepted_evidence_json
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
      accepted_evidence_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, -1, -1, -1, -1, 0, 0, '', '')
  `);
  const updateDispatch = database.prepare(`
    UPDATE dispatch_intents SET
      revision = ?, progress_state = ?, site_revision = ?,
      site_execution = ?, site_evidence = ?, site_cleanup = ?,
      site_material_available = ?, site_quarantined_capacity = ?,
      accepted_evidence_cid = ?, accepted_evidence_json = ?
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
      AND revision = ? AND progress_state = ? AND site_revision = ?
      AND site_execution = ? AND site_evidence = ? AND site_cleanup = ?
      AND site_material_available = ? AND site_quarantined_capacity = ?
      AND accepted_evidence_cid = ? AND accepted_evidence_json = ?
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
  ]);
  const restoredState = row => {
    const state = rowState(row);
    if (state.slice(0, 6).some(value => !integer(value)) ||
        !bit(state[6]) || !bit(state[7]) ||
        typeof state[8] !== 'string' ||
        typeof row.accepted_evidence_json !== 'string') {
      fail('InvalidCoordinatorJournalState');
    }
    return Object.freeze([
      ...state.slice(0, 6),
      state[6] === 1,
      state[7] === 1,
      state[8],
    ]);
  };
  const parseProjection = value => {
    if (!Array.isArray(value) || value.length !== 18 ||
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
    ]);
    return Object.freeze({expected: state(0), next: state(9)});
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
  const persistTransition = (prepared, evidenceJson) => {
    const {key, generation, states} = prepared;
    const found = selectDispatch.get(key[0], key[1], generation, key[3]);
    if (found === undefined) fail('CoordinatorJournalRecordMissing');
    const current = rowState(found);
    if (sameState(current, states.next)) {
      if (evidenceJson !== undefined &&
          found.accepted_evidence_json !== evidenceJson) {
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
    const result = updateDispatch.run(
      ...states.next, nextEvidenceJson,
      key[0], key[1], generation, key[3],
      ...states.expected, found.accepted_evidence_json,
    );
    if (result.changes !== 1) fail('CoordinatorDispatchStateCollision');
    return states;
  };
  const advanceTransition = (transition, evidence, record, control) => {
    ensureOpen();
    const prepared = prepareTransition(transition, record, control);
    let evidenceJson;
    if (evidence !== undefined) {
      if (typeof control.evidenceIdentity !== 'function' ||
          typeof control.evidenceJson !== 'function' ||
          control.evidenceIdentity(evidence) !== prepared.states.next[8]) {
        fail('RemoteExecutionEvidenceMismatch');
      }
      evidenceJson = control.evidenceJson(evidence);
    }
    transaction(database, () => persistTransition(prepared, evidenceJson));
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
        recovered.push(Object.freeze({
          request,
          record,
          evidence,
          evidenceWire: row.accepted_evidence_json || undefined,
        }));
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
    advance(transition, record, control) {
      return advanceTransition(transition, undefined, record, control);
    },
    advanceEvidence(transition, evidence, record, control) {
      return advanceTransition(transition, evidence, record, control);
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

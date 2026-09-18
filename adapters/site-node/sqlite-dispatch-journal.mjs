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
import {admitRemoteDispatchJson} from
  '../host-common/remote-dispatch-wire.mjs';

const fail = (code, cause) => {
  const error = Object.assign(new Error(code, {cause}), {code});
  throw error;
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
    catch (rollback) { fail('RemoteJournalRollbackFailed', rollback); }
    throw error;
  }
}

export function openSqliteDispatchJournal(root, {
  siteKey,
  siteGeneration,
  runtimeRevision,
  maxDispatches = 100_000,
  maxRequestBytes = 65_536,
} = {}) {
  if (!text(root) || !text(siteKey) || !count(siteGeneration) ||
      !text(runtimeRevision) ||
      !count(maxDispatches) || maxDispatches === 0 ||
      !count(maxRequestBytes) || maxRequestBytes === 0) {
    fail('InvalidRemoteJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'dispatch-journal.sqlite3');
  let currentGeneration = siteGeneration;
  let currentRuntimeRevision = runtimeRevision;
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
    database.exec('PRAGMA wal_autocheckpoint = 1000');
    database.exec(`
      CREATE TABLE IF NOT EXISTS journal_metadata (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      ) STRICT;
      CREATE TABLE IF NOT EXISTS dispatches (
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
        execution_state INTEGER NOT NULL DEFAULT 0,
        evidence_state INTEGER NOT NULL DEFAULT 0,
        cleanup_state INTEGER NOT NULL DEFAULT 0,
        material_available INTEGER NOT NULL DEFAULT 0,
        quarantined_capacity INTEGER NOT NULL DEFAULT 0,
        material_generation TEXT NOT NULL DEFAULT '',
        holding_evidence_cid TEXT NOT NULL DEFAULT '',
        execution_evidence_cid TEXT NOT NULL DEFAULT '',
        execution_evidence_json TEXT NOT NULL DEFAULT '',
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
        insert.run('schema_version', 'actql-remote-site-journal/0.4');
        insert.run('site_key', siteKey);
        insert.run('site_generation', String(siteGeneration));
        insert.run('runtime_revision', runtimeRevision);
      } else if (version.value === 'actql-remote-site-journal/0.1') {
        database.exec(`
          ALTER TABLE dispatches ADD COLUMN revision INTEGER NOT NULL
            DEFAULT 0 CHECK (revision >= 0);
          ALTER TABLE dispatches ADD COLUMN execution_state INTEGER NOT NULL
            DEFAULT 0;
          ALTER TABLE dispatches ADD COLUMN evidence_state INTEGER NOT NULL
            DEFAULT 0;
          ALTER TABLE dispatches ADD COLUMN cleanup_state INTEGER NOT NULL
            DEFAULT 0;
          ALTER TABLE dispatches ADD COLUMN material_available INTEGER NOT NULL
            DEFAULT 0;
          ALTER TABLE dispatches ADD COLUMN quarantined_capacity INTEGER
            NOT NULL DEFAULT 0;
          ALTER TABLE dispatches ADD COLUMN material_generation TEXT NOT NULL
            DEFAULT '';
          ALTER TABLE dispatches ADD COLUMN holding_evidence_cid TEXT NOT NULL
            DEFAULT '';
          ALTER TABLE dispatches ADD COLUMN execution_evidence_cid TEXT
            NOT NULL DEFAULT '';
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-site-journal/0.2', 'schema_version');
      } else if (version.value !== 'actql-remote-site-journal/0.2' &&
          version.value !== 'actql-remote-site-journal/0.3' &&
          version.value !== 'actql-remote-site-journal/0.4') {
        fail('UnsupportedRemoteJournalVersion');
      }
    });
    transaction(database, () => {
      const version = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (version?.value === 'actql-remote-site-journal/0.2') {
        const foreign = database.prepare(`
          SELECT COUNT(*) AS count FROM dispatches WHERE site_key != ?
        `).get(siteKey);
        const newest = database.prepare(`
          SELECT MAX(site_generation) AS generation FROM dispatches
        `).get();
        if (Number(foreign.count) !== 0 ||
            (newest.generation !== null &&
            Number(newest.generation) > siteGeneration)) {
          fail('ForeignRemoteJournalSite');
        }
        const insert = database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        );
        insert.run('site_key', siteKey);
        insert.run('site_generation', String(siteGeneration));
        insert.run('runtime_revision', runtimeRevision);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-site-journal/0.3', 'schema_version');
      } else if (version?.value !== 'actql-remote-site-journal/0.3' &&
          version?.value !== 'actql-remote-site-journal/0.4') {
        fail('UnsupportedRemoteJournalVersion');
      }
      const current = database.prepare(
        'SELECT value FROM journal_metadata WHERE key = ?',
      ).get('schema_version');
      if (current?.value === 'actql-remote-site-journal/0.3') {
        const unverifiable = database.prepare(`
          SELECT COUNT(*) AS count FROM dispatches WHERE evidence_state = 2
        `).get();
        if (Number(unverifiable.count) !== 0) {
          fail('RemoteJournalEvidenceMigrationRequired');
        }
        database.exec(`
          ALTER TABLE dispatches ADD COLUMN execution_evidence_json TEXT
            NOT NULL DEFAULT ''
        `);
        database.prepare(
          'UPDATE journal_metadata SET value = ? WHERE key = ?',
        ).run('actql-remote-site-journal/0.4', 'schema_version');
      }
      const metadata = Object.fromEntries(database.prepare(`
        SELECT key, value FROM journal_metadata
        WHERE key IN ('site_key', 'site_generation', 'runtime_revision')
      `).all().map(row => [row.key, row.value]));
      if (metadata.site_key !== siteKey ||
          metadata.site_generation !== String(siteGeneration) ||
          metadata.runtime_revision !== runtimeRevision) {
        fail('RemoteJournalGenerationMismatch');
      }
    });
    if (!existed) syncDirectory(directory);
  } catch (error) {
    database.close();
    throw error;
  }

  const selectDispatch = database.prepare(`
    SELECT dispatch_request_cid, request_json, revision, execution_state,
      evidence_state, cleanup_state, material_available,
      quarantined_capacity, material_generation, holding_evidence_cid,
      execution_evidence_cid, execution_evidence_json
    FROM dispatches
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
  `);
  const selectAllDispatches = database.prepare(`
    SELECT dispatch_request_cid, request_json, revision, execution_state,
      evidence_state, cleanup_state, material_available,
      quarantined_capacity, material_generation, holding_evidence_cid,
      execution_evidence_cid, execution_evidence_json
    FROM dispatches
    ORDER BY coordinator_authority, site_generation, dispatch_id
  `);
  const selectAttempt = database.prepare(`
    SELECT dispatch_id, dispatch_request_cid
    FROM dispatches
    WHERE coordinator_authority = ? AND run_definition_cid = ?
      AND task_key = ? AND task_attempt = ?
  `);
  const countDispatches = database.prepare(
    'SELECT COUNT(*) AS count FROM dispatches',
  );
  const insertDispatch = database.prepare(`
    INSERT INTO dispatches (
      coordinator_authority, site_key, site_generation, dispatch_id,
      dispatch_request_cid, run_definition_cid, task_key, task_attempt,
      request_json, revision, execution_state, evidence_state, cleanup_state,
      material_available, quarantined_capacity, material_generation,
      holding_evidence_cid, execution_evidence_cid,
      execution_evidence_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0, 0, 0, '', '', '', '')
  `);
  const updateDispatch = database.prepare(`
    UPDATE dispatches SET
      revision = ?, execution_state = ?, evidence_state = ?,
      cleanup_state = ?, material_available = ?, quarantined_capacity = ?,
      material_generation = ?, holding_evidence_cid = ?,
      execution_evidence_cid = ?, execution_evidence_json = ?
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
      AND revision = ? AND execution_state = ? AND evidence_state = ?
      AND cleanup_state = ? AND material_available = ?
      AND quarantined_capacity = ? AND material_generation = ?
      AND holding_evidence_cid = ? AND execution_evidence_cid = ?
      AND execution_evidence_json = ?
  `);

  const ensureOpen = () => {
    if (closed) fail('RemoteJournalClosed');
  };
  const integer = value => Number.isSafeInteger(value) && value >= 0;
  const bit = value => value === 0 || value === 1;
  const stateFromRow = row => {
    const values = [
      row.revision,
      row.execution_state,
      row.evidence_state,
      row.cleanup_state,
    ];
    if (values.some(value => !integer(value)) ||
        !bit(row.material_available) || !bit(row.quarantined_capacity) ||
        typeof row.material_generation !== 'string' ||
        typeof row.holding_evidence_cid !== 'string' ||
        typeof row.execution_evidence_cid !== 'string') {
      fail('InvalidRemoteJournalState');
    }
    return Object.freeze([
      ...values,
      row.material_available === 1,
      row.quarantined_capacity === 1,
      row.material_generation,
      row.holding_evidence_cid,
      row.execution_evidence_cid,
    ]);
  };
  const requestFromRow = (row, control) => {
    try {
      return admitRemoteDispatchJson(
        control,
        row.request_json,
        row.dispatch_request_cid,
        maxRequestBytes,
      );
    } catch (error) {
      fail('InvalidRemoteJournalRequest', error);
    }
  };
  const parseProjection = value => {
    if (!Array.isArray(value) || value.length !== 18 ||
        value.some(item => typeof item !== 'string')) {
      fail('InvalidRemoteJournalTransition');
    }
    const parseInteger = item => {
      if (!/^(0|[1-9][0-9]*)$/.test(item)) {
        fail('InvalidRemoteJournalTransition');
      }
      const parsed = Number(item);
      if (!integer(parsed)) fail('InvalidRemoteJournalTransition');
      return parsed;
    };
    const parseBit = item => {
      if (item !== '0' && item !== '1') {
        fail('InvalidRemoteJournalTransition');
      }
      return Number(item);
    };
    const state = offset => Object.freeze([
      parseInteger(value[offset]),
      parseInteger(value[offset + 1]),
      parseInteger(value[offset + 2]),
      parseInteger(value[offset + 3]),
      parseBit(value[offset + 4]),
      parseBit(value[offset + 5]),
      value[offset + 6],
      value[offset + 7],
      value[offset + 8],
    ]);
    return Object.freeze({expected: state(0), next: state(9)});
  };
  const rowState = row => Object.freeze([
    row.revision,
    row.execution_state,
    row.evidence_state,
    row.cleanup_state,
    row.material_available,
    row.quarantined_capacity,
    row.material_generation,
    row.holding_evidence_cid,
    row.execution_evidence_cid,
  ]);
  const equalState = (left, right) =>
    left.length === right.length &&
    left.every((value, index) => value === right[index]);
  const preparePhysicalTransition = (key, projection, revision) => {
    const generation = Number(key?.[2]);
    if (!Array.isArray(key) || key.length !== 7 ||
        key.some(value => !text(value)) || key[1] !== siteKey ||
        !count(generation) || generation > currentGeneration) {
      fail('ForeignRemoteJournalSite');
    }
    const states = parseProjection(projection);
    if (revision !== undefined && revision !== states.expected[0]) {
      fail('RemoteDispatchStateCollision');
    }
    return Object.freeze({key, generation, states});
  };
  const persistPhysicalTransition = (prepared, executionEvidenceJson) => {
    const {key, generation, states} = prepared;
    const found = selectDispatch.get(key[0], key[1], generation, key[3]);
    if (found === undefined) fail('RemoteJournalRecordMissing');
    const current = rowState(found);
    if (equalState(current, states.next)) {
      if (executionEvidenceJson !== undefined &&
          found.execution_evidence_json !== executionEvidenceJson) {
        fail('RemoteDispatchStateCollision');
      }
      return states;
    }
    if (!equalState(current, states.expected)) {
      fail('RemoteDispatchStateCollision');
    }
    let nextEvidenceJson = found.execution_evidence_json;
    if (executionEvidenceJson !== undefined) {
      if (!text(executionEvidenceJson) || states.next[2] !== 2 ||
          !text(states.next[8])) {
        fail('InvalidRemoteExecutionEvidence');
      }
      nextEvidenceJson = executionEvidenceJson;
    } else if (states.next[2] === 2 && states.expected[2] !== 2) {
      fail('RemoteExecutionEvidenceMissing');
    } else if (states.next[2] === 3) {
      nextEvidenceJson = '';
    }
    const result = updateDispatch.run(
      ...states.next, nextEvidenceJson,
      key[0], key[1], generation, key[3],
      ...states.expected, found.execution_evidence_json,
    );
    if (result.changes !== 1) fail('RemoteDispatchStateCollision');
    return states;
  };
  const persistTransition = (key, projection, revision) => {
    const prepared = preparePhysicalTransition(key, projection, revision);
    transaction(database, () => persistPhysicalTransition(prepared));
    return prepared.states;
  };
  const install = (request, requestJson, control) => {
    ensureOpen();
    if (!text(requestJson) || Buffer.byteLength(requestJson, 'utf8') >
        maxRequestBytes || control === null || typeof control !== 'object' ||
        typeof control.identity !== 'function' ||
        typeof control.journalKey !== 'function') {
      fail('InvalidRemoteJournalRequest');
    }
    const identity = control.identity(request);
    const key = control.journalKey(request);
    if (!text(identity) || !Array.isArray(key) || key.length !== 7 ||
        key.some(value => !text(value))) {
      fail('InvalidRemoteJournalRequest');
    }
    const generation = Number(key[2]);
    const attempt = Number(key[6]);
    if (key[1] !== siteKey || generation !== currentGeneration ||
        !count(generation) || !count(attempt) || attempt === 0) {
      fail('ForeignRemoteJournalSite');
    }
    return transaction(database, () => {
      const existing = selectDispatch.get(key[0], key[1], generation, key[3]);
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
        fail('RemoteJournalCapacityExceeded');
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
    configuration() {
      ensureOpen();
      return Object.freeze({
        siteKey,
        siteGeneration: currentGeneration,
        runtimeRevision: currentRuntimeRevision,
      });
    },
    recoverJournal(journal, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.admit !== 'function' ||
          typeof control.restoreHistorical !== 'function' ||
          typeof control.restore !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const recovered = [];
      for (const row of selectAllDispatches.all()) {
        const request = requestFromRow(row, control);
        const record = control.restoreHistorical(journal, request);
        control.restore(record, stateFromRow(row));
        recovered.push(Object.freeze({request, record}));
      }
      return Object.freeze(recovered);
    },
    accept(admission, request, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.admissionJson !== 'function' ||
          typeof control.commitAdmission !== 'function' ||
          typeof control.admissionIsNew !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const requestJson = control.admissionJson(admission);
      if (requestJson !== control.requestJson(request)) {
        fail('RemoteAdmissionRequestMismatch');
      }
      install(request, requestJson, control);
      const record = control.commitAdmission(admission, true);
      const key = control.journalKey(request);
      const found = selectDispatch.get(
        key[0], key[1], Number(key[2]), key[3],
      );
      if (found === undefined) fail('RemoteJournalRecordMissing');
      if (control.admissionIsNew(admission)) {
        control.restore(record, stateFromRow(found));
      }
      return record;
    },
    advance(transition, record, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.transitionKey !== 'function' ||
          typeof control.transitionProjection !== 'function' ||
          typeof control.commitTransition !== 'function' ||
          typeof control.revision !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const states = persistTransition(
        control.transitionKey(transition),
        control.transitionProjection(transition),
        control.revision(record),
      );
      control.commitTransition(transition, true);
      if (control.revision(record) !== states.next[0]) {
        fail('RemoteJournalControlDiverged');
      }
      return record;
    },
    advanceEvidence(transition, evidence, record, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.transitionKey !== 'function' ||
          typeof control.transitionProjection !== 'function' ||
          typeof control.commitTransition !== 'function' ||
          typeof control.revision !== 'function' ||
          typeof control.evidenceIdentity !== 'function' ||
          typeof control.evidenceJson !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const evidenceJson = control.evidenceJson(evidence);
      const evidenceCid = control.evidenceIdentity(evidence);
      const projection = control.transitionProjection(transition);
      if (!Array.isArray(projection) || projection[17] !== evidenceCid) {
        fail('RemoteExecutionEvidenceMismatch');
      }
      const prepared = preparePhysicalTransition(
        control.transitionKey(transition),
        projection,
        control.revision(record),
      );
      transaction(database, () => {
        persistPhysicalTransition(prepared, evidenceJson);
      });
      control.commitTransition(transition, true);
      if (control.revision(record) !== prepared.states.next[0]) {
        fail('RemoteJournalControlDiverged');
      }
      return record;
    },
    forceLoss(transition, record, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.forceLossKey !== 'function' ||
          typeof control.forceLossProjection !== 'function' ||
          typeof control.commitForceLoss !== 'function' ||
          typeof control.revision !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const states = persistTransition(
        control.forceLossKey(transition),
        control.forceLossProjection(transition),
        control.revision(record),
      );
      control.commitForceLoss(transition, true);
      if (control.revision(record) !== states.next[0]) {
        fail('RemoteJournalControlDiverged');
      }
      return record;
    },
    restart(restart, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.restartMetadata !== 'function' ||
          typeof control.restartCount !== 'function' ||
          typeof control.restartAt !== 'function' ||
          typeof control.transitionKey !== 'function' ||
          typeof control.transitionProjection !== 'function' ||
          typeof control.commitRestart !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const metadata = control.restartMetadata(restart);
      if (!Array.isArray(metadata) || metadata.length !== 4 ||
          metadata.some(value => !text(value))) {
        fail('InvalidRemoteJournalRestart');
      }
      const oldGeneration = Number(metadata[1]);
      const newGeneration = Number(metadata[2]);
      if (metadata[0] !== siteKey || oldGeneration !== currentGeneration ||
          !count(newGeneration) || newGeneration <= oldGeneration) {
        fail('RemoteJournalGenerationMismatch');
      }
      const total = control.restartCount(restart);
      if (!count(total) || total > maxDispatches) {
        fail('InvalidRemoteJournalRestart');
      }
      const transitions = [];
      for (let index = 0; index < total; index++) {
        const transition = control.restartAt(restart, index);
        transitions.push(preparePhysicalTransition(
          control.transitionKey(transition),
          control.transitionProjection(transition),
          undefined,
        ));
      }
      transaction(database, () => {
        const storedGeneration = database.prepare(`
          SELECT value FROM journal_metadata WHERE key = 'site_generation'
        `).get()?.value;
        const storedRevision = database.prepare(`
          SELECT value FROM journal_metadata WHERE key = 'runtime_revision'
        `).get()?.value;
        const alreadyCommitted = storedGeneration === String(newGeneration) &&
          storedRevision === metadata[3];
        if (!alreadyCommitted &&
            (storedGeneration !== String(oldGeneration) ||
            storedRevision !== currentRuntimeRevision)) {
          fail('RemoteJournalGenerationMismatch');
        }
        for (const transition of transitions) {
          persistPhysicalTransition(transition);
        }
        if (!alreadyCommitted) {
          const generationUpdate = database.prepare(`
            UPDATE journal_metadata SET value = ?
            WHERE key = 'site_generation' AND value = ?
          `).run(String(newGeneration), String(oldGeneration));
          const revisionUpdate = database.prepare(`
            UPDATE journal_metadata SET value = ?
            WHERE key = 'runtime_revision' AND value = ?
          `).run(metadata[3], currentRuntimeRevision);
          if (generationUpdate.changes !== 1 || revisionUpdate.changes !== 1) {
            fail('RemoteJournalGenerationMismatch');
          }
        }
      });
      const affected = control.commitRestart(restart, true);
      if (affected !== total) fail('RemoteJournalControlDiverged');
      currentGeneration = newGeneration;
      currentRuntimeRevision = metadata[3];
      return affected;
    },
    inspect(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const found = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      return found === undefined ? undefined : Object.freeze({
        dispatch_request_cid: found.dispatch_request_cid,
        request_json: found.request_json,
      });
    },
    inspectState(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const found = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      return found === undefined ? undefined : stateFromRow(found);
    },
    inspectEvidence(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const found = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      if (found === undefined || found.evidence_state !== 2 ||
          !text(found.execution_evidence_cid) ||
          !text(found.execution_evidence_json)) {
        return undefined;
      }
      return Object.freeze({
        execution_evidence_cid: found.execution_evidence_cid,
        execution_evidence_json: found.execution_evidence_json,
      });
    },
    close() {
      if (closed) return false;
      database.close();
      closed = true;
      return true;
    },
  });
}

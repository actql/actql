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
} = {}) {
  if (!text(root) || !text(coordinatorAuthority) || !count(maxDispatches) ||
      maxDispatches === 0 || !count(maxRequestBytes) ||
      maxRequestBytes === 0) {
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
        insert.run('schema_version', 'actql-remote-coordinator-journal/0.1');
        insert.run('coordinator_authority', coordinatorAuthority);
      } else if (version.value !==
          'actql-remote-coordinator-journal/0.1') {
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
    SELECT dispatch_request_cid, request_json
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
    SELECT dispatch_request_cid, request_json
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
      request_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const ensureOpen = () => {
    if (closed) fail('CoordinatorJournalClosed');
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
          typeof control.restoreCoordinatorIntent !== 'function') {
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
        recovered.push(Object.freeze({request, record}));
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
    contains(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const row = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      return row !== undefined &&
        row.dispatch_request_cid === control.identity(request) &&
        row.request_json === control.requestJson(request);
    },
    close() {
      if (closed) return false;
      closed = true;
      database.close();
      return true;
    },
  });
}

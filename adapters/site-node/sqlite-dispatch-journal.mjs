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
  maxDispatches = 100_000,
  maxRequestBytes = 65_536,
} = {}) {
  if (!text(root) || !text(siteKey) || !count(siteGeneration) ||
      !count(maxDispatches) || maxDispatches === 0 ||
      !count(maxRequestBytes) || maxRequestBytes === 0) {
    fail('InvalidRemoteJournalConfiguration');
  }
  mkdirSync(root, {recursive: true, mode: 0o700});
  const directory = realpathSync(root);
  const path = join(directory, 'dispatch-journal.sqlite3');
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
        database.prepare(
          'INSERT INTO journal_metadata (key, value) VALUES (?, ?)',
        ).run('schema_version', 'actql-remote-site-journal/0.1');
      } else if (version.value !== 'actql-remote-site-journal/0.1') {
        fail('UnsupportedRemoteJournalVersion');
      }
    });
    if (!existed) syncDirectory(directory);
  } catch (error) {
    database.close();
    throw error;
  }

  const selectDispatch = database.prepare(`
    SELECT dispatch_request_cid, request_json
    FROM dispatches
    WHERE coordinator_authority = ? AND site_key = ?
      AND site_generation = ? AND dispatch_id = ?
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
      request_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);

  const ensureOpen = () => {
    if (closed) fail('RemoteJournalClosed');
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
    if (key[1] !== siteKey || generation !== siteGeneration ||
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
    accept(admission, request, control) {
      ensureOpen();
      if (control === null || typeof control !== 'object' ||
          typeof control.admissionJson !== 'function' ||
          typeof control.commitAdmission !== 'function') {
        fail('MissingRemoteSiteControl');
      }
      const requestJson = control.admissionJson(admission);
      if (requestJson !== control.requestJson(request)) {
        fail('RemoteAdmissionRequestMismatch');
      }
      install(request, requestJson, control);
      return control.commitAdmission(admission, true);
    },
    inspect(request, control) {
      ensureOpen();
      const key = control.journalKey(request);
      const found = selectDispatch.get(key[0], key[1], Number(key[2]), key[3]);
      return found === undefined ? undefined : Object.freeze({...found});
    },
    close() {
      if (closed) return false;
      database.close();
      closed = true;
      return true;
    },
  });
}

import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {mkdtempSync, rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createSqliteTransaction} from '../host-common/sqlite-transaction.mjs';
import {openClientObservationStorage} from './client-observation-journal.mjs';

const ref = {namespaceId: 'local', authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`};
const context = {traceId: '1'.repeat(32), spanId: '2'.repeat(16), traceFlags: 1};
const binding = {ref, scope: 'local', revision: 'metadata/0.1'};
const charge = {...binding, bytes: 10, maxRecords: 2, maxBytes: 20};
function setup(path) {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE IF NOT EXISTS client_requests (
    namespace_id TEXT, authority_scope_cid TEXT, run_definition_cid TEXT,
    caller_request_id TEXT) STRICT;`);
  return {db, storage: openClientObservationStorage(db, createSqliteTransaction(db, 'Fixture'))};
}
function admit(db) {
  db.prepare('INSERT INTO client_requests VALUES (?, ?, ?, ?)')
    .run(ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid, 'original');
}

test('budget survives real database reopen with exact request and context binding', () => {
  const directory = mkdtempSync(join(tmpdir(), 'actql-observation-'));
  let opened;
  try {
    const path = join(directory, 'journal.sqlite3');
    opened = setup(path);
    admit(opened.db);
    opened.storage.initialize({...binding, requestId: 'original',
      context: {...context, baggage: {secret: 'SECRET'}}});
    assert.deepEqual(opened.storage.consume(charge), {accepted: true, context});
    opened.db.close();
    opened = setup(path);
    assert.deepEqual(opened.storage.consume(charge), {accepted: true, context});
    assert.deepEqual(opened.storage.consume(charge), {accepted: false});
    assert.throws(() => opened.storage.initialize({...binding, requestId: 'original'}));
    assert.equal(opened.storage.consume({...charge, revision: 'other'}), undefined);
  } finally {
    opened?.db.close();
    rmSync(directory, {recursive: true, force: true});
  }
});

test('missing, tampered and foreign custody cannot mint a fresh budget', () => {
  const {db, storage} = setup(':memory:');
  try {
    admit(db);
    assert.equal(storage.consume(charge), undefined);
    assert.throws(() => storage.initialize({...binding, requestId: 'foreign'}));
    storage.initialize({...binding, requestId: 'original', context});
    db.prepare('UPDATE client_observation_runs SET context_json = ?')
      .run(JSON.stringify({...context, baggage: 'secret'}));
    assert.equal(storage.consume(charge), undefined);
    db.exec("UPDATE client_observation_runs SET context_json = NULL, caller_request_id = 'foreign'");
    assert.equal(storage.consume(charge), undefined);
    assert.equal(db.prepare('SELECT records FROM client_observation_runs').get().records, 0);
    assert.equal(db.prepare('SELECT count(*) AS n FROM client_requests').get().n, 1);
  } finally { db.close(); }
});

test('Host custody capacity refuses only extra observations, never original requests', () => {
  const {db, storage} = setup(':memory:');
  try {
    admit(db);
    storage.initialize({...binding, requestId: 'original', context, maxRuns: 1});
    const next = {...ref, runDefinitionCid: `sha256:${'c'.repeat(64)}`};
    db.prepare('INSERT INTO client_requests VALUES (?, ?, ?, ?)')
      .run(next.namespaceId, next.authorityScopeCid, next.runDefinitionCid, 'next');
    assert.throws(() => storage.initialize({...binding, ref: next,
      requestId: 'next', maxRuns: 1}), {message: 'ObservationBudgetUnavailable'});
    assert.equal(db.prepare('SELECT count(*) AS n FROM client_observation_runs').get().n, 1);
    assert.equal(db.prepare('SELECT count(*) AS n FROM client_requests').get().n, 2);
    db.prepare('UPDATE client_observation_runs SET context_json = ?').run('x'.repeat(1024));
    assert.equal(storage.consume(charge), undefined, 'oversized custody is not parsed as context');
  } finally { db.close(); }
});

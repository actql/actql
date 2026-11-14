// Tests the test oracle against independent SQLite facts, not a product Run.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {observeProjectFileStoreLedger, observeProjectFileStoreAttempts}
  from './fixtures/project-file-store-ledger-observation.mjs';

const files = [{path: 'one.jsonl', body: '{"id":1}\n'}];
const ref = {namespaceId: 'namespace', authorityScopeCid: 'authority', runDefinitionCid: 'definition'};
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'file-store-oracle-'));
  t.after(() => rm(root, {recursive: true}));
  const ledgerRoot = join(root, 'state/effects/ledger'); await mkdir(ledgerRoot, {recursive: true});
  const path = join(ledgerRoot, 'effect-ledger.sqlite3');
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE effect_ledger_entries (logical_item_locator_cid TEXT, revision INTEGER, entry_cid TEXT, entry_json TEXT);
    CREATE TABLE effect_ledger_heads (logical_item_locator_cid TEXT, logical_request_scope_cid TEXT, revision INTEGER, entry_cid TEXT);
    CREATE TABLE effect_ledger_responses (logical_item_locator_cid TEXT, dispatch_entry_cid TEXT, logical_request_scope_cid TEXT, status_code INTEGER, response_bytes BLOB, physical_sha256 TEXT);
    CREATE TABLE effect_ledger_batch_responses (id TEXT);
    CREATE TABLE effect_ledger_batch_members (id TEXT);
    CREATE TABLE effect_ledger_outcomes (dispatch_entry_cid TEXT, logical_item_locator_cid TEXT, response_physical_sha256 TEXT, outcome_cid TEXT, outcome_json TEXT);`);
  const insert = db.prepare('INSERT INTO effect_ledger_entries VALUES (?, ?, ?, ?)');
  insert.run('locator', 1, 'prepared', JSON.stringify({state: 'prepared'}));
  insert.run('locator', 2, 'dispatch', JSON.stringify({state: 'dispatching'}));
  insert.run('locator', 3, 'terminal', JSON.stringify({state: 'applied', attempt_sequence: 1,
    canonical_request_cid: 'request', effect_preview_cid: 'preview', outcome_receipt_cid: 'receipt'}));
  db.prepare('INSERT INTO effect_ledger_heads VALUES (?, ?, ?, ?)').run('locator', 'scope', 3, 'terminal');
  db.prepare('INSERT INTO effect_ledger_responses VALUES (?, ?, ?, ?, ?, ?)').run('locator', 'dispatch', 'scope',
    200, Buffer.from('{"action":"stored","bytes":9,"path":"one.jsonl","request_cid":"request"}'), 'physical');
  db.prepare('INSERT INTO effect_ledger_outcomes VALUES (?, ?, ?, ?, ?)').run('dispatch', 'locator', 'physical',
    'receipt', JSON.stringify({version: 'actql-effect-row-outcome-receipt/0.1', typed_outcome: {state: 'applied'},
      dispatch_entry_cid: 'dispatch', effect_preview_cid: 'preview', effect_member_preview_cid: 'member'}));
  db.close();
  await mkdir(join(root, 'requests'));
  const requests = new DatabaseSync(join(root, 'requests/client-requests.sqlite3'));
  requests.exec(`CREATE TABLE client_requests (namespace_id TEXT, authority_scope_cid TEXT, run_definition_cid TEXT,
    caller_request_id TEXT, logical_request_scope_cid TEXT, intent_fingerprint_cid TEXT, program_definition_cid TEXT,
    parameter_values_cid TEXT, caller_input_intent_cid TEXT, dispatch_reserved INTEGER, physical_start_reserved INTEGER);
    INSERT INTO client_requests VALUES ('namespace','authority','definition','caller','scope','intent','program','params','input',1,1);
    CREATE TABLE client_source_operation_originals (namespace_id TEXT, authority_scope_cid TEXT, run_definition_cid TEXT,
      stage INTEGER, input_index INTEGER, task INTEGER, source_attempt_id TEXT, run_invocation_cid TEXT,
      dispatch_request_cid TEXT, original_wire TEXT);
    INSERT INTO client_source_operation_originals VALUES ('namespace','authority','definition',0,0,0,'attempt','invocation','dispatch','original');
    CREATE TABLE delivery_read_audit (value TEXT);`);
  requests.close();
  await mkdir(join(root, 'checkpoints/journal'), {recursive: true});
  const models = new DatabaseSync(join(root, 'checkpoints/journal/checkpoint-journal.sqlite3'));
  for (const table of ['resume_model_scopes', 'resume_model_slots', 'resume_model_attempts']) {
    models.exec(`CREATE TABLE ${table} (value TEXT)`);
  }
  models.close();
  return {root, path};
}

test('read-only oracle retains every receipt and excludes permitted Saved read audit', async t => {
  const {root, path} = await fixture(t), before = await readFile(path);
  const observed = await observeProjectFileStoreLedger(root, files);
  assert.equal(observed.successfulStores, 1); assert.equal(observed.receipts.length, 1);
  assert.equal(observed.memberPreviews, 1); assert.deepEqual(await readFile(path), before);
  const attempts = observeProjectFileStoreAttempts(root, ref);
  const db = new DatabaseSync(join(root, 'requests/client-requests.sqlite3'));
  db.exec("INSERT INTO delivery_read_audit VALUES ('saved read')"); db.close();
  assert.deepEqual(observeProjectFileStoreAttempts(root, ref), attempts);
  assert.deepEqual(await observeProjectFileStoreLedger(root, files), observed);
});

test('oracle rejects a duplicate dispatch even with an unchanged successful head', async t => {
  const {root, path} = await fixture(t), db = new DatabaseSync(path);
  db.prepare('INSERT INTO effect_ledger_entries VALUES (?, ?, ?, ?)')
    .run('locator', 4, 'extra-dispatch', '{"state":"dispatching"}'); db.close();
  await assert.rejects(observeProjectFileStoreLedger(root, files));
});

test('oracle rejects wrong destination receipt and pre-approval write', async t => {
  const {root, path} = await fixture(t);
  await assert.rejects(observeProjectFileStoreLedger(root, files, {beforeApproval: true}));
  const db = new DatabaseSync(path);
  db.prepare('UPDATE effect_ledger_responses SET response_bytes = ?').run(
    Buffer.from('{"action":"stored","bytes":9,"path":"foreign.jsonl","request_cid":"request"}')); db.close();
  await assert.rejects(observeProjectFileStoreLedger(root, files));
});

test('Saved original snapshot detects new Source and refuses any Model attempt', async t => {
  const {root} = await fixture(t), before = observeProjectFileStoreAttempts(root, ref);
  const requests = new DatabaseSync(join(root, 'requests/client-requests.sqlite3'));
  requests.exec("UPDATE client_source_operation_originals SET source_attempt_id='another-attempt'"); requests.close();
  assert.notDeepEqual(observeProjectFileStoreAttempts(root, ref), before);
  const models = new DatabaseSync(join(root, 'checkpoints/journal/checkpoint-journal.sqlite3'));
  models.exec("INSERT INTO resume_model_attempts VALUES ('unexpected')"); models.close();
  assert.throws(() => observeProjectFileStoreAttempts(root, ref));
});

// Tests the test oracle against independent SQLite facts, not a product Run.
import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {createCipheriv, createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {observeProjectFileStoreLedger, observeProjectFileStoreAttempts,
  observeProjectFileStoreSourceAcquisitions}
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


const canonical = value => value === null || typeof value !== 'object'
  ? JSON.stringify(value) : Array.isArray(value)
    ? '[' + value.map(canonical).join(',') + ']'
    : '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}';
const cid = text => 'sha256:' + createHash('sha256').update(text).digest('hex');
const originalCid = 'sha256:' + 'a'.repeat(64);
const attempt = () => ({call_slot_cid: originalCid, semantic_request_cid: originalCid,
  batch_index: 0, page_index: 0, network_attempt: 1, outcome: 'captured',
  raw_response_artifact_cid: originalCid});
const receipt = () => ({version: 'actql-lookup-attempt-receipt/0.1',
  state: 'succeeded', self_cid: originalCid, attempts: [attempt()]});

// Independently encrypted observation facts only. This never opens a product
// Host, issues a semantic receipt, grants authority or claims physical I/O.
async function capturedFixture(t, bodies = [receipt()], {badTag = false, other = 'original'} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'file-source-evidence-oracle-'));
  t.after(() => rm(root, {recursive: true}));
  const selected = {runDefinitionCid: 'sha256:' + '1'.repeat(64)};
  const storeAuthority = 'sha256:' + '2'.repeat(64), capturedRunCid = 'sha256:' + '3'.repeat(64);
  const recordCid = cid(canonical({run_definition_cid: selected.runDefinitionCid,
    store_authority_cid: storeAuthority, version: 'actql-effect-computation-record/0.1'}));
  const entries = bodies.map(body => ({kind: 'acquisition_attempt_receipt', cid: originalCid, body}));
  // Keep a nonreceipt dependency too: the observer must return the entire
  // authenticated inventory, even when receipt/attempt counts stay unchanged.
  entries.push({kind: 'request_values', cid: 'sha256:' + '4'.repeat(64), body: {other}});
  const record = {version: 'actql-completed-effectful-capture/0.1', store_authority_cid: storeAuthority,
    run_definition: JSON.stringify({run_definition_cid: selected.runDefinitionCid}),
    captured_run: JSON.stringify({captured_run_cid: capturedRunCid,
      effect_context: {effect_dependency_inventory: entries}})};
  const key = Buffer.alloc(32, 7), nonce = Buffer.alloc(12, 9);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from('actql-private-publication-evidence/0.1\0effect_capture\0' + capturedRunCid));
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(record)), cipher.final()]);
  const tag = cipher.getAuthTag(); if (badTag) tag[0] ^= 1;
  const envelope = Buffer.from(JSON.stringify({version: 'actql-private-publication-evidence/0.1',
    nonce: nonce.toString('base64'), tag: tag.toString('base64'), ciphertext: ciphertext.toString('base64')}));
  const objectCid = cid(envelope);
  for (const directory of ['publication/objects', 'publication/physical-holdings', 'checkpoints']) {
    await mkdir(join(root, directory), {recursive: true});
  }
  const files = [
    ['publication/store.json', JSON.stringify({store_authority_cid: storeAuthority})],
    ['checkpoints/private-evidence.key', key],
    ['publication/objects/' + objectCid.slice(7), envelope],
    ['publication/physical-holdings/' + recordCid.slice(7) + '.json', JSON.stringify({
      holding_cid: recordCid, namespace: 'publication-private', manifest_cid: capturedRunCid,
      objects: [{cid: objectCid, byte_count: envelope.length}]} )],
  ];
  for (const [path, bytes] of files) await writeFile(join(root, path), bytes);
  const snapshot = async () => Promise.all(files.map(async ([path]) => [path, cid(await readFile(join(root, path)))]));
  return {root, ref: selected, snapshot, capturedRunCid};
}

test('File Source oracle reads authenticated actual attempt records and freezes the complete snapshot', async t => {
  const f = await capturedFixture(t), before = await f.snapshot();
  const observed = await observeProjectFileStoreSourceAcquisitions(f.root, f.ref, 65536);
  assert.equal(observed.summary.receipts, 1); assert.equal(observed.summary.attempts, 1);
  assert.equal(observed.summary.capturedRunCid, f.capturedRunCid);
  assert.match(observed.summary.snapshotCid, /^sha256:[0-9a-f]{64}$/u);
  assert.equal(observed.snapshot.entries.length, 2);
  assert.equal(observed.snapshot.entries.find(entry => entry.kind === 'request_values').wire, '{"other":"original"}');
  assert.throws(() => { observed.snapshot.entries[0].wire = '{}'; }, TypeError);
  assert.deepEqual(await observeProjectFileStoreSourceAcquisitions(f.root, f.ref, 65536), observed);
  assert.deepEqual(await f.snapshot(), before);
  const changed = await capturedFixture(t, [receipt()], {other: 'changed'});
  const next = await observeProjectFileStoreSourceAcquisitions(changed.root, changed.ref, 65536);
  assert.equal(next.summary.attempts, observed.summary.attempts);
  assert.notEqual(next.summary.snapshotCid, observed.summary.snapshotCid);
  assert.notDeepEqual(next.snapshot, observed.snapshot);
});

test('File Source oracle allows a source-free capture without inventing an attempt', async t => {
  const f = await capturedFixture(t, []);
  const observed = await observeProjectFileStoreSourceAcquisitions(f.root, f.ref, 65536);
  assert.equal(observed.summary.receipts, 0); assert.equal(observed.summary.attempts, 0);
  assert.equal(observed.snapshot.entries.length, 1);
});

test('File Source oracle rejects malformed succeeded receipts and noncaptured attempts', async t => {
  const values = [
    {...receipt(), version: 'foreign'}, {...receipt(), state: 'unknown'},
    {...receipt(), self_cid: 'sha256:' + 'b'.repeat(64)}, {...receipt(), attempts: null},
    {...receipt(), attempts: [{...attempt(), outcome: 'dispatched'}]},
    {...receipt(), attempts: [{...attempt(), call_slot_cid: 'foreign'}]},
    {...receipt(), attempts: [{...attempt(), batch_index: -1}]},
    {...receipt(), attempts: [{...attempt(), page_index: 0.5}]},
    {...receipt(), attempts: [{...attempt(), network_attempt: 0}]},
    {...receipt(), attempts: [{...attempt(), runtime_error_cid: originalCid}]},
  ];
  for (const body of values) {
    const f = await capturedFixture(t, [body]), before = await f.snapshot();
    await assert.rejects(observeProjectFileStoreSourceAcquisitions(f.root, f.ref, 65536));
    assert.deepEqual(await f.snapshot(), before);
  }
});

test('File Source oracle refuses foreign, oversized and unauthenticated captures without mutation', async t => {
  const f = await capturedFixture(t), before = await f.snapshot();
  await assert.rejects(observeProjectFileStoreSourceAcquisitions(f.root,
    {runDefinitionCid: 'sha256:' + 'f'.repeat(64)}, 65536));
  await assert.rejects(observeProjectFileStoreSourceAcquisitions(f.root, f.ref, 8));
  assert.deepEqual(await f.snapshot(), before);
  const tampered = await capturedFixture(t, [receipt()], {badTag: true}), original = await tampered.snapshot();
  await assert.rejects(observeProjectFileStoreSourceAcquisitions(tampered.root, tampered.ref, 65536));
  assert.deepEqual(await tampered.snapshot(), original);
});

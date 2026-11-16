// Test-only, read-only observation of this fixture's fresh physical Ledger.
// No adapter import, receipt issuer, execution authority or database mutation.
import assert from 'node:assert/strict';
import {access} from 'node:fs/promises';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {observeProjectEffectDependencies} from './project-effect-dependency-observation.mjs';

const tables = ['effect_ledger_entries', 'effect_ledger_heads',
  'effect_ledger_responses', 'effect_ledger_batch_responses',
  'effect_ledger_batch_members', 'effect_ledger_outcomes'];

// File reads use the captured lookup attempt chain, not the optional BigQuery
// Job-original table below. Inspect the SAME authenticated completed capture;
// the complete immutable snapshot also detects any cold-phase evidence change.
export async function observeProjectFileStoreSourceAcquisitions(stateDir, ref, maximumBytes) {
  const {summary, snapshot} = await observeProjectEffectDependencies(stateDir, ref, maximumBytes);
  const cid = /^sha256:[0-9a-f]{64}$/u;
  let receipts = 0, attempts = 0;
  for (const entry of snapshot.entries) {
    if (entry.kind !== 'acquisition_attempt_receipt') continue;
    const receipt = JSON.parse(entry.wire);
    assert.equal(receipt.version, 'actql-lookup-attempt-receipt/0.1');
    assert.equal(receipt.state, 'succeeded');
    assert.equal(receipt.self_cid, entry.cid);
    assert(Array.isArray(receipt.attempts));
    for (const attempt of receipt.attempts) {
      assert(attempt !== null && typeof attempt === 'object' && !Array.isArray(attempt));
      assert.equal(attempt.outcome, 'captured');
      for (const field of ['call_slot_cid', 'semantic_request_cid', 'raw_response_artifact_cid']) {
        assert.equal(typeof attempt[field], 'string');
        assert(cid.test(attempt[field]));
      }
      for (const field of ['batch_index', 'page_index']) {
        assert(Number.isSafeInteger(attempt[field]) && attempt[field] >= 0);
      }
      assert(Number.isSafeInteger(attempt.network_attempt) && attempt.network_attempt >= 1);
      assert(!Object.hasOwn(attempt, 'runtime_error_cid'));
    }
    receipts++;
    attempts += receipt.attempts.length;
    assert(Number.isSafeInteger(attempts));
  }
  for (const entry of snapshot.entries) Object.freeze(entry);
  for (const reference of snapshot.references) Object.freeze(reference);
  Object.freeze(snapshot.entries); Object.freeze(snapshot.references); Object.freeze(snapshot);
  return Object.freeze({summary: Object.freeze({receipts, attempts,
    capturedRunCid: snapshot.capturedRunCid, snapshotCid: summary.snapshotCid}), snapshot});
}

export function observeProjectFileStoreAttempts(stateDir, ref) {
  const requests = new DatabaseSync(join(stateDir, 'requests', 'client-requests.sqlite3'), {readOnly: true});
  let request, sources;
  try {
    const key = [ref.namespaceId, ref.authorityScopeCid, ref.runDefinitionCid];
    request = requests.prepare(`SELECT namespace_id, authority_scope_cid, run_definition_cid,
      caller_request_id, logical_request_scope_cid, intent_fingerprint_cid, program_definition_cid,
      parameter_values_cid, caller_input_intent_cid, dispatch_reserved, physical_start_reserved
      FROM client_requests WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?`).get(...key);
    assert(request, 'The SAME admitted original request must remain present');
    sources = requests.prepare(`SELECT stage, input_index, task, source_attempt_id,
      run_invocation_cid, dispatch_request_cid, original_wire FROM client_source_operation_originals
      WHERE namespace_id = ? AND authority_scope_cid = ? AND run_definition_cid = ?
      ORDER BY stage, input_index, task`).all(...key);
  } finally {requests.close();}
  const checkpoints = new DatabaseSync(join(stateDir, 'checkpoints', 'journal', 'checkpoint-journal.sqlite3'),
    {readOnly: true});
  let model;
  try {
    // Neither authored File case contains INFER. This fresh one-Run app must
    // have no Model scope, slot or attempt; read/delivery audit rows may grow.
    model = Object.fromEntries(['resume_model_scopes', 'resume_model_slots', 'resume_model_attempts']
      .map(table => [table, checkpoints.prepare(`SELECT COUNT(*) AS count FROM ${table}`).get().count]));
    assert.deepEqual(model, {resume_model_scopes: 0, resume_model_slots: 0, resume_model_attempts: 0});
  } finally {checkpoints.close();}
  return {request: {...request}, sources: sources.map(row => ({...row})), model};
}

export async function observeProjectFileStoreLedger(stateDir, expectedFiles, {beforeApproval = false} = {}) {
  const path = join(stateDir, 'state', 'effects', 'ledger', 'effect-ledger.sqlite3');
  try {await access(path);} catch (error) {
    if (beforeApproval && error.code === 'ENOENT') return {successfulStores: 0};
    throw error;
  }
  const database = new DatabaseSync(path, {readOnly: true});
  let snapshot;
  try {
    snapshot = Object.fromEntries(tables.map(table => [table,
      database.prepare(`SELECT * FROM ${table}`).all().map(row =>
        Object.fromEntries(Object.entries(row).map(([key, value]) =>
          [key, value instanceof Uint8Array ? {hex: Buffer.from(value).toString('hex')} : value])))
        .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)))]));
  } finally {database.close();}
  const responses = snapshot.effect_ledger_responses;
  assert.equal(snapshot.effect_ledger_batch_responses.length, 0);
  assert.equal(snapshot.effect_ledger_batch_members.length, 0);
  if (beforeApproval) {
    assert.equal(responses.length, 0);
    assert.equal(snapshot.effect_ledger_outcomes.length, 0);
    return {successfulStores: 0};
  }
  assert.equal(responses.length, expectedFiles.length);
  assert.equal(snapshot.effect_ledger_heads.length, expectedFiles.length);
  assert.equal(snapshot.effect_ledger_outcomes.length, expectedFiles.length);
  assert.equal(new Set(snapshot.effect_ledger_entries.map(row => row.logical_item_locator_cid)).size,
    expectedFiles.length);
  const expected = new Map(expectedFiles.map(file => [file.path, Buffer.byteLength(file.body)]));
  const paths = [], members = new Set(), receipts = [];
  for (const response of responses) {
    assert.equal(response.status_code, 200);
    const value = JSON.parse(Buffer.from(response.response_bytes.hex, 'hex').toString('utf8'));
    assert.deepEqual(Object.keys(value).sort(), ['action', 'bytes', 'path', 'request_cid']);
    assert.equal(value.action, 'stored'); assert(expected.has(value.path));
    assert.equal(value.bytes, expected.get(value.path)); paths.push(value.path);
    const history = snapshot.effect_ledger_entries.filter(row =>
      row.logical_item_locator_cid === response.logical_item_locator_cid);
    const dispatch = history.filter(row => JSON.parse(row.entry_json).state === 'dispatching');
    assert.equal(dispatch.length, 1, 'Exactly one durable dispatch per original file');
    assert.equal(dispatch[0].entry_cid, response.dispatch_entry_cid);
    const head = snapshot.effect_ledger_heads.find(row =>
      row.logical_item_locator_cid === response.logical_item_locator_cid);
    const terminal = history.find(row => row.entry_cid === head.entry_cid);
    assert.equal(terminal.revision, Math.max(...history.map(row => row.revision)));
    assert.equal(head.revision, terminal.revision);
    const entry = JSON.parse(terminal.entry_json);
    assert.equal(entry.state, 'applied'); assert.equal(entry.attempt_sequence, 1);
    assert.equal(entry.canonical_request_cid, value.request_cid);
    assert.equal(head.logical_request_scope_cid, response.logical_request_scope_cid);
    const outcome = snapshot.effect_ledger_outcomes.find(row =>
      row.dispatch_entry_cid === response.dispatch_entry_cid);
    assert.equal(outcome.logical_item_locator_cid, response.logical_item_locator_cid);
    assert.equal(outcome.response_physical_sha256, response.physical_sha256);
    assert.equal(outcome.outcome_cid, entry.outcome_receipt_cid);
    const receipt = JSON.parse(outcome.outcome_json);
    assert.equal(receipt.version, 'actql-effect-row-outcome-receipt/0.1');
    assert.equal(receipt.typed_outcome.state, 'applied');
    assert.equal(receipt.dispatch_entry_cid, response.dispatch_entry_cid);
    assert.equal(receipt.effect_preview_cid, entry.effect_preview_cid);
    members.add(receipt.effect_member_preview_cid);
    receipts.push({path: value.path, receipt});
  }
  assert.deepEqual(paths.sort(), [...expected.keys()].sort());
  return {successfulStores: paths.length, memberPreviews: members.size,
    receipts: receipts.sort((a, b) => a.path.localeCompare(b.path)), snapshot};
}

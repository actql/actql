// Real SQLite, explicit Resource/Store/Common doubles. No cold admission,
// physical Store ACK, Resource consume, numerical allowance or Provider send.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {C, input, open, immediateIdentity} from './model-resume-state.fixture.mjs';

const freeze = value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'model-durable-invalidation-'));
  const parks = new WeakMap(), saves = new WeakMap(), requests = new WeakMap();
  const resource = {inspect: value => parks.get(value), current: value => parks.has(value) ? value : undefined,
    invalidationCurrent: (request, park) => requests.get(request) === park ? request : undefined};
  const storage = {inspect: value => saves.get(value), current: value => saves.has(value) ? value : undefined};
  const cut = freeze({scope_cid: immediateIdentity.scopeCid,
    input_artifact_cid: immediateIdentity.inputArtifactCid,
    fixed_input_receipt_cid: immediateIdentity.inputArtifactCid, run_version: 1,
    continuation: null, slots: [{ordinal: 0, slot_cid: C('slot-0'), attempt_index: 0,
      state: 'Unsent', entry_identity_cid: null, settlement_identity_cid: null}]});
  const verifierOverrides = {originalResourceCut: resource, originalStateSaved: storage,
    projectOriginalCurrentCut: () => cut};
  const opened = [];
  const reopen = () => {const result = open(root, {verifierOverrides}); opened.push(result.journal); return result.journal;};
  const journal = reopen();
  t.after(() => {for (const owner of opened) owner.close(); rmSync(root, {recursive: true, force: true});});
  journal.registerImmediateModelCallSet({modelCallSet: input(1).modelCallSet, declaredResults: ['result']});
  const park = Object.freeze({}), save = Object.freeze({}), request = Object.freeze({});
  parks.set(park, freeze({identity: {...immediateIdentity}, phase: 'parked', cut}));
  saves.set(save, freeze({identity: {...immediateIdentity}, phase: 'parked', cut,
    documentCid: C('document'), holdingCid: C('holding'), storageBindingCid: C('storage'),
    resourceStateCid: C('resource'), documentWire: 'explicit saved original fixture'}));
  requests.set(request, park);
  const operation = journal.prepareOriginalModelCurrentCut(journal.observeOriginalModelJournal(immediateIdentity),
    {parkReceipt: park, savedReceipt: save});
  journal.commitOriginalModelCurrentCut(operation);
  return {root, journal, operation, park, save, request, parks, saves, resource, storage, reopen};
}
function row(f) {
  const db = new DatabaseSync(f.journal.path, {readOnly: true});
  try {return db.prepare('SELECT * FROM resume_model_scopes').get();} finally {db.close();}
}

test('fresh linked cut persists one original ready identity before any invalidation', t => {
  const f = fixture(t), stored = row(f);
  const record = JSON.parse(stored.current_cut_invalidation_json);
  assert.deepEqual(Object.keys(record).sort(), ['identity', 'linked_cut_wire', 'operation_id', 'phase', 'request_binding']);
  assert.match(record.operation_id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u);
  assert.equal(record.phase, 'ready'); assert.equal(record.request_binding, null);
  assert.equal(record.linked_cut_wire, stored.current_cut_link_json);
  assert.deepEqual(record.identity, immediateIdentity);
});

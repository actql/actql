// Actual SQLite observations with explicit Resource/Store/Common fixture ports.
// No authenticated restoration, physical Store ACK, unpark or send is tested.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {C, input, open, immediateIdentity} from './model-resume-state.fixture.mjs';

const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};
// Independently selected fixture cut, not an expectation computed by the issuer.
const cut = freeze({scope_cid: immediateIdentity.scopeCid,
  input_artifact_cid: immediateIdentity.inputArtifactCid,
  fixed_input_receipt_cid: immediateIdentity.inputArtifactCid, run_version: 1,
  continuation: null, slots: [{ordinal: 0, slot_cid: C('slot-0'), attempt_index: 0,
    state: 'Unsent', entry_identity_cid: null, settlement_identity_cid: null}]});
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'model-cut-reconciliation-'));
  const parks = new WeakMap(), saves = new WeakMap(), requests = new WeakMap();
  const resource = {inspect: token => parks.get(token), current: token => parks.has(token) ? token : undefined,
    invalidationCurrent: (request, park) => requests.get(request) === park ? request : undefined};
  const storage = {inspect: token => saves.get(token), current: token => saves.has(token) ? token : undefined};
  const verifierOverrides = {originalResourceCut: resource, originalStateSaved: storage,
    projectOriginalCurrentCut: () => cut};
  const opened = [];
  const reopen = () => {const value = open(root, {verifierOverrides}); opened.push(value); return value.journal;};
  const journal = reopen();
  t.after(() => {for (const value of opened) value.journal.close(); rmSync(root, {recursive: true, force: true});});
  journal.registerImmediateModelCallSet({modelCallSet: input(1).modelCallSet, declaredResults: ['result']});
  function receipts() {
    const park = Object.freeze({}), save = Object.freeze({}), request = Object.freeze({});
    parks.set(park, freeze({identity: {...immediateIdentity}, phase: 'parked', cut}));
    saves.set(save, freeze({identity: {...immediateIdentity}, phase: 'parked', cut,
      documentCid: C('document'), holdingCid: C('holding'), storageBindingCid: C('storage'),
      resourceStateCid: C('resource'), documentWire: 'explicit Store fixture observation'}));
    requests.set(request, park);
    return {parkReceipt: park, savedReceipt: save, request};
  }
  const original = receipts();
  const before = journal.observeOriginalModelJournal(immediateIdentity);
  const operation = journal.prepareOriginalModelCurrentCut(before, original);
  journal.commitOriginalModelCurrentCut(operation);
  return {journal, operation, original, reopen, receipts, parks, saves, resource, storage, verifierOverrides};
}

test('reopened journal issues only a read-only reconciled reference of the exact link', t => {
  const f = fixture(t), bytes = readFileSync(f.journal.path);
  f.journal.close();
  const journal = f.reopen(), receipts = f.receipts();
  const observation = journal.observeOriginalModelJournal(immediateIdentity);
  const recovered = journal.recoverOriginalModelCurrentCut(observation, receipts);
  assert.deepEqual(journal.originalModelCurrentCutOperationStatus(recovered), {state: 'reconciled'});
  const fresh = journal.originalModelCurrentCutObservation(recovered);
  assert.notStrictEqual(fresh, observation);
  assert.strictEqual(journal.reconfirmOriginalModelJournal(fresh), fresh);
  assert.throws(() => journal.invalidateOriginalModelCurrentCut(recovered, receipts.request),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.throws(() => journal.commitOriginalModelCurrentCut(recovered),
    {code: 'ModelOriginalCurrentCutOperationAlreadyAttempted'});
  assert.deepEqual(readFileSync(journal.path), bytes);
});

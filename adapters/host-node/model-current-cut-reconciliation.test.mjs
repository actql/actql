// Actual SQLite observations with explicit Resource/Store/Common fixture ports.
// No authenticated restoration, physical Store ACK, unpark or send is tested.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {C, input, open, immediateIdentity, immediateReference, seedApproval, saved} from './model-resume-state.fixture.mjs';

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
function fixture(t, {entered = false, settled = false, deferred = false} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'model-cut-reconciliation-'));
  const parks = new WeakMap(), saves = new WeakMap(), requests = new WeakMap();
  const resource = {inspect: token => parks.get(token), current: token => parks.has(token) ? token : undefined,
    invalidationCurrent: (request, park) => requests.get(request) === park ? request : undefined};
  const storage = {inspect: token => saves.get(token), current: token => saves.has(token) ? token : undefined};
  let selectedCut = cut;
  const verifierOverrides = {originalResourceCut: resource, originalStateSaved: storage,
    projectOriginalCurrentCut: () => selectedCut};
  const opened = [];
  const reopen = () => {const value = open(root, {verifierOverrides}); opened.push(value); return value.journal;};
  const journal = reopen();
  t.after(() => {for (const value of opened) value.journal.close(); rmSync(root, {recursive: true, force: true});});
  if (deferred) {
    journal.registerResumeCallSet(input(1)); seedApproval(journal.path);
    selectedCut = freeze({...cut, run_version: 1, continuation: {
      checkpoint_cid: C('checkpoint'), intent_id: 'intent', claimant: 'owner-1',
      generation: 1, resolution_cid: C('resolution')}});
  } else {
    journal.registerImmediateModelCallSet({modelCallSet: input(1).modelCallSet, declaredResults: ['result']});
  }
  if (entered) {
    const reference = immediateReference(0);
    const value = opened[0];
    const entry = journal.enterImmediateModelCall(reference, value.issueImmediate(reference));
    selectedCut = freeze({...cut, slots: [{...cut.slots[0], attempt_index: 1, state: 'EnteredUnknown'}]});
    if (settled) {
      // Explicit persisted settlement double, before the original cut is linked.
      mutate(journal.path, "UPDATE resume_model_attempts SET state = 'SavedSuccess', settlement_json = ?",
        JSON.stringify(saved(entry)));
      mutate(journal.path, "UPDATE resume_model_slots SET state = 'SavedSuccess'");
      selectedCut = freeze({...cut, slots: [{...cut.slots[0], attempt_index: 1, state: 'SavedSuccess'}]});
    }
  }
  function receipts() {
    const park = Object.freeze({}), save = Object.freeze({}), request = Object.freeze({});
    parks.set(park, freeze({identity: {...immediateIdentity}, phase: 'parked', cut: selectedCut}));
    saves.set(save, freeze({identity: {...immediateIdentity}, phase: 'parked', cut: selectedCut,
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

function mutate(path, sql, ...args) {
  const db = new DatabaseSync(path);
  try {db.prepare(sql).run(...args);} finally {db.close();}
}
function fresh(f) {return f.journal.observeOriginalModelJournal(immediateIdentity);}
function link(f) {
  const db = new DatabaseSync(f.journal.path, {readOnly: true});
  try {return db.prepare('SELECT current_cut_link_json FROM resume_model_scopes').get().current_cut_link_json;}
  finally {db.close();}
}
const digest = bytes => createHash('sha256').update(bytes).digest('hex');

test('reopened journal issues only a read-only reconciled reference of the exact link', t => {
  const f = fixture(t);
  f.journal.close();
  const journal = f.reopen(), receipts = f.receipts();
  const observation = journal.observeOriginalModelJournal(immediateIdentity);
  // Reopening initializes the existing journal installation. Fence the actual
  // read-only operation after that initialization, not the previous connection.
  const before = digest(readFileSync(journal.path));
  const recovered = journal.recoverOriginalModelCurrentCut(observation, receipts);
  assert.deepEqual(journal.originalModelCurrentCutOperationStatus(recovered), {state: 'reconciled'});
  const fresh = journal.originalModelCurrentCutObservation(recovered);
  assert.notStrictEqual(fresh, observation);
  assert.strictEqual(journal.reconfirmOriginalModelJournal(fresh), fresh);
  assert.throws(() => journal.invalidateOriginalModelCurrentCut(recovered, receipts.request),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.throws(() => journal.commitOriginalModelCurrentCut(recovered),
    {code: 'ModelOriginalCurrentCutOperationAlreadyAttempted'});
  assert.equal(digest(readFileSync(journal.path)), before);
});

test('reconciliation retains refusal of old, copied and foreign nominal objects', t => {
  const f = fixture(t), other = f.reopen(), observation = other.observeOriginalModelJournal(immediateIdentity);
  assert.throws(() => other.originalModelCurrentCutObservation(f.operation), {code: 'ForeignModelOriginalCutOperation'});
  const current = other.recoverOriginalModelCurrentCut(observation, f.receipts());
  assert.throws(() => other.originalModelCurrentCutObservation({...current}), {code: 'ForeignModelOriginalCutOperation'});
  assert.throws(() => f.journal.originalModelCurrentCutObservation(current), {code: 'ForeignModelOriginalCutOperation'});
  assert.throws(() => other.recoverOriginalModelCurrentCut({...observation}, f.receipts()),
    {code: 'ForeignModelOriginalJournalObservation'});
  assert.throws(() => other.recoverOriginalModelCurrentCut(observation,
    {parkReceipt: {...f.original.parkReceipt}, savedReceipt: f.original.savedReceipt}));
  assert.throws(() => other.recoverOriginalModelCurrentCut(observation,
    {parkReceipt: f.original.parkReceipt, savedReceipt: {...f.original.savedReceipt}}));
});

for (const field of ['runId', 'runDefinitionCid', 'preparedInvocationCid', 'scopeCid',
  'providerBindingCid', 'inputArtifactCid', 'taskIndex', 'strategyRevision']) {
  test(`reconciliation refuses a changed original Resource binding: ${field}`, t => {
    const f = fixture(t), receipts = f.receipts();
    const previous = f.parks.get(receipts.parkReceipt);
    f.parks.set(receipts.parkReceipt, freeze({...previous, identity: {...previous.identity,
      [field]: typeof previous.identity[field] === 'number' ? 1 : C('changed')}}));
    assert.throws(() => f.journal.recoverOriginalModelCurrentCut(fresh(f), receipts),
      {code: 'ModelOriginalCurrentCutBindingMismatch'});
  });
}

for (const field of ['documentCid', 'holdingCid', 'storageBindingCid', 'resourceStateCid', 'phase']) {
  test(`reconciliation refuses a different saved original: ${field}`, t => {
    const f = fixture(t), receipts = f.receipts(), previous = f.saves.get(receipts.savedReceipt);
    f.saves.set(receipts.savedReceipt, freeze({...previous, [field]: field === 'phase' ? 'stopping' : C('changed')}));
    assert.throws(() => f.journal.recoverOriginalModelCurrentCut(fresh(f), receipts),
      {code: 'ModelOriginalCurrentCutBindingMismatch'});
  });
}

for (const [name, sql, args, options] of [
  ['Run version', 'UPDATE runs SET version = version + 1', [], {}],
  ['Run status', "UPDATE runs SET status = 'failed'", [], {}],
  ['Slot state', "UPDATE resume_model_slots SET state = 'SavedFailure'", [], {entered: true}],
  ['Slot attempt', 'UPDATE resume_model_slots SET attempt_index = 2', [], {entered: true}],
  ['Entry bytes', 'UPDATE resume_model_attempts SET entry_json = ?', ['{}'], {entered: true}],
  ['settlement bytes', "UPDATE resume_model_attempts SET settlement_json = json_set(settlement_json, '$.evidence.captureCid', ?)",
    [C('changed capture')], {entered: true, settled: true}],
  ['continuation claimant', "UPDATE resume_intents SET claimant = 'changed'", [], {deferred: true}],
  ['continuation generation', 'UPDATE resume_intents SET generation = 2', [], {deferred: true}],
  ['approval resolution', 'UPDATE resolutions SET verified_resolution_wire = ?', ['{}'], {deferred: true}],
]) {
  test(`reconciliation refuses changed whole facts: ${name}`, t => {
    const f = fixture(t, options), observation = fresh(f);
    mutate(f.journal.path, sql, ...args);
    assert.throws(() => f.journal.recoverOriginalModelCurrentCut(observation, f.original));
    // Taking a newer observation cannot erase the persisted original fence.
    assert.throws(() => f.journal.recoverOriginalModelCurrentCut(fresh(f), f.original));
  });
}

test('verification callback mutation is detected after original port inspection', t => {
  const f = fixture(t), observation = fresh(f), inspect = f.resource.inspect;
  let changed = false;
  f.resource.inspect = token => {
    if (!changed) {changed = true; mutate(f.journal.path, 'UPDATE runs SET version = version + 1');}
    return inspect(token);
  };
  assert.throws(() => f.journal.recoverOriginalModelCurrentCut(observation, f.original),
    {code: 'ModelOriginalCurrentCutFactsChanged'});
});

test('Resource or Store custody loss cannot be replaced by matching DATA', t => {
  const f = fixture(t), observation = fresh(f);
  f.storage.current = () => true;
  assert.throws(() => f.journal.recoverOriginalModelCurrentCut(observation, f.original),
    {code: 'ModelOriginalCurrentCutCustodyChanged'});
  f.storage.current = token => f.saves.has(token) ? token : undefined;
  f.resource.current = () => ({...f.original.parkReceipt});
  assert.throws(() => f.journal.recoverOriginalModelCurrentCut(observation, f.original),
    {code: 'ModelOriginalCurrentCutCustodyChanged'});
});

for (const replacement of [null, '{}', 'not JSON']) {
  test(`null/replaced/corrupt link refuses reconciliation: ${String(replacement)}`, t => {
    const f = fixture(t);
    mutate(f.journal.path, 'UPDATE resume_model_scopes SET current_cut_link_json = ?', replacement);
    assert.throws(() => f.journal.recoverOriginalModelCurrentCut(fresh(f), f.original));
    assert.equal(link(f), replacement);
  });
}

test('reconciled reference cannot clear the existing mutation fence or issue a copied ACK', t => {
  const f = fixture(t), observation = fresh(f);
  const recovered = f.journal.recoverOriginalModelCurrentCut(observation, f.original);
  const again = f.journal.recoverOriginalModelCurrentCut(observation, f.original);
  for (const reference of [recovered, again]) {
    assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(reference, f.original.request),
      {code: 'ModelOriginalCurrentCutUnavailable'});
    assert.throws(() => f.journal.originalModelCurrentCutInvalidationCurrent({}, reference,
      f.original.parkReceipt, f.original.request), {code: 'ForeignModelOriginalCutInvalidation'});
  }
  assert.throws(() => f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire}),
    {code: 'ModelOriginalCurrentCutInvalidationRequired'});
  // The existing live operation remains the only confirmed-COMMIT path.
  const ack = f.journal.invalidateOriginalModelCurrentCut(f.operation, f.original.request);
  assert.strictEqual(f.journal.originalModelCurrentCutInvalidationCurrent(ack, f.operation,
    f.original.parkReceipt, f.original.request), ack);
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(f.operation, f.original.request),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.throws(() => f.journal.originalModelCurrentCutObservation(recovered),
    {code: 'ModelOriginalCurrentCutFactsChanged'});
});

for (const afterCommit of [false, true]) {
  test(`Unknown unlink ${afterCommit ? 'after' : 'before'} COMMIT remains unavailable after reopen`, t => {
    const f = fixture(t), exec = DatabaseSync.prototype.exec;
    let commits = 0;
    DatabaseSync.prototype.exec = function(sql, ...args) {
      if (sql === 'COMMIT' && ++commits === 3) {
        if (afterCommit) exec.call(this, sql, ...args);
        throw Error('OriginalCommitResponseUnknown');
      }
      return exec.call(this, sql, ...args);
    };
    try {assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(f.operation, f.original.request),
      error => error.code === 'CheckpointJournalCommitOutcomeUnknown' && error.outcome === 'unknown');}
    finally {DatabaseSync.prototype.exec = exec;}
    assert.equal(f.journal.originalModelCurrentCutOperationStatus(f.operation).state, 'unknown');
    assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(f.operation, f.original.request),
      {code: 'ModelOriginalCurrentCutUnavailable'});
    f.journal.close();
    const reopened = f.reopen(), observation = reopened.observeOriginalModelJournal(immediateIdentity);
    if (afterCommit) {
      assert.equal(link(f), null);
      assert.throws(() => reopened.recoverOriginalModelCurrentCut(observation, f.receipts()),
        {code: 'ModelOriginalCurrentCutUnavailable'});
    } else {
      const receipts = f.receipts(), reconciled = reopened.recoverOriginalModelCurrentCut(observation, receipts);
      assert.equal(reopened.originalModelCurrentCutOperationStatus(reconciled).state, 'reconciled');
      assert.throws(() => reopened.invalidateOriginalModelCurrentCut(reconciled, receipts.request),
        {code: 'ModelOriginalCurrentCutUnavailable'});
    }
    assert.ok(f.parks.has(f.original.parkReceipt)); assert.ok(f.saves.has(f.original.savedReceipt));
  });
}

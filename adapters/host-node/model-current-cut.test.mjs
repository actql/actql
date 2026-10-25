// Real SQLite/CAS/COMMIT tests with explicit Resource, Store and codec doubles.
// These do not prove physical park, Store ACK, funded startup or public INFER.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {C, input, open, immediateIdentity, immediateReference, seedApproval} from './model-resume-state.fixture.mjs';
import {assertOriginalModelJournalInvalidation} from './model-resume-state.mjs';

const freeze = value => {
  if (value !== null && typeof value === 'object') {
    for (const child of Object.values(value)) freeze(child);
    Object.freeze(value);
  }
  return value;
};
const cutData = facts => ({scope_cid: facts.identity.scopeCid,
  input_artifact_cid: facts.identity.inputArtifactCid,
  fixed_input_receipt_cid: facts.identity.inputArtifactCid,
  run_version: facts.run.version, continuation: facts.run.status !== 'resuming' ? null : {
    checkpoint_cid: facts.currentIntent.checkpoint_cid, intent_id: facts.currentIntent.intent_id,
    claimant: facts.currentIntent.claimant, generation: facts.currentIntent.generation,
    resolution_cid: facts.currentIntent.resolution_cid},
  slots: facts.slots.filter(slot => slot.scope_cid === facts.identity.scopeCid).map(slot => ({
    ordinal: slot.ordinal, slot_cid: slot.slot_cid, attempt_index: slot.attempt_index,
    state: slot.state, entry_identity_cid: null, settlement_identity_cid: null}))});
function fixture(t, {deferred = false} = {}) {
  const root = mkdtempSync(join(tmpdir(), 'model-current-cut-'));
  const parks = new WeakMap(), saves = new WeakMap(), requests = new WeakMap();
  const resource = {inspect: token => parks.get(token), current: token => parks.has(token) ? token : undefined,
    invalidationCurrent: (request, park) => requests.get(request) === park ? request : undefined};
  const storage = {inspect: token => saves.get(token), current: token => saves.has(token) ? token : undefined};
  const f = open(root, {verifierOverrides: {originalResourceCut: resource,
    originalStateSaved: storage, projectOriginalCurrentCut: ({facts}) => cutData(facts)}});
  t.after(() => {f.journal.close(); rmSync(root, {recursive: true, force: true});});
  const registration = input(1);
  let claim;
  if (deferred) {
    f.journal.registerResumeCallSet(registration); claim = seedApproval(f.journal.path);
  } else f.journal.registerImmediateModelCallSet({modelCallSet: registration.modelCallSet, declaredResults: ['result']});
  const observation = f.journal.observeOriginalModelJournal(immediateIdentity);
  const facts = f.journal.originalModelJournalObservationFacts(observation);
  const park = Object.freeze({}), save = Object.freeze({}), request = Object.freeze({});
  const cut = cutData(facts);
  parks.set(park, freeze({identity: {...immediateIdentity}, phase: 'parked', cut}));
  saves.set(save, freeze({identity: {...immediateIdentity}, phase: 'parked', cut,
    documentCid: C('actual fixture document'), holdingCid: C('actual fixture holding'),
    storageBindingCid: C('actual fixture storage'), resourceStateCid: C('actual fixture resource'),
    documentWire: 'explicit Store-verified fixture double'}));
  requests.set(request, park);
  return {...f, root, observation, park, save, request, parks, saves, resource, claim,
    prepare: () => f.journal.prepareOriginalModelCurrentCut(observation, {parkReceipt: park, savedReceipt: save})};
}
function rows(path) {
  const db = new DatabaseSync(path, {readOnly: true});
  try {return Object.fromEntries(['runs', 'resume_model_scopes', 'resume_model_slots',
    'resume_model_attempts', 'run_cancellation_fences'].map(table =>
    [table, db.prepare(`SELECT * FROM ${table}`).all()]));}
  finally {db.close();}
}

test('current cut exact same-journal link and committed invalidation preserve originals', t => {
  const f = fixture(t); const before = rows(f.journal.path); const op = f.prepare();
  assert.strictEqual(f.journal.commitOriginalModelCurrentCut(op), op);
  const linked = rows(f.journal.path);
  const link = linked.resume_model_scopes[0].current_cut_link_json;
  assert.ok(typeof link === 'string');
  const ready = JSON.parse(linked.resume_model_scopes[0].current_cut_invalidation_json);
  assert.equal(ready.phase, 'ready'); assert.equal(ready.request_binding, null);
  assert.equal(ready.linked_cut_wire, link);
  linked.resume_model_scopes[0].current_cut_link_json = null;
  linked.resume_model_scopes[0].current_cut_invalidation_json = null;
  assert.deepEqual(linked, before);
  assert.throws(() => f.journal.reconfirmOriginalModelJournal(f.observation), {code: 'ModelOriginalJournalObservationChanged'});
  const fresh = f.journal.originalModelCurrentCutObservation(op);
  assert.notStrictEqual(fresh, f.observation);
  assert.strictEqual(f.journal.reconfirmOriginalModelJournal(fresh), fresh);
  const receipt = f.journal.invalidateOriginalModelCurrentCut(op, f.request);
  assert.strictEqual(f.journal.originalModelCurrentCutInvalidationCurrent(receipt, op, f.park, f.request), receipt);
  const finished = rows(f.journal.path), confirmed = JSON.parse(finished.resume_model_scopes[0].current_cut_invalidation_json);
  assert.equal(confirmed.phase, 'confirmed');
  assert.equal(confirmed.operation_id, ready.operation_id);
  assert.deepEqual(confirmed.request_binding, {operation_id: ready.operation_id,
    resource_state_cid: f.saves.get(f.save).resourceStateCid});
  finished.resume_model_scopes[0].current_cut_invalidation_json = null;
  assert.deepEqual(finished, before);
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.throws(() => f.journal.originalModelCurrentCutInvalidationCurrent({...receipt}, op, f.park, f.request),
    {code: 'ForeignModelOriginalCutInvalidation'});
});

test('installed journal port admits only its own current original observation and committed four refs', t => {
  const f = fixture(t);
  const port = f.journal.installOriginalModelJournalPort(f.observation);
  assert.ok(Object.isFrozen(port));
  assert.deepEqual(Object.keys(port), ['kind']);
  assert.strictEqual(f.journal.originalModelJournalPortCurrent(port), port);
  assert.throws(() => f.journal.installOriginalModelJournalPort({...f.observation}),
    {code: 'ForeignModelOriginalJournalObservation'});
  assert.throws(() => f.journal.originalModelJournalPortCurrent({...port}),
    {code: 'ForeignModelOriginalJournalPort'});
  const op = f.prepare();
  assert.throws(() => f.journal.originalModelJournalPortInvalidationCurrent(port, {}, op, f.park, f.request),
    {code: 'ForeignModelOriginalCutInvalidation'});
  f.journal.commitOriginalModelCurrentCut(op);
  assert.throws(() => f.journal.installOriginalModelJournalPort(f.observation),
    {code: 'ModelOriginalJournalObservationChanged'});
  const receipt = f.journal.invalidateOriginalModelCurrentCut(op, f.request);
  assert.strictEqual(f.journal.originalModelJournalPortInvalidationCurrent(port, receipt, op, f.park, f.request), receipt);
  assert.equal(assertOriginalModelJournalInvalidation(port, receipt, op, f.park, f.request), undefined);
  for (const [received, operation, park, request] of [[{...receipt}, op, f.park, f.request],
    [receipt, {...op}, f.park, f.request], [receipt, op, {...f.park}, f.request],
    [receipt, op, f.park, {...f.request}]]) {
    assert.throws(() => f.journal.originalModelJournalPortInvalidationCurrent(port, received, operation, park, request));
    assert.throws(() => assertOriginalModelJournalInvalidation(port, received, operation, park, request));
  }
  for (const forged of [undefined, {...port}, true, () => true, 'sha256:' + '0'.repeat(64)]) {
    assert.throws(() => assertOriginalModelJournalInvalidation(forged, receipt, op, f.park, f.request),
      {code: 'ForeignModelOriginalJournalPort'});
  }
  f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire});
  assert.throws(() => f.journal.originalModelJournalPortInvalidationCurrent(port, receipt, op, f.park, f.request),
    {code: 'ModelOriginalCurrentCutFactsChanged'});
  assert.throws(() => assertOriginalModelJournalInvalidation(port, receipt, op, f.park, f.request),
    {code: 'ModelOriginalCurrentCutFactsChanged'});
});

test('installed journal port rejects another journal and a closed original installation', t => {
  const f = fixture(t), foreign = fixture(t);
  const port = f.journal.installOriginalModelJournalPort(f.observation);
  assert.throws(() => foreign.journal.originalModelJournalPortCurrent(port),
    {code: 'ForeignModelOriginalJournalPort'});
  assert.throws(() => foreign.journal.installOriginalModelJournalPort(f.observation),
    {code: 'ForeignModelOriginalJournalObservation'});
  const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const receipt = f.journal.invalidateOriginalModelCurrentCut(op, f.request);
  assert.throws(() => foreign.journal.originalModelJournalPortInvalidationCurrent(port, receipt, op, f.park, f.request),
    {code: 'ForeignModelOriginalJournalPort'});
  f.journal.close();
  assert.throws(() => f.journal.originalModelJournalPortCurrent(port), {code: 'CheckpointJournalClosed'});
  assert.throws(() => f.journal.originalModelJournalPortInvalidationCurrent(port, receipt, op, f.park, f.request),
    {code: 'CheckpointJournalClosed'});
});

test('current cut nominal ports reject missing copied foreign Boolean and changed bindings', t => {
  const f = fixture(t);
  for (const [parkReceipt, savedReceipt] of [[undefined, f.save], [f.park, undefined],
    [{...f.park}, f.save], [f.park, {...f.save}], [f.park, C('same body')]]) {
    assert.throws(() => f.journal.prepareOriginalModelCurrentCut(f.observation, {parkReceipt, savedReceipt}));
  }
  const actual = f.parks.get(f.park);
  for (const change of [{identity: {...immediateIdentity, runId: 'foreign'}},
    {phase: 'reading'}, {cut: {...actual.cut, run_version: 2}},
    {cut: {...actual.cut, input_artifact_cid: C('foreign')}}]) {
    f.parks.set(f.park, freeze({...actual, ...change}));
    assert.throws(() => f.prepare(), {code: 'ModelOriginalCurrentCutBindingMismatch'});
  }
  f.parks.set(f.park, actual); f.resource.current = () => true;
  assert.throws(() => f.prepare(), {code: 'ModelOriginalCurrentCutCustodyChanged'});
  assert.equal(rows(f.journal.path).resume_model_scopes[0].current_cut_link_json, null);
});

test('current cut detects original mutation between observation preparation and commit', t => {
  const f = fixture(t); const op = f.prepare();
  f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire});
  assert.throws(() => f.journal.commitOriginalModelCurrentCut(op), {code: 'ModelOriginalCurrentCutFactsChanged'});
  assert.deepEqual(f.journal.originalModelCurrentCutOperationStatus(op), {state: 'failed'});
  assert.equal(rows(f.journal.path).resume_model_scopes[0].current_cut_link_json, null);
});

test('current cut blocks Entry cancellation and Run mutation until exact invalidation', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const before = rows(f.journal.path); const ref = immediateReference(0);
  assert.throws(() => f.journal.enterImmediateModelCall(ref, f.issueImmediate(ref)),
    {code: 'ModelOriginalCurrentCutInvalidationRequired'});
  assert.throws(() => f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire}),
    {code: 'ModelOriginalCurrentCutInvalidationRequired'});
  assert.deepEqual(rows(f.journal.path), before);
  f.journal.invalidateOriginalModelCurrentCut(op, f.request);
  assert.doesNotThrow(() => f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire}));
});

test('current cut guards lease renewal without a diagnostic mutation hook', t => {
  const f = fixture(t, {deferred: true}); const op = f.prepare();
  f.journal.commitOriginalModelCurrentCut(op);
  const before = f.journal.originalModelJournalObservationFacts(
    f.journal.originalModelCurrentCutObservation(op)).currentIntent;
  assert.throws(() => f.journal.renewResume(f.claim, 1200), {code: 'ModelOriginalCurrentCutInvalidationRequired'});
  const after = f.journal.originalModelJournalObservationFacts(
    f.journal.originalModelCurrentCutObservation(op)).currentIntent;
  assert.deepEqual(after, before);
  f.journal.invalidateOriginalModelCurrentCut(op, f.request);
  assert.doesNotThrow(() => f.journal.renewResume(f.claim, 1200));
});

test('current cut changed replaced or absent link yields no invalidation receipt', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const db = new DatabaseSync(f.journal.path);
  try {db.prepare('UPDATE resume_model_scopes SET current_cut_link_json = NULL WHERE scope_cid = ?').run(immediateIdentity.scopeCid);}
  finally {db.close();}
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'ModelOriginalCurrentCutFactsChanged'});
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(op).state, 'failed');
  assert.throws(() => f.journal.originalModelCurrentCutInvalidationCurrent({}, op, f.park, f.request));
});

test('current cut affected-row CAS mismatch is not committed invalidation', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const db = new DatabaseSync(f.journal.path);
  try {db.exec(`CREATE TRIGGER refuse_original_cut_update BEFORE UPDATE OF current_cut_link_json
    ON resume_model_scopes BEGIN SELECT RAISE(IGNORE); END`);}
  finally {db.close();}
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'ModelResumeStateConflict'});
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(op).state, 'failed');
  assert.equal(typeof rows(f.journal.path).resume_model_scopes[0].current_cut_link_json, 'string');
  assert.ok(f.parks.has(f.park));
});

test('current cut replaced wire and invalidation request reject before nominal issuance', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, {...f.request}),
    {code: 'ForeignModelOriginalCutInvalidationRequest'});
  const db = new DatabaseSync(f.journal.path);
  try {
    const data = JSON.parse(rows(f.journal.path).resume_model_scopes[0].current_cut_link_json);
    data.documentCid = C('replacement');
    db.prepare('UPDATE resume_model_scopes SET current_cut_link_json = ? WHERE scope_cid = ?')
      .run(JSON.stringify(data), immediateIdentity.scopeCid);
  } finally {db.close();}
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'ModelOriginalCurrentCutFactsChanged'});
  assert.ok(f.parks.has(f.park));
});

test('current cut missing current Resource custody keeps original link and holdings', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  f.resource.current = () => undefined;
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request),
    {code: 'ModelOriginalCurrentCutCustodyChanged'});
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(op).state, 'linked');
  assert.equal(typeof rows(f.journal.path).resume_model_scopes[0].current_cut_link_json, 'string');
  assert.ok(f.saves.has(f.save));
});

test('current cut real COMMIT response loss preserves Unknown and never infers receipt from absence', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const exec = DatabaseSync.prototype.exec;
  let commits = 0;
  DatabaseSync.prototype.exec = function(sql, ...args) {
    const result = exec.call(this, sql, ...args);
    if (sql === 'COMMIT' && ++commits === 3) throw Error('OriginalCommitResponseLost');
    return result;
  };
  try {assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request),
    error => error.code === 'CheckpointJournalCommitOutcomeUnknown' && error.outcome === 'unknown');}
  finally {DatabaseSync.prototype.exec = exec;}
  assert.equal(rows(f.journal.path).resume_model_scopes[0].current_cut_link_json, null);
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(op).state, 'unknown');
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
});

test('current cut actual failed COMMIT retains original link and no issuer', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const before = rows(f.journal.path); const exec = DatabaseSync.prototype.exec;
  let commits = 0;
  DatabaseSync.prototype.exec = function(sql, ...args) {
    if (sql === 'COMMIT' && ++commits === 3) throw Error('OriginalCommitFailed');
    return exec.call(this, sql, ...args);
  };
  try {assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request),
    {code: 'CheckpointJournalCommitOutcomeUnknown'});}
  finally {DatabaseSync.prototype.exec = exec;}
  const after = rows(f.journal.path), durable = JSON.parse(after.resume_model_scopes[0].current_cut_invalidation_json);
  const prior = JSON.parse(before.resume_model_scopes[0].current_cut_invalidation_json);
  assert.equal(durable.phase, 'attempted'); assert.equal(durable.operation_id, prior.operation_id);
  assert.equal(durable.linked_cut_wire, prior.linked_cut_wire);
  assert.deepEqual(durable.request_binding, {operation_id: prior.operation_id,
    resource_state_cid: f.saves.get(f.save).resourceStateCid});
  after.resume_model_scopes[0].current_cut_invalidation_json = before.resume_model_scopes[0].current_cut_invalidation_json;
  assert.deepEqual(after, before);
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(op).state, 'unknown');
  assert.ok(f.parks.has(f.park));
});

test('current cut foreign connection and restart retain data but cannot reissue nominal operation', t => {
  const f = fixture(t); const op = f.prepare(); f.journal.commitOriginalModelCurrentCut(op);
  const other = open(f.root); t.after(() => other.journal.close());
  assert.throws(() => other.journal.invalidateOriginalModelCurrentCut(op, f.request),
    {code: 'ForeignModelOriginalCutOperation'});
  assert.equal(typeof rows(other.journal.path).resume_model_scopes[0].current_cut_link_json, 'string');
  f.journal.close();
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(op, f.request), {code: 'CheckpointJournalClosed'});
});

test('current cut old layout refuses before DDL without changing original rows', t => {
  const f = fixture(t); f.journal.close();
  const db = new DatabaseSync(f.journal.path);
  try {
    db.exec('ALTER TABLE resume_model_scopes DROP COLUMN current_cut_link_json');
    db.exec('ALTER TABLE resume_model_scopes DROP COLUMN current_cut_invalidation_json');
    db.prepare('UPDATE journal_metadata SET value = ? WHERE key = ?').run(
      'actql-checkpoint-journal/0.1;model-call-provenance=1;effect-settlement=1', 'schema_version');
  } finally {db.close();}
  const before = readFileSync(f.journal.path); const old = rows(f.journal.path);
  assert.throws(() => open(f.root), {code: 'UnsupportedCheckpointJournal'});
  assert.deepEqual(readFileSync(f.journal.path), before);
  assert.deepEqual(rows(f.journal.path), old);
});

// Real SQLite, explicit Resource/Store/Common doubles. No cold admission,
// physical Store ACK, Resource consume, numerical allowance or Provider send.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {C, input, open, immediateIdentity} from './model-resume-state.fixture.mjs';
import {MODEL_CURRENT_CUT_JOURNAL_LAYOUT} from './sqlite-checkpoint-journal.mjs';
import {readFileSync} from 'node:fs';

const freeze = value => {
  if (value !== null && typeof value === 'object') {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};
function fixture(t, {link = true} = {}) {
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
  if (link) journal.commitOriginalModelCurrentCut(operation);
  return {root, journal, operation, park, save, request, parks, saves, requests, resource, storage, reopen};
}
function update(f, sql, ...args) {
  const db = new DatabaseSync(f.journal.path);
  try {db.prepare(sql).run(...args);} finally {db.close();}
}
const record = f => JSON.parse(row(f).current_cut_invalidation_json);
const observation = journal => journal.observeOriginalModelJournal(immediateIdentity);
const phases = [
  ['prepared', f => f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request)],
  ['attempted', f => f.journal.markOriginalModelCurrentCutInvalidationAttempted(f.operation)],
  ['confirmed', f => f.journal.commitOriginalModelCurrentCutInvalidation(f.operation)],
];
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

test('three confirmed transactions preserve one ID, same request, exact link and old four-ref ACK', t => {
  const f = fixture(t), original = record(f), id = original.operation_id;
  assert.equal(f.journal.originalModelCurrentCutOperationId(f.operation), id);
  let ack;
  for (const [phase, advance] of phases) {
    const before = observation(f.journal);
    ack = advance(f);
    const actual = record(f);
    assert.equal(actual.phase, phase);
    assert.equal(actual.operation_id, id);
    assert.equal(actual.linked_cut_wire, original.linked_cut_wire);
    assert.deepEqual(actual.identity, original.identity);
    assert.deepEqual(actual.request_binding, {operation_id: id, resource_state_cid: C('resource')});
    assert.throws(() => f.journal.reconfirmOriginalModelJournal(before), {code: 'ModelOriginalJournalObservationChanged'});
    const data = f.journal.lookupOriginalModelCutInvalidation(observation(f.journal), id);
    assert.deepEqual(data, {kind: 'observed', record: actual});
    assert.ok(Object.isFrozen(data.record.request_binding));
  }
  assert.equal(row(f).current_cut_link_json, null);
  assert.strictEqual(f.journal.originalModelCurrentCutInvalidationCurrent(ack, f.operation, f.park, f.request), ack);
  assert.throws(() => f.journal.commitOriginalModelCurrentCutInvalidation(f.operation), {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.throws(() => f.journal.originalModelCurrentCutInvalidationCurrent({...ack}, f.operation, f.park, f.request),
    {code: 'ForeignModelOriginalCutInvalidation'});
  assert.doesNotThrow(() => f.journal.fenceRunCancellation({originalRunWire: input(1).modelCallSet.originalRunWire}));
});

for (const [ordinal, [phase, advance]] of phases.entries()) {
  for (const afterCommit of [false, true]) {
    test(`${phase} ${afterCommit ? 'after' : 'before'} COMMIT loss stops same operation and cold DATA cannot continue`, t => {
      const f = fixture(t), id = record(f).operation_id;
      for (let index = 0; index < ordinal; index++) phases[index][1](f);
      const exec = DatabaseSync.prototype.exec;
      let attempted = 0;
      DatabaseSync.prototype.exec = function(sql, ...args) {
        if (sql === 'COMMIT') {
          attempted++;
          if (afterCommit) exec.call(this, sql, ...args);
          throw Error('OriginalInvalidationCommitResponseUnknown');
        }
        return exec.call(this, sql, ...args);
      };
      try {assert.throws(() => advance(f), error =>
        error.code === 'CheckpointJournalCommitOutcomeUnknown' && error.outcome === 'unknown');}
      finally {DatabaseSync.prototype.exec = exec;}
      assert.equal(attempted, 1);
      assert.equal(f.journal.originalModelCurrentCutOperationStatus(f.operation).state, 'unknown');
      const expected = afterCommit ? phase : ['ready', 'prepared', 'attempted'][ordinal];
      assert.equal(record(f).phase, expected);
      assert.equal(record(f).operation_id, id);
      const retained = row(f);
      for (const [, retry] of phases) assert.throws(() => retry(f), {code: 'ModelOriginalCurrentCutUnavailable'});
      assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(f.operation, f.request),
        {code: 'ModelOriginalCurrentCutUnavailable'});
      assert.deepEqual(row(f), retained);
      f.journal.close();
      const cold = f.reopen();
      const data = cold.lookupOriginalModelCutInvalidation(observation(cold), id);
      assert.equal(data.record.phase, expected);
      assert.equal(data.record.operation_id, id);
      assert.throws(() => cold.invalidateOriginalModelCurrentCut(f.operation, f.request), {code: 'ForeignModelOriginalCutOperation'});
      assert.throws(() => cold.invalidateOriginalModelCurrentCut(data, f.request), {code: 'ForeignModelOriginalCutOperation'});
      assert.throws(() => cold.originalModelCurrentCutInvalidationCurrent(data, data, f.park, f.request),
        {code: 'ForeignModelOriginalCutOperation'});
      assert.deepEqual(row({...f, journal: cold}), retained);
      assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
    });
  }
}

for (const [ordinal, [phase, advance]] of phases.entries()) {
  test(`${phase} rechecks original Store after request callback, keeping custody on refusal`, t => {
    const f = fixture(t);
    for (let index = 0; index < ordinal; index++) phases[index][1](f);
    const before = row(f);
    f.resource.invalidationCurrent = request => {f.storage.current = () => undefined; return request;};
    assert.throws(() => advance(f), {code: 'ModelOriginalCurrentCutCustodyChanged'});
    assert.deepEqual(row(f), before);
    assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
  });
  test(`${phase} reselects all original facts after callback without issuing outcome`, t => {
    const f = fixture(t);
    for (let index = 0; index < ordinal; index++) phases[index][1](f);
    const before = record(f);
    f.resource.invalidationCurrent = request => {
      update(f, 'UPDATE runs SET version = version + 1 WHERE run_id = ?', immediateIdentity.runId);
      return request;
    };
    assert.throws(() => advance(f), {code: 'ModelOriginalCurrentCutFactsChanged'});
    assert.deepEqual(record(f), before);
    assert.equal(f.journal.originalModelCurrentCutOperationStatus(f.operation).state, 'failed');
  });
  test(`${phase} exact CAS requires one affected row and preserves original responsibility`, t => {
    const f = fixture(t);
    for (let index = 0; index < ordinal; index++) phases[index][1](f);
    const before = row(f), db = new DatabaseSync(f.journal.path);
    try {db.exec('CREATE TRIGGER refuse_invalidation BEFORE UPDATE OF current_cut_invalidation_json ON resume_model_scopes BEGIN SELECT RAISE(IGNORE); END');}
    finally {db.close();}
    assert.throws(() => advance(f), {code: 'ModelResumeStateConflict'});
    assert.deepEqual(row(f), before);
    assert.equal(f.journal.originalModelCurrentCutOperationStatus(f.operation).state, 'failed');
    assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
  });
}

test('foreign/copied request and operation cannot prepare intent, duplicate binding is unavailable', t => {
  const f = fixture(t), before = row(f);
  for (const request of [{...f.request}, true, C('resource'), Object.freeze({})]) {
    assert.throws(() => f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, request),
      {code: 'ForeignModelOriginalCutInvalidationRequest'});
  }
  assert.throws(() => f.journal.prepareOriginalModelCurrentCutInvalidation({...f.operation}, f.request),
    {code: 'ForeignModelOriginalCutOperation'});
  assert.deepEqual(row(f), before);
  f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request);
  assert.throws(() => f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request),
    {code: 'ModelOriginalCurrentCutUnavailable'});
  f.requests.delete(f.request);
  assert.throws(() => f.journal.markOriginalModelCurrentCutInvalidationAttempted(f.operation),
    {code: 'ForeignModelOriginalCutInvalidationRequest'});
  assert.equal(record(f).phase, 'prepared');
});

test('missing legacy metadata is Unknown DATA, not ready, fresh identity or unlink permission', t => {
  const f = fixture(t), id = record(f).operation_id;
  update(f, 'UPDATE resume_model_scopes SET current_cut_invalidation_json = NULL');
  const before = row(f);
  assert.deepEqual(f.journal.lookupOriginalModelCutInvalidation(observation(f.journal), id), {kind: 'legacy_unknown'});
  assert.throws(() => f.journal.invalidateOriginalModelCurrentCut(f.operation, f.request), {code: 'ModelOriginalCurrentCutFactsChanged'});
  f.journal.close();
  const cold = f.reopen();
  const data = cold.lookupOriginalModelCutInvalidation(observation(cold), id);
  assert.deepEqual(data, {kind: 'legacy_unknown'});
  assert.throws(() => cold.invalidateOriginalModelCurrentCut(data, f.request), {code: 'ForeignModelOriginalCutOperation'});
  assert.deepEqual(row({...f, journal: cold}), before);
});

const corruptions = [
  ['outer ID changed independently', value => ({...value, operation_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'})],
  ['inner ID differs', value => ({...value, request_binding: {...value.request_binding, operation_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'}})],
  ['foreign state CID', value => ({...value, request_binding: {...value.request_binding, resource_state_cid: C('foreign')}})],
  ['extra request field', value => ({...value, request_binding: {...value.request_binding, grant: true}})],
  ['missing request field', value => ({...value, request_binding: {operation_id: value.operation_id}})],
  ['confirmed while link remains', value => ({...value, phase: 'confirmed'})],
  ['ready with bound request', value => ({...value, phase: 'ready'})],
  ['unknown phase', value => ({...value, phase: 'unknown'})],
  ['foreign identity', value => ({...value, identity: {...value.identity, runId: 'foreign'}})],
  ['foreign original identity in both nested locations', value => {
    const identity = {...value.identity, providerBindingCid: C('foreign-provider')};
    return {...value, identity, linked_cut_wire: JSON.stringify({...JSON.parse(value.linked_cut_wire), identity})};
  }],
  ['extra outer field', value => ({...value, permission: true})],
];
for (const [name, corrupt] of corruptions) test(`closed durable data refuses ${name}`, t => {
  const f = fixture(t);
  f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request);
  const value = record(f), id = value.operation_id;
  update(f, 'UPDATE resume_model_scopes SET current_cut_invalidation_json = ?', JSON.stringify(corrupt(value)));
  assert.throws(() => f.journal.lookupOriginalModelCutInvalidation(observation(f.journal), id),
    {code: 'ModelOriginalCurrentCutInvalidationCorrupt'});
  assert.throws(() => f.journal.markOriginalModelCurrentCutInvalidationAttempted(f.operation),
    {code: 'ModelOriginalCurrentCutFactsChanged'});
  assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
});

test('operation lookup rejects another ID and stale/copy observation', t => {
  const f = fixture(t), id = record(f).operation_id, before = observation(f.journal);
  assert.throws(() => f.journal.lookupOriginalModelCutInvalidation(before, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
    {code: 'ModelOriginalCurrentCutOperationIdentityMismatch'});
  assert.throws(() => f.journal.lookupOriginalModelCutInvalidation({...before}, id), {code: 'ForeignModelOriginalJournalObservation'});
  f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request);
  assert.throws(() => f.journal.lookupOriginalModelCutInvalidation(before, id), {code: 'ModelOriginalCurrentCutFactsChanged'});
});

test('old layout discriminator refuses before DDL and does not change synthetic database bytes', t => {
  const f = fixture(t); f.journal.close();
  update(f, 'UPDATE journal_metadata SET value = ? WHERE key = ?', MODEL_CURRENT_CUT_JOURNAL_LAYOUT, 'schema_version');
  const before = readFileSync(f.journal.path);
  assert.throws(() => f.reopen(), {code: 'UnsupportedCheckpointJournal'});
  assert.deepEqual(readFileSync(f.journal.path), before);
});

test('current discriminator with missing column refuses before DDL without implicit migration', t => {
  const f = fixture(t); f.journal.close();
  const db = new DatabaseSync(f.journal.path);
  try {db.exec('ALTER TABLE resume_model_scopes DROP COLUMN current_cut_invalidation_json');} finally {db.close();}
  const before = readFileSync(f.journal.path);
  // A claimed current layout with damage keeps the existing SQLite refusal;
  // it is not a request to create/repair a missing column or retry migration.
  assert.throws(() => f.reopen(), error => error.code === 'ERR_SQLITE_ERROR' &&
    error.message.includes('current_cut_invalidation_json'));
  assert.deepEqual(readFileSync(f.journal.path), before);
});

for (const afterCommit of [false, true]) test(`fresh link ${afterCommit ? 'after' : 'before'} COMMIT loss retains minted ID without relinking`, t => {
  const f = fixture(t, {link: false}), exec = DatabaseSync.prototype.exec;
  DatabaseSync.prototype.exec = function(sql, ...args) {
    if (sql === 'COMMIT') {
      if (afterCommit) exec.call(this, sql, ...args);
      throw Error('OriginalLinkResponseUnknown');
    }
    return exec.call(this, sql, ...args);
  };
  try {assert.throws(() => f.journal.commitOriginalModelCurrentCut(f.operation),
    error => error.code === 'CheckpointJournalCommitOutcomeUnknown' && error.outcome === 'unknown');}
  finally {DatabaseSync.prototype.exec = exec;}
  const id = f.journal.originalModelCurrentCutOperationId(f.operation), before = row(f);
  assert.match(id, /^[0-9a-f-]{36}$/u);
  assert.equal(f.journal.originalModelCurrentCutOperationStatus(f.operation).state, 'unknown');
  assert.throws(() => f.journal.commitOriginalModelCurrentCut(f.operation), {code: 'ModelOriginalCurrentCutOperationAlreadyAttempted'});
  assert.equal(f.journal.originalModelCurrentCutOperationId(f.operation), id);
  f.journal.close(); const cold = f.reopen();
  const data = cold.lookupOriginalModelCutInvalidation(observation(cold), id);
  if (afterCommit) {assert.equal(data.record.phase, 'ready'); assert.equal(data.record.operation_id, id);}
  else assert.deepEqual(data, {kind: 'legacy_unknown'});
  assert.throws(() => cold.commitOriginalModelCurrentCut(f.operation), {code: 'ForeignModelOriginalCutOperation'});
  assert.deepEqual(row({...f, journal: cold}), before);
});

for (const phase of ['prepared', 'attempted', 'confirmed']) test(`cold ${phase} lookup cannot reissue operation or overwrite its identity`, t => {
  const f = fixture(t);
  for (const [current, advance] of phases) {advance(f); if (current === phase) break;}
  const id = record(f).operation_id, before = row(f);
  f.journal.close(); const cold = f.reopen();
  const observed = observation(cold), data = cold.lookupOriginalModelCutInvalidation(observed, id);
  assert.equal(data.record.phase, phase);
  assert.throws(() => cold.prepareOriginalModelCurrentCutInvalidation(data, f.request), {code: 'ForeignModelOriginalCutOperation'});
  const fresh = cold.prepareOriginalModelCurrentCut(observed, {parkReceipt: f.park, savedReceipt: f.save});
  assert.throws(() => cold.commitOriginalModelCurrentCut(fresh), {code: 'ModelOriginalCurrentCutUnavailable'});
  assert.equal(cold.originalModelCurrentCutOperationId(fresh), undefined);
  assert.deepEqual(row({...f, journal: cold}), before);
});

test('prepared/null contradiction refuses observation and preserves Resource/Store custody', t => {
  const f = fixture(t); f.journal.prepareOriginalModelCurrentCutInvalidation(f.operation, f.request);
  update(f, 'UPDATE resume_model_scopes SET current_cut_link_json = NULL');
  assert.throws(() => observation(f.journal), {code: 'ModelOriginalCurrentCutInvalidationCorrupt'});
  assert.ok(f.parks.has(f.park)); assert.ok(f.saves.has(f.save));
});

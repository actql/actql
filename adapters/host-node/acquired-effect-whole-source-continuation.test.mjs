// Continuation connection controls. These explicit Core/checkpoint ports prove
// variant selection, original forwarding and cleanup reachability, not physical
// Source execution, encrypted storage or public cold recovery.
import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';

const ok = value => ({$tag: 1, _0: value});

function fixture() {
  const prepared = {}, capacity = {}, ledger = {}, owner = {}, input = {}, read = {}, identity = {}, dag = {};
  const sourceIdentity = ['original-program', 'original-parameters', '0', '1', '1', 'original-source'];
  const rows = ['{"id":3}'];
  const calls = [], records = new Map();
  let current = true, wholeCapacity = true, missingSource = false, pendingClose = false, retainedCurrent;
  const occurrence = {stage: 0, input: 1, task: 1, computeTask: 0};
  const preparedSource = {occurrence, checkedSource: {sourceInput: ['original-program', 'original-parameters']},
    readTuple: {source: 'original-source'}, physicalBinding: {binding: 'original-installation'},
    physicalPolicy: {policy: 'original-policy'}};
  const source = {occurrence, preparedSource, adapter: {retainedCapture(actual) {
    assert.strictEqual(actual, preparedSource);
    return {wholeInput: wholeCapacity, capacity};
  }}};
  const captured = {inputKind: 'whole-input', occurrence, capture: {source: () => input}};
  const checkpoints = {
    journal: {committedApprovalAt: () => ({current: true})},
    async computationSourceAuthorization() {
      return {assertCurrent() {}, close() {}, authorize() {assert.fail('Retained Source cannot start another read');}};
    },
    async retainComputationSource(run, definition, wire) {
      assert.equal(run, 'original-run'); assert.equal(definition, 'original-definition');
      const cid = `capture-${records.size}`; records.set(cid, JSON.parse(wire)); return cid;
    },
    async computationSourceReferences() { return [...records.keys()]; },
    async readComputationSource(_view, cid) { return Buffer.from(JSON.stringify(records.get(cid))); },
    async retireComputationSources() { calls.push('retire'); },
  };
  const moon = {
    clientProgramExportWholeSourceCapture(actual, selected, binding) {
      assert.strictEqual(actual, input); assert.strictEqual(selected, capacity);
      assert.equal(JSON.parse(binding).scope.task, 1);
      calls.push('export-whole');
      return ok({_0: sourceIdentity, _1: 'original-schema', _2: 'original-rows', _3: rows});
    },
    clientProgramExportSourceCapture() { assert.fail('Whole input is not a Query capture'); },
    clientProgramRestoreWholeSourceCapture(selected, expected, saved, facts, schema, rowsCid,
      savedRows, receiving, available, issuer) {
      assert.strictEqual(selected, capacity); assert.equal(expected, saved);
      assert.deepEqual(facts, sourceIdentity); assert.equal(schema, 'original-schema');
      assert.equal(rowsCid, 'original-rows'); assert.deepEqual(savedRows, rows);
      assert.strictEqual(receiving, ledger); assert.equal(issuer, undefined);
      assert.equal(available(), true); retainedCurrent = available; calls.push('restore-whole'); return ok(owner);
    },
    clientProgramRestoreSourceCapture() { assert.fail('Whole restore cannot construct a Query requirement'); },
    clientProgramSourceCaptureSource(actual) {
      assert.strictEqual(actual, owner); return missingSource ? undefined : input;
    },
    clientProgramIdentifyCapturedEffectSourceRelation(actual) {
      assert.strictEqual(actual, input); return ok(identity);
    },
    clientProgramIssueEffectWholeSourceInputLogical(actual, value, originalIdentity, selected) {
      assert.strictEqual(actual, prepared); assert.strictEqual(value, input);
      assert.strictEqual(originalIdentity, identity); assert.strictEqual(selected, capacity); return ok({});
    },
    clientProgramSourceCaptureOriginalRead(actual) { assert.strictEqual(actual, owner); return read; },
    clientProgramSourceCaptureRetainInput(actual, selected, task) {
      assert.strictEqual(actual, owner); assert.strictEqual(selected, dag); assert.equal(task, 0);
      calls.push('retain-input'); return ok();
    },
    clientProgramSourceCaptureRetainTask() { assert.fail('Input read is not a completed Query task'); },
    clientProgramCloseSourceCapture(actual) {
      assert.strictEqual(actual, owner); calls.push('close'); return !pendingClose;
    },
  };
  const make = restore => {
    const continuation = acquiredEffectContinuation({moon, checkpoints,
      acquired: {prepared, runDefinition: {identity: 'original-definition'},
        control: {runDefinitionRunId: () => 'original-run'}},
      submission: {request: 'original-request'}, declaredResults: [], principalId: 'original-principal',
      unitId: 'original-unit', currentRun: () => current, restore});
    continuation.accessFor({authorization: {async authorize() {
      calls.push('current-authorize'); return {action: 'dispatch'};
    }}}, occurrence);
    return continuation;
  };
  const save = async () => {
    const original = make(); await original.prepared([source]);
    await original.captured(source, captured, 'original-evidence', 1, 2);
    return {original, saved: await original.retainAll()};
  };
  const cold = async saved => {
    const restored = make({view: {runId: 'original-run'}, continuation: saved});
    await restored.prepared([source]);
    return {restored, record: (await restored.beforeRead(source)).retained};
  };
  return {source, ledger, dag, read, captured, calls, records, save, cold,
    setWhole(value) {wholeCapacity = value;}, setMissingSource() {missingSource = true;},
    setPending(value) {pendingClose = value;}, revoke() {current = false;},
    retainedCurrent: () => retainedCurrent()};
}

test('Whole continuation forwards its original input and receiving Ledger without a Query projection or repeat read', async () => {
  const f = fixture(), {saved} = await f.save();
  const record = [...f.records.values()][0];
  assert.equal(record.input_kind, 'whole-input');
  for (const name of ['requirement_cid', 'descriptor', 'original_input']) assert(!Object.hasOwn(record, name));
  const {restored, record: retained} = await f.cold(saved);
  const {captured} = restored.restore(f.source, retained, f.ledger);
  assert.equal(captured.inputKind, 'whole-input'); assert(!Object.hasOwn(captured, 'requirement'));
  assert.strictEqual(captured.capture.originalRead(), f.read);
  captured.capture.retainTask(f.dag, 0);
  assert.deepEqual(f.calls, ['export-whole', 'current-authorize', 'restore-whole', 'retain-input']);
  assert.equal(f.retainedCurrent(), true); f.revoke(); assert.equal(f.retainedCurrent(), false);
  f.setPending(true);
  await assert.rejects(restored.close(), {code: 'SourceCaptureCleanupPending'});
  assert.equal(f.calls.includes('retire'), false);
  f.setPending(false); await restored.close();
  assert.deepEqual(f.calls.slice(-3), ['close', 'close', 'retire']);
});

test('Whole continuation rejects a mixed, malformed or substituted capture variant before restore', async () => {
  for (const fault of ['missing-kind', 'query-kind', 'unknown-kind', 'query-descriptor', 'query-original', 'bad-identity', 'bad-rows', 'query-owner']) {
    const f = fixture(), {saved} = await f.save();
    const record = [...f.records.values()][0];
    if (fault === 'missing-kind') delete record.input_kind;
    if (fault === 'query-kind') record.input_kind = 'query';
    if (fault === 'unknown-kind') record.input_kind = 'foreign';
    if (fault === 'query-descriptor') record.descriptor = {};
    if (fault === 'query-original') record.original_input = {};
    if (fault === 'bad-identity') record.source_identity = [null];
    if (fault === 'bad-rows') record.rows = [{}];
    if (fault === 'query-owner') f.setWhole(false);
    const {restored, record: retained} = await f.cold(saved);
    assert.throws(() => restored.restore(f.source, retained, f.ledger), {code: 'HeldAcquisitionChanged'}, fault);
    assert.equal(f.calls.includes('restore-whole'), false, fault);
    await restored.close();
  }
});

test('Whole persistence requires the same installed Whole capacity rather than the capture kind alone', async () => {
  const f = fixture(); f.setWhole(false);
  await assert.rejects(f.save(), {code: 'HeldAcquisitionChanged'});
  assert.equal(f.records.size, 0); assert.deepEqual(f.calls, []);
});

test('Whole restore retains its returned owner before a missing Source observation', async () => {
  const f = fixture(), {saved} = await f.save();
  const {restored, record} = await f.cold(saved); f.setMissingSource();
  assert.throws(() => restored.restore(f.source, record, f.ledger), {code: 'SourceCaptureCustodyUnavailable'});
  await restored.close(); assert.deepEqual(f.calls.slice(-2), ['close', 'retire']);
});

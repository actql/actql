// Pure continuation sequencing controls. Memory-backed checkpoint doubles do
// not prove physical capture, encrypted Store, authorization or public restart.
import assert from 'node:assert/strict';
import test from 'node:test';
import {acquiredEffectContinuation} from './acquired-effect-continuation.mjs';
import {boundSourceInventoryFixture} from './fixtures/ordinary-source-binding.fixture.mjs';

const LEGACY = 'actql-acquired-effect-continuation/0.1';
const BOUND = 'actql-acquired-effect-bound-continuation/0.1';
function fixture({legacy = false} = {}) {
  const entries = boundSourceInventoryFixture().acquisitions;
  const records = new Map(), calls = {binding: [0, 0], captureRestore: 0, source: 0};
  const sources = entries.map((entry, index) => {
    const {stage, input, task, installationBinding, ...prepared} = structuredClone(entry);
    const preparedSource = {...prepared, occurrence: {stage, input, task}};
    const adapter = legacy || index === 0 ? {} : {
      ordinaryRecoveryBinding(actual) {
        assert.equal(actual, preparedSource);
        calls.binding[index]++;
        return installationBinding;
      },
    };
    return {occurrence: {stage, input, task}, preparedSource, adapter};
  });
  const checkpoints = {
    async retainComputationSource(_run, _definition, wire) {
      const name = `capture-${records.size}`; records.set(name, wire); return name;
    },
    async computationSourceReferences() { return [...records.keys()]; },
    async readComputationSource(_view, name) { return Buffer.from(records.get(name)); },
    async retireComputationSources() {},
  };
  const moon = {
    clientProgramExportSourceCapture(source) { return {$tag: 1, _0: source}; },
    clientProgramSourceCaptureExportRequirement(source) { return entries[source.index].checkedSource.requirementCid; },
    clientProgramSourceCaptureExportDescriptor() { return 'independent-fixture-descriptor'; },
    clientProgramSourceCaptureExportRows() { return ['{"id":1}']; },
    clientProgramRestoreSourceCapture() { calls.captureRestore++; throw new Error('UnexpectedCaptureRestore'); },
  };
  const acquired = {runDefinition: {identity: 'original-definition'},
    control: {runDefinitionRunId: () => 'original-run'}};
  const make = restore => {
    const owner = acquiredEffectContinuation({moon, checkpoints, acquired,
      submission: {requestId: 'original-submission'}, declaredResults: ['joined'],
      principalId: 'fixture', unitId: 'original-unit', restore});
    for (const source of sources) owner.accessFor({authorization: {
      authorize() { calls.source++; throw new Error('UnexpectedAuthorization'); },
    }}, source.occurrence);
    return owner;
  };
  const capture = async () => {
    const owner = make();
    await owner.prepared(sources);
    for (const [index, source] of sources.entries()) {
      await owner.captured(source, {requirement: {}, capture: {source: () => ({index})}},
        'original-source-evidence', '2026-10-15T00:00:00.000Z', '2026-10-15T00:00:01.000Z');
    }
    return {owner, saved: await owner.retainAll()};
  };
  const restore = saved => make({continuation: saved, view: {runId: 'original-run'}}).prepared(sources);
  return {sources, records, calls, make, capture, restore, entries};
}

test('Effect continuation retains the issued binding only with its original mixed Source scope', async () => {
  const f = fixture(), {saved} = await f.capture();
  assert.equal(saved.version, BOUND);
  assert.equal(Object.hasOwn(saved.sources[0].scope, 'installationBinding'), false);
  assert.deepEqual(saved.sources[1].scope.installationBinding, f.entries[1].installationBinding);
  await f.restore(saved);
  assert.equal(f.calls.source, 0);
  assert.equal(f.calls.captureRestore, 0);
  assert.deepEqual(f.calls.binding, [0, 2]);
});

for (const field of ['connectorId', 'connectorRegistration', 'connectorRevision', 'bindingCid']) {
  test(`Effect retained scope refuses a changed original ${field} before capture restore`, async () => {
    const f = fixture(), {saved} = await f.capture();
    saved.sources[1].scope.installationBinding[field] = field === 'bindingCid'
      ? `sha256:${'d'.repeat(64)}` : 'foreign';
    await assert.rejects(f.restore(saved), {code: 'HeldAcquisitionChanged'});
    assert.equal(f.calls.captureRestore, 0); assert.equal(f.calls.source, 0);
  });
}

for (const fault of ['missing', 'extra', 'owner-missing', 'saved-target', 'saved-evidence-binding']) {
  test(`Effect bound continuation refuses ${fault} without current-configuration repair`, async () => {
    const f = fixture(), {saved} = await f.capture();
    if (fault === 'missing') delete saved.sources[1].scope.installationBinding;
    if (fault === 'extra') saved.sources[1].scope.installationBinding.extra = true;
    if (fault === 'owner-missing') delete f.sources[1].adapter.ordinaryRecoveryBinding;
    if (fault === 'saved-target') saved.sources[1].scope.physicalBinding.resource = 'foreign';
    if (fault === 'saved-evidence-binding') {
      const key = saved.sources[1].capture_cid;
      const record = JSON.parse(f.records.get(key));
      record.scope.installationBinding.connectorRevision = 'foreign';
      f.records.set(key, JSON.stringify(record));
    }
    await assert.rejects(f.restore(saved), {code: 'HeldAcquisitionChanged'});
    assert.equal(f.calls.captureRestore, 0); assert.equal(f.calls.source, 0);
  });
}

test('malformed issuing owner binding is refused before any retained capture is written', async () => {
  const f = fixture();
  f.sources[1].adapter.ordinaryRecoveryBinding = () => ({...f.entries[1].installationBinding, extra: true});
  await assert.rejects(f.make().prepared(f.sources), {code: 'HeldAcquisitionChanged'});
  assert.equal(f.records.size, 0); assert.equal(f.calls.source, 0);
});

test('legacy DuckDB-only continuation retains its original shape and bytes', async () => {
  const f = fixture({legacy: true}), {saved} = await f.capture();
  assert.equal(saved.version, LEGACY);
  assert(saved.sources.every(value => !Object.hasOwn(value.scope, 'installationBinding')));
  const original = JSON.stringify(saved);
  await f.restore(saved);
  assert.equal(JSON.stringify(saved), original);
  assert.equal(f.calls.source, 0);
});

test('legacy binding-free row scope is not upgraded from a current installation', async () => {
  const f = fixture({legacy: true}), {saved} = await f.capture();
  const original = JSON.stringify(saved);
  f.sources[1].adapter.ordinaryRecoveryBinding = () => f.entries[1].installationBinding;
  await assert.rejects(f.restore(saved), {code: 'HeldAcquisitionChanged'});
  assert.equal(JSON.stringify(saved), original);
  assert.equal(f.calls.source, 0); assert.equal(f.calls.captureRestore, 0);
});

function sourceFreeModelRestoreFixture({checkedCount = 0, changeSaved} = {}) {
  const prepared = {}, submission = {requestId: 'same-original-submission'};
  let reads = 0;
  const unavailable = Object.assign(new Error('ContinuationEvidenceNotFound'), {code: 'ContinuationEvidenceNotFound'});
  const checkpoints = {async computationSourceReferences() {reads++; throw unavailable;}};
  const options = {checkpoints, moon: {clientProgramEffectAcquisitionCount(value) {
    assert.strictEqual(value, prepared); return checkedCount;
  }}, acquired: {prepared, runDefinition: {identity: 'same-definition'},
    control: {runDefinitionRunId: () => 'same-run'}}, submission, unitId: 'same-unit', declaredResults: []};
  return {async restore() {
    const fresh = acquiredEffectContinuation(options);
    await fresh.prepared([]);
    const saved = await fresh.retainAll();
    changeSaved?.(saved);
    const restored = acquiredEffectContinuation({...options,
      restore: {view: {kind: 'model_invocation', prepareAttemptId: null}, continuation: saved}});
    await restored.prepared([]);
    return restored;
  }, unavailable, reads: () => reads};
}

test('source-free Model restoration retains its actual empty Source inventory without opening an unissued Source ledger', async () => {
  const f = sourceFreeModelRestoreFixture();
  const restored = await f.restore();
  assert.equal(restored.restoringModel, true); assert.equal(f.reads(), 0);
});

test('source-free Model restoration still validates its exact saved Source closure before skipping Source storage', async () => {
  for (const changeSaved of [saved => {saved.run_definition_cid = 'foreign';},
    saved => {saved.sources.push({scope: {task: 0}});}, saved => {saved.pending_task = 0;}]) {
    const f = sourceFreeModelRestoreFixture({changeSaved});
    await assert.rejects(f.restore(), {code: 'HeldAcquisitionChanged'});
    assert.equal(f.reads(), 0);
  }
});

test('a nonzero checked Source inventory never treats an absent Source ledger as source-free Model recovery', async () => {
  const f = sourceFreeModelRestoreFixture({checkedCount: 1});
  await assert.rejects(f.restore(), error => error === f.unavailable);
  assert.equal(f.reads(), 1);
});

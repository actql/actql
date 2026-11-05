import assert from 'node:assert/strict';
import test from 'node:test';
import {runInstalledComposedInfers} from './installed-composed-infer-run.mjs';
import {boundSourceInventoryFixture} from './fixtures/ordinary-source-binding.fixture.mjs';

// The actual composed caller and continuation execute with explicit physical
// ports. These cases prove original forwarding, not a funded/installed Host.
function fixture({refuseSecond = false, single = false, retainedAdapter = true} = {}) {
  const calls = [], stopped = new Error('AfterOriginalSourceBinding');
  const refused = new Error('OriginalSourceOwnerRefused');
  let custody, setups = 0;
  const sources = boundSourceInventoryFixture().acquisitions.map((entry, index) => {
    const {stage, input, task, installationBinding, ...fields} = entry;
    const occurrence = Object.freeze({stage, input, task});
    const preparedSource = Object.freeze({...fields, occurrence});
    const adapter = Object.freeze({ordinaryRecoveryBinding(actual) {
      assert.strictEqual(this, adapter);
      assert.strictEqual(actual, preparedSource);
      calls.push(index);
      if (single) throw stopped;
      if (refuseSecond && index === 1) throw refused;
      return installationBinding;
    }});
    return {adapter, occurrence, preparedSource, access: {authorization: {}},
      captured: {capture: {source: () => ({index})}}, sourceEvidenceWire: 'original-evidence'};
  });
  const arguments_ = {
    moon: {
      clientProgramResultCount: () => 0,
      clientProgramOpenMultiCapturedComposedInferHost() {
        setups++;
        assert.deepEqual(calls, [0, 1]);
        throw stopped;
      },
    },
    control: {runDefinitionRunId: () => 'original-run'},
    preparedProgram: {}, plan: {runDefinition: {identity: 'original-definition', wire: '{"run_id":"original-run"}'}},
    selected: {components: []}, acquiredInfer: {sources, ledger: {},
      captureStartedAt: '2026-10-20T00:00:00.000Z', captureCompletedAt: '2026-10-20T00:00:01.000Z'},
    modelController: {discover: () => []}, checkpoints: {async retireComputationSources() {}},
    computeConfigurations: {}, signal: new AbortController().signal,
    retainExecution(value) {assert.equal(custody, undefined); custody = value;},
  };
  if (single) {
    arguments_.acquiredInfer = {captured: sources[0].captured, preparedSource: sources[0].preparedSource,
      ...(retainedAdapter ? {adapter: sources[0].adapter} : {}), sourceAccess: sources[0].access};
    arguments_.prepareAcquisition = () => assert.fail('reuse the original preparation');
    arguments_.sourceAccessFor = prepared => {assert.equal(prepared, sources[0].preparedSource); return sources[0].access;};
    arguments_.sourceAdapterFor = prepared => {assert.equal(prepared, sources[0].preparedSource); return sources[0].adapter;};
  }
  return {arguments_, calls, stopped, refused, setups: () => setups, custody: () => custody};
}

test('composed INFER forwards both original Source adapters before installing the driver', async () => {
  const f = fixture();
  await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.stopped);
  assert.deepEqual(f.calls, [0, 1]);
  assert.equal(f.setups(), 1);
  assert.equal(await f.custody().close(), true);
  assert.equal(f.custody().cleanupPending(), false);
});

test('composed INFER preserves the same Source owner refusal before driver work', async () => {
  const f = fixture({refuseSecond: true});
  await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.refused);
  assert.deepEqual(f.calls, [0, 1]);
  assert.equal(f.setups(), 0);
  assert.equal(await f.custody().close(), true);
});

for (const retainedAdapter of [true, false]) {
  test(`single composed INFER keeps its original Source adapter (retained=${retainedAdapter})`, async () => {
    const f = fixture({single: true, retainedAdapter});
    await assert.rejects(runInstalledComposedInfers(f.arguments_), error => error === f.stopped);
    assert.deepEqual(f.calls, [0]); assert.equal(f.setups(), 0);
    assert.equal(await f.custody().close(), true);
  });
}

test('single composed INFER refuses a missing original Source owner before binding or driver work', async () => {
  const f = fixture({single: true, retainedAdapter: false});
  delete f.arguments_.sourceAdapterFor;
  await assert.rejects(runInstalledComposedInfers(f.arguments_), {message: 'InstalledComposedInferSourceOwnerUnavailable'});
  assert.deepEqual(f.calls, []); assert.equal(f.setups(), 0);
  assert.equal(await f.custody().close(), true);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {selectAcquiredEffectPlanInputs, selectAcquiredEffectSources,
  prepareInstalledAcquiredEffectLedger} from './acquired-effect-sources.mjs';

// Actual inert Node selection with explicit checked Plan/Request/resource
// ports. These observations do not execute a Source or prove Core funding.
const ok = _0 => ({$tag: 1, _0});
function fixture({coordinates = [[2, 1, 0, 4], [2, 3, 1, 4], [6, 0, 2, 9]], count = 3} = {}) {
  const prepared = {}, request = {}, parent = {}, calls = [];
  const declaration = {}, provider = {}, inputLimits = {};
  const adapter = Object.freeze({realizationKey: 'row-source-acquired',
    supportsRetainedRelationOutput: true,
    admitsSource: ref => ref === 'same-backend',
    prepare() {assert.fail('Selection is not physical acquisition');},
    open() {assert.fail('Selection is not physical acquisition');},
    managedEffectPlanSelection() {
      return {declaration, provider, inputLimits, transferBytes: 7n, executionBytes: 11n};
    },
    ledgerCapacity(original) {calls.push(['capacity', original]);return original;},
  });
  const moon = {
    clientProgramEffectAcquisitionCount: () => count,
    clientProgramEffectDirectSourceCoordinates(actual) {
      assert.strictEqual(actual, prepared);return ok(coordinates);
    },
    clientProgramSelectInstalledEffectSourceInput(actual, identity, stage, input) {
      assert.strictEqual(actual, prepared);assert.strictEqual(identity, request);
      calls.push(['select', stage, input]);return ok({stage, input});
    },
    clientProgramSelectedSourceInputKind: route => route.stage === 6 ? 'query' : 'whole-input',
    clientProgramSelectedSourceInputRef: () => 'same-backend',
    clientProgramInstalledEffectRowSourceInputPrepare(d, p, limits) {
      assert.strictEqual(d, declaration);assert.strictEqual(p, provider);
      assert.strictEqual(limits, inputLimits);return ok({declaration, provider, inputLimits});
    },
    clientProgramInstalledEffectManagedRunPrepareLedger(actual, owner, identity, capacities, transfer, execution) {
      assert.strictEqual(actual, parent);assert.strictEqual(owner, prepared);
      assert.strictEqual(identity, request);calls.push(['ledger', capacities, transfer, execution]);
      return ok({parent});
    },
  };
  return {moon, prepared, request, parent, adapter, calls,
    options: {moon, preparedEffect: prepared, requestIdentity: request, sourceProfile: {sources: [adapter]}}};
}

test('three mixed Source occurrences preserve repeated backing, exact ports and sparse Compute tasks', () => {
  const f = fixture();
  const plan = selectAcquiredEffectPlanInputs(f.options);
  assert.equal(plan.inputs.length, 3);
  assert.deepEqual(plan.transferBytes, [7n, 7n, 7n]);
  assert.deepEqual(plan.executionBytes, [11n, 11n, 11n]);
  const selected = selectAcquiredEffectSources(f.options);
  assert.equal(selected.length, 3);
  assert.ok(selected.every(value => value.adapter === f.adapter));
  assert.deepEqual(selected.map(value => value.sourceKind), ['whole-input', 'whole-input', 'query']);
  assert.deepEqual(selected.map(value => value.occurrence), [
    {stage: 2, input: 1, task: 0, computeTask: 4},
    {stage: 2, input: 3, task: 1, computeTask: 4},
    {stage: 6, input: 0, task: 2, computeTask: 9},
  ]);
  assert.deepEqual(f.calls.filter(value => value[0] === 'select'), [
    ['select', 2, 1], ['select', 2, 3], ['select', 6, 0],
    ['select', 2, 1], ['select', 2, 3], ['select', 6, 0],
  ]);
});

test('each selected Source occurrence contributes its original capacity to the same managed parent', () => {
  const f = fixture();
  const selected = selectAcquiredEffectSources(f.options);
  const capacities = selected.map((_, index) => ({managedRun: f.parent, capacity: {index},
    transferBytes: BigInt(index + 1), executionBytes: BigInt(index + 4)}));
  const sources = selected.map((value, index) => ({...value, preparedSource: capacities[index]}));
  assert.strictEqual(prepareInstalledAcquiredEffectLedger({...f.options, sources}).parent, f.parent);
  assert.deepEqual(f.calls.at(-1), ['ledger', capacities.map(value => value.capacity), [1n, 2n, 3n], [4n, 5n, 6n]]);
  const foreign = sources.map((value, index) => index === 1 ? {...value,
    preparedSource: {...value.preparedSource, managedRun: {}}} : value);
  const ledgersBefore = f.calls.filter(value => value[0] === 'ledger').length;
  assert.throws(() => prepareInstalledAcquiredEffectLedger({...f.options, sources: foreign}), /InstalledEffectOriginalRunUnavailable/);
  assert.equal(f.calls.filter(value => value[0] === 'ledger').length, ledgersBefore);
});

test('invalid count, duplicate original port, foreign slot or incomplete inventory refuses before provider selection', () => {
  for (const options of [{count: -1}, {count: 1.5}, {count: NaN},
    {coordinates: [[2, 1, 0, 4], [2, 1, 1, 4], [6, 0, 2, 9]]},
    {coordinates: [[2, 1, 0, 4], [2, 3, 0, 4], [6, 0, 2, 9]]},
    {coordinates: [[2, 1, 0, 4], [6, 0, 1, 9]]}]) {
    const f = fixture(options);
    assert.throws(() => selectAcquiredEffectPlanInputs(f.options), /UnsupportedEffectSourceCount|InvalidInstalledEffectSourceCoordinates/);
    assert.deepEqual(f.calls, []);
  }
});

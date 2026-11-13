import assert from 'node:assert/strict';
import test from 'node:test';
import {selectAcquiredEffectPlanInputs, selectAcquiredEffectSources,
  prepareInstalledAcquiredEffectLedger} from './acquired-effect-sources.mjs';
import {openAcquiredEffectComputation} from './acquired-effect-computation.mjs';

// Actual inert Node selection with explicit checked Plan/Request/resource
// ports. These observations do not execute a Source or prove Core funding.
const ok = _0 => ({$tag: 1, _0});
function fixture({coordinates = [[2, 1, 0, 4], [2, 3, 1, 4], [6, 0, 2, 9]], count = 3,
  prepareFailure} = {}) {
  const prepared = {}, request = {}, parent = {}, plan = {}, calls = [];
  const counters = {fullSelections: 0, planProjections: 0, preparations: 0};
  const declaration = {}, provider = {}, inputLimits = {};
  const adapter = Object.freeze({realizationKey: 'row-source-acquired',
    supportsRetainedRelationOutput: true,
    admitsSource: ref => ref === 'same-backend',
    prepare() {
      counters.preparations++;
      if (prepareFailure !== undefined) throw prepareFailure;
      assert.fail('Selection is not physical acquisition');
    },
    open() {assert.fail('Selection is not physical acquisition');},
    managedEffectPlanSelection() {
      return {declaration, provider, inputLimits, transferBytes: 7n, executionBytes: 11n};
    },
    ledgerCapacity(original) {calls.push(['capacity', original]);return original;},
  });
  const moon = {
    clientProgramEffectAcquisitionCount: () => count,
    clientProgramEffectDirectSourceCoordinates(actual) {
      counters.fullSelections++;
      assert.strictEqual(actual, prepared);return ok(coordinates);
    },
    clientProgramInstalledEffectManagedPlanSourceCoordinates(actual, owner, identity) {
      assert.strictEqual(actual, plan);assert.strictEqual(owner, prepared);
      assert.strictEqual(identity, request);counters.planProjections++;return ok(coordinates);
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
  return {moon, prepared, request, parent, plan, adapter, calls, counters,
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

test('real preplan/open flow projects retained Plan coordinates once and keeps mutable current checks', async () => {
  const failure = new Error('OriginalSourcePreparationRefused');
  const f = fixture({prepareFailure: failure});
  selectAcquiredEffectPlanInputs(f.options);
  const selection = selectAcquiredEffectSources({...f.options, managedPlan: f.plan});
  let custody, current = 0;
  f.moon.clientProgramEffectSerializationOccurrences = () => [];
  f.moon.clientProgramInstalledEffectManagedOperationPlan = (parent, prepared, request) => {
    assert.strictEqual(parent, f.parent);assert.strictEqual(prepared, f.prepared);
    assert.strictEqual(request, f.request);return ok(f.plan);
  };
  f.moon.clientProgramInstalledEffectManagedHostOpen = () => assert.fail('No provider or Host entry');
  await assert.rejects(openAcquiredEffectComputation({moon: f.moon,
    acquired: {prepared: f.prepared, requestIdentity: f.request}, managedRun: f.parent,
    sourceProfile: f.options.sourceProfile, sourceSelection: selection, sourceSelectionPlan: f.plan,
    retainComputationOwner(value) {custody = value;}, assertUpdateSelectionCurrent() {current++;},
  }), error => error === failure);
  assert.deepEqual(f.counters, {fullSelections: 1, planProjections: 1, preparations: 1});
  assert.ok(current > 0, 'immutable reuse does not remove mutable current fences');
  await custody.close();assert.equal(await custody.cleanup(), true);

  const currentFailure = new Error('CurrentOwnerChanged');
  await assert.rejects(openAcquiredEffectComputation({moon: f.moon,
    acquired: {prepared: f.prepared, requestIdentity: f.request}, managedRun: f.parent,
    sourceProfile: f.options.sourceProfile, sourceSelection: selection, sourceSelectionPlan: f.plan,
    retainComputationOwner() {}, assertUpdateSelectionCurrent() {throw currentFailure;},
  }), error => error === currentFailure);
  assert.deepEqual(f.counters, {fullSelections: 1, planProjections: 1, preparations: 1});
});

test('a retained installation selection cannot substitute another original Plan', async () => {
  const f = fixture();
  const selection = selectAcquiredEffectSources({...f.options, managedPlan: f.plan});
  f.moon.clientProgramEffectSerializationOccurrences = () => [];
  f.moon.clientProgramInstalledEffectManagedOperationPlan = () => ok({});
  f.moon.clientProgramInstalledEffectManagedHostOpen = () => assert.fail('No Host entry');
  let custody;
  await assert.rejects(openAcquiredEffectComputation({moon: f.moon,
    acquired: {prepared: f.prepared, requestIdentity: f.request}, managedRun: f.parent,
    sourceProfile: f.options.sourceProfile, sourceSelection: selection, sourceSelectionPlan: f.plan,
    retainComputationOwner(value) {custody = value;},
  }), /ForeignInstalledEffectSourceSelection/);
  assert.equal(f.counters.preparations, 0);
  await custody.close();assert.equal(await custody.cleanup(), true);
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

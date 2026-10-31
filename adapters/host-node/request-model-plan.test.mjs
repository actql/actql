import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Actual Host constructor with explicit Core/current/installation ports.
// This does not issue Common originals or prove physical constructor backing.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'prepareRequestMockModelPlan');
assert(node);
function fixture({count = 0, timed = false, missingCapacity = false, expire = false} = {}) {
  const parent = {}, input = {}, prepared = {}, request = {}, compilation = {}, module = {}, plan = {};
  const graph = {}, occurrence = {}, bounds = {}, q = {}, admission = {}, initialControl = {};
  const declarations = [{}, {}], requirements = [{}, {}], acquisitions = [{}, {}], capacities = [{}, {}];
  const calls = [], model = {graph, occurrence, compiled: {}, runDefinition: {}, scope: undefined};
  const run = {prepared, request, model, queryTimePreparation: timed ? q : undefined};
  let current = true;
  const primary = new Error('original-installation-current');
  const ok = value => ({$tag: 1, _0: value});
  const contracts = {values: 'values', expression: 'fragment', ordered: 'ordered'};
  const control = {
    prepareCheckedClientMockModelSourceFreePlan(...args) {
      assert.deepEqual(args, [module, request, model.compiled, model.runDefinition, occurrence, graph, bounds]);
      calls.push('bind-source-free'); return plan;
    },
    bindCheckedClientMockModelCapturePlan(...args) {
      assert.deepEqual(args, [module, model.compiled, model.runDefinition, occurrence, graph, bounds]);
      calls.push('bind-captured'); return plan;
    },
  };
  model.control = control;
  const moon = {
    clientProgramAcquisitionCount: value => {assert.equal(value, prepared); return count;},
    clientProgramPreparedComposedInferBounds(o, g) {
      assert.equal(o, occurrence); assert.equal(g, graph); calls.push('bounds'); return ok(bounds);
    },
    clientProgramComposedInferRetainedLimits(value) {
      assert.equal(value, bounds); return [11n, 12n, 13n, 14n, 15n, 16n, 17n, 18n, 19n];
    },
    clientProgramPrepareInstalledMockModelSourceFreeWithContracts(...args) {
      assert.deepEqual(args, [prepared, compilation, admission, 'values', 'fragment', 'ordered', true]);
      assert.equal(model.selectedBounds, bounds); assert.equal(model.budget.readRetainedBytes, 13n);
      calls.push('source-free-module'); if (expire) current = false; return ok(module);
    },
    clientProgramPrepareLocalQueryRequirement(...args) {
      const stage = args[1]; assert.equal(timed, false);
      assert.deepEqual(args, [prepared, stage, 0, admission, 'values', 'fragment', 'ordered']);
      calls.push('requirement'+stage); return ok(requirements[stage]);
    },
    clientProgramPrepareLocalQueryRequirementAtQueryTime(...args) {
      const stage = args[1]; assert.equal(timed, true);
      assert.deepEqual(args, [prepared, stage, 0, q, request, admission, 'values', 'fragment', 'ordered']);
      calls.push('timed-requirement'+stage); return ok(requirements[stage]);
    },
    clientProgramRowSourcePrepareAcquisition(declaration, requirement, query, evidence) {
      const index = declarations.indexOf(declaration); assert(index >= 0);
      assert.equal(requirement, requirements[index]); assert.equal(query, 'query'); assert.equal(evidence, 'evidence');
      calls.push('acquisition'+index); return ok(acquisitions[index]);
    },
    clientProgramInstalledRowCaptureCapacity(acquisition) {
      const index = acquisitions.indexOf(acquisition); assert(index >= 0);
      calls.push('capacity'+index); return missingCapacity && index === 1 ? undefined : capacities[index];
    },
    clientProgramInstalledMockModelCapturePlanPrepare(...args) {
      assert.deepEqual(args, [prepared, request, compilation, capacities,
        [1048576n, 1048576n], [1048576n, 1048576n], admission, 'values', 'fragment', 'ordered', true, timed ? q : undefined]);
      assert.equal(args[4], args[5], 'Reuse the original fixed document bound vector');
      calls.push('captured-module'); return ok(module);
    },
  };
  run.runtime = moon;
  const originals = {installation: {projectRuntime: moon, initialControl, retainedRelationOutput: true,
    computeRuns: new WeakMap([[prepared, run]])}};
  const ports = {assertSourceManagedHostPreparation(value) {
    assert.equal(value, originals); if (!current) throw primary;
  }, originalSourceManagedHostRequest(value, p) {assert.equal(value, originals); assert.equal(p, prepared);},
  prepareInstalledSequenceContractOriginal: () => ({moon, control: initialControl, contracts, admission}),
  runtimeCore: actual => {assert.equal(actual, moon); return {publicationControl: control};},
  checked: value => {assert.equal(value.$tag, 1); return value._0;},
  clientOperationError: code => Object.assign(new Error(code), {code}),
  readInstalledMockPreparation: () => ({sources: declarations.map(declaration => ({declaration}))}),
  readInitialControlInstallationAsset(c, o, path) {
    assert.equal(c, initialControl); assert.equal(o, originals);
    return path.endsWith('actql-query-acquisition.json') ? 'query' : 'evidence';
  }};
  const construct = Function(...Object.keys(ports), `return (${source.slice(node.start, node.end)});`)(...Object.values(ports));
  return {run, model, compilation, module, plan, bounds, capacities, acquisitions, calls, primary,
    construct: () => construct(originals, run, model, compilation, parent, input)};
}

test('Request Model constructs its actual source-free module from the original compiler and selected bounds', () => {
  const f = fixture(); assert.equal(f.construct(), f.plan);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.modelPlan, f.plan);
  assert.deepEqual(f.calls, ['bounds', 'source-free-module', 'bind-source-free']);
  assert.deepEqual(f.model.budget, {bootstrapRetainedBytes: 11n, bootstrapExecutionBytes: 12n,
    readRetainedBytes: 13n, readExecutionBytes: 14n, modelRetainedBytes: 15n, modelExecutionBytes: 16n,
    maxReservations: 17, maxHoldings: 18, maxDelegations: 19});
});

test('Request Model retains both actual query acquisitions and its original optional QueryTime before binding', () => {
  for (const timed of [false, true]) {
    const f = fixture({count: 2, timed}); assert.equal(f.construct(), f.plan);
    assert.deepEqual(f.run.modelAcquisitions.map(value => value.acquisition), f.acquisitions);
    assert.deepEqual(f.run.modelAcquisitions.map(value => value.capacity), f.capacities);
    assert.deepEqual(f.calls, ['bounds', (timed ? 'timed-' : '')+'requirement0', 'acquisition0', 'capacity0',
      (timed ? 'timed-' : '')+'requirement1', 'acquisition1', 'capacity1', 'captured-module', 'bind-captured']);
  }
});

test('Request Model keeps partial original acquisitions and module output when later validation fails', () => {
  const f = fixture({count: 2, missingCapacity: true});
  assert.throws(f.construct, {code: 'InstalledSourceCapacityUnavailable'});
  assert.equal(f.run.modelAcquisitions[1].acquisition, f.acquisitions[1]);
  assert.equal(f.run.modelAcquisitions[1].capacity, undefined);
  assert(!f.calls.includes('captured-module'));
  const g = fixture({expire: true}); assert.throws(g.construct, error => error === g.primary);
  assert.equal(g.run.preparedSequences, g.module); assert(!g.calls.includes('bind-source-free'));
});

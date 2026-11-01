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
function fixture({count = 0, timed = false, refuseCapture, expire = false, missingModule = false,
  serialized = false, expirePrefix = false, missingPrefix = false, physical = false, missingPhysical = false, missingProvider = false, expireProvider = false} = {}) {
  const parent = {}, input = {}, prepared = {}, request = {}, compilation = {}, module = {}, plan = {};
  const graph = {}, occurrence = {}, bounds = {}, q = {}, admission = {}, initialControl = {};
  const declarations = [{}, {}], provider = {}, sourceRef = {}, selectedSource = {};
  const sourceProfile = {sources: []};
  const calls = [], model = {graph, occurrence, compiled: {}, runDefinition: {}, scope: undefined};
  const run = {prepared, request, model, queryTimePreparation: timed ? q : undefined};
  const serializationGraph = {}, prefix = {}, prefixLimits = {}, workspace = {};
  if (serialized) {
    model.serializationGraph = serializationGraph;
    const contentControl = {prepareModelRequestPrefix(...args) {
      assert.equal(this, contentControl);
      assert.deepEqual(args, [parent, input, request, model.compiled, model.runDefinition,
        prefixLimits, workspace, timed ? q : undefined]);
      assert.equal(model.selectedBounds, bounds);
      calls.push('same Request prefix');
      if (expirePrefix) current = false;
      return prefix;
    }};
    if (missingPrefix) delete contentControl.prepareModelRequestPrefix;
    run.contentPreparation = {prepared, managed: run, contentControl, prefixLimits, workspace,
      plan: {compiled: model.compiled, runDefinition: model.runDefinition, serializationGraph}};
  }
  let current = true;
  const primary = new Error('original-installation-current');
  const ok = value => ({$tag: 1, _0: value});
  const contracts = {values: 'values', expression: 'fragment', ordered: 'ordered'};
  const control = {
    prepareCheckedClientRequestModelSourceFreePlan(...args) {
      assert.deepEqual(args, [parent, input, module, request, model.compiled, model.runDefinition, occurrence, graph, bounds]);
      assert.equal(physical, false, 'The Node installation must select its actual layout-bound Plan');
      calls.push('bind-source-free'); return plan;
    },
    bindCheckedClientMockModelCapturePlan(...args) {
      assert.deepEqual(args, [module, model.compiled, model.runDefinition, occurrence, graph, bounds]);
      calls.push('bind-captured'); return plan;
    },
  };
  if (physical) {
    model.originalReadInstallation = Object.freeze({nodeInstallation: Object.freeze({layout: Object.freeze({
      retained_bytes: 70n, execution_bytes: 30n}), installation: {}, runtimeArtifactCid: 'runtime', layoutArtifactCid: 'layout', probability: undefined}),
      modelRetainedBytes: 90n, modelExecutionBytes: 40n,
      bootstrap: Object.freeze({maxReservations: 21, maxHoldings: 22, maxDelegations: 23})});
    control.prepareCheckedClientRequestNodeModelSourceFreePlan = function(...args) {
      assert.equal(this, control);
      assert.deepEqual(args, [parent, input, module, request, model.compiled, model.runDefinition,
        occurrence, graph, bounds, model.originalReadInstallation]);
      calls.push('bind-Node-layout'); return plan;
    };
    control.prepareCheckedClientRequestNodeModelCapturePlan = function(...args) {
      assert.equal(this, control);
      assert.deepEqual(args, [parent, input, module, request, model.compiled, model.runDefinition,
        occurrence, graph, bounds, model.originalReadInstallation]);
      calls.push('bind-Node-capture-layout'); return plan;
    };
    if (missingPhysical) {
      delete control.prepareCheckedClientRequestNodeModelSourceFreePlan;
      delete control.prepareCheckedClientRequestNodeModelCapturePlan;
    }
  }
  model.control = control;
  const moon = {
    clientProgramSelectInstalledSourceInput(p, stage, index) {
      assert.equal(p, prepared); assert.equal(stage, 0); assert.equal(index, 0); return ok(selectedSource);
    },
    clientProgramInstalledSourceInputKind(value) {assert.equal(value, selectedSource); return 'query';},
    clientProgramInstalledSourceInputRef(value) {assert.equal(value, selectedSource); return sourceRef;},
    clientProgramPrepareRequestModelProviderCaptureModule(...args) {
      assert.deepEqual(args, [parent, input, request, model.compiled, model.runDefinition, compilation,
        declarations[0], provider, 'query', 'evidence', 512n, 256n,
        admission, true, timed ? q : undefined]);
      assert.equal(run.serialization, prefix);
      calls.push('provider-capture-module'); if (expire) current = false; return ok(module);
    },
    clientProgramAcquisitionCount: value => {assert.equal(value, prepared); return count;},
    clientProgramPreparedComposedInferBounds(o, g) {
      assert.equal(o, occurrence); assert.equal(g, graph); calls.push('bounds'); return ok(bounds);
    },
    clientProgramComposedInferRetainedLimits(value) {
      assert.equal(value, bounds); return [11n, 12n, 13n, 14n, 15n, 16n, 17n, 18n, 19n];
    },
    clientProgramPrepareRequestModelSourceFreeModule(...args) {
      assert.deepEqual(args, [parent, input, request, model.compiled, model.runDefinition,
        compilation, admission, true, timed ? q : undefined]);
      assert.equal(model.selectedBounds, bounds); assert.equal(model.budget.readRetainedBytes, physical ? 70n : 13n);
      if (serialized) assert.equal(run.serialization, prefix, 'Retain original prefix before module constructor');
      calls.push('source-free-module'); if (expire) current = false; return ok(module);
    },
    clientProgramPrepareRequestModelCaptureModule(...args) {
      assert.deepEqual(args, [parent, input, request, model.compiled, model.runDefinition, compilation,
        declarations, 'query', 'evidence', [1048576n, 1048576n], [1048576n, 1048576n],
        admission, true, timed ? q : undefined]);
      assert.equal(args[9], args[10], 'Reuse the original fixed document bound vector');
      calls.push('captured-module'); if (refuseCapture) throw refuseCapture;
      if (expire) current = false; return ok(module);
    },
  };
  for (const name of ['clientProgramPrepareInstalledMockModelSourceFreeWithContracts',
    'clientProgramInstalledMockModelCapturePlanPrepare', 'clientProgramPrepareLocalQueryRequirement',
    'clientProgramPrepareLocalQueryRequirementAtQueryTime', 'clientProgramRowSourcePrepareAcquisition',
    'clientProgramInstalledRowCaptureCapacity']) moon[name] = () => assert.fail('legacy unbacked Model constructor');
  if (missingModule) {
    delete moon.clientProgramPrepareRequestModelSourceFreeModule;
    delete moon.clientProgramPrepareRequestModelCaptureModule;
    delete moon.clientProgramPrepareRequestModelProviderCaptureModule;
  }
  run.runtime = moon;
  const originals = {installation: {projectRuntime: moon, initialControl, retainedRelationOutput: true,
    computeRuns: new WeakMap([[prepared, run]]), managedSourceProfile: sourceProfile}};
  run.sourceProfile = sourceProfile;
  const adapter = {managedEffectPlanSelection() {
    assert.equal(this, adapter); calls.push('original provider selection');
    if (expireProvider) current = false;
    return Object.freeze({declaration: declarations[0], provider: missingProvider ? undefined : provider,
      transferBytes: 512n, executionBytes: 256n});
  }};
  const ports = {assertSourceManagedHostPreparation(value) {
    assert.equal(value, originals); if (!current) throw primary;
  }, originalSourceManagedHostRequest(value, p) {assert.equal(value, originals); assert.equal(p, prepared);},
  prepareInstalledSequenceContractOriginal: () => ({moon, control: initialControl, contracts, admission}),
  runtimeCore: actual => {assert.equal(actual, moon); return {publicationControl: control};},
  checked: value => {assert.equal(value.$tag, 1); return value._0;},
  clientOperationError: code => Object.assign(new Error(code), {code}),
  installedSourceFor(profile, ref) {assert.equal(profile, sourceProfile); assert.equal(ref, sourceRef); return adapter;},
  readInstalledMockPreparation: () => ({sources: declarations.map(declaration => ({declaration}))}),
  readInitialControlInstallationAsset(c, o, path) {
    assert.equal(c, initialControl); assert.equal(o, originals);
    return path.endsWith('actql-query-acquisition.json') ? 'query' : 'evidence';
  }};
  const construct = Function(...Object.keys(ports), `return (${source.slice(node.start, node.end)});`)(...Object.values(ports));
  return {run, model, compilation, module, plan, bounds, calls, primary, prefix,
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

test('Request Model constructs both actual query acquisitions only inside same Request module with original QueryTime', () => {
  for (const timed of [false, true]) {
    const f = fixture({count: 2, timed}); assert.equal(f.construct(), f.plan);
    assert.equal(f.run.modelAcquisitions, undefined);
    assert.deepEqual(f.calls, ['bounds', 'captured-module', 'bind-captured']);
  }
});

test('Request Model keeps original native refusal and retained module output for same Request cleanup', () => {
  const primary = new Error('original Request capture refusal'), f = fixture({count: 2, refuseCapture: primary});
  assert.throws(f.construct, cause => cause === primary);
  assert.equal(f.run.preparedSequences, undefined); assert.equal(f.run.modelAcquisitions, undefined);
  assert.deepEqual(f.calls, ['bounds', 'captured-module']);
  const g = fixture({expire: true}); assert.throws(g.construct, error => error === g.primary);
  assert.equal(g.run.preparedSequences, g.module); assert(!g.calls.includes('bind-source-free'));
});

test('Request Model refuses absent Request module ports before any legacy constructor can run', () => {
  for (const count of [0, 2]) {
    const f = fixture({count, missingModule: true});
    assert.throws(f.construct, {code: count === 0 ? 'NodeManagedRunRuntimeUnavailable' : 'InstalledMockModelOperationalAdmissionUnavailable'});
    assert.deepEqual(f.calls, ['bounds']); assert.equal(f.run.preparedSequences, undefined);
  }
});


test('Request mixed Model constructs the same prefix before module and binds its Plan through original parent and input', () => {
  const f = fixture({serialized: true, timed: true});
  assert.equal(f.construct(), f.plan);
  assert.equal(f.run.serialization, f.prefix);
  assert.deepEqual(f.calls, ['bounds', 'same Request prefix', 'source-free-module', 'bind-source-free']);
  const missing = fixture({serialized: true, missingPrefix: true});
  assert.throws(missing.construct, {code: 'InstalledContentRunPreparationUnavailable'});
  assert.deepEqual(missing.calls, ['bounds']);
});

test('Request mixed Model retains returned prefix through current refusal before module or Plan replacement', () => {
  const f = fixture({serialized: true, expirePrefix: true});
  assert.throws(f.construct, cause => cause === f.primary);
  assert.equal(f.run.serialization, f.prefix);
  assert.equal(f.run.preparedSequences, undefined);
  assert.equal(f.run.modelPlan, undefined);
  assert.deepEqual(f.calls, ['bounds', 'same Request prefix']);
});


test('Request Node Model caller retains actual installation extents and binds the same module and bounds', () => {
  const f = fixture({physical: true, serialized: true});
  assert.equal(f.construct(), f.plan);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.modelPlan, f.plan);
  assert.deepEqual(f.calls, ['bounds', 'same Request prefix', 'source-free-module', 'bind-Node-layout']);
  assert.equal(f.model.budget.readRetainedBytes, 70n); assert.equal(f.model.budget.readExecutionBytes, 30n);
  assert.equal(f.model.budget.modelRetainedBytes, 90n); assert.equal(f.model.budget.modelExecutionBytes, 40n);
  assert.equal(f.model.budget.maxReservations, 21); assert.equal(f.model.budget.maxHoldings, 22);
  assert.equal(f.model.budget.maxDelegations, 23);
});

test('Request Node Model caller refuses absent layout-bound Plan and keeps partial module through current failure', () => {
  const missing = fixture({physical: true, missingPhysical: true});
  assert.throws(missing.construct, {code: 'NodeManagedRunRuntimeUnavailable'});
  assert(!missing.calls.includes('bind-source-free')); assert(!missing.calls.includes('bind-Node-layout'));
  const f = fixture({physical: true, expire: true});
  assert.throws(f.construct, cause => cause === f.primary);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.modelPlan, undefined);
  assert(f.model.originalReadInstallation); assert.equal(f.model.budget.readRetainedBytes, 70n);
});


test('Request acquired Node Model retains original provider and prefix before same Request module and physical Plan', () => {
  const f = fixture({count: 1, physical: true, serialized: true, timed: true});
  assert.equal(f.construct(), f.plan);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.serialization, f.prefix);
  assert.deepEqual(f.calls, ['bounds', 'original provider selection', 'same Request prefix',
    'provider-capture-module', 'bind-Node-capture-layout']);
  assert.equal(f.run.modelSourceSelection.transferBytes, 512n);
});

test('Request acquired Node Model refuses absent original provider and keeps partials through original current failure', () => {
  const missing = fixture({count: 1, physical: true, serialized: true, missingProvider: true});
  assert.throws(missing.construct, {code: 'InstalledModelSourcePreparationUnavailable'});
  assert(!missing.calls.includes('same Request prefix'));
  const f = fixture({count: 1, physical: true, serialized: true, expire: true});
  assert.throws(f.construct, cause => cause === f.primary);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.serialization, f.prefix);
  assert.equal(f.run.modelPlan, undefined);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {modelConfiguration, registerCompositionModel} from './fixtures/composed-infer-effect-input.mjs';
import {createHash} from 'node:crypto';
import {installModelProviders} from '../adapters/host-node/installed-model.mjs';
import {bindInferOriginalReadRecipe} from '../adapters/host-node/infer-original-installation.mjs';
import {prepareInstalledEffectManagedPlanRun} from '../adapters/host-node/installed-effect-managed-run.mjs';
import {readInstalledModelExecution} from '../adapters/host-node/installed-model.mjs';

// Actual fixture and installed reader; constructor/reservation ports are
// explicit controls, not a compiled ABI, Model grant or provider invocation.
test('packed Salesforce composition retains its original Model materials before the Request read', async () => {
  const base = JSON.parse(readFileSync(new URL(
    '../adapters/host-node/fixtures/two-source/two-source.environment.json', import.meta.url), 'utf8'));
  const model = await modelConfiguration(base);
  const prepared = {}, execution = {}, events = [];
  const original = model.installation.executionContracts[0];
  const moon = {
    clientProgramSelectedInferStep(actual) {
      assert.equal(actual, prepared);return 0;
    },
    clientProgramInferModelTaskCid(actual, step) {
      assert.equal(actual, prepared);assert.equal(step, 0);return model.taskCid;
    },
    clientProgramReadInferModelExecution(actual, step, wire, cid) {
      assert.equal(this, moon);assert.equal(actual, prepared);assert.equal(step, 0);
      assert.equal(wire, original.bodyWire);assert.equal(cid, original.cid);
      assert.deepEqual(events, ['reserve']);events.push('read');
      return {$tag: 1, _0: execution};
    },
  };
  const beforeRead = (count, wireAt, containers) => {
    assert.equal(count, 1);assert.equal(wireAt(0), original.bodyWire);
    assert.equal(containers, model.installation.executionContracts.length +
      model.installation.dependencyBodies.length);
    events.push('reserve');
  };
  assert.equal(readInstalledModelExecution(moon, prepared, model.installation,
    undefined, beforeRead).execution, execution);
  assert.deepEqual(events, ['reserve', 'read']);
  assert(Object.isFrozen(model.installation));
  for (const originals of [model.installation.executionContracts,
    model.installation.dependencyBodies]) {
    assert(Object.isFrozen(originals));
    assert(originals.every(Object.isFrozen));
  }
  assert.throws(() => readInstalledModelExecution(moon, prepared,
    {...model.installation}, undefined, beforeRead), {
    name: 'TypeError', message: 'InstalledModelMaterialOriginalUnavailable',
  });
  assert.deepEqual(events, ['reserve', 'read'], 'Mutable copies never enter either port');
});


// Original fixture -> installed registration -> checked recipe binding ->
// actual strict Effect caller. Native/profile/constructor ports are explicit;
// reaching the demand port is not compiled or physical Runtime acceptance.
test('packed composition physical supplier retains its own read profile before Effect demand', async () => {
  const base = JSON.parse(readFileSync(new URL(
    '../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const model = await modelConfiguration(base), profile = {}, events = [];
  const runtimeSource = readFileSync(new URL('../adapters/host-node/infer-operation.mjs', import.meta.url));
  const hash = bytes => `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  let captured, cleanups = 0, sends = 0;
  const prepared = {}, request = {}, graph = {}, occurrence = {}, compiled = {}, definition = {},
    compilation = {}, runDefinition = {}, bounds = {};
  const moon = {
    clientProgramInstallModelProvider(id) {assert.equal(id, 'models/composition');return {};},
    clientProgramInferPlanProgramCid(g) {assert.equal(g, graph);return `sha256:${'1'.repeat(64)}`;},
    clientProgramInferPlanParametersCid(g) {assert.equal(g, graph);return `sha256:${'2'.repeat(64)}`;},
    clientProgramInferPlanBoundary(g) {assert.equal(g, graph);return {_3: `sha256:${'3'.repeat(64)}`};},
    clientProgramModelRequestPreflight(start, cleanup) {return {start, cleanup};},
    clientProgramModelPhysicalRequestPlan(actual, ...args) {
      assert.equal(actual, request);assert.deepEqual(args.slice(0, 4), [1000n, 33n, 0n, 500n]);
      events.push('physical-plan');return {$tag: 1, _0: {send: args[4]}};
    },
    clientProgramModelRequestInput(actual, field) {assert.equal(actual, request);assert.equal(field, 'score');return '200';},
    clientProgramModelResponse(actual, wire, selector) {
      assert.equal(actual, request);assert.equal(wire, '{"risk":"high"}');
      assert.equal(selector, 'composition-risk-model');return {};
    },
  };
  const control = {readInstalledModelResponseProfile(wire, cid) {
    captured = JSON.parse(wire);const {self_cid, ...body} = captured;
    assert.equal(self_cid, cid);
    const canonical = value => Array.isArray(value) ? '[' + value.map(canonical).join(',') + ']'
      : value !== null && typeof value === 'object' ? '{' + Object.keys(value).sort()
        .map(key => JSON.stringify(key) + ':' + canonical(value[key])).join(',') + '}' : JSON.stringify(value);
    assert.equal(cid, hash(canonical(body)));events.push('profile');return profile;
  }};
  const register = () => registerCompositionModel(moon, model.taskCid, score => {
    assert.equal(score, 200);sends++;
  }, {installation: model.installation, runtimeSource, publicationControl: control,
    cleanup() {cleanups++;return false;}});
  const entry = register()[0];
  assert.equal(entry.localMock, undefined);
  assert.deepEqual(entry.quantityCapacity, {limits: {tokens: 66n, costUnits: 0n, durationMs: 1000n},
    perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}});
  assert.equal(captured.task.contract_cid, model.taskCid);
  assert.equal(captured.adapter.sdk, null);
  assert.equal(captured.operation.endpoint, JSON.parse(entry.bindingOriginals.configuration.wire).endpoint);
  const selected = installModelProviders(moon, () => [entry]).get('models/composition');
  const recipe = selected.originalReadRecipe;
  assert.equal(recipe.nodeInstallation.layout.response_profile, profile);
  assert.equal(recipe.nodeInstallation.runtimeArtifactCid, hash(runtimeSource));
  assert.equal(recipe.nodeInstallation.layout.prepared_rows, 2n);
  const native = [11n, 12n, 13n, 14n, 15n, 16n, 9n, 10n, 11n];
  const original = bindInferOriginalReadRecipe(moon, recipe, graph, native, [15n, 16n]);
  assert.equal(original.nodeInstallation.layout.retained_bytes, recipe.nodeInstallation.layout.retained_bytes + 13n);
  assert.equal(original.modelRetainedBytes, recipe.modelRetainedBytes + 15n);
  assert.equal(original.nodeInstallation.layout.response_profile, profile);
  assert.throws(() => bindInferOriginalReadRecipe(moon, {...recipe}, graph, native, [15n, 16n]),
    {code: 'InferOriginalReadRecipeUnavailable'});
  const facts = Object.freeze({prepared, identity: request, compilation, definition, allowed: {},
    queryTimePreparation: undefined, modelCompiled: compiled, runDefinition});
  const demandBoundary = new Error('OriginalDemandBoundary');
  const options = {runs: new WeakMap(), liveRuns: new Set(), runtime: moon, manager: {},
    prepared, request, requestInput: {}, selection: {}, facts, inputs: {},
    model: Object.freeze({kind: 'installed-model', compiled, definition, occurrence, graph}),
    modelSelection: {occurrence, graph, selectedBounds: bounds, originalReadInstallation: original},
    publicationControl: {prepareCheckedClientNodeEffectModelDemand(...args) {
      assert.deepEqual(args, [prepared, compiled, compilation, runDefinition, occurrence, graph, bounds, original]);
      events.push('demand');throw demandBoundary;
    }}, assertCurrent() {}, checked() {assert.fail('no native Result is synthesized by this boundary');}};
  assert.throws(() => prepareInstalledEffectManagedPlanRun({...options,
    runs: new WeakMap(), liveRuns: new Set(), modelSelection: {occurrence, graph, selectedBounds: bounds}}),
  {code: 'InstalledEffectModelRuntimeUnavailable'});
  assert.deepEqual(events, ['profile']);
  assert.throws(() => prepareInstalledEffectManagedPlanRun(options), error => error === demandBoundary);
  assert.throws(() => prepareInstalledEffectManagedPlanRun(options), error => error === demandBoundary);
  assert.deepEqual(events, ['profile', 'demand'], 'Failed same Run cannot select a second demand');
  assert.equal(sends, 0);
  const preflight = entry.physicalPreflight(request);
  assert.equal(sends, 0);assert.equal(preflight.cleanup(), false);assert.equal(cleanups, 1);
  const physical = preflight.start();assert.equal(sends, 0);
  physical._1.send();assert.equal(sends, 1);
});

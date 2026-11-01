import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {openNodeComposedInferProvider} from './infer-operation.mjs';

// Actual Host constructor with explicit Core/current/installation ports.
// This does not issue Common originals or prove physical constructor backing.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const runtimeSource = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8');
const modulePorts = Object.freeze({
  prepareCheckedClientRequestModelSourceFreeModule: 'clientProgramPrepareRequestModelSourceFreeModule',
  prepareCheckedClientRequestModelCaptureModule: 'clientProgramPrepareRequestModelCaptureModule',
  prepareCheckedClientRequestModelProviderCaptureModule: 'clientProgramPrepareRequestModelProviderCaptureModule',
  prepareCheckedClientRequestModelProviderComponentCaptureModule: 'clientProgramPrepareRequestModelProviderComponentCaptureModule',
});
const actualModuleMethods = new Map();
function findModuleMethods(node) {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'Property' && node.method && Object.hasOwn(modulePorts, node.key.name)) actualModuleMethods.set(node.key.name, node);
  for (const value of Object.values(node)) {if (Array.isArray(value)) value.forEach(findModuleMethods); else if (value && typeof value === 'object') findModuleMethods(value);}
}
findModuleMethods(parse(runtimeSource, {ecmaVersion: 'latest', sourceType: 'module'}));
const node = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'prepareRequestMockModelPlan');
assert(node);
function fixture({count = 0, timed = false, refuseCapture, expire = false, missingModule = false,
  serialized = false, expirePrefix = false, missingPrefix = false, physical = false, missingPhysical = false, missingProvider = false, expireProvider = false, expireComponent = false, missingComponent = false, facadeBindings = false, missingSelectorPort, absentSourceRef = false, throwSelector = false, selectorCause} = {}) {
  const parent = {}, input = {}, prepared = {}, request = {}, compilation = {}, module = {}, plan = {};
  const graph = {}, occurrence = {}, bounds = {}, q = {}, admission = {}, initialControl = {};
  const declarations = [{}, {}], provider = {}, sourceRef = 'fixture/transfers', selectedSource = {};
  const sourceProfile = {sources: []};
  const inputPrefix = {}, componentProvider = {}, suffixBinder = () => assert.fail('construction does not execute suffix');
  const rawCompiled = {}, rawDefinition = {};
  const compiled = facadeBindings ? Object.freeze({kind: 'infer'}) : rawCompiled;
  const definition = facadeBindings ? Object.freeze({kind: 'run_definition', identity: 'fixture-definition'}) : rawDefinition;
  const calls = [], model = {graph, occurrence, compiled, runDefinition: definition, scope: undefined, component: undefined};
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
  if (count === 1 && !serialized) model.selection = Object.freeze({graph, occurrence, provider: {}});
  model.control = control;
  const moon = {
    clientProgramComposedInferLocalProvider(actualOccurrence, _open, _issue, _retain, _cleanup, actualPrefix) {
      assert.strictEqual(actualOccurrence, occurrence); assert.strictEqual(actualPrefix, inputPrefix);
      calls.push('component provider');
      if (expireComponent) current = false;
      return componentProvider;
    },
    clientProgramPrepareRequestModelProviderComponentCaptureModule(...args) {
      assert.deepEqual(args.slice(0, 15), [parent, input, request, rawCompiled, rawDefinition, compilation,
        declarations[0], provider, 'query', 'evidence', 512n, 256n,
        admission, true, timed ? q : undefined]);
      assert.equal(args.length, 16); assert.equal(model.component, undefined);
      calls.push('backed component module');
      assert.strictEqual(args[15]({}, inputPrefix, suffixBinder), componentProvider);
      assert.strictEqual(model.component.provider, componentProvider);
      return ok(module);
    },
    clientProgramSelectInstalledSourceInput(...args) {
      assert.deepEqual(args, [prepared, request, 0, 0],
        'Select with the SAME original Request in the actual four-argument ABI');
      if (throwSelector) throw selectorCause;
      return ok(selectedSource);
    },
    clientProgramSelectedSourceInputKind(value) {assert.equal(value, selectedSource); return 'query';},
    clientProgramSelectedSourceInputRef(value) {assert.equal(value, selectedSource); return absentSourceRef ? undefined : sourceRef;},
    clientProgramPrepareRequestModelProviderCaptureModule(...args) {
      assert.deepEqual(args, [parent, input, request, rawCompiled, rawDefinition, compilation,
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
      assert.deepEqual(args, [parent, input, request, rawCompiled, rawDefinition,
        compilation, admission, true, timed ? q : undefined]);
      assert.equal(model.selectedBounds, bounds); assert.equal(model.budget.readRetainedBytes, physical ? 70n : 13n);
      if (serialized) assert.equal(run.serialization, prefix, 'Retain original prefix before module constructor');
      calls.push('source-free-module'); if (expire) current = false; return ok(module);
    },
    clientProgramPrepareRequestModelCaptureModule(...args) {
      assert.deepEqual(args, [parent, input, request, rawCompiled, rawDefinition, compilation,
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
  if (missingComponent) delete moon.clientProgramPrepareRequestModelProviderComponentCaptureModule;
  if (missingSelectorPort !== undefined) delete moon[missingSelectorPort];
  const checkedResult = value => {assert.equal(value.$tag, 1); return value._0;};
  if (facadeBindings) {
    const compiledRunTokens = new WeakMap([[compiled, rawCompiled]]), tokens = new WeakMap([[definition, rawDefinition]]);
    const tokenStart = runtimeSource.indexOf('  const token = value => {');
    const tokenEnd = runtimeSource.indexOf('  const inspectEvidence =', tokenStart);
    const methods = [...actualModuleMethods.values()].map(value => runtimeSource.slice(value.start, value.end)).join(',');
    const bindings = Function('moon', 'compiledRunTokens', 'tokens', 'checked',
      runtimeSource.slice(tokenStart, tokenEnd) + ';return {' + methods + '};')(moon, compiledRunTokens, tokens, checkedResult);
    Object.assign(control, bindings);
  } else {
    for (const [name, native] of Object.entries(modulePorts)) {
      control[name] = (...args) => checkedResult(Reflect.apply(moon[native], moon, args));
    }
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
  const ports = {openNodeComposedInferProvider, assertSourceManagedHostPreparation(value) {
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
  return {run, model, compilation, module, plan, bounds, calls, primary, prefix, control, parent, input, request, rawCompiled, rawDefinition,
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


test('Request acquired Node Model does not retain provider DATA after its original current callback refuses', () => {
  const f = fixture({count: 1, physical: true, serialized: true, expireProvider: true});
  assert.throws(f.construct, cause => cause === f.primary);
  assert.equal(f.run.modelSourceSelection, undefined);
  assert.equal(f.run.serialization, undefined); assert.equal(f.run.preparedSequences, undefined);
});


test('Request acquired Node Model facade unwraps only same registered compiler and Definition and forwards original layout fields', () => {
  const text = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8'); let selected;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'prepareCheckedClientRequestNodeModelCapturePlan') {
      assert(!selected); selected = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk); else if (value && typeof value === 'object') walk(value);
    }
  };
  walk(parse(text, {ecmaVersion: 'latest', sourceType: 'module'})); assert(selected);
  const parent = {}, input = {}, module = {}, request = {}, compiled = {kind: 'infer'}, rawCompiled = {},
    definition = {}, rawDefinition = {}, occurrence = {}, graph = {}, bounds = {}, plan = {};
  const installation = {nodeInstallation: {layout: {}, installation: {}, runtimeArtifactCid: 'runtime',
    layoutArtifactCid: 'layout', probability: undefined}, modelRetainedBytes: 90n, modelExecutionBytes: 40n,
    bootstrap: {maxReservations: 21, maxHoldings: 22, maxDelegations: 23}};
  const node = installation.nodeInstallation; let calls = 0;
  const moon = {clientProgramPrepareRequestNodeModelCapturePlan(...args) {
    assert.equal(this, moon);
    assert.deepEqual(args, [parent, input, module, request, rawCompiled, rawDefinition, occurrence, graph,
      bounds, node.layout, node.installation, 'runtime', 'layout', undefined, 90n, 40n, 21, 22, 23]);
    calls++; return plan;
  }};
  const ports = {moon, compiledRunTokens: new WeakMap([[compiled, rawCompiled]]), checked: value => value,
    token(value) {if (value !== definition) throw new TypeError('Foreign Definition'); return rawDefinition;}};
  const facade = Function(...Object.keys(ports), 'return ({' + text.slice(selected.start, selected.end) + '}).prepareCheckedClientRequestNodeModelCapturePlan')(...Object.values(ports));
  const bind = (c = compiled, d = definition) => facade(parent, input, module, request, c, d,
    occurrence, graph, bounds, installation);
  assert.equal(bind(), plan); assert.throws(() => bind({...compiled}), /Foreign Client compiled Infer/);
  assert.throws(() => bind(compiled, {...definition}), /Foreign Definition/); assert.equal(calls, 1);
  delete moon.clientProgramPrepareRequestNodeModelCapturePlan;
  assert.throws(() => bind(), /Installed Node Model Plan unavailable/); assert.equal(calls, 1);
});


test('Request plain Node Model constructs and retains its original component only inside the backed module factory', () => {
  const f = fixture({count: 1, physical: true, timed: true});
  assert.strictEqual(f.construct(), f.plan);
  assert.strictEqual(f.run.preparedSequences, f.module);
  assert(f.model.component);
  assert.deepEqual(f.calls, ['bounds', 'original provider selection', 'backed component module',
    'component provider', 'bind-Node-capture-layout']);
});

test('Request plain Node Model retains its partial deferred component through original current refusal', () => {
  const f = fixture({count: 1, physical: true, expireComponent: true});
  assert.throws(f.construct, error => error === f.primary);
  assert(f.model.component);
  assert.strictEqual(f.run.preparedSequences, undefined);
  assert.strictEqual(f.run.modelPlan, undefined);
  assert.deepEqual(f.calls, ['bounds', 'original provider selection', 'backed component module', 'component provider']);
});


test('Request Model module unwraps same compiler and Definition before its existing native constructor', () => {
  for (const options of [{}, {count: 1, physical: true, serialized: true},
    {count: 1, physical: true}, {count: 2}]) {
    const f = fixture({...options, facadeBindings: true});
    assert.equal(f.construct(), f.plan);
    assert.equal(f.run.preparedSequences, f.module);
    const before = f.calls.length;
    assert.throws(() => f.control.prepareCheckedClientRequestModelSourceFreeModule(f.parent, f.input,
      f.request, {...f.model.compiled}, f.model.runDefinition, f.compilation), /Foreign Client compiled Infer preparation/u);
    assert.throws(() => f.control.prepareCheckedClientRequestModelSourceFreeModule(f.parent, f.input,
      f.request, f.model.compiled, {...f.model.runDefinition}, f.compilation), /Foreign publication contract/u);
    assert.equal(f.calls.length, before, 'Foreign facades never enter a native module constructor');
  }
});


test('Request acquired Node Model selector refuses missing originals before any provider module', () => {
  for (const missingSelectorPort of ['clientProgramSelectInstalledSourceInput',
    'clientProgramSelectedSourceInputKind', 'clientProgramSelectedSourceInputRef']) {
    const f = fixture({count: 1, physical: true, serialized: true, missingSelectorPort});
    assert.throws(f.construct, {code: 'NodeManagedRunRuntimeUnavailable'});
    assert.deepEqual(f.calls, ['bounds']);
    assert.equal(f.run.modelSourceSelection, undefined);
  }
  const absent = fixture({count: 1, physical: true, serialized: true, absentSourceRef: true});
  assert.throws(absent.construct, {code: 'InstalledModelSourcePreparationUnavailable'});
  assert.deepEqual(absent.calls, ['bounds']);
  for (const selectorCause of [undefined, null, new Error('original selector refusal')]) {
    const f = fixture({count: 1, physical: true, serialized: true, throwSelector: true, selectorCause});
    let thrown = false;
    try {f.construct();} catch (cause) {thrown = true; assert.strictEqual(cause, selectorCause);}
    assert(thrown);
    assert.deepEqual(f.calls, ['bounds']);
    assert.equal(f.run.preparedSequences, undefined);
  }
});

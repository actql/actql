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
  prepareCheckedClientRequestModelDuckDBComponentCaptureModule: 'clientProgramPrepareRequestModelDuckDBComponentCaptureModule',
  prepareCheckedClientRequestModelsDuckDBComponentCaptureModule: 'clientProgramPrepareRequestModelsDuckDBComponentCaptureModule',
  prepareCheckedClientRequestModelCaptureModule: 'clientProgramPrepareRequestModelCaptureModule',
  prepareCheckedClientRequestModelComponentCaptureModule: 'clientProgramPrepareRequestModelComponentCaptureModule',
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
const budgetNode = parse(source, {ecmaVersion: 'latest', sourceType: 'module'}).body
  .find(value => value.type === 'FunctionDeclaration' && value.id.name === 'retainRequestModelBoundsAndBudget');
assert(budgetNode);
const budgetSource = source.slice(budgetNode.start, budgetNode.end);
function fixture({count = 0, timed = false, refuseCapture, expire = false, missingModule = false,
  serialized = false, expirePrefix = false, missingPrefix = false, physical = false, missingPhysical = false, missingProvider = false, expireProvider = false, expireComponent = false, missingComponent = false, facadeBindings = false, missingSelectorPort, absentSourceRef = false, throwSelector = false, selectorCause, native = false, nativeChange, missingNativeModule = false} = {}) {
  const parent = {}, input = {}, prepared = {}, request = {}, compilation = {}, module = {}, plan = {};
  const graph = {}, occurrence = {}, bounds = {}, q = {}, admission = {}, initialControl = {};
  const declarations = [{}, {}], provider = {}, sourceRef = 'fixture/transfers', selectedSource = {};
  const sourceProfile = {sources: []};
  const inputPrefix = {}, componentProvider = {}, suffixBinder = () => assert.fail('construction does not execute suffix');
  const rawCompiled = {}, rawDefinition = {};
  const compiled = facadeBindings ? Object.freeze({kind: 'infer'}) : rawCompiled;
  const definition = facadeBindings ? Object.freeze({kind: 'run_definition', identity: 'fixture-definition'}) : rawDefinition;
  // This fixture owns the existing Mock module path. Real configured
  // source-free components have separate deferred-provider caller controls.
  const calls = [], model = {graph, occurrence, compiled, runDefinition: definition, scope: undefined, component: undefined,
    selection: Object.freeze({localMock: true, graph, occurrence})};
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
    prepareCheckedClientRequestModelCapturePlan(...args) {
      assert.equal(this, control);
      assert.deepEqual(args, [parent, input, module, request, model.compiled, model.runDefinition, occurrence, graph, bounds]);
      assert.equal(physical, false);
      calls.push('bind-generic-captured'); return plan;
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
    clientProgramPrepareRequestModelDuckDBComponentCaptureModule(...args) {
      assert.equal(this, moon);
      assert.deepEqual(args.slice(0,17), [parent,input,request,rawCompiled,rawDefinition,compilation,
        sourceRef,'main','records','native-query','native-evidence','native-receipts',512n,256n,
        admission,true,timed ? q : undefined]);
      assert.equal(args.length,18); assert.equal(model.component,undefined);
      calls.push('backed native component module');
      assert.strictEqual(args[17]({},inputPrefix,suffixBinder),componentProvider);
      assert.strictEqual(model.component.provider,componentProvider);
      return ok(module);
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
    clientProgramPrepareRequestModelComponentCaptureModule(...args) {
      assert.deepEqual(args.slice(0, 14), [parent, input, request, rawCompiled, rawDefinition, compilation,
        declarations, 'query', 'evidence', [1048576n, 1048576n], [1048576n, 1048576n],
        admission, true, timed ? q : undefined]);
      assert.equal(args.length, 15);
      assert.equal(args[9], args[10], 'Reuse the original fixed document bound vector');
      calls.push('captured-module'); if (refuseCapture) throw refuseCapture;
      assert.strictEqual(args[14]({}, inputPrefix, suffixBinder), componentProvider);
      assert.strictEqual(model.component.provider, componentProvider);
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
    delete moon.clientProgramPrepareRequestModelComponentCaptureModule;
    delete moon.clientProgramPrepareRequestModelProviderCaptureModule;
  }
  if (missingComponent) delete moon.clientProgramPrepareRequestModelProviderComponentCaptureModule;
  if (missingNativeModule) delete moon.clientProgramPrepareRequestModelDuckDBComponentCaptureModule;
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
    return Object.freeze(native ? {nativeSource:Object.freeze({sourceRef,schema:'main',table:'records',
      contracts:Object.freeze(['native-query','native-evidence','native-receipts']),...nativeChange}),
      transferBytes:512n,executionBytes:256n}
      : {declaration: declarations[0], provider: missingProvider ? undefined : provider,
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
  const construct = Function(...Object.keys(ports), `${budgetSource}\nreturn (${source.slice(node.start, node.end)});`)(...Object.values(ports));
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
    assert.deepEqual(f.calls, ['bounds', 'captured-module', 'component provider', 'bind-captured']);
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

test('Request two-Source Mock retains its same deferred component when the current callback refuses', () => {
  const f = fixture({count: 2, expireComponent: true, facadeBindings: true});
  assert.throws(f.construct, error => error === f.primary);
  assert(f.model.component);
  assert.strictEqual(f.run.preparedSequences, undefined);
  assert.strictEqual(f.run.modelPlan, undefined);
  assert.deepEqual(f.calls, ['bounds', 'captured-module', 'component provider']);
});

test('Request two-Source component facade forwards originals and rejects copied compiler or Definition', () => {
  const f = fixture({count: 2, timed: true, facadeBindings: true});
  assert.strictEqual(f.construct(), f.plan);
  const method = f.control.prepareCheckedClientRequestModelComponentCaptureModule;
  const before = f.calls.length;
  const invoke = (compiled, definition) => method(f.parent, f.input, f.request, compiled,
    definition, f.compilation, [], 'query', 'evidence', [], [], {}, true, undefined, () => {});
  assert.throws(() => invoke({...f.model.compiled}, f.model.runDefinition), /Foreign Client compiled Infer preparation/);
  assert.throws(() => invoke(f.model.compiled, {...f.model.runDefinition}), /Foreign publication contract/);
  assert.equal(f.calls.length, before);
  assert.deepEqual(f.calls, ['bounds', 'captured-module', 'component provider', 'bind-captured']);
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

test('Request acquired generic Model binds the same original provider module without a Node response declaration', () => {
  const f = fixture({count: 1});
  assert.equal(f.construct(), f.plan);
  assert.equal(f.run.preparedSequences, f.module);
  assert.equal(f.model.originalReadInstallation, undefined);
  assert.deepEqual(f.calls, ['bounds', 'original provider selection', 'backed component module',
    'component provider', 'bind-generic-captured']);
  assert.equal(f.model.budget.readRetainedBytes, 13n);
  assert.equal(f.model.budget.modelRetainedBytes, 15n);
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
    bootstrap: {bootstrapRetainedBytes: 31n, bootstrapExecutionBytes: 37n,
      maxReservations: 21, maxHoldings: 22, maxDelegations: 23}};
  const node = installation.nodeInstallation; let calls = 0;
  const moon = {clientProgramPrepareRequestNodeModelCapturePlan(...args) {
    assert.equal(this, moon);
    assert.deepEqual(args, [parent, input, module, request, rawCompiled, rawDefinition, occurrence, graph,
      bounds, node.layout, node.installation, 'runtime', 'layout', undefined, 90n, 40n, 21, 22, 23, 31n, 37n]);
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

test('Request source-free Node Model facade retains the separate original bootstrap and complete read envelope', () => {
  const text = readFileSync(new URL('../host-common/runtime-core.mjs', import.meta.url), 'utf8'); let selected;
  const walk = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === 'prepareCheckedClientRequestNodeModelSourceFreePlan') {
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
    bootstrap: {bootstrapRetainedBytes: 31n, bootstrapExecutionBytes: 37n,
      maxReservations: 21, maxHoldings: 22, maxDelegations: 23}};
  const node = installation.nodeInstallation; let calls = 0;
  const moon = {clientProgramPrepareRequestNodeModelSourceFreePlan(...args) {
    assert.equal(this, moon);
    assert.deepEqual(args, [parent, input, module, request, rawCompiled, rawDefinition, occurrence, graph,
      bounds, node.layout, node.installation, 'runtime', 'layout', undefined, 90n, 40n, 21, 22, 23, 31n, 37n]);
    calls++; return plan;
  }};
  const ports = {moon, compiledRunTokens: new WeakMap([[compiled, rawCompiled]]), checked: value => value,
    token(value) {if (value !== definition) throw new TypeError('Foreign Definition'); return rawDefinition;}};
  const facade = Function(...Object.keys(ports), 'return ({' + text.slice(selected.start, selected.end) + '}).prepareCheckedClientRequestNodeModelSourceFreePlan')(...Object.values(ports));
  const bind = (c = compiled, d = definition) => facade(parent, input, module, request, c, d,
    occurrence, graph, bounds, installation);
  assert.equal(bind(), plan); assert.throws(() => bind({...compiled}), /Foreign Client compiled Infer/);
  assert.throws(() => bind(compiled, {...definition}), /Foreign Definition/); assert.equal(calls, 1);
  delete moon.clientProgramPrepareRequestNodeModelSourceFreePlan;
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

// Actual facade forwarding, explicit native constructor ports. No Common
// original, tuple layout, physical funding or ordinary ABI is manufactured.
test('plural Model module forwards the same compiler definition and indexed native callback',()=>{
  const parsed=parse(runtimeSource,{ecmaVersion:'latest',sourceType:'module'});let method;
  const walk=node=>{if(!node||typeof node!=='object')return;
    if(node.type==='Property'&&node.method&&node.key.name==='prepareCheckedClientRequestModelsSourceFreeComponentModule')method=node;
    for(const value of Object.values(node)){if(Array.isArray(value))value.forEach(walk);else if(value&&typeof value==='object')walk(value);}};
  walk(parsed);assert(method);
  const parent={},input={},request={},compiled=Object.freeze({kind:'infer'}),definition={},rawCompiled={},rawDefinition={};
  const compilation={},contracts={},queryTime={},module={},calls=[];
  const prefixes=[{},{}],suffixes=[()=>{},()=>{}],providers=[{},{}];
  const construct=(index,capacity,prefix,bindSuffix)=>{
    assert.strictEqual(prefix,prefixes[index]);assert.strictEqual(bindSuffix,suffixes[index]);
    assert.ok(capacity);calls.push(index);return providers[index];
  };
  const moon={clientProgramPrepareRequestModelsSourceFreeComponentModule(...args){
    assert.strictEqual(this,moon);assert.deepEqual(args.slice(0,9),
      [parent,input,request,rawCompiled,rawDefinition,compilation,contracts,true,queryTime]);
    assert.strictEqual(args[9],construct,'forward the original callback unchanged');
    for(let index=0;index<2;index++)assert.strictEqual(args[9](index,{},prefixes[index],suffixes[index]),providers[index]);
    return {$tag:1,_0:module};
  }};
  const bind=Function('moon','compiledRunTokens','token','checked',
    'return ({'+runtimeSource.slice(method.start,method.end)+'});')(moon,new WeakMap([[compiled,rawCompiled]]),
      value=>{if(value!==definition)throw new TypeError('Foreign publication contract');return rawDefinition;},
      value=>{assert.equal(value.$tag,1);return value._0;});
  const invoke=(selected=compiled,publication=definition)=>bind.prepareCheckedClientRequestModelsSourceFreeComponentModule(
    parent,input,request,selected,publication,compilation,contracts,true,queryTime,construct);
  assert.strictEqual(invoke(),module);assert.deepEqual(calls,[0,1]);
  assert.throws(()=>invoke({...compiled}),/Foreign Client compiled Infer preparation/);
  assert.throws(()=>invoke(compiled,{...definition}),/Foreign publication contract/);
  assert.deepEqual(calls,[0,1],'foreign facades cannot enter another constructor');
});


for (const [method, port, plural] of [
  ['prepareCheckedClientRequestModelsSourceFreePlan', 'clientProgramPrepareRequestModelsSourceFreePlan', true],
  ['prepareCheckedClientRequestModelCapturePlan', 'clientProgramPrepareRequestModelCapturePlan', false],
]) test(`${plural ? 'plural' : 'single captured'} Model Plan forwards the same complete selected bounds and private compiler original`, () => {
  const parsed = parse(runtimeSource, {ecmaVersion: 'latest', sourceType: 'module'});
  let selectedMethod;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'Property' && node.method && node.key.name === method) selectedMethod = node;
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit); else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parsed); assert(selectedMethod);
  const parent={}, input={}, original={}, request={}, compiled=Object.freeze({kind:'infer'}), definition={}, rawCompiled={}, rawDefinition={};
  const occurrences=plural ? Object.freeze([{},{}]) : {}, graphs=plural ? Object.freeze([{},{}]) : {},
    bounds=plural ? Object.freeze([{},{}]) : {}, plan={};
  let calls=0;
  const moon={[port](...args) {
    assert.equal(this, moon); calls++;
    assert.deepEqual(args,[parent,input,original,request,rawCompiled,rawDefinition,occurrences,graphs,bounds]);
    return plan;
  }};
  const object=Function('moon','compiledRunTokens','token','checked',
    'return ({'+runtimeSource.slice(selectedMethod.start,selectedMethod.end)+'});')(moon,new WeakMap([[compiled,rawCompiled]]),
      value=>{assert.equal(value,definition);return rawDefinition;},value=>value);
  assert.equal(object[method](parent,input,original,request,compiled,definition,occurrences,graphs,bounds),plan);
  assert.throws(()=>object[method](parent,input,original,request,{...compiled},definition,occurrences,graphs,bounds),/Foreign Client compiled Infer preparation/);
  assert.equal(calls,1);
});


function completeModelPlanFixture({expireMember, badOrder = false, captured = false, native = false, nativeChange, missingNativeModule = false} = {}) {
  const parent = {}, input = {}, prepared = {}, request = {}, compilation = {}, module = {}, plan = {},
    compiled = native ? Object.freeze({kind: 'infer'}) : {}, definition = {}, admission = {}, initialControl = {}, calls = [], prefixes = [{}, {}], providers = [{}, {}];
  const selected = Object.freeze([0, 1].map(() => Object.freeze({graph: {}, occurrence: {}, selectedBounds: {}})));
  const model = {prepared, compiled, runDefinition: definition,
    selection: Object.freeze({components: selected}), graph: Object.freeze(selected.map(value => value.graph))};
  model.components = Object.freeze(selected.map(selection => ({group: model, selection,
    graph: selection.graph, occurrence: selection.occurrence, component: undefined})));
  if (badOrder) model.components = Object.freeze([...model.components].reverse());
  const run = {prepared, request, model}, primary = new Error('original Model member constructor current');
  let live = true;
  const current = () => {if (!live) throw primary;};
  const moon = {
    clientProgramAcquisitionCount(p) {assert.equal(p, prepared); return native ? 1 : captured ? 2 : 0;},
    clientProgramPreparedComposedInferBounds() {assert.fail('Reuse each retained selected Limits');},
    clientProgramComposedInferRetainedLimits(bounds) {
      const index = selected.findIndex(value => value.selectedBounds === bounds); assert(index >= 0);
      calls.push('bounds'+index); return [1n, 2n, 3n, 4n, 5n, 6n, 7n, 8n, 9n];
    },
  };
  const control = {
    prepareCheckedClientRequestModelsSourceFreeComponentModule(...args) {
      assert.equal(this, control);
      assert.deepEqual(args.slice(0, 9), [parent, input, request, compiled, definition, compilation, admission, true, undefined]);
      calls.push('one complete module');
      for (let index = 0; index < 2; index++) {
        assert.equal(args[9](index, {}, prefixes[index], () => {}), providers[index]);
        assert.equal(model.components[index].component.provider, providers[index]);
      }
      return module;
    },
    prepareCheckedClientRequestModelsSourceFreePlan(...args) {
      assert.equal(this, control); calls.push('one complete Plan');
      assert.deepEqual(args.slice(0, 6), [parent, input, module, request, compiled, definition]);
      assert.deepEqual(args[6], selected.map(value => value.occurrence));
      assert.equal(args[7], model.graph);
      assert.deepEqual(args[8], selected.map(value => value.selectedBounds));
      assert(Object.isFrozen(args[6])); assert(Object.isFrozen(args[8]));
      return plan;
    },
  };
  model.control = control;
  run.runtime = moon;
  const sourceProfile = {}, coordinates = Object.freeze((native ? [[4, 1, 0]] : [[4, 1, 0], [6, 2, 1]]).map(Object.freeze)),
    sourceOriginals = native ? [Object.freeze({nativeSource: Object.freeze({sourceRef: 'source:native', schema: 'main', table: 'records',
      contracts: Object.freeze(['native-query', 'native-evidence', 'native-receipts']), ...nativeChange}),
      transferBytes: 123n, executionBytes: 45n})]
      : [0, 1].map(() => Object.freeze({declaration: {}, provider: {}, transferBytes: 123n, executionBytes: 45n}));
  const originals = {installation: {projectRuntime: moon, initialControl, retainedRelationOutput: false,
    managedSourceProfile: sourceProfile, computeRuns: new WeakMap([[prepared, run]])}};
  if (captured || native) {
    run.sourceProfile = sourceProfile;
    moon.clientProgramRequestModelDirectSourceCoordinates = (p, i) => {
      assert.equal(p, parent); assert.equal(i, input); return coordinates;
    };
    moon.clientProgramSelectInstalledSourceInput = (p, r, stage, input) => {
      assert.equal(p, prepared); assert.equal(r, request);
      const index = coordinates.findIndex(value => value[0] === stage && value[1] === input);
      assert(index >= 0); calls.push('Direct'+stage+':'+input); return sourceOriginals[index];
    };
    moon.clientProgramSelectedSourceInputKind = () => 'query';
    moon.clientProgramSelectedSourceInputRef = value => native ? 'source:native' : sourceOriginals.indexOf(value);
    control.prepareCheckedClientRequestModelsProviderComponentCaptureModule = function(...args) {
      assert.equal(this, control); assert.deepEqual(args.slice(0, 6), [parent, input, request, compiled, definition, compilation]);
      assert.deepEqual(args.slice(6, 12), [sourceOriginals.map(source => source.declaration), sourceOriginals.map(source => source.provider),
        'query-contract', 'evidence-contract', [123n, 123n], [45n, 45n]]);
      calls.push('one captured complete module');
      for (let index = 0; index < 2; index++) assert.equal(args[15](index, {}, prefixes[index], () => {}), providers[index]);
      return module;
    };
    control.prepareCheckedClientRequestModelsCapturePlan = function(...args) {
      assert.equal(this, control); assert.deepEqual(args.slice(0, 6), [parent, input, module, request, compiled, definition]);
      assert.deepEqual(args[6], selected.map(value => value.occurrence)); assert.equal(args[7], model.graph);
      calls.push('one captured complete Plan'); return plan;
    };
  }
  if (native) {
    // Exercise the actual thin facade as well as the Host caller. The returned
    // compilation is the same private original, never an equal facade/clone.
    const rawCompiled = {}, rawDefinition = {};
    moon.clientProgramPrepareRequestModelsDuckDBComponentCaptureModule = function(...args) {
      assert.equal(this, moon);
      assert.deepEqual(args.slice(0, 17), [parent, input, request, rawCompiled, rawDefinition, compilation,
        'source:native', 'main', 'records', 'native-query', 'native-evidence', 'native-receipts', 123n, 45n,
        admission, true, undefined]);
      calls.push('one native complete module');
      for (let index = 0; index < 2; index++) {
        assert.equal(args[17](index, {}, prefixes[index], () => {}), providers[index]);
      }
      return module;
    };
    const method = actualModuleMethods.get('prepareCheckedClientRequestModelsDuckDBComponentCaptureModule');
    if (method !== undefined) Object.assign(control, Function('moon', 'compiledRunTokens', 'token', 'checked',
      'return ({' + runtimeSource.slice(method.start, method.end) + '});')(moon,
      new WeakMap([[compiled, rawCompiled]]), value => {assert.equal(value, definition); return rawDefinition;}, value => value));
    if (missingNativeModule) delete control.prepareCheckedClientRequestModelsDuckDBComponentCaptureModule;
  }
  const ports = {assertSourceManagedHostPreparation: current, originalSourceManagedHostRequest: current,
    prepareInstalledSequenceContractOriginal: () => ({moon, control: initialControl, contracts: {}, admission}),
    runtimeCore: () => ({publicationControl: control}), checked: value => value,
    readInitialControlInstallationAsset(actual, o, path) {
      assert.equal(actual, initialControl); assert.equal(o, originals);
      return path.includes('process-evidence') ? 'evidence-contract' : 'query-contract';
    },
    installedSourceFor(profile, index) {assert.equal(profile, sourceProfile); if (native) assert.equal(index, 'source:native'); return {managedEffectPlanSelection() {return sourceOriginals[native ? 0 : index];}};},
    clientOperationError: code => Object.assign(new Error(code), {code}),
    openNodeComposedInferProvider(options) {
      const index = selected.indexOf(options.selected); assert(index >= 0);
      assert.equal(options.moon, moon); assert.equal(options.inputPrefix, prefixes[index]); assert.equal(options.deferred, true);
      calls.push('provider'+index); if (expireMember === index) live = false;
      return Object.freeze({provider: providers[index], bindOriginal() {}});
    }};
  const construct = Function(...Object.keys(ports), budgetSource + '\nreturn ' + source.slice(node.start, node.end))(...Object.values(ports));
  return {calls, model, run, plan, module, primary, invoke: () => construct(originals, run, model, compilation, parent, input)};
}

test('complete Request Model caller constructs one module and Plan from every retained ordered Limits and provider', () => {
  const f = completeModelPlanFixture(); assert.equal(f.invoke(), f.plan);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.modelPlan, f.plan);
  assert.deepEqual(f.calls, ['bounds0', 'bounds1', 'one complete module', 'provider0', 'provider1', 'one complete Plan']);
  assert(f.model.components.every(member => member.budget.readRetainedBytes === 3n && member.component !== undefined));
});

test('complete Request Model caller retains both original providers when the later current callback refuses', () => {
  const f = completeModelPlanFixture({expireMember: 1});
  assert.throws(f.invoke, cause => cause === f.primary);
  assert(f.model.components.every(member => member.component !== undefined));
  assert.equal(f.run.preparedSequences, undefined); assert.equal(f.run.modelPlan, undefined);
  assert.deepEqual(f.calls, ['bounds0', 'bounds1', 'one complete module', 'provider0', 'provider1']);
  const swapped = completeModelPlanFixture({badOrder: true});
  assert.throws(swapped.invoke, {code: 'InstalledModelGroupPreparationUnavailable'});
  assert.deepEqual(swapped.calls, []);
});


test('complete captured Request Model module uses actual checked Direct Stage and input coordinates for its same provider originals', () => {
  const f = completeModelPlanFixture({captured: true}); assert.equal(f.invoke(), f.plan);
  assert.equal(f.run.preparedSequences, f.module); assert.equal(f.run.modelSourceSelections.length, 2);
  assert.deepEqual(f.calls, ['bounds0', 'bounds1', 'Direct4:1', 'Direct6:2',
    'one captured complete module', 'provider0', 'provider1', 'one captured complete Plan']);
});


test('single native Model module retains the exact original Query protocols and private compiler', () => {
  const f=fixture({count:1,native:true,facadeBindings:true});
  assert.equal(f.construct(),f.plan);
  assert.equal(f.run.preparedSequences,f.module);
  assert.deepEqual(f.calls,['bounds','original provider selection','backed native component module','component provider','bind-generic-captured']);
});

test('single native Model refuses changed Source or incomplete protocols before constructing a module', () => {
  for (const nativeChange of [{sourceRef:'source:foreign'}, {contracts:Object.freeze(['query','evidence'])},
    {contracts:['native-query','native-evidence','native-receipts']}, {table:''}]) {
    const f=fixture({count:1,native:true,nativeChange});
    assert.throws(f.construct,{code:'InstalledModelSourcePreparationUnavailable'});
    assert.equal(f.run.preparedSequences,undefined);
    assert.equal(f.model.component,undefined);
    assert.deepEqual(f.calls,['bounds','original provider selection']);
  }
  const missing=fixture({count:1,native:true,missingNativeModule:true});
  assert.throws(missing.construct,{code:'InstalledModelSourcePreparationUnavailable'});
  assert.equal(missing.run.preparedSequences,undefined);
});


test('native captured Model group uses one original Source and compiler for both ordered components', () => {
  const f = completeModelPlanFixture({native: true});
  assert.equal(f.invoke(), f.plan);
  assert.equal(f.run.preparedSequences, f.module);
  assert.equal(f.run.modelSourceSelections.length, 1);
  assert.deepEqual(f.calls, ['bounds0', 'bounds1', 'Direct4:1', 'one native complete module',
    'provider0', 'provider1', 'one captured complete Plan']);
});

test('native captured Model group refuses changed original Source and missing typed module before providers', () => {
  for (const options of [{nativeChange: {table: ''}}, {nativeChange: {sourceRef: 1}},
    {nativeChange: {contracts: ['native-query', 'native-evidence', 'native-receipts']}}, {missingNativeModule: true}]) {
    const f = completeModelPlanFixture({native: true, ...options});
    assert.throws(f.invoke, {code: 'InstalledModelSourcePreparationUnavailable'});
    assert.equal(f.run.preparedSequences, undefined);
    assert(f.model.components.every(member => member.component === undefined));
  }
});

test('native captured Model group keeps both original children when later current refuses', () => {
  const f = completeModelPlanFixture({native: true, expireMember: 1});
  assert.throws(f.invoke, cause => cause === f.primary);
  assert(f.model.components.every(member => member.component !== undefined));
  assert.equal(f.run.preparedSequences, undefined);
  assert.equal(f.run.modelPlan, undefined);
});

// Exercise the actual request-selection branch twice, as funded preparation
// and submit do for the same original Program. No Core/physical grant is made.
test('multiple Model request selection reuses its original ordered components after adoption', () => {
  let branch;
  const visit = node => {
    if (!node || typeof node !== 'object') return;
    if (node.type === 'IfStatement' && source.slice(node.test.start, node.test.end) === 'occurrences.length > 1') {
      assert.equal(branch, undefined); branch = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'})); assert(branch);
  const preparedProgram = {}, occurrences = Object.freeze([{}, {}]), quantityCapacity = {};
  const inferSelections = new WeakMap(), sourceCoordinates = Object.freeze([[0, 0, 0]]);
  let calls = 0, adopted = false;
  const prepareInferSelection = (prepared, occurrence, retain) => {
    assert.equal(prepared, preparedProgram); assert.equal(retain, false);
    assert.equal(adopted, false, 'adopted input cannot construct another Model graph');
    calls++; return Object.freeze({occurrence, quantityCapacity, graph: {}});
  };
  const select = Function('occurrences', 'preparedProgram', 'inferSelections',
    'prepareInferSelection', 'modelCoordinates', 'prepareSubmit', source.slice(branch.start, branch.end));
  const run = () => select(occurrences, preparedProgram, inferSelections, prepareInferSelection, sourceCoordinates,
    {originalInferRun: () => undefined});
  run(); const original = inferSelections.get(preparedProgram); adopted = true; run();
  assert.equal(inferSelections.get(preparedProgram), original); assert.equal(calls, 2);
  assert.equal(original.sourceCoordinates, sourceCoordinates);
  assert.equal(original.quantityCapacity, quantityCapacity);
  original.components.forEach((component, index) => {
    assert.equal(component.occurrence, occurrences[index]); assert.equal(original.graph[index], component.graph);
  });
});

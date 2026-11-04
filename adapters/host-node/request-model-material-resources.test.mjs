import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
import {configuration} from '../../scripts/fixtures/installed-infer-fixture.mjs';
import {readInstalledModelExecution, readInstalledModelDependencies,
  admitInstalledModelProviderBinding, consumeInstalledModelExecutionAbsence,
  consumeInstalledModelPreparationRefusal} from './installed-model.mjs';

// Actual exported readers with explicit native/current reservation ports.
// The sentinel ends before a Core issuer, Provider, Account or physical IO.
const frozen = (executions, bodies) => Object.freeze({environmentWire: '{}',
  executionContracts: Object.freeze(executions.map(Object.freeze)),
  dependencyBodies: Object.freeze(bodies.map(Object.freeze))});

test('empty original Model execution absence belongs to the same tuple and one consumption', () => {
  const prepared = {}, installation = frozen([], []), occurrence = {};
  const moon = {clientProgramInferOccurrenceCoordinates(value) {
    assert.equal(value, occurrence); return {_2: 0};
  }, clientProgramInferOccurrenceModelTaskCid() {assert.fail('No Task lookup for an empty inventory');}};
  const absent = () => {
    try {readInstalledModelExecution(moon, prepared, installation, occurrence,
      () => assert.fail('No funded reader runs for absent immutable DATA'));}
    catch (error) {assert.equal(error.code, 'InstalledInferModelExecutionUnavailable'); return error;}
    assert.fail('The original empty inventory must refuse');
  };
  const error = absent();
  assert.equal(consumeInstalledModelExecutionAbsence({...error}, prepared, installation, occurrence), false);
  assert.equal(consumeInstalledModelExecutionAbsence(error, prepared, installation, occurrence), true);
  assert.equal(consumeInstalledModelExecutionAbsence(error, prepared, installation, occurrence), false);
  for (const tuple of [[{}, installation, occurrence], [prepared, frozen([], []), occurrence],
    [prepared, installation, {}]]) {
    const foreign = absent();
    assert.equal(consumeInstalledModelExecutionAbsence(foreign, ...tuple), false);
    assert.equal(consumeInstalledModelExecutionAbsence(foreign, prepared, installation, occurrence), false);
  }
});

test('Model execution absence does not promote custom metadata or callback errors to no-work proof', () => {
  const prepared = {}, occurrence = {}, callbackFailure = Object.assign(new Error('callback'),
    {code: 'InstalledInferModelExecutionUnavailable'});
  const moon = {clientProgramInferOccurrenceCoordinates: () => ({_2: 0}),
    clientProgramInferOccurrenceModelTaskCid: () => 'task'};
  const cases = [
    frozen([{modelTaskCid: 'other', cid: 'execution', bodyWire: '{}'}], []),
    Object.freeze({environmentWire: '{}', executionContracts: Object.freeze(new Proxy([], {})),
      dependencyBodies: Object.freeze([])}),
    Object.freeze({environmentWire: '{}', executionContracts: Object.freeze(Object.defineProperty([], 'find',
      {value() {throw callbackFailure;}})), dependencyBodies: Object.freeze([])}),
    Object.freeze({environmentWire: '{}', executionContracts: Object.freeze(Object.defineProperty([], Symbol.iterator,
      {value() {throw callbackFailure;}})), dependencyBodies: Object.freeze([])}),
  ];
  for (const installation of cases) {
    let failure;
    try {readInstalledModelExecution(moon, prepared, installation, occurrence,
      () => assert.fail('No selected execution body'));}
    catch (error) {failure = error;}
    assert(failure);
    assert.equal(consumeInstalledModelExecutionAbsence(failure, prepared, installation, occurrence), false);
  }
  assert.equal(consumeInstalledModelExecutionAbsence(callbackFailure, prepared, frozen([], []), occurrence), false);
  const installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{}'}], []);
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, occurrence,
    () => {throw callbackFailure;}), error => error === callbackFailure);
  assert.equal(consumeInstalledModelExecutionAbsence(callbackFailure, prepared, installation, occurrence), false);
});

test('original native Model metadata rejection follows returned material funding and consumes the same tuple once', () => {
  const prepared = {}, occurrence = {}, issue = {}, execution = {};
  const installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{}'}], []);
  const calls = [], beforeRead = () => {calls.push('funded');};
  const moon = {clientProgramInferOccurrenceCoordinates: () => ({_2: 0}),
    clientProgramInferOccurrenceModelTaskCid: () => 'task',
    clientProgramReadComposedInferModelExecution(value) {
      assert.equal(value, occurrence); calls.push('native'); return {$tag: 0, _0: issue};
    },
    clientProgramInferDependencyReferences: () => ({_0: 'prompt', _1: 'retry', _2: 'backoff'}),
    clientProgramInferMediaDependencyReferences: () => [],
    clientProgramReadInferModelDependencies(value) {
      assert.equal(value, execution); calls.push('native'); return {$tag: 0, _0: issue};
    }};
  for (const read of [() => readInstalledModelExecution(moon, prepared, installation, occurrence, beforeRead),
    () => readInstalledModelDependencies(moon, execution, installation, beforeRead, prepared, occurrence)]) {
    let failure;
    try {read();} catch (error) {failure = error;}
    assert.equal(failure.cause, issue);
    assert.deepEqual(calls.splice(0), ['funded', 'native']);
    assert.equal(consumeInstalledModelPreparationRefusal({...failure}, prepared, installation, occurrence, beforeRead, execution), false);
    assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, beforeRead, execution), true);
    assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, beforeRead, execution), false);
  }
});

test('native metadata witness excludes funding throws, native throws, foreign callbacks and asynchronous funding', () => {
  const prepared = {}, occurrence = {}, installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{}'}], []);
  const lookalike = Object.assign(new Error('MoonBitHostFailure'), {code: 'MoonBitHostFailure', cause: {}});
  const beforeRead = () => {}, moon = {clientProgramInferOccurrenceCoordinates: () => ({_2: 0}),
    clientProgramInferOccurrenceModelTaskCid: () => 'task',
    clientProgramReadComposedInferModelExecution: () => ({$tag: 0, _0: {}})};
  for (const [fund, read] of [[() => {throw lookalike;}, () => assert.fail('No native read after funding throw')],
    [beforeRead, () => {throw lookalike;}], [() => Promise.resolve(), moon.clientProgramReadComposedInferModelExecution]]) {
    moon.clientProgramReadComposedInferModelExecution = read;
    let failure;
    try {readInstalledModelExecution(moon, prepared, installation, occurrence, fund);} catch (error) {failure = error;}
    assert(failure);
    assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, fund), false);
  }
  moon.clientProgramReadComposedInferModelExecution = () => ({$tag: 0, _0: {}});
  let failure;
  try {readInstalledModelExecution(moon, prepared, installation, occurrence, beforeRead);} catch (error) {failure = error;}
  assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, () => {}), false);
  assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, beforeRead), false);
});

test('native metadata rejection cannot certify custom element reads or replaced original selection intrinsics', () => {
  const prepared = {}, occurrence = {}, entry = Object.freeze({modelTaskCid: 'task', cid: 'execution', bodyWire: '{}'});
  let getters = 0;
  const entries = [];
  Object.defineProperty(entries, '0', {get() {getters++; return entry;}, enumerable: true});
  const installation = Object.freeze({environmentWire: '{}', executionContracts: Object.freeze(entries),
    dependencyBodies: Object.freeze([])});
  const moon = {clientProgramInferOccurrenceCoordinates: () => ({_2: 0}),
    clientProgramInferOccurrenceModelTaskCid: () => 'task',
    clientProgramReadComposedInferModelExecution: () => ({$tag: 0, _0: {}})};
  const beforeRead = () => {};
  let failure;
  try {readInstalledModelExecution(moon, prepared, installation, occurrence, beforeRead);} catch (error) {failure = error;}
  assert(getters > 0);
  assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, installation, occurrence, beforeRead), false);
  const ordinary = frozen([entry], []), original = Object.getOwnPropertyDescriptor(Array.prototype, 'find');
  const replaced = () => {Object.defineProperty(Array.prototype, 'find', {...original,
    value(...args) {return Reflect.apply(original.value, this, args);}});};
  try {
    try {readInstalledModelExecution(moon, prepared, ordinary, occurrence, replaced);} catch (error) {failure = error;}
    assert.equal(consumeInstalledModelPreparationRefusal(failure, prepared, ordinary, occurrence, replaced), false);
  } finally {Object.defineProperty(Array.prototype, 'find', original);}
});

const managerSource = readFileSync(new URL('./ordinary-source-managed.mjs', import.meta.url), 'utf8');
const managerHelpers = managerSource.slice(managerSource.indexOf('  function constructRequestDomain('),
  managerSource.indexOf('  const view = Object.freeze({'));
const materialStart = managerSource.indexOf('    prepareModelMaterials(');
const materialEnd = managerSource.indexOf('    prepareModelGraph(', materialStart);
const hostSource = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const hostTree = parse(hostSource, {ecmaVersion: 'latest', sourceType: 'module'});
let materialCallback;
let mockGraph;
const bindingCallbacks = [];
const walk = node => {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && node.id.name === 'requestModelMaterials') materialCallback = node.init;
  if (node.type === 'VariableDeclarator' && node.id.name === 'graph' &&
      node.init?.type === 'ConditionalExpression' &&
      node.init.alternate?.callee?.name === 'checked' &&
      node.init.alternate.arguments[0]?.callee?.property?.name === 'clientProgramInstalledComposedInferPlanGraph') mockGraph = node.init;
  if (node.type === 'CallExpression' && node.callee.name === 'admitInstalledModelProviderBinding') bindingCallbacks.push(node.arguments[3]);
  for (const child of Object.values(node)) if (Array.isArray(child)) child.forEach(walk);
  else if (child && typeof child === 'object') walk(child);
};
walk(hostTree);
assert(materialCallback && mockGraph && bindingCallbacks.length === 2);

// Execute the actual Host and manager bodies with explicit typed constructor
// ports. The Core companion owns the real Resource debit; these ports are not
// a Model/Account grant, compiled ABI, Provider send or ordinary acceptance.
function effectMaterialCaller({foreignBorrow = false, refuse = false, replaceAfter = false} = {}) {
  const prepared = {}, request = {}, parent = {}, input = {}, holder = {}, evidence = {}, graph = {}, events = [];
  let nativeCalls = 0;
  const state = {prepared, parent, holder, compilationKind: 'effectful'};
  const producer = {preparation: state, receipt: input};
  const fail = code => {throw Object.assign(new Error(code), {code});};
  const moon = {
    clientProgramPreparationBorrowRead() {assert.fail('Effect is never a Program borrower');},
    clientProgramRequestProgramModuleIssueCode() {assert.fail('no successful issue reclassification');},
    clientProgramPrepareRequestModelContractMaterials(p, i, count, wireAt, containers) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(i, input);
      assert.equal(state.preparing, true); nativeCalls++;
      assert.throws(() => manager.prepareModelMaterials(prepared, request, 0, () => '', 0),
        {code: 'ForeignInstalledSourceProducer'});
      if (refuse) throw undefined;
      events.push(['materials', count, containers, Array.from({length: count}, (_, index) => wireAt(index))]);
      return {value: undefined};
    },
    clientProgramPrepareRequestModelProviderBinding(p, i, ...values) {
      assert.equal(this, moon); assert.equal(p, parent); assert.equal(i, input);
      assert.equal(state.preparing, true); nativeCalls++;
      events.push(['binding', ...values]); return {value: evidence};
    },
  };
  state.effectBorrowMethods = {clientProgramEffectPreparationInputRead(value) {
    assert.equal(value, holder); return foreignBorrow ? undefined : prepared;
  }};
  state.context = {runtime: moon};
  const manager = Function('current', 'producerForRequest', 'fail', 'checkedRequestProgramPreparation',
    `const pendingRunRegistrations=new Set();${managerHelpers}return ({${managerSource.slice(materialStart, materialEnd)}});`)(
    () => {if (replaceAfter && state.modelProviderBinding !== undefined) state.prepared = {};},
    value => {assert.equal(value, request); return producer;}, fail,
    (runtime, result) => {assert.equal(runtime, moon); return result.value;});
  const preparation = {
    prepareManagedModelMaterials(runtime, p, ...args) {
      assert.equal(this, preparation); assert.equal(runtime, moon); assert.equal(p, prepared);
      return manager.prepareModelMaterials(prepared, request, ...args);
    },
    prepareManagedModelBinding(runtime, p, ...args) {
      assert.equal(this, preparation); assert.equal(runtime, moon); assert.equal(p, prepared);
      return manager.prepareModelBinding(prepared, request, ...args);
    },
    prepareManagedModelGraph(runtime, p, occurrence, execution) {
      assert.equal(this, preparation); assert.equal(runtime, moon); assert.equal(p, prepared);
      assert(occurrence && execution); events.push(['graph']); return graph;
    },
  };
  const select = (node, extra = {}) => Function('preparation', 'moon', 'preparedProgram', 'prepareSubmit', 'effectful', ...Object.keys(extra),
    `return (${hostSource.slice(node.start, node.end)});`)(preparation, moon, prepared,
    {kindOf: p => {assert.equal(p, prepared); return 'effectful';}}, true, ...Object.values(extra));
  return {prepared, evidence, graph, state, moon, events, select, nativeCalls: () => nativeCalls,
    beforeRead: select(materialCallback), bindingCallbacks: bindingCallbacks.map(node => select(node))};
}

test('Effect Model actual Host reserves execution and dependency materials through its same Request before readers', () => {
  const f = effectMaterialCaller(), occurrence = {}, execution = {}, dependencies = {};
  const installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{"execution":1}'}], [
    {cid: 'prompt', bodyWire: '{"prompt":2}'}, {cid: 'retry', bodyWire: '{"retry":3}'},
    {cid: 'backoff', bodyWire: '{"backoff":4}'},
  ]);
  Object.assign(f.moon, {
    clientProgramInferOccurrenceCoordinates: () => ({_2: 4}),
    clientProgramInferOccurrenceModelTaskCid: () => 'task',
    clientProgramReadComposedInferModelExecution(o, wire, cid) {
      assert.equal(this, f.moon); assert.equal(o, occurrence);
      assert.deepEqual([wire, cid], ['{"execution":1}', 'execution']);
      assert.equal(f.events.at(-1)[0], 'materials'); f.events.push(['execution reader']);
      return {$tag: 1, _0: execution};
    },
    clientProgramInferDependencyReferences: () => ({_0: 'prompt', _1: 'retry', _2: 'backoff'}),
    clientProgramInferMediaDependencyReferences: () => [],
    clientProgramReadInferModelDependencies(e, ...wires) {
      assert.equal(this, f.moon); assert.equal(e, execution);
      assert.deepEqual(wires, ['{"prompt":2}', '{"retry":3}', '{"backoff":4}']);
      assert.equal(f.events.at(-1)[0], 'materials'); f.events.push(['dependency reader']);
      return {$tag: 1, _0: dependencies};
    },
  });
  assert.equal(readInstalledModelExecution(f.moon, f.prepared, installation, occurrence, f.beforeRead).execution, execution);
  assert.equal(readInstalledModelDependencies(f.moon, execution, installation, f.beforeRead), dependencies);
  assert.deepEqual(f.events, [
    ['materials', 1, 4, ['{"execution":1}']], ['execution reader'],
    ['materials', 3, 4, ['{"prompt":2}', '{"retry":3}', '{"backoff":4}']], ['dependency reader'],
  ]);
  assert.equal(f.nativeCalls(), 2);
});

test('Effect Model actual Mock and physical binding callbacks retain only the same backed issuer result', () => {
  for (let index = 0; index < bindingCallbacks.length; index++) {
    const f = effectMaterialCaller();
    const originals = {installationRevision: {wire: '{"installation":1}', cid: 'installation'},
      configurationContract: {wire: '{"contract":2}', cid: 'contract'}, configuration: {wire: '{"configuration":3}', cid: 'configuration'}};
    Object.assign(f.moon, {
      clientProgramModelProviderBinding() {assert.fail('unbacked legacy issuer');},
      strategyRunEvidenceJson(value) {assert.equal(value, f.evidence); return JSON.stringify({provider_id: 'mock', self_cid: 'binding',
        installation_revision_cid: 'installation', configuration_contract_cid: 'contract', configuration_cid: 'configuration'});},
      strategyRunEvidenceIdentity(value) {assert.equal(value, f.evidence); return 'binding';},
    });
    const actual = admitInstalledModelProviderBinding(f.moon, 'mock', {bindingOriginals: originals}, f.bindingCallbacks[index]);
    assert.equal(actual.value, f.evidence); assert.equal(f.state.modelProviderBinding, f.evidence);
    assert.deepEqual(f.events, [['binding', 'mock', '{"installation":1}', '{"contract":2}', '{"configuration":3}']]);
    assert.equal(f.nativeCalls(), 1);
    if (index === 0) {
      f.moon.clientProgramInstalledComposedInferPlanGraph = () => assert.fail('unbacked Mock Graph issuer');
      assert.equal(f.select(mockGraph, {occurrence: {}, execution: {}, serializationGraph: undefined}), f.graph);
      assert.deepEqual(f.events.at(-1), ['graph']);
    }
  }
});

test('Effect Model actual material caller preserves failed undefined and foreign or changed original custody', () => {
  const refused = effectMaterialCaller({refuse: true});
  for (let attempt = 0; attempt < 2; attempt++) {
    let caught = false;
    try {refused.beforeRead(1, () => assert.fail('reader after refusal'), 1);}
    catch (cause) {caught = true; assert.equal(cause, undefined);}
    assert.equal(caught, true);
  }
  assert.equal(refused.nativeCalls(), 1);
  const foreign = effectMaterialCaller({foreignBorrow: true});
  assert.throws(() => foreign.beforeRead(1, () => assert.fail('foreign reader'), 1), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(foreign.nativeCalls(), 0);
  const changed = effectMaterialCaller({replaceAfter: true});
  assert.throws(() => changed.bindingCallbacks[0]('mock', '{}', '{}', '{}'), {code: 'ForeignInstalledSourceProducer'});
  assert.equal(changed.state.modelProviderBinding, changed.evidence);
  assert.equal(changed.state.preparationFailed, true);
  assert.equal(changed.nativeCalls(), 1);
});

test('packed Model fixture supplies its original immutable material envelope to the funded reader', () => {
  const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url)));
  const {installation, taskCid} = configuration(base);
  const entry = installation.executionContracts[0], prepared = {}, calls = [];
  const original = new Error('original Core execution reader');
  const moon = {
    clientProgramSelectedInferStep(value) {assert.equal(value, prepared); return 3;},
    clientProgramInferModelTaskCid(value, step) {
      assert.equal(value, prepared); assert.equal(step, 3); return taskCid;
    },
    clientProgramReadInferModelExecution(value, step, wire, cid) {
      assert.equal(value, prepared); assert.equal(step, 3);
      assert.equal(wire, entry.bodyWire); assert.equal(cid, entry.cid);
      calls.push('original reader'); throw original;
    },
  };
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, undefined,
    (count, wireAt, containers) => {
      assert.equal(count, 1);
      assert.equal(containers, installation.executionContracts.length + installation.dependencyBodies.length);
      assert.equal(wireAt(0), entry.bodyWire);
      calls.push('same Request reservation');
    }), cause => cause === original);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  assert(Object.isFrozen(installation));
  for (const entries of [installation.executionContracts, installation.dependencyBodies]) {
    assert(Object.isFrozen(entries));
    assert(entries.every(Object.isFrozen));
  }
});

test('Model execution reservation precedes original reader and preserves captured method receiver and wire', () => {
  const prepared = {}, occurrence = {}, primary = new Error('original native execution');
  const installation = frozen([{modelTaskCid: 'task', cid: 'execution', bodyWire: '{"original":true}'}], []);
  const calls = [];
  const moon = {
    clientProgramInferOccurrenceCoordinates(o) {assert.equal(o, occurrence); return {_2: 4};},
    clientProgramInferOccurrenceModelTaskCid(o) {assert.equal(o, occurrence); return 'task';},
    clientProgramReadComposedInferModelExecution(o, wire, cid) {
      assert.equal(this, moon); assert.equal(o, occurrence);
      assert.equal(wire, installation.executionContracts[0].bodyWire); assert.equal(cid, 'execution');
      calls.push('original reader'); throw primary;
    },
  };
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, occurrence,
    (count, wireAt, containers) => {
      calls.push('same Request reservation'); assert.equal(count, 1); assert.equal(containers, 1);
      assert.equal(wireAt(0), installation.executionContracts[0].bodyWire);
      moon.clientProgramReadComposedInferModelExecution = () => assert.fail('replacement reader');
    }), cause => cause === primary);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  const denied = new Error('original capacity refusal'); calls.length = 0;
  assert.throws(() => readInstalledModelExecution(moon, prepared, installation, occurrence,
    () => {throw denied;}), cause => cause === denied);
  assert.deepEqual(calls, []);
});

test('Model dependency reservation counts actual selected bodies and preserves absent dependency refusal', () => {
  const execution = {}, primary = new Error('original missing dependency');
  const installation = frozen([], [
    {cid: 'prompt', bodyWire: '{"prompt":1}'},
    {cid: 'retry', bodyWire: '{"retry":2}'},
    {cid: 'media', bodyWire: '{"media":3}'},
    {cid: 'unselected', bodyWire: 'x'.repeat(10000)},
  ]);
  const calls = [], moon = {
    clientProgramInferDependencyReferences(e) {assert.equal(e, execution); return {_0: 'prompt', _1: 'retry', _2: 'absent'};},
    clientProgramInferMediaDependencyReferences(e) {assert.equal(e, execution); return [{_0: 'image', _1: 'media'}];},
    clientProgramReadInferModelDependenciesWithMedia(e, prompt, retry, backoff, media) {
      assert.equal(this, moon); assert.equal(e, execution);
      assert.deepEqual([prompt, retry, backoff], ['{"prompt":1}', '{"retry":2}', undefined]);
      assert.deepEqual(media, [{_0: 'image', _1: '{"media":3}'}]);
      calls.push('original reader'); throw primary;
    },
  };
  assert.throws(() => readInstalledModelDependencies(moon, execution, installation,
    (count, wireAt, containers) => {
      assert.equal(count, 4); assert.equal(containers, 4);
      assert.deepEqual(Array.from({length: count}, (_, index) => wireAt(index)),
        ['{"prompt":1}', '{"retry":2}', '', '{"media":3}']);
      calls.push('same Request reservation');
      moon.clientProgramReadInferModelDependenciesWithMedia = () => assert.fail('replacement reader');
    }), cause => cause === primary);
  assert.deepEqual(calls, ['same Request reservation', 'original reader']);
  let accessed = false;
  const foreign = Object.freeze({environmentWire: '{}', executionContracts: Object.freeze([]),
    get dependencyBodies() {accessed = true; return [];} });
  assert.throws(() => readInstalledModelDependencies(moon, execution, foreign, () => assert.fail('foreign originals')),
    /InstalledModelMaterialOriginalUnavailable/);
  assert.equal(accessed, false);
});

test('Model provider metadata retains same owned issuer result without legacy reissue or mutation fallback', () => {
  const value = {}, originals = Object.freeze({
    installationRevision: Object.freeze({wire: '{"installation":1}', cid: 'installation'}),
    configurationContract: Object.freeze({wire: '{"contract":2}', cid: 'contract'}),
    configuration: Object.freeze({wire: '{"configuration":3}', cid: 'configuration'}),
  });
  const moon = {
    clientProgramModelProviderBinding() {assert.fail('legacy issuer');},
    strategyRunEvidenceJson(actual) {assert.equal(actual, value); return JSON.stringify({provider_id: 'mock', self_cid: 'binding',
      installation_revision_cid: 'installation', configuration_contract_cid: 'contract', configuration_cid: 'configuration'});},
    strategyRunEvidenceIdentity(actual) {assert.equal(actual, value); return 'binding';},
  };
  let calls = 0;
  const result = admitInstalledModelProviderBinding(moon, 'mock', {bindingOriginals: originals},
    (...args) => {
      assert.deepEqual(args, ['mock', originals.installationRevision.wire,
        originals.configurationContract.wire, originals.configuration.wire]);
      calls++; return value;
    });
  assert.equal(result.value, value); assert.equal(result.originals, originals); assert.equal(calls, 1);
  const primary = new Error('original before-binding refusal');
  assert.throws(() => admitInstalledModelProviderBinding(moon, 'mock', {bindingOriginals: originals}, () => {throw primary;}),
    cause => cause === primary);
});

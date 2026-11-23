import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {createContentInferenceControls} from '../host-common/runtime-content-inference-control.mjs';
import {selectInstalledSerializationGraph} from './local-values-plan.mjs';

type InferenceMoon = Parameters<typeof createContentInferenceControls>[0];
type GraphFixtureRuntime = {-readonly [Name in keyof InferenceMoon]?: InferenceMoon[Name]};
type GraphConstruction = ReturnType<typeof createContentInferenceControls>['prepareCheckedClientRequestSerializationGraph'];
type FacadeGraph = ReturnType<GraphConstruction>;
type SourceNode = Readonly<{type?: string; key?: Readonly<{name?: string}>; start: number; end: number}>;
type PreparationState = {
  parent: object; prepared: object; holder: object; compilationFamily: string;
  context: Readonly<{runtime: object}> | undefined;
  contentGraph?: FacadeGraph; preparing?: boolean;
  preparationFailed?: boolean; preparationFailure?: unknown;
};

// Actual private caller bodies with explicit Request/current ports. No
// Common, Resource admission, Account, Store or physical ACK is simulated.
function extract(file: string, name: string, ports: Readonly<Record<string, unknown>>) {
  const source = readFileSync(new URL(file, import.meta.url), 'utf8');
  let selected: SourceNode | undefined;
  const visit = (value: unknown) => {
    const node = value as SourceNode | null | undefined;
    if (node === null || typeof node !== 'object') return;
    if (node.type === 'Property' && node.key?.name === name) {
      assert.equal(selected, undefined, name); selected = node;
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(visit);
      else if (value && typeof value === 'object') visit(value);
    }
  };
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert(selected, name);
  const body = source.slice(selected.start, selected.end);
  const helpers = file === './ordinary-source-managed.mjs' ? source.slice(source.indexOf('  function constructRequestDomain('), source.indexOf('  const view = Object.freeze({')) : '';
  return Function(...Object.keys(ports),
    `const pendingRunRegistrations=new Set();${helpers}return ({${body}}).${name};`)(...Object.values(ports));
}

function contentInference(moon: GraphFixtureRuntime, serializationPlanTokens: WeakMap<object, unknown>) {
  return createContentInferenceControls(moon as InferenceMoon, {
    serializationPlanTokens, serializationGenerationTokens: new WeakMap(),
    compiledRunResult: result => result,
    compiledContent() {assert.fail('unexpected compiled Content lookup');},
    token() {assert.fail('unexpected definition lookup');},
  });
}

function fixture() {
  const prepared = {}, request = {}, parent = {}, input = {}, contracts = {}, holder = {};
  const graph = {}, tokens = new WeakMap<object, unknown>(), calls: string[] = [];
  const state: PreparationState = {
    parent, prepared, holder, compilationFamily: 'content', context: undefined,
  };
  const options = {task: 0, step: 1, maxRows: 2, maxBytes: 128,
    resultDataPolicy: {kind: 'data_policy', cid: 'original-policy', wire: 'original-wire'}};
  let refused: unknown, constructing = false, after: (() => void) | undefined, borrowed = prepared;
  const moon: GraphFixtureRuntime & {clientProgramPreparationBorrowRead(h: unknown): object} = {
    clientProgramPreparationBorrowRead(h) { assert.equal(h, holder); return borrowed; },
    clientProgramPrepareRequestSerializationGraph(p, i, task, step, cid, wire, rows, bytes, roots, c) {
      assert.equal(this, moon);
      assert.deepEqual([p, i, task, step, cid, wire, rows, bytes, roots, c],
        [parent, input, 0, 1, 'original-policy', 'original-wire', 2, 128, true, contracts]);
      assert.equal(state.preparing, true); calls.push('owned-constructor');
      constructing = true;
      assert.throws(() => prepare(prepared, request, construct), {code: 'ForeignInstalledSourceProducer'});
      if (refused) throw refused;
      return graph;
    },
    clientProgramSerializationPlanGraphWire(g) {assert.equal(g, graph); return 'original-graph-wire';},
    clientProgramSerializationPlanGraph() {throw new Error('legacy Graph issuer must not run');},
  };
  state.context = {runtime: moon};
  const control = contentInference(moon, tokens);
  const construct = (p: unknown, i: unknown, c: unknown) =>
    control.prepareCheckedClientRequestSerializationGraph(p, i, c, prepared, options, false);
  const producer = {receipt: input, preparation: state};
  const prepare = extract('./ordinary-source-managed.mjs', 'prepareContentGraph', {
    current() {
      if (constructing && state.contentGraph !== undefined) {
        assert.equal(tokens.get(state.contentGraph), graph);
        if (after) after();
      }
    },
    producerForRequest(r: unknown) {assert.equal(r, request); return producer;},
    originals: {installation: {sequenceContractOriginal: {moon, admission: contracts}}},
    fail: (code: string) => {throw Object.assign(new Error(code), {code});},
  });
  return {state, graph, tokens, calls, prepare: () => prepare(prepared, request, construct),
    refuse: (error: unknown) => {refused = error;}, after: (callback: () => void) => {after = callback;},
    changeBorrow() {borrowed = {};}, removePort() {delete moon.clientProgramPrepareRequestSerializationGraph;}};
}

test('actual Content Graph caller forwards same parent/input/contracts and retains original before post-current', () => {
  const f = fixture();
  const selected = f.prepare();
  assert.equal(f.tokens.get(selected), f.graph);
  assert.equal(f.state.contentGraph, selected);
  assert.equal(f.prepare(), selected);
  assert.deepEqual(f.calls, ['owned-constructor']);
  assert.equal(f.state.preparing, false);
});

test('Content Graph refuses missing owned port and retains same constructor or post-current failure for Request cleanup', () => {
  const missing = fixture(); missing.removePort();
  assert.throws(missing.prepare, /Request Content Graph constructor unavailable/);
  assert.equal(missing.state.preparationFailed, true);
  assert.equal(missing.state.contentGraph, undefined);
  assert.deepEqual(missing.calls, []);
  const primary = new Error('original capacity refusal'), refused = fixture(); refused.refuse(primary);
  assert.throws(refused.prepare, error => error === primary);
  assert.throws(refused.prepare, error => error === primary);
  assert.deepEqual(refused.calls, ['owned-constructor']);
  const changed = fixture(); changed.after(() => changed.changeBorrow());
  assert.throws(changed.prepare, {code: 'ForeignInstalledSourceProducer'});
  assert.equal(changed.tokens.get(changed.state.contentGraph!), changed.graph);
  assert.equal(changed.state.preparing, false);
  const retained = changed.state.preparationFailure;
  assert.throws(changed.prepare, error => error === retained);
  assert.deepEqual(changed.calls, ['owned-constructor']);
});

test('acquired Content Graph forwards same Request without borrowing an external policy or legacy issuer', () => {
  const parent = {}, input = {}, contracts = {}, prepared = {}, graph = {}, tokens = new WeakMap();
  const options = {task: 1, step: 3, maxRows: 3, maxBytes: 4096,
    resultDataPolicy: new Proxy({}, {get() {throw new Error('acquired policy is an original checked Source');}})};
  let calls = 0;
  const moon: GraphFixtureRuntime = {
    clientProgramPrepareRequestAcquiredSerializationGraph(...args) {
      assert.equal(this, moon); calls++;
      assert.deepEqual(args, [parent, input, 1, 3, 3, 4096, false, contracts]);
      return graph;
    },
    clientProgramAcquiredSerializationPlanComponent() {throw new Error('legacy issuer');},
    clientProgramSerializationPlanGraphWire(value) {assert.equal(value, graph); return 'same-original-wire';},
  };
  const control = contentInference(moon, tokens);
  const construct = () =>
    control.prepareCheckedClientRequestAcquiredSerializationGraph(parent, input, contracts, prepared, options, true);
  const selected = construct();
  assert.equal(tokens.get(selected), graph); assert.equal(calls, 1);
  delete moon.clientProgramPrepareRequestAcquiredSerializationGraph;
  assert.throws(construct,
    /Request acquired Content Graph constructor unavailable/);
  assert.equal(calls, 1);
});

test('Effect Content uses the captured original Effect borrower before and after its same Request constructor', () => {
  const prepared = {}, request = {}, input = {}, parent = {}, holder = {}, graph = {}, admission = {};
  let reads = 0, calls = 0;
  const moon = {clientProgramPreparationBorrowRead() {assert.fail('Effect cannot borrow a pure Program');}};
  const state: {parent: object; prepared: object; holder: object; compilationKind: string;
    context: {runtime: object}; effectBorrowMethods: {clientProgramEffectPreparationInputRead(original: unknown): object};
    contentGraph?: unknown; preparing?: boolean} = {parent, prepared, holder, compilationKind: 'effectful',
    context: {runtime: moon}, effectBorrowMethods: {
      clientProgramEffectPreparationInputRead(original) {
        assert.equal(this, moon); assert.equal(original, holder); reads++; return prepared;
      },
    }};
  const prepare = extract('./ordinary-source-managed.mjs', 'prepareContentGraph', {
    current() {}, producerForRequest(value: unknown) {assert.equal(value, request); return {receipt: input, preparation: state};},
    originals: {installation: {sequenceContractOriginal: {moon, admission}}},
    fail(code: string) {throw Object.assign(new Error(code), {code});},
  });
  assert.equal(prepare(prepared, request, (...actual: unknown[]) => {
    assert.deepEqual(actual, [parent, input, admission, true]);
    assert.equal(state.preparing, true); calls++; return graph;
  }), graph);
  assert.equal(reads, 2); assert.equal(calls, 1); assert.equal(state.contentGraph, graph);
});

test('Effect Content forwards its original Model occurrence through both native Request constructors', () => {
  for (const acquired of [false, true]) {
    const parent = {}, input = {}, contracts = {}, prepared = {}, occurrence = {}, graph = {};
    const options = {task: 0, step: 1, maxRows: 3, maxBytes: 128,
      resultDataPolicy: {kind: 'data_policy', cid: 'policy-cid', wire: 'policy-wire'}};
    const serializationPlanTokens = new WeakMap(); let calls = 0;
    const moon: GraphFixtureRuntime = {clientProgramSerializationPlanGraphWire(value) {assert.equal(value, graph); return 'same-graph';}};
    const name = acquired ? 'clientProgramPrepareRequestModelAcquiredSerializationGraph'
      : 'clientProgramPrepareRequestModelSerializationGraph';
    moon[name] = function (...actual: unknown[]) {
      assert.equal(this, moon); calls++;
      assert.deepEqual(actual, [parent, input, occurrence, 0, 1,
        ...(acquired ? [] : ['policy-cid', 'policy-wire']), 3, 128, false, contracts]);
      return graph;
    };
    const control = contentInference(moon, serializationPlanTokens);
    const construct = () => acquired
      ? control.prepareCheckedClientRequestAcquiredSerializationGraph(parent, input, contracts,
        prepared, options, true, occurrence)
      : control.prepareCheckedClientRequestSerializationGraph(parent, input, contracts,
        prepared, options, true, occurrence);
    const selected = construct();
    assert.equal(serializationPlanTokens.get(selected), graph); assert.equal(calls, 1);
    delete moon[name];
    assert.throws(construct, /constructor unavailable/);
    assert.equal(calls, 1);
  }
});

test('Effect serialization selection requires the funded intermediate path and exact Effect occurrence', () => {
  const prepared = {}, selected = {}, policy = {}; let calls = 0;
  const moon = {
    clientProgramSerializationOccurrences() {assert.fail('Effect cannot use the pure occurrence reader');},
    clientProgramAcquisitionCount() {assert.fail('Effect uses its funded constructor');},
    clientProgramEffectSerializationOccurrences(value: unknown) {assert.equal(value, prepared); return [{_0: 0, _1: 1}];},
  };
  const options: Parameters<typeof selectInstalledSerializationGraph>[0] = {
    moon, preparedProgram: prepared, effectful: true, resultDataPolicy: policy,
    control: {
      prepareCheckedClientSerializationComponent() {assert.fail('Effect uses its funded constructor');},
      prepareCheckedClientSerializationGraph() {assert.fail('Effect uses its funded constructor');},
      prepareCheckedClientAcquiredSerializationComponent() {assert.fail('Effect uses its funded constructor');},
      prepareCheckedClientAcquiredSerializationGraph() {assert.fail('Effect uses its funded constructor');},
    },
    prepareSerializationGraph(original, intermediate) {
      assert.equal(intermediate, true); assert.equal(original.task, 0); assert.equal(original.step, 1);
      assert.equal(original.resultDataPolicy, policy); calls++; return selected;
    }};
  assert.equal(selectInstalledSerializationGraph(options, true), selected);
  assert.throws(() => selectInstalledSerializationGraph(options), /Unsupported/);
  assert.throws(() => selectInstalledSerializationGraph({...options, prepareSerializationGraph: undefined}, true), /Unsupported/);
  assert.equal(calls, 1);
});

test('ordinary Effect Content selects its own acquisition counter and forwards the same Model occurrence', () => {
  for (const acquisitions of [0, 1]) {
    const prepared = {}, request = {}, parent = {}, input = {}, contracts = {}, options = {}, occurrence = {}, result = {};
    const originals = {}; let calls = 0;
    const runtime = {
      clientProgramAcquisitionCount() {assert.fail('Effect cannot use the pure acquisition counter');},
      clientProgramEffectAcquisitionCount(value: unknown) {assert.equal(this, runtime); assert.equal(value, prepared); return acquisitions;},
    };
    const manager = {prepareContentGraph(value: unknown, original: unknown, construct: (...args: unknown[]) => unknown) {
      assert.equal(value, prepared); assert.equal(original, request);
      return construct(parent, input, contracts, true);
    }};
    const control: Record<string, (...args: unknown[]) => unknown> = {};
    control[acquisitions === 0 ? 'prepareCheckedClientRequestSerializationGraph'
      : 'prepareCheckedClientRequestAcquiredSerializationGraph'] = (...actual) => {
      assert.deepEqual(actual, [parent, input, contracts, prepared, options, true, occurrence]); calls++; return result;
    };
    const prepare = extract('./embedded-local.mjs', 'prepareManagedContentGraph', {
      sourceManaged: manager, computeManaged: undefined, moon: runtime, originals,
      assertSourceManagedInstallationCurrent(actual: unknown, original: unknown) {assert.equal(actual, manager); assert.equal(original, originals);},
      assertManagedComputeInstallationCurrent() {assert.fail('different installation');},
      originalSourceManagedHostRequest(original: unknown, value: unknown) {assert.equal(original, originals); assert.equal(value, prepared); return request;},
      runtimeCore(actual: unknown) {assert.equal(actual, runtime); return {publicationControl: control};},
      clientOperationError(code: string) {return Object.assign(new Error(code), {code});},
    });
    assert.equal(prepare(runtime, prepared, options, true, occurrence), result);
    assert.throws(() => prepare(runtime, prepared, options, true), {code: 'ForeignInstalledSourceProducer'});
    assert.equal(calls, 1);
  }
});
